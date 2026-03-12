import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class CanonicalUseCasesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    func testEvidenceCatalogUseCaseLoadsEvidenceAndVersions() async throws {
        let useCase = EvidenceCatalogUseCase(modelContext: context)
        let businessId = UUID()
        let evidence = EvidenceDocument(
            businessId: businessId,
            taxYear: 2026,
            sourceType: .importedPDF,
            legalDocumentType: .invoice,
            storageCategory: .electronicTransaction,
            originalFilename: "invoice.pdf",
            mimeType: "application/pdf",
            fileHash: "hash-1",
            originalFilePath: "/tmp/invoice.pdf"
        )
        let version = EvidenceVersion(
            evidenceId: evidence.id,
            changedBy: "reviewer",
            nextStructuredFields: EvidenceStructuredFields(totalAmount: Decimal(string: "12000")!),
            reason: "ocr-fix",
            modelSource: .user
        )

        try await useCase.save(evidence)
        try await useCase.saveVersion(version)

        let loaded = try await useCase.loadEvidence(businessId: businessId, taxYear: 2026)
        let versions = try await useCase.versions(evidenceId: evidence.id)

        XCTAssertEqual(loaded.map(\.id), [evidence.id])
        XCTAssertEqual(versions.map(\.id), [version.id])
    }

    func testCounterpartyMasterUseCaseSearchesCounterparties() async throws {
        let useCase = CounterpartyMasterUseCase(modelContext: context)
        let businessId = UUID()
        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "山田商事",
            invoiceRegistrationNumber: "T9999999999999",
            invoiceIssuerStatus: .registered
        )

        try await useCase.save(counterparty)

        let searched = try await useCase.searchCounterparties(businessId: businessId, query: "山田")
        let registered = try await useCase.findByRegistrationNumber("T9999999999999")

        XCTAssertEqual(searched.map(\.id), [counterparty.id])
        XCTAssertEqual(registered?.id, counterparty.id)
    }

    func testChartOfAccountsUseCaseLoadsAccountsByTypeAndCode() async throws {
        let useCase = ChartOfAccountsUseCase(modelContext: context)
        let businessId = UUID()
        let expenseAccount = CanonicalAccount(
            businessId: businessId,
            code: "505",
            name: "広告宣伝費",
            accountType: .expense,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.advertising.rawValue,
            displayOrder: 1
        )
        let assetAccount = CanonicalAccount(
            businessId: businessId,
            code: "101",
            name: "現金",
            accountType: .asset,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.cash.rawValue,
            displayOrder: 2
        )

        try await useCase.save(expenseAccount)
        try await useCase.save(assetAccount)

        let loaded = try await useCase.accounts(businessId: businessId, type: .expense)
        let byCode = try await useCase.account(businessId: businessId, code: "101")

        XCTAssertEqual(loaded.map(\.id), [expenseAccount.id])
        XCTAssertEqual(byCode?.id, assetAccount.id)
    }

    func testChartOfAccountsUseCaseRejectsMissingLegalReportLine() async {
        let useCase = ChartOfAccountsUseCase(modelContext: context)
        let account = CanonicalAccount(
            businessId: UUID(),
            code: "999",
            name: "未設定科目",
            accountType: .expense,
            normalBalance: .debit,
            displayOrder: 1
        )

        await XCTAssertThrowsErrorAsync {
            try await useCase.save(account)
        }
    }

    func testDistributionTemplateUseCaseReturnsOnlyActiveRules() async throws {
        let useCase = DistributionTemplateUseCase(modelContext: context)
        let businessId = UUID()
        let currentRule = DistributionRule(
            businessId: businessId,
            name: "現行配賦",
            scope: .allProjects,
            basis: .equal,
            effectiveFrom: Date(timeIntervalSince1970: 1_735_689_600),
            effectiveTo: nil
        )
        let futureRule = DistributionRule(
            businessId: businessId,
            name: "将来配賦",
            scope: .selectedProjects,
            basis: .fixedWeight,
            weights: [DistributionWeight(projectId: UUID(), weight: Decimal(string: "1.0")!)],
            effectiveFrom: Date(timeIntervalSince1970: 1_767_225_600),
            effectiveTo: nil
        )

        try await useCase.save(currentRule)
        try await useCase.save(futureRule)

        let active = try await useCase.activeRules(
            businessId: businessId,
            at: Date(timeIntervalSince1970: 1_736_553_600)
        )

        XCTAssertEqual(active.map(\.id), [currentRule.id])
    }

    func testPostingWorkflowUseCaseApprovesCandidateIntoBalancedJournal() async throws {
        let useCase = PostingWorkflowUseCase(modelContext: context)
        let businessId = UUID()
        let debitAccountId = UUID()
        let creditAccountId = UUID()
        try await seedAccount(
            id: debitAccountId,
            businessId: businessId,
            code: "501",
            name: "接待交際費",
            accountType: .expense,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.entertainment.rawValue
        )
        try await seedAccount(
            id: creditAccountId,
            businessId: businessId,
            code: "101",
            name: "現金",
            accountType: .asset,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.cash.rawValue
        )
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: 2025,
            candidateDate: Date(timeIntervalSince1970: 1_741_478_400),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: debitAccountId,
                    creditAccountId: creditAccountId,
                    amount: Decimal(string: "8800")!,
                    taxCodeId: "TAX-10",
                    memo: "接待交際費"
                )
            ],
            status: .needsReview,
            source: .manual,
            memo: "会食"
        )

        try await useCase.saveCandidate(candidate)
        let entry = try await useCase.approveCandidate(candidateId: candidate.id)
        let approvedCandidates = try await useCase.candidates(businessId: businessId, status: .approved)
        let journals = try await useCase.journals(businessId: businessId, taxYear: 2025)
        let auditEvents = try context.fetch(FetchDescriptor<AuditEventEntity>())

        XCTAssertEqual(entry.lines.count, 2)
        XCTAssertTrue(entry.isBalanced)
        XCTAssertEqual(entry.voucherNo, "2025-003-00001")
        XCTAssertEqual(Set(entry.lines.compactMap(\.legalReportLineId)), Set([LegalReportLine.entertainment.rawValue, LegalReportLine.cash.rawValue]))
        XCTAssertEqual(approvedCandidates.map(\.id), [candidate.id])
        XCTAssertEqual(journals.map(\.id), [entry.id])
        XCTAssertEqual(
            Set(auditEvents.map(\.eventTypeRaw)),
            Set([AuditEventType.candidateApproved.rawValue, AuditEventType.journalApproved.rawValue])
        )
    }

    func testPostingWorkflowUseCaseRejectCandidateStoresAuditEvent() async throws {
        let useCase = PostingWorkflowUseCase(modelContext: context)
        let businessId = UUID()
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: 2025,
            candidateDate: Date(timeIntervalSince1970: 1_741_478_400),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: UUID(),
                    creditAccountId: UUID(),
                    amount: Decimal(string: "1800")!,
                    memo: "reject"
                )
            ],
            status: .needsReview,
            source: .manual,
            memo: "reject"
        )

        try await useCase.saveCandidate(candidate)
        let rejected = try await useCase.rejectCandidate(candidate.id)
        let auditEvents = try context.fetch(FetchDescriptor<AuditEventEntity>())

        XCTAssertEqual(rejected.status, .rejected)
        XCTAssertEqual(auditEvents.map(\.eventTypeRaw), [AuditEventType.candidateRejected.rawValue])
    }

    func testPostingWorkflowUseCaseCancelJournalCreatesReversalAndAuditEvent() async throws {
        let useCase = PostingWorkflowUseCase(modelContext: context)
        let businessId = UUID()
        let debitAccountId = UUID()
        let creditAccountId = UUID()
        try await seedAccount(
            id: debitAccountId,
            businessId: businessId,
            code: "502",
            name: "通信費",
            accountType: .expense,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.communication.rawValue
        )
        try await seedAccount(
            id: creditAccountId,
            businessId: businessId,
            code: "101",
            name: "現金",
            accountType: .asset,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.cash.rawValue
        )
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: 2025,
            candidateDate: Date(timeIntervalSince1970: 1_741_478_400),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: debitAccountId,
                    creditAccountId: creditAccountId,
                    amount: Decimal(string: "4200")!,
                    memo: "cancel"
                )
            ],
            status: .needsReview,
            source: .manual,
            memo: "cancel"
        )

        try await useCase.saveCandidate(candidate)
        let approved = try await useCase.approveCandidate(candidateId: candidate.id)
        let reversal = try await useCase.cancelJournal(journalId: approved.id, reason: "取消")
        let persistedOriginal = try await useCase.journal(approved.id)
        let journals = try await useCase.journals(businessId: businessId, taxYear: 2025)
        let auditEvents = try context.fetch(FetchDescriptor<AuditEventEntity>())

        XCTAssertEqual(reversal.entryType, .reversal)
        XCTAssertTrue(reversal.isBalanced)
        XCTAssertNotNil(persistedOriginal?.lockedAt)
        XCTAssertEqual(journals.map(\.id).count, 2)
        XCTAssertTrue(
            auditEvents.contains { $0.eventTypeRaw == AuditEventType.journalCancelled.rawValue }
        )
    }

    func testPostingWorkflowUseCaseReopenCandidateCreatesNeedsReviewCopy() async throws {
        let useCase = PostingWorkflowUseCase(modelContext: context)
        let businessId = UUID()
        let debitAccountId = UUID()
        let creditAccountId = UUID()
        try await seedAccount(
            id: debitAccountId,
            businessId: businessId,
            code: "503",
            name: "旅費交通費",
            accountType: .expense,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.travelTransport.rawValue
        )
        try await seedAccount(
            id: creditAccountId,
            businessId: businessId,
            code: "101",
            name: "現金",
            accountType: .asset,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.cash.rawValue
        )
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: 2025,
            candidateDate: Date(timeIntervalSince1970: 1_741_478_400),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: debitAccountId,
                    creditAccountId: creditAccountId,
                    amount: Decimal(string: "7300")!,
                    taxCodeId: "TAX-10",
                    memo: "reopen"
                )
            ],
            status: .needsReview,
            source: .ocr,
            memo: "reopen"
        )

        try await useCase.saveCandidate(candidate)
        let approved = try await useCase.approveCandidate(candidateId: candidate.id)
        _ = try await useCase.cancelJournal(journalId: approved.id, reason: "reopen")
        let reopened = try await useCase.reopenCandidate(fromJournalId: approved.id, reason: "再レビュー")
        let pending = try await useCase.candidates(businessId: businessId, status: .needsReview)
        let auditEvents = try context.fetch(FetchDescriptor<AuditEventEntity>())

        XCTAssertNotEqual(reopened.id, candidate.id)
        XCTAssertEqual(reopened.status, .needsReview)
        XCTAssertEqual(reopened.proposedLines, candidate.proposedLines)
        XCTAssertEqual(reopened.source, candidate.source)
        XCTAssertEqual(pending.map(\.id), [reopened.id])
        XCTAssertTrue(
            auditEvents.contains { $0.eventTypeRaw == AuditEventType.candidateCreated.rawValue }
        )
    }

    func testPostingWorkflowUseCaseCancelAndReopenJournalCreatesReversalAndCandidateTogether() async throws {
        let useCase = PostingWorkflowUseCase(modelContext: context)
        let businessId = UUID()
        let debitAccountId = UUID()
        let creditAccountId = UUID()
        try await seedAccount(
            id: debitAccountId,
            businessId: businessId,
            code: "504",
            name: "通信費",
            accountType: .expense,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.communication.rawValue
        )
        try await seedAccount(
            id: creditAccountId,
            businessId: businessId,
            code: "102",
            name: "普通預金",
            accountType: .asset,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.deposits.rawValue
        )
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: 2025,
            candidateDate: Date(timeIntervalSince1970: 1_741_478_400),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: debitAccountId,
                    creditAccountId: creditAccountId,
                    amount: Decimal(string: "5100")!,
                    memo: "atomic"
                )
            ],
            status: .needsReview,
            source: .manual,
            memo: "atomic"
        )

        try await useCase.saveCandidate(candidate)
        let approved = try await useCase.approveCandidate(candidateId: candidate.id)
        let result = try await useCase.cancelAndReopenJournal(journalId: approved.id, reason: "差戻し")
        let persistedOriginal = try await useCase.journal(approved.id)
        let journals = try await useCase.journals(businessId: businessId, taxYear: 2025)
        let pending = try await useCase.candidates(businessId: businessId, status: .needsReview)

        XCTAssertEqual(result.reversal.entryType, .reversal)
        XCTAssertEqual(result.reopened.status, .needsReview)
        XCTAssertNotNil(persistedOriginal?.lockedAt)
        XCTAssertEqual(journals.count, 2)
        XCTAssertEqual(pending.map(\.id), [result.reopened.id])
    }

    func testPostingWorkflowUseCaseSyncApprovedCandidateRollsBackStatusWhenJournalSaveFails() async throws {
        let businessId = UUID()
        let debitAccountId = UUID()
        let creditAccountId = UUID()
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: 2025,
            candidateDate: Date(timeIntervalSince1970: 1_741_478_400),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: debitAccountId,
                    creditAccountId: creditAccountId,
                    amount: Decimal(string: "1200")!,
                    memo: "rollback"
                )
            ],
            status: .needsReview,
            source: .manual,
            memo: "rollback"
        )
        let candidateRepository = InMemoryPostingCandidateRepository(initialCandidates: [candidate])
        let journalRepository = FailingCanonicalJournalEntryRepository()
        let chartRepository = InMemoryChartOfAccountsRepository(
            initialAccounts: [
                seededAccount(
                    id: debitAccountId,
                    businessId: businessId,
                    code: "505",
                    name: "広告宣伝費",
                    accountType: .expense,
                    normalBalance: .debit,
                    defaultLegalReportLineId: LegalReportLine.advertising.rawValue
                ),
                seededAccount(
                    id: creditAccountId,
                    businessId: businessId,
                    code: "101",
                    name: "現金",
                    accountType: .asset,
                    normalBalance: .debit,
                    defaultLegalReportLineId: LegalReportLine.cash.rawValue
                ),
            ]
        )
        let useCase = PostingWorkflowUseCase(
            postingCandidateRepository: candidateRepository,
            journalEntryRepository: journalRepository
            ,
            chartOfAccountsRepository: chartRepository
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await useCase.syncApprovedCandidate(candidate, journalId: UUID())
        }

        let persisted = try await candidateRepository.findById(candidate.id)
        XCTAssertEqual(persisted?.status, .needsReview)
        let savedEntryCount = await journalRepository.savedEntryCount()
        XCTAssertEqual(savedEntryCount, 0)
    }

    private func seedAccount(
        id: UUID,
        businessId: UUID,
        code: String,
        name: String,
        accountType: CanonicalAccountType,
        normalBalance: NormalBalance,
        defaultLegalReportLineId: String
    ) async throws {
        try await SwiftDataChartOfAccountsRepository(modelContext: context).save(
            seededAccount(
                id: id,
                businessId: businessId,
                code: code,
                name: name,
                accountType: accountType,
                normalBalance: normalBalance,
                defaultLegalReportLineId: defaultLegalReportLineId
            )
        )
    }

    private func seededAccount(
        id: UUID,
        businessId: UUID,
        code: String,
        name: String,
        accountType: CanonicalAccountType,
        normalBalance: NormalBalance,
        defaultLegalReportLineId: String
    ) -> CanonicalAccount {
        CanonicalAccount(
            id: id,
            businessId: businessId,
            code: code,
            name: name,
            accountType: accountType,
            normalBalance: normalBalance,
            defaultLegalReportLineId: defaultLegalReportLineId,
            displayOrder: 0
        )
    }
}

private actor InMemoryPostingCandidateRepository: PostingCandidateRepository {
    private var storage: [UUID: PostingCandidate]

    init(initialCandidates: [PostingCandidate] = []) {
        self.storage = Dictionary(uniqueKeysWithValues: initialCandidates.map { ($0.id, $0) })
    }

    func findById(_ id: UUID) async throws -> PostingCandidate? {
        storage[id]
    }

    func findByIds(_ ids: Set<UUID>) async throws -> [PostingCandidate] {
        guard !ids.isEmpty else { return [] }
        return storage.values.filter { ids.contains($0.id) }
    }

    func findByEvidence(evidenceId: UUID) async throws -> [PostingCandidate] {
        storage.values.filter { $0.evidenceId == evidenceId }
    }

    func findByStatus(businessId: UUID, status: CandidateStatus) async throws -> [PostingCandidate] {
        storage.values.filter { $0.businessId == businessId && $0.status == status }
    }

    func save(_ candidate: PostingCandidate) async throws {
        storage[candidate.id] = candidate
    }

    func delete(_ id: UUID) async throws {
        storage[id] = nil
    }
}

private actor FailingCanonicalJournalEntryRepository: CanonicalJournalEntryRepository {
    enum Failure: Error {
        case saveFailed
    }

    private(set) var savedEntries: [CanonicalJournalEntry] = []

    func savedEntryCount() -> Int {
        savedEntries.count
    }

    func findById(_ id: UUID) async throws -> CanonicalJournalEntry? {
        savedEntries.first { $0.id == id }
    }

    func findAllByBusiness(businessId: UUID) async throws -> [CanonicalJournalEntry] {
        savedEntries.filter { $0.businessId == businessId }
    }

    func findByBusinessAndYear(businessId: UUID, taxYear: Int) async throws -> [CanonicalJournalEntry] {
        savedEntries.filter { $0.businessId == businessId && $0.taxYear == taxYear }
    }

    func findByDateRange(businessId: UUID, from: Date, to: Date) async throws -> [CanonicalJournalEntry] {
        savedEntries.filter { $0.businessId == businessId && from ... to ~= $0.journalDate }
    }

    func findByEvidence(evidenceId: UUID) async throws -> [CanonicalJournalEntry] {
        savedEntries.filter { $0.sourceEvidenceId == evidenceId }
    }

    func save(_ entry: CanonicalJournalEntry) async throws {
        throw Failure.saveFailed
    }

    func delete(_ id: UUID) async throws {
        savedEntries.removeAll { $0.id == id }
    }

    func nextVoucherNumber(businessId: UUID, taxYear: Int, month: Int) async throws -> VoucherNumber {
        VoucherNumber(taxYear: taxYear, month: month, sequence: 1)
    }
}

private actor InMemoryChartOfAccountsRepository: ChartOfAccountsRepository {
    private var storage: [UUID: CanonicalAccount]

    init(initialAccounts: [CanonicalAccount] = []) {
        storage = Dictionary(uniqueKeysWithValues: initialAccounts.map { ($0.id, $0) })
    }

    func findById(_ id: UUID) async throws -> CanonicalAccount? {
        storage[id]
    }

    func findByLegacyId(businessId: UUID, legacyAccountId: String) async throws -> CanonicalAccount? {
        storage.values.first { $0.businessId == businessId && $0.legacyAccountId == legacyAccountId }
    }

    func findByCode(businessId: UUID, code: String) async throws -> CanonicalAccount? {
        storage.values.first { $0.businessId == businessId && $0.code == code }
    }

    func findAllByBusiness(businessId: UUID) async throws -> [CanonicalAccount] {
        storage.values.filter { $0.businessId == businessId }
    }

    func findByType(businessId: UUID, accountType: CanonicalAccountType) async throws -> [CanonicalAccount] {
        storage.values.filter { $0.businessId == businessId && $0.accountType == accountType }
    }

    func save(_ account: CanonicalAccount) async throws {
        storage[account.id] = account
    }

    func delete(_ id: UUID) async throws {
        storage[id] = nil
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {}
}
