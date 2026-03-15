import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class StatementMatchServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var repository: SwiftDataStatementRepository!
    private var service: StatementMatchService!
    private var postingWorkflow: PostingWorkflowUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        repository = SwiftDataStatementRepository(modelContext: context)
        service = StatementMatchService(modelContext: context)
        postingWorkflow = PostingWorkflowUseCase(modelContext: context)
    }

    override func tearDown() {
        postingWorkflow = nil
        service = nil
        repository = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testRefreshSuggestionsPrefersSameDayAndTokenMatch() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let importRecord = StatementImportRecord(
            businessId: businessId,
            evidenceId: UUID(),
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            fileSource: .csv,
            originalFileName: "match.csv"
        )
        try await repository.saveImport(importRecord)
        let line = StatementLineRecord(
            importId: importRecord.id,
            businessId: businessId,
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            date: makeDate(2026, 1, 10),
            description: "Client Deposit",
            amount: Decimal(120000),
            direction: .inflow,
            counterparty: "ACME"
        )
        try await repository.saveLine(line)

        let bankAccountId = try await canonicalAccountId(
            businessId: businessId,
            legacyAccountId: AccountingConstants.bankAccountId
        )
        let preferred = PostingCandidate(
            businessId: businessId,
            taxYear: 2026,
            candidateDate: makeDate(2026, 1, 10),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: bankAccountId,
                    amount: Decimal(120000)
                )
            ],
            confidenceScore: 0.8,
            status: .needsReview,
            source: .importFile,
            memo: "Client Deposit ACME"
        )
        let weaker = PostingCandidate(
            businessId: businessId,
            taxYear: 2026,
            candidateDate: makeDate(2026, 1, 13),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: bankAccountId,
                    amount: Decimal(120000)
                )
            ],
            confidenceScore: 0.8,
            status: .needsReview,
            source: .importFile,
            memo: "other memo"
        )
        try await postingWorkflow.saveCandidate(weaker)
        try await postingWorkflow.saveCandidate(preferred)

        let refreshed = try await service.refreshSuggestions(for: line)

        XCTAssertEqual(refreshed.suggestedCandidateId, preferred.id)
    }

    func testCandidateMatchPromotesToJournalMatchWhenApprovedJournalExists() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let line = try await insertBankLine(businessId: businessId, amount: 5500, direction: .outflow)
        let bankAccountId = try await canonicalAccountId(
            businessId: businessId,
            legacyAccountId: AccountingConstants.bankAccountId
        )
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: 2026,
            candidateDate: line.date,
            proposedLines: [
                PostingCandidateLine(
                    creditAccountId: bankAccountId,
                    amount: Decimal(5500)
                )
            ],
            status: .needsReview,
            source: .manual,
            memo: "会食"
        )
        try await postingWorkflow.saveCandidate(candidate)

        _ = try await service.matchCandidate(lineId: line.id, candidateId: candidate.id)

        let journalId = UUID()
        let journal = CanonicalJournalEntry(
            id: journalId,
            businessId: businessId,
            taxYear: 2026,
            journalDate: line.date,
            voucherNo: "V-001",
            sourceCandidateId: candidate.id,
            description: "会食",
            lines: [
                JournalLine(
                    journalId: journalId,
                    accountId: bankAccountId,
                    debitAmount: .zero,
                    creditAmount: Decimal(5500)
                )
            ],
            approvedAt: Date()
        )
        try await SwiftDataCanonicalJournalEntryRepository(modelContext: context).save(journal)

        try await service.promoteCandidateMatches(businessId: businessId)
        let promoted = try await repository.findLine(line.id)

        XCTAssertEqual(promoted?.matchState, .journalMatched)
        XCTAssertEqual(promoted?.matchedJournalId, journal.id)
    }

    func testClearMatchReturnsLineToUnmatched() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let line = try await insertBankLine(businessId: businessId, amount: 3300, direction: .outflow)
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: 2026,
            candidateDate: line.date,
            proposedLines: [],
            status: .draft,
            source: .manual,
            memo: "テスト"
        )
        try await postingWorkflow.saveCandidate(candidate)
        _ = try await service.matchCandidate(lineId: line.id, candidateId: candidate.id)

        let cleared = try await service.clearMatch(lineId: line.id)

        XCTAssertEqual(cleared.matchState, .unmatched)
        XCTAssertNil(cleared.matchedCandidateId)
        XCTAssertNil(cleared.matchedJournalId)
    }

    private func insertBankLine(
        businessId: UUID,
        amount: Int,
        direction: StatementDirection
    ) async throws -> StatementLineRecord {
        let importRecord = StatementImportRecord(
            businessId: businessId,
            evidenceId: UUID(),
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            fileSource: .csv,
            originalFileName: "line.csv"
        )
        try await repository.saveImport(importRecord)
        let line = StatementLineRecord(
            importId: importRecord.id,
            businessId: businessId,
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            date: makeDate(2026, 1, 10),
            description: "会食",
            amount: Decimal(amount),
            direction: direction,
            counterparty: "テスト商店"
        )
        try await repository.saveLine(line)
        return line
    }

    private func canonicalAccountId(
        businessId: UUID,
        legacyAccountId: String
    ) async throws -> UUID {
        let account = try await SwiftDataChartOfAccountsRepository(modelContext: context)
            .findByLegacyId(businessId: businessId, legacyAccountId: legacyAccountId)
        return try XCTUnwrap(account?.id)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
