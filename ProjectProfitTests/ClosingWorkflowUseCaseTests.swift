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
        context = container.mainContext
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = ClosingWorkflowUseCase(modelContext: context)
        XCTAssertNotNil(dataStore.businessProfile?.id)
    }

    override func tearDown() {
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
        XCTAssertTrue(mutations(dataStore).transitionFiscalYearState(.softClose, for: 2025))

        createApprovedJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 100_000,
            year: 2025
        )

        let entry = try? useCase.generateClosingEntry(for: 2025)

        XCTAssertNil(entry)
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .softClose)
    }

    func testTransitionFiscalYearStateDelegatesValidatedTransition() throws {
        let transitioned = try useCase.transitionFiscalYearState(.softClose, for: 2025)

        XCTAssertEqual(transitioned.yearLockState, .softClose)
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .softClose)
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
