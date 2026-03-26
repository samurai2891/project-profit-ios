import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ClosingWorkflowUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: ClosingWorkflowUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        FeatureFlags.useCanonicalPosting = true
        context = container.mainContext
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = ClosingWorkflowUseCase(modelContext: context)
        XCTAssertNotNil(dataStore.businessProfile?.id)
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testGenerateClosingEntryReturnsNilWithoutSourceJournals() {
        let entry = try? useCase.generateClosingEntry(for: 2025)

        XCTAssertNil(entry)
        XCTAssertTrue(fetchClosingEntries(taxYear: 2025).isEmpty)
    }

    func testGenerateClosingEntryReturnsNilForLockedYear() {
        seedClosingSourceJournals(year: 2025)
        mutations(dataStore).lockFiscalYear(2025)

        let entry = try? useCase.generateClosingEntry(for: 2025)

        XCTAssertNil(entry)
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .finalLock)
    }

    func testTransitionFiscalYearStateDelegatesValidatedTransition() throws {
        let transitioned = try useCase.transitionFiscalYearState(.softClose, for: 2025)

        XCTAssertEqual(transitioned.yearLockState, .softClose)
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .softClose)
    }

    func testTransitionFiscalYearStateFailsWhenPendingCandidateExistsForTaxClose() throws {
        seedClosingSourceJournals(year: 2025)
        XCTAssertNotNil(try useCase.generateClosingEntry(for: 2025))
        createPendingCandidate(year: 2025, status: .needsReview)

        XCTAssertThrowsError(
            try useCase.transitionFiscalYearState(.taxClose, for: 2025)
        ) { error in
            guard case .invalidInput(let message) = error as? AppError else {
                return XCTFail("Expected invalidInput error, got \(error)")
            }
            XCTAssertTrue(message.hasPrefix("年度締めを進められません:\n"))
            XCTAssertTrue(message.contains("未承認の仕訳候補が 1 件あります"))
        }
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .open)
    }

    func testTransitionFiscalYearStateFailsWhenClosingEntryMissingForTaxClose() throws {
        seedClosingSourceJournals(year: 2025)

        XCTAssertThrowsError(
            try useCase.transitionFiscalYearState(.taxClose, for: 2025)
        ) { error in
            guard case .invalidInput(let message) = error as? AppError else {
                return XCTFail("Expected invalidInput error, got \(error)")
            }
            XCTAssertTrue(message.hasPrefix("年度締めを進められません:\n"))
            XCTAssertTrue(message.contains("税務締め以降へ進む前に決算仕訳の生成が必要です"))
        }
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .open)
    }

    func testTransitionFiscalYearStateSucceedsAfterClosingPreflightPasses() throws {
        seedClosingSourceJournals(year: 2025)

        let softClosed = try useCase.transitionFiscalYearState(.softClose, for: 2025)
        XCTAssertEqual(softClosed.yearLockState, .softClose)

        XCTAssertNotNil(try useCase.generateClosingEntry(for: 2025))

        let taxClosed = try useCase.transitionFiscalYearState(.taxClose, for: 2025)
        XCTAssertEqual(taxClosed.yearLockState, .taxClose)

        let filed = try useCase.transitionFiscalYearState(.filed, for: 2025)
        XCTAssertEqual(filed.yearLockState, .filed)
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .filed)
    }

    private func createApprovedJournal(
        debitLegacyAccountId: String,
        creditLegacyAccountId: String,
        amount: Int,
        year: Int
    ) {
        createCanonicalJournal(
            debitLegacyAccountId: debitLegacyAccountId,
            creditLegacyAccountId: creditLegacyAccountId,
            amount: amount,
            year: year,
            month: 6,
            day: 1,
            entryType: .normal,
            approved: true
        )
    }

    private func createCanonicalJournal(
        debitLegacyAccountId: String,
        creditLegacyAccountId: String,
        amount: Int,
        year: Int,
        month: Int,
        day: Int,
        entryType: CanonicalJournalEntryType,
        approved: Bool
    ) {
        let calendar = Calendar(identifier: .gregorian)
        let journalDate = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let journalId = UUID()

        let entry = CanonicalJournalEntry(
            id: journalId,
            businessId: currentBusinessId(),
            taxYear: year,
            journalDate: journalDate,
            voucherNo: VoucherNumber(taxYear: year, month: month, sequence: nextVoucherSequence(for: year)).value,
            entryType: entryType,
            description: "テスト",
            lines: [
                JournalLine(
                    journalId: journalId,
                    accountId: canonicalAccountId(debitLegacyAccountId),
                    debitAmount: Decimal(amount),
                    creditAmount: 0,
                    legalReportLineId: canonicalAccount(debitLegacyAccountId).defaultLegalReportLineId,
                    sortOrder: 0
                ),
                JournalLine(
                    journalId: journalId,
                    accountId: canonicalAccountId(creditLegacyAccountId),
                    debitAmount: 0,
                    creditAmount: Decimal(amount),
                    legalReportLineId: canonicalAccount(creditLegacyAccountId).defaultLegalReportLineId,
                    sortOrder: 1
                )
            ],
            approvedAt: approved ? journalDate : nil,
            createdAt: journalDate,
            updatedAt: journalDate
        )

        context.insert(CanonicalJournalEntryEntityMapper.toEntity(entry))
        try! context.save()
    }

    private func createPendingCandidate(year: Int, status: CandidateStatus) {
        let candidate = PostingCandidate(
            businessId: currentBusinessId(),
            taxYear: year,
            candidateDate: Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 6, day: 1))!,
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: UUID(),
                    creditAccountId: UUID(),
                    amount: Decimal(string: "1000")!
                )
            ],
            status: status,
            source: .manual
        )

        context.insert(PostingCandidateEntityMapper.toEntity(candidate))
        try! context.save()
    }

    private func seedClosingSourceJournals(year: Int) {
        createApprovedJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 100_000,
            year: year
        )
        createApprovedJournal(
            debitLegacyAccountId: AccountingConstants.miscExpenseAccountId,
            creditLegacyAccountId: AccountingConstants.cashAccountId,
            amount: 40_000,
            year: year
        )
    }

    private func canonicalAccountId(_ legacyId: String) -> UUID {
        try! XCTUnwrap(dataStore.canonicalAccounts().first(where: { $0.legacyAccountId == legacyId })?.id)
    }

    private func canonicalAccount(_ legacyId: String) -> CanonicalAccount {
        let accountId = canonicalAccountId(legacyId)
        return try! XCTUnwrap(dataStore.canonicalAccount(id: accountId))
    }

    private func nextVoucherSequence(for year: Int) -> Int {
        fetchCanonicalEntries(taxYear: year).count + 1
    }

    private func fetchCanonicalEntries(taxYear: Int) -> [CanonicalJournalEntry] {
        let businessId = currentBusinessId()
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate<JournalEntryEntity> {
                $0.businessId == businessId && $0.taxYear == taxYear
            }
        )
        return (try? context.fetch(descriptor).map(CanonicalJournalEntryEntityMapper.toDomain)) ?? []
    }

    private func fetchClosingEntries(taxYear: Int) -> [CanonicalJournalEntry] {
        fetchCanonicalEntries(taxYear: taxYear).filter { $0.entryType == .closing }
    }

    private func currentBusinessId() -> UUID {
        try! XCTUnwrap(dataStore.businessProfile?.id)
    }
}
