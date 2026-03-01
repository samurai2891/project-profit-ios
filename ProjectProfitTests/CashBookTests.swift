import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class CashBookTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - 1. Cash Sale (現金売上 column)

    /// Dr cash 50000 / Cr sales 50000
    /// entry.debit=50000, entry.counterAccountId="acct-sales"
    func testCashSale_DebitWithSalesCounterAccount() {
        dataStore.addManualJournalEntry(
            date: date(2025, 6, 15),
            memo: "現金売上",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 50_000, credit: 0, memo: "入金"),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 50_000, memo: "売上"),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.debit, 50_000)
        XCTAssertEqual(entry.credit, 0)
        XCTAssertEqual(entry.counterAccountId, AccountingConstants.salesAccountId)
        XCTAssertEqual(entry.accountId, AccountingConstants.cashAccountId)
    }

    // MARK: - 2. Cash Purchase (現金仕入 column)

    /// Dr purchases 30000 / Cr cash 30000
    /// entry.credit=30000, entry.counterAccountId="acct-purchases"
    func testCashPurchase_CreditWithPurchasesCounterAccount() {
        dataStore.addManualJournalEntry(
            date: date(2025, 7, 10),
            memo: "仕入",
            lines: [
                (accountId: AccountingConstants.purchasesAccountId, debit: 30_000, credit: 0, memo: "仕入"),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 30_000, memo: "出金"),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.credit, 30_000)
        XCTAssertEqual(entry.debit, 0)
        XCTAssertEqual(entry.counterAccountId, AccountingConstants.purchasesAccountId)
    }

    // MARK: - 3. Other Deposit (その他入金 column)

    /// Dr cash 20000 / Cr ar 20000 (売掛金回収)
    /// entry.debit=20000, entry.counterAccountId="acct-ar"
    func testOtherDeposit_DebitWithNonSalesCounter() {
        dataStore.addManualJournalEntry(
            date: date(2025, 8, 1),
            memo: "売掛金回収",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 20_000, credit: 0, memo: "入金"),
                (accountId: AccountingConstants.accountsReceivableAccountId, debit: 0, credit: 20_000, memo: "売掛金"),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.debit, 20_000)
        XCTAssertEqual(entry.credit, 0)
        XCTAssertEqual(entry.counterAccountId, AccountingConstants.accountsReceivableAccountId)
        // View logic: debit > 0 && counterAccountId != salesAccountId -> その他入金
        XCTAssertNotEqual(entry.counterAccountId, AccountingConstants.salesAccountId)
    }

    // MARK: - 4. Other Withdrawal (その他出金 column)

    /// Dr rent 80000 / Cr cash 80000
    /// entry.credit=80000, entry.counterAccountId="acct-rent"
    func testOtherWithdrawal_CreditWithNonPurchasesCounter() {
        dataStore.addManualJournalEntry(
            date: date(2025, 9, 1),
            memo: "家賃支払",
            lines: [
                (accountId: "acct-rent", debit: 80_000, credit: 0, memo: "地代家賃"),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 80_000, memo: "出金"),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.credit, 80_000)
        XCTAssertEqual(entry.debit, 0)
        XCTAssertEqual(entry.counterAccountId, "acct-rent")
        // View logic: credit > 0 && counterAccountId != purchasesAccountId -> その他出金
        XCTAssertNotEqual(entry.counterAccountId, AccountingConstants.purchasesAccountId)
    }

    // MARK: - 5. Running Balance increments on debit

    /// 2 deposits (50000, 30000) -> running balances 50000, 80000
    func testRunningBalance_IncrementsOnDebit() {
        dataStore.addManualJournalEntry(
            date: date(2025, 3, 1),
            memo: "入金1",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 50_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 50_000, memo: ""),
            ]
        )

        dataStore.addManualJournalEntry(
            date: date(2025, 3, 5),
            memo: "入金2",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 30_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 30_000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].runningBalance, 50_000)
        XCTAssertEqual(entries[1].runningBalance, 80_000)
    }

    // MARK: - 6. Running Balance decrements on credit

    /// Deposit 100000 then withdrawal 40000 -> balances 100000, 60000
    func testRunningBalance_DecrementsOnCredit() {
        dataStore.addManualJournalEntry(
            date: date(2025, 4, 1),
            memo: "入金",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 100_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 100_000, memo: ""),
            ]
        )

        dataStore.addManualJournalEntry(
            date: date(2025, 4, 10),
            memo: "出金",
            lines: [
                (accountId: "acct-rent", debit: 40_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 40_000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].runningBalance, 100_000)
        XCTAssertEqual(entries[1].runningBalance, 60_000)
    }

    // MARK: - 7. Chronological order

    /// Entries from Jan, Feb, Mar -> sorted by date ascending
    func testMultipleTransactions_ChronologicalOrder() {
        // Insert in reverse order to verify sorting
        dataStore.addManualJournalEntry(
            date: date(2025, 3, 15),
            memo: "3月取引",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 10_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 10_000, memo: ""),
            ]
        )

        dataStore.addManualJournalEntry(
            date: date(2025, 1, 10),
            memo: "1月取引",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 20_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 20_000, memo: ""),
            ]
        )

        dataStore.addManualJournalEntry(
            date: date(2025, 2, 20),
            memo: "2月取引",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 15_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 15_000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].memo, "1月取引")
        XCTAssertEqual(entries[1].memo, "2月取引")
        XCTAssertEqual(entries[2].memo, "3月取引")

        // Verify dates are ascending
        XCTAssertTrue(entries[0].date < entries[1].date)
        XCTAssertTrue(entries[1].date < entries[2].date)
    }

    // MARK: - 8. Year filter

    /// 2025 and 2026 entries, filter for 2025 only
    func testCashBook_YearFilter() {
        dataStore.addManualJournalEntry(
            date: date(2025, 6, 1),
            memo: "2025年取引",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 30_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 30_000, memo: ""),
            ]
        )

        dataStore.addManualJournalEntry(
            date: date(2026, 1, 15),
            memo: "2026年取引",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 50_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 50_000, memo: ""),
            ]
        )

        let entries2025 = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries2025.count, 1)
        XCTAssertEqual(entries2025[0].memo, "2025年取引")
        XCTAssertEqual(entries2025[0].debit, 30_000)

        // Verify 2026 entries exist when queried for 2026
        let entries2026 = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 12, 31)
        )

        XCTAssertEqual(entries2026.count, 1)
        XCTAssertEqual(entries2026[0].memo, "2026年取引")
    }

    // MARK: - 9. Empty when no entries

    /// No cash entries -> empty array
    func testCashBook_EmptyWhenNoEntries() {
        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - 10. Mixed income/expense running balance

    /// January: sale 100k, rent -50k, sale 80k, supplies -20k
    /// Running balances: 100k, 50k, 130k, 110k
    func testCashBook_MixedIncomeExpense_RunningBalance() {
        // Sale 100,000
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 5),
            memo: "売上1",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 100_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 100_000, memo: ""),
            ]
        )

        // Rent payment 50,000
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 10),
            memo: "家賃",
            lines: [
                (accountId: "acct-rent", debit: 50_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 50_000, memo: ""),
            ]
        )

        // Sale 80,000
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 15),
            memo: "売上2",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 80_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 80_000, memo: ""),
            ]
        )

        // Supplies 20,000
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 20),
            memo: "消耗品",
            lines: [
                (accountId: "acct-supplies", debit: 20_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 20_000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 1, 31)
        )

        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].runningBalance, 100_000)
        XCTAssertEqual(entries[1].runningBalance, 50_000)
        XCTAssertEqual(entries[2].runningBalance, 130_000)
        XCTAssertEqual(entries[3].runningBalance, 110_000)

        // Verify NTA column classification for each entry
        // Entry 0: debit=100k, counter=sales -> 現金売上
        XCTAssertEqual(entries[0].debit, 100_000)
        XCTAssertEqual(entries[0].counterAccountId, AccountingConstants.salesAccountId)

        // Entry 1: credit=50k, counter=rent -> その他出金
        XCTAssertEqual(entries[1].credit, 50_000)
        XCTAssertEqual(entries[1].counterAccountId, "acct-rent")

        // Entry 2: debit=80k, counter=sales -> 現金売上
        XCTAssertEqual(entries[2].debit, 80_000)
        XCTAssertEqual(entries[2].counterAccountId, AccountingConstants.salesAccountId)

        // Entry 3: credit=20k, counter=supplies -> その他出金
        XCTAssertEqual(entries[3].credit, 20_000)
        XCTAssertEqual(entries[3].counterAccountId, "acct-supplies")
    }

    // MARK: - 11. Compound entry max-amount counter account heuristic

    /// Dr cash 10000 / Cr sales 7000 + Cr other-income 3000
    /// counterAccountId = "acct-sales" (max amount heuristic)
    func testCompoundEntry_MaxAmountCounterAccount() {
        dataStore.addManualJournalEntry(
            date: date(2025, 5, 1),
            memo: "複合仕訳",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 10_000, credit: 0, memo: "入金"),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 7_000, memo: "売上"),
                (accountId: AccountingConstants.otherIncomeAccountId, debit: 0, credit: 3_000, memo: "雑収入"),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.debit, 10_000)
        // Max amount sibling line: sales=7000 > other-income=3000
        // The SubLedger code picks max(by: $0.amount < $1.amount) from sibling lines
        // PPJournalLine.amount = max(debit, credit), so sales line amount=7000
        XCTAssertEqual(entry.counterAccountId, AccountingConstants.salesAccountId)
    }

    // MARK: - 12. Tax category marks via PPTransaction

    /// Transaction with reducedRate -> entry.taxCategory = .reducedRate
    func testCashBook_TaxMarks() {
        let project = dataStore.addProject(name: "税テスト", description: "")

        _ = dataStore.addTransaction(
            type: .expense,
            amount: 1_080,
            date: date(2025, 10, 5),
            categoryId: "cat-supplies",
            memo: "軽減税率品",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: AccountingConstants.cashAccountId,
            taxAmount: 80,
            taxRate: 8,
            isTaxIncluded: true,
            taxCategory: .reducedRate
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        // Cash line should appear in cash book (credit side since expense)
        let cashEntries = entries.filter { $0.credit > 0 }
        XCTAssertFalse(cashEntries.isEmpty, "Should have a cash credit entry for the expense")

        // taxCategory is pulled from the source PPTransaction
        let taxEntry = cashEntries.first { $0.taxCategory == .reducedRate }
        XCTAssertNotNil(taxEntry, "Cash book entry should carry reducedRate tax category")
        XCTAssertEqual(taxEntry?.taxCategory, .reducedRate)
    }

    // MARK: - 13. Annual cash flow across 12 months

    /// Create entries across 12 months of 2025, verify all appear
    /// in cash book with correct running balance at year end
    func testAnnualCashFlow_12Months() {
        // Monthly pattern: odd months deposit 100k (sales), even months withdraw 60k (rent)
        let monthlyAmounts: [(month: Int, isDeposit: Bool, amount: Int)] = [
            (1, true, 100_000),
            (2, false, 60_000),
            (3, true, 100_000),
            (4, false, 60_000),
            (5, true, 100_000),
            (6, false, 60_000),
            (7, true, 100_000),
            (8, false, 60_000),
            (9, true, 100_000),
            (10, false, 60_000),
            (11, true, 100_000),
            (12, false, 60_000),
        ]

        for entry in monthlyAmounts {
            if entry.isDeposit {
                dataStore.addManualJournalEntry(
                    date: date(2025, entry.month, 15),
                    memo: "\(entry.month)月売上",
                    lines: [
                        (accountId: AccountingConstants.cashAccountId, debit: entry.amount, credit: 0, memo: ""),
                        (accountId: AccountingConstants.salesAccountId, debit: 0, credit: entry.amount, memo: ""),
                    ]
                )
            } else {
                dataStore.addManualJournalEntry(
                    date: date(2025, entry.month, 15),
                    memo: "\(entry.month)月家賃",
                    lines: [
                        (accountId: "acct-rent", debit: entry.amount, credit: 0, memo: ""),
                        (accountId: AccountingConstants.cashAccountId, debit: 0, credit: entry.amount, memo: ""),
                    ]
                )
            }
        }

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 12, "Should have 12 monthly entries")

        // Verify chronological order
        for i in 0..<(entries.count - 1) {
            XCTAssertTrue(entries[i].date <= entries[i + 1].date,
                          "Entries should be in chronological order")
        }

        // Calculate expected running balance:
        // Jan: +100k = 100k
        // Feb: -60k = 40k
        // Mar: +100k = 140k
        // Apr: -60k = 80k
        // May: +100k = 180k
        // Jun: -60k = 120k
        // Jul: +100k = 220k
        // Aug: -60k = 160k
        // Sep: +100k = 260k
        // Oct: -60k = 200k
        // Nov: +100k = 300k
        // Dec: -60k = 240k
        let expectedBalances = [
            100_000, 40_000, 140_000, 80_000, 180_000, 120_000,
            220_000, 160_000, 260_000, 200_000, 300_000, 240_000,
        ]

        for (index, expected) in expectedBalances.enumerated() {
            XCTAssertEqual(entries[index].runningBalance, expected,
                           "Month \(index + 1) balance should be \(expected)")
        }

        // Year-end balance = 6 * 100k - 6 * 60k = 600k - 360k = 240k
        XCTAssertEqual(entries.last?.runningBalance, 240_000,
                       "Year-end running balance should be 240,000")

        // Verify deposit entries have sales counter account
        let depositEntries = entries.filter { $0.debit > 0 }
        XCTAssertEqual(depositEntries.count, 6)
        XCTAssertTrue(depositEntries.allSatisfy {
            $0.counterAccountId == AccountingConstants.salesAccountId
        })

        // Verify withdrawal entries have rent counter account
        let withdrawalEntries = entries.filter { $0.credit > 0 }
        XCTAssertEqual(withdrawalEntries.count, 6)
        XCTAssertTrue(withdrawalEntries.allSatisfy {
            $0.counterAccountId == "acct-rent"
        })
    }

    // MARK: - Additional NTA Column Classification Tests

    /// Verify that account metadata is correctly populated on entries
    func testCashBook_AccountMetadata() {
        dataStore.addManualJournalEntry(
            date: date(2025, 2, 1),
            memo: "メタデータ確認",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 5_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 5_000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.accountId, AccountingConstants.cashAccountId)
        XCTAssertEqual(entry.accountCode, "101")
        XCTAssertEqual(entry.accountName, "現金")
        XCTAssertEqual(entry.memo, "メタデータ確認")
    }

    /// Verify that accounts payable withdrawal shows as その他出金
    func testCashBook_AccountsPayableWithdrawal() {
        dataStore.addManualJournalEntry(
            date: date(2025, 11, 1),
            memo: "買掛金支払",
            lines: [
                (accountId: AccountingConstants.accountsPayableAccountId, debit: 45_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 45_000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.credit, 45_000)
        XCTAssertEqual(entry.counterAccountId, AccountingConstants.accountsPayableAccountId)
        // View: credit > 0, counter != purchases -> その他出金
        XCTAssertNotEqual(entry.counterAccountId, AccountingConstants.purchasesAccountId)
    }

    /// Verify travel expense withdrawal shows in その他出金 column
    func testCashBook_TravelExpenseWithdrawal() {
        dataStore.addManualJournalEntry(
            date: date(2025, 4, 20),
            memo: "出張交通費",
            lines: [
                (accountId: "acct-travel", debit: 12_500, credit: 0, memo: "旅費"),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 12_500, memo: "出金"),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].credit, 12_500)
        XCTAssertEqual(entries[0].counterAccountId, "acct-travel")
    }

    /// Only cash-account lines appear in cash book, not other accounts
    func testCashBook_OnlyCashAccountLines() {
        // This entry has no cash line -- it should not appear in cash book
        dataStore.addManualJournalEntry(
            date: date(2025, 5, 10),
            memo: "銀行振替",
            lines: [
                (accountId: AccountingConstants.bankAccountId, debit: 100_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 100_000, memo: ""),
            ]
        )

        // This entry has a cash line
        dataStore.addManualJournalEntry(
            date: date(2025, 5, 11),
            memo: "現金入金",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 50_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 50_000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        // Only the cash entry should appear
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].memo, "現金入金")
    }

    /// Unposted (unbalanced) entries should not appear in cash book
    func testCashBook_UnpostedEntriesExcluded() {
        // Balanced entry -> posted
        dataStore.addManualJournalEntry(
            date: date(2025, 6, 1),
            memo: "正常仕訳",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 10_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 10_000, memo: ""),
            ]
        )

        // Unbalanced entry -> not posted
        dataStore.addManualJournalEntry(
            date: date(2025, 6, 2),
            memo: "不均衡仕訳",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 5_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 3_000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 1, "Only posted (balanced) entries should appear")
        XCTAssertEqual(entries[0].memo, "正常仕訳")
    }
}
