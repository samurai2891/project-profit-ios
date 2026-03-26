import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ClosingEntryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!
    var businessId: UUID!
    var accounts: [CanonicalAccount]!
    var useCase: ClosingEntryUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        businessId = dataStore.businessProfile?.id
        accounts = dataStore.canonicalAccounts()
        useCase = ClosingEntryUseCase(modelContext: context)
        XCTAssertNotNil(businessId)
        XCTAssertFalse(accounts.isEmpty)
    }

    override func tearDown() {
        accounts = nil
        businessId = nil
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testClosingEntry_Basic() {
        createApprovedJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 1_000_000,
            year: 2025
        )
        createApprovedJournal(
            debitLegacyAccountId: "acct-rent",
            creditLegacyAccountId: AccountingConstants.cashAccountId,
            amount: 600_000,
            year: 2025
        )

        let result = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )
        try! context.save()

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.entryType, .closing)
        XCTAssertNotNil(result?.approvedAt)

        let closingLines = result!.lines.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(closingLines.count, 3)

        let revenueLine = closingLines.first { $0.accountId == canonicalAccountId(AccountingConstants.salesAccountId) }
        XCTAssertEqual(decimalInt(revenueLine?.debitAmount), 1_000_000)
        XCTAssertEqual(decimalInt(revenueLine?.creditAmount), 0)

        let expenseLine = closingLines.first { $0.accountId == canonicalAccountId("acct-rent") }
        XCTAssertEqual(decimalInt(expenseLine?.debitAmount), 0)
        XCTAssertEqual(decimalInt(expenseLine?.creditAmount), 600_000)

        let capitalLine = closingLines.first { $0.accountId == canonicalAccountId(AccountingConstants.ownerCapitalAccountId) }
        XCTAssertEqual(decimalInt(capitalLine?.debitAmount), 0)
        XCTAssertEqual(decimalInt(capitalLine?.creditAmount), 400_000)
    }

    func testClosingEntry_NetLoss() {
        createApprovedJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 300_000,
            year: 2025
        )
        createApprovedJournal(
            debitLegacyAccountId: "acct-rent",
            creditLegacyAccountId: AccountingConstants.cashAccountId,
            amount: 500_000,
            year: 2025
        )

        let result = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )
        try! context.save()

        let capitalLine = result?.lines.first { $0.accountId == canonicalAccountId(AccountingConstants.ownerCapitalAccountId) }
        XCTAssertEqual(decimalInt(capitalLine?.debitAmount), 200_000)
        XCTAssertEqual(decimalInt(capitalLine?.creditAmount), 0)
    }

    func testClosingEntry_Idempotent() {
        createApprovedJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 100_000,
            year: 2025
        )

        let first = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )
        try! context.save()

        let second = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )

        XCTAssertEqual(first?.id, second?.id)
    }

    func testClosingEntry_Delete() {
        createApprovedJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 100_000,
            year: 2025
        )

        _ = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )
        try! context.save()

        try! useCase.delete(businessId: businessId, taxYear: 2025)
        try! context.save()

        XCTAssertTrue(fetchClosingEntries(taxYear: 2025).isEmpty)
    }

    func testClosingEntry_Regenerate() {
        createApprovedJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 100_000,
            year: 2025
        )

        let first = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )
        try! context.save()

        try! useCase.delete(businessId: businessId, taxYear: 2025)
        try! context.save()

        let second = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )
        try! context.save()

        XCTAssertNotEqual(first?.id, second?.id)
    }

    func testClosingEntry_NoRevenueOrExpense() {
        let result = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )
        XCTAssertNil(result)
    }

    func testReports_ExcludeClosingEntries() {
        createApprovedJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 500_000,
            year: 2025
        )
        createApprovedJournal(
            debitLegacyAccountId: "acct-rent",
            creditLegacyAccountId: AccountingConstants.cashAccountId,
            amount: 200_000,
            year: 2025
        )

        _ = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )
        try! context.save()

        let profitLoss = AccountingReportService.generateProfitLoss(
            fiscalYear: 2025,
            accounts: accounts,
            journals: fetchCanonicalEntries(taxYear: 2025)
        )

        XCTAssertEqual(decimalInt(profitLoss.totalRevenue), 500_000)
        XCTAssertEqual(decimalInt(profitLoss.totalExpenses), 200_000)
        XCTAssertEqual(decimalInt(profitLoss.netIncome), 300_000)
    }

    func testClosingEntry_IncludesCanonicalOpeningEntry() {
        createCanonicalJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.ownerCapitalAccountId,
            amount: 120_000,
            year: 2025,
            month: 1,
            day: 1,
            entryType: .opening,
            approved: true
        )
        createApprovedJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 300_000,
            year: 2025
        )
        createApprovedJournal(
            debitLegacyAccountId: "acct-rent",
            creditLegacyAccountId: AccountingConstants.cashAccountId,
            amount: 50_000,
            year: 2025
        )

        let result = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )
        try! context.save()

        let capitalLine = result?.lines.first { $0.accountId == canonicalAccountId(AccountingConstants.ownerCapitalAccountId) }
        XCTAssertEqual(decimalInt(capitalLine?.creditAmount), 250_000)
        XCTAssertEqual(decimalInt(capitalLine?.debitAmount), 0)
    }

    func testClosingEntry_ExcludesUnapprovedCanonicalEntry() {
        createCanonicalJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 999_999,
            year: 2025,
            approved: false
        )

        let result = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )

        XCTAssertNil(result)
    }

    func testClosingEntry_IgnoresLegacySupplementalEntries() {
        createLegacySupplementalEntry(
            sourceKey: "manual:\(UUID().uuidString)",
            year: 2025,
            debitAccountId: AccountingConstants.cashAccountId,
            creditAccountId: AccountingConstants.salesAccountId,
            amount: 700_000
        )

        let result = try! useCase.generate(
            businessId: businessId,
            taxYear: 2025
        )

        XCTAssertNil(result)
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
            approved: true
        )
    }

    private func createCanonicalJournal(
        debitLegacyAccountId: String,
        creditLegacyAccountId: String,
        amount: Int,
        year: Int,
        month: Int = 6,
        day: Int = 15,
        entryType: CanonicalJournalEntryType = .normal,
        approved: Bool
    ) {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let journalId = UUID()
        let entry = CanonicalJournalEntry(
            id: journalId,
            businessId: businessId,
            taxYear: year,
            journalDate: date,
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
                ),
            ],
            approvedAt: approved ? date : nil,
            createdAt: date,
            updatedAt: date
        )
        context.insert(CanonicalJournalEntryEntityMapper.toEntity(entry))
        try! context.save()
    }

    private func fetchCanonicalEntries(taxYear: Int) -> [CanonicalJournalEntry] {
        let currentBusinessId = businessId!
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.businessId == currentBusinessId && $0.taxYear == taxYear },
            sortBy: [SortDescriptor(\.journalDate)]
        )
        return (try? context.fetch(descriptor).map(CanonicalJournalEntryEntityMapper.toDomain)) ?? []
    }

    private func fetchClosingEntries(taxYear: Int) -> [CanonicalJournalEntry] {
        fetchCanonicalEntries(taxYear: taxYear).filter { $0.entryType == .closing }
    }

    private func createLegacySupplementalEntry(
        sourceKey: String,
        year: Int,
        debitAccountId: String,
        creditAccountId: String,
        amount: Int
    ) {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: year, month: 6, day: 15))!
        let entry = PPJournalEntry(
            sourceKey: sourceKey,
            date: date,
            entryType: .manual,
            memo: "legacy supplemental",
            isPosted: true
        )
        context.insert(entry)
        context.insert(
            PPJournalLine(
                entryId: entry.id,
                accountId: debitAccountId,
                debit: amount,
                credit: 0,
                displayOrder: 0
            )
        )
        context.insert(
            PPJournalLine(
                entryId: entry.id,
                accountId: creditAccountId,
                debit: 0,
                credit: amount,
                displayOrder: 1
            )
        )
        try! context.save()
    }

    private func canonicalAccount(_ legacyAccountId: String) -> CanonicalAccount {
        guard let account = accounts.first(where: { $0.legacyAccountId == legacyAccountId }) else {
            XCTFail("Canonical account not found for \(legacyAccountId)")
            fatalError("Canonical account not found for \(legacyAccountId)")
        }
        return account
    }

    private func canonicalAccountId(_ legacyAccountId: String) -> UUID {
        canonicalAccount(legacyAccountId).id
    }

    private func decimalInt(_ value: Decimal?) -> Int {
        guard let value else { return 0 }
        return NSDecimalNumber(decimal: value).intValue
    }

    private func nextVoucherSequence(for taxYear: Int) -> Int {
        fetchCanonicalEntries(taxYear: taxYear).count + 1
    }
}
