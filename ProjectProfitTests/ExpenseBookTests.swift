import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class ExpenseBookTests: XCTestCase {
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

    // MARK: - 1. All Expense Accounts

    func testExpenseBook_AllExpenseAccounts() {
        // Create entries for rent, travel, supplies
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 4, 1),
            memo: "事務所家賃",
            lines: [
                (accountId: "acct-rent", debit: 80000, credit: 0, memo: "地代家賃"),
                (accountId: "acct-cash", debit: 0, credit: 80000, memo: "現金"),
            ]
        )

        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 4, 5),
            memo: "出張交通費",
            lines: [
                (accountId: "acct-travel", debit: 15000, credit: 0, memo: "旅費交通費"),
                (accountId: "acct-cash", debit: 0, credit: 15000, memo: "現金"),
            ]
        )

        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 4, 10),
            memo: "文房具購入",
            lines: [
                (accountId: "acct-supplies", debit: 3000, credit: 0, memo: "消耗品費"),
                (accountId: "acct-cash", debit: 0, credit: 3000, memo: "現金"),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)

        XCTAssertEqual(entries.count, 3)

        let accountIds = Set(entries.map(\.accountId))
        XCTAssertTrue(accountIds.contains("acct-rent"), "家賃が含まれること")
        XCTAssertTrue(accountIds.contains("acct-travel"), "旅費交通費が含まれること")
        XCTAssertTrue(accountIds.contains("acct-supplies"), "消耗品費が含まれること")
    }

    // MARK: - 2. Account Filter

    func testExpenseBook_AccountFilter() {
        // Create entries for multiple expense types
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 5, 1),
            memo: "家賃5月",
            lines: [
                (accountId: "acct-rent", debit: 80000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 80000, memo: ""),
            ]
        )

        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 5, 3),
            memo: "電車代",
            lines: [
                (accountId: "acct-travel", debit: 5000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 5000, memo: ""),
            ]
        )

        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 5, 10),
            memo: "ペン購入",
            lines: [
                (accountId: "acct-supplies", debit: 1000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 1000, memo: ""),
            ]
        )

        // Filter to rent only
        let rentEntries = dataStore.getSubLedgerEntries(
            type: .expenseBook,
            accountFilter: "acct-rent"
        )

        XCTAssertEqual(rentEntries.count, 1)
        XCTAssertEqual(rentEntries.first?.accountId, "acct-rent")
        XCTAssertEqual(rentEntries.first?.debit, 80000)
    }

    // MARK: - 3. Account Filter No Match

    func testExpenseBook_AccountFilter_NoMatch() {
        // Create a rent entry only
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 6, 1),
            memo: "家賃6月",
            lines: [
                (accountId: "acct-rent", debit: 80000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 80000, memo: ""),
            ]
        )

        // Filter for advertising (unused)
        let entries = dataStore.getSubLedgerEntries(
            type: .expenseBook,
            accountFilter: "acct-advertising"
        )

        XCTAssertTrue(entries.isEmpty, "使用していない科目でフィルタすると空になること")
    }

    // MARK: - 4. Excludes Purchases

    func testExpenseBook_ExcludesPurchases() {
        // Create a purchase entry (仕入高)
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 4, 15),
            memo: "商品仕入",
            lines: [
                (accountId: "acct-purchases", debit: 50000, credit: 0, memo: "仕入高"),
                (accountId: "acct-cash", debit: 0, credit: 50000, memo: "現金"),
            ]
        )

        // Also create a normal expense for comparison
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 4, 15),
            memo: "文房具",
            lines: [
                (accountId: "acct-supplies", debit: 2000, credit: 0, memo: "消耗品費"),
                (accountId: "acct-cash", debit: 0, credit: 2000, memo: "現金"),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)

        // Only supplies should appear, not purchases
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.accountId, "acct-supplies")
        XCTAssertFalse(
            entries.contains { $0.accountId == "acct-purchases" },
            "仕入高は経費帳に含まれないこと（仕入帳セクションに属する）"
        )
    }

    // MARK: - 5. Excludes COGS

    func testExpenseBook_ExcludesCOGS() {
        // Create a COGS entry (売上原価)
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 12, 31),
            memo: "売上原価算出",
            lines: [
                (accountId: "acct-cogs", debit: 100000, credit: 0, memo: "売上原価"),
                (accountId: "acct-purchases", debit: 0, credit: 100000, memo: "仕入高"),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)

        XCTAssertFalse(
            entries.contains { $0.accountId == "acct-cogs" },
            "売上原価は経費帳に含まれないこと"
        )
    }

    // MARK: - 6. Excludes Opening/Closing Inventory

    func testExpenseBook_ExcludesOpeningClosingInventory() {
        // Create opening inventory entry (期首商品棚卸高 — expense type)
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 1, 1),
            memo: "期首棚卸",
            lines: [
                (accountId: "acct-opening-inventory", debit: 200000, credit: 0, memo: "期首商品棚卸高"),
                (accountId: "acct-closing-inventory", debit: 0, credit: 200000, memo: "期末商品棚卸高"),
            ]
        )

        // Also create a normal expense
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 1, 5),
            memo: "通信費",
            lines: [
                (accountId: "acct-communication", debit: 8000, credit: 0, memo: "通信費"),
                (accountId: "acct-cash", debit: 0, credit: 8000, memo: "現金"),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)

        XCTAssertFalse(
            entries.contains { $0.accountId == "acct-opening-inventory" },
            "期首商品棚卸高は経費帳に含まれないこと"
        )
        XCTAssertFalse(
            entries.contains { $0.accountId == "acct-closing-inventory" },
            "期末商品棚卸高は経費帳に含まれないこと（asset型なので元々対象外）"
        )

        // Only communication expense should appear
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.accountId, "acct-communication")
    }

    // MARK: - 7. Counter Account Cash (現金 column)

    func testExpenseBook_CounterAccountId_Cash() {
        // Dr rent 50000 / Cr cash 50000 → counterAccountId = "acct-cash"
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 7, 1),
            memo: "家賃現金払い",
            lines: [
                (accountId: "acct-rent", debit: 50000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 50000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.counterAccountId, "acct-cash",
                       "相手勘定が現金の場合、現金列に表示されること")
    }

    // MARK: - 8. Counter Account Bank (その他 column)

    func testExpenseBook_CounterAccountId_Bank() {
        // Dr rent 50000 / Cr bank 50000 → counterAccountId = "acct-bank"
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 7, 1),
            memo: "家賃振込",
            lines: [
                (accountId: "acct-rent", debit: 50000, credit: 0, memo: ""),
                (accountId: "acct-bank", debit: 0, credit: 50000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.counterAccountId, "acct-bank",
                       "相手勘定が銀行の場合、その他列に表示されること")
    }

    // MARK: - 9. Running Balance Per Account

    func testExpenseBook_RunningBalance_PerAccount() {
        // Two entries for rent, one for travel
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 4, 1),
            memo: "家賃4月",
            lines: [
                (accountId: "acct-rent", debit: 80000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 80000, memo: ""),
            ]
        )

        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 4, 10),
            memo: "交通費",
            lines: [
                (accountId: "acct-travel", debit: 15000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 15000, memo: ""),
            ]
        )

        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 5, 1),
            memo: "家賃5月",
            lines: [
                (accountId: "acct-rent", debit: 80000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 80000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)

        // Sort is by date, then accountCode, so:
        //   4/1  rent (code 501)  → running balance for rent = 80000
        //   4/10 travel (code 503) → running balance for travel = 15000
        //   5/1  rent (code 501)  → running balance for rent = 160000
        XCTAssertEqual(entries.count, 3)

        let rentEntries = entries.filter { $0.accountId == "acct-rent" }
        let travelEntries = entries.filter { $0.accountId == "acct-travel" }

        XCTAssertEqual(rentEntries.count, 2)
        XCTAssertEqual(rentEntries[0].runningBalance, 80000, "家賃1回目の残高")
        XCTAssertEqual(rentEntries[1].runningBalance, 160000, "家賃2回目の残高")

        XCTAssertEqual(travelEntries.count, 1)
        XCTAssertEqual(travelEntries[0].runningBalance, 15000, "交通費は独立した残高")
    }

    // MARK: - 10. Date Filter

    func testExpenseBook_DateFilter() {
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 3, 15),
            memo: "3月家賃",
            lines: [
                (accountId: "acct-rent", debit: 80000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 80000, memo: ""),
            ]
        )

        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 4, 15),
            memo: "4月家賃",
            lines: [
                (accountId: "acct-rent", debit: 80000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 80000, memo: ""),
            ]
        )

        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 5, 15),
            memo: "5月家賃",
            lines: [
                (accountId: "acct-rent", debit: 80000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 80000, memo: ""),
            ]
        )

        // Filter to April only
        let entries = dataStore.getSubLedgerEntries(
            type: .expenseBook,
            startDate: date(2025, 4, 1),
            endDate: date(2025, 4, 30)
        )

        XCTAssertEqual(entries.count, 1, "4月のみの家賃が取得されること")
        XCTAssertEqual(entries.first?.memo, "4月家賃")
        XCTAssertEqual(entries.first?.debit, 80000)
    }

    // MARK: - 11. Chronological Order

    func testExpenseBook_ChronologicalOrder() {
        // Insert entries out of chronological order
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 6, 15),
            memo: "6月中旬",
            lines: [
                (accountId: "acct-supplies", debit: 3000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 3000, memo: ""),
            ]
        )

        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 6, 1),
            memo: "6月初日",
            lines: [
                (accountId: "acct-supplies", debit: 1000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 1000, memo: ""),
            ]
        )

        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 6, 30),
            memo: "6月末日",
            lines: [
                (accountId: "acct-supplies", debit: 5000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 5000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)

        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].date < entries[1].date, "日付の昇順でソートされること")
        XCTAssertTrue(entries[1].date < entries[2].date, "日付の昇順でソートされること")
        XCTAssertEqual(entries[0].memo, "6月初日")
        XCTAssertEqual(entries[1].memo, "6月中旬")
        XCTAssertEqual(entries[2].memo, "6月末日")
    }

    // MARK: - 12. Multiple Expenses Annual Scenario

    func testExpenseBook_MultipleExpenses_AnnualScenario() {
        // Jan rent 80k
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 1, 25),
            memo: "1月家賃",
            lines: [
                (accountId: "acct-rent", debit: 80000, credit: 0, memo: ""),
                (accountId: "acct-bank", debit: 0, credit: 80000, memo: ""),
            ]
        )

        // Feb rent 80k
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 2, 25),
            memo: "2月家賃",
            lines: [
                (accountId: "acct-rent", debit: 80000, credit: 0, memo: ""),
                (accountId: "acct-bank", debit: 0, credit: 80000, memo: ""),
            ]
        )

        // Mar travel 15k
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 3, 10),
            memo: "3月出張",
            lines: [
                (accountId: "acct-travel", debit: 15000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 15000, memo: ""),
            ]
        )

        // Apr supplies 5k
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 4, 20),
            memo: "4月消耗品",
            lines: [
                (accountId: "acct-supplies", debit: 5000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 5000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)

        XCTAssertEqual(entries.count, 4, "全4エントリが取得されること")

        // Verify running balances per account
        let rentEntries = entries.filter { $0.accountId == "acct-rent" }
        let travelEntries = entries.filter { $0.accountId == "acct-travel" }
        let suppliesEntries = entries.filter { $0.accountId == "acct-supplies" }

        // Rent: 80000 → 160000
        XCTAssertEqual(rentEntries.count, 2)
        XCTAssertEqual(rentEntries[0].runningBalance, 80000, "1月家賃の残高")
        XCTAssertEqual(rentEntries[1].runningBalance, 160000, "2月家賃の累計残高")

        // Travel: 15000
        XCTAssertEqual(travelEntries.count, 1)
        XCTAssertEqual(travelEntries[0].runningBalance, 15000, "3月出張の残高")

        // Supplies: 5000
        XCTAssertEqual(suppliesEntries.count, 1)
        XCTAssertEqual(suppliesEntries[0].runningBalance, 5000, "4月消耗品の残高")

        // Verify counter accounts
        XCTAssertEqual(rentEntries[0].counterAccountId, "acct-bank", "家賃は銀行振込")
        XCTAssertEqual(travelEntries[0].counterAccountId, "acct-cash", "出張は現金払い")
        XCTAssertEqual(suppliesEntries[0].counterAccountId, "acct-cash", "消耗品は現金払い")
    }

    // MARK: - 13. SubLedger Account IDs for Expense Book

    func testSubLedgerAccountIds_ExpenseBook() {
        let accountIds = dataStore.subLedgerAccountIds(for: .expenseBook)

        // Should include standard expense accounts
        XCTAssertTrue(accountIds.contains("acct-rent"), "地代家賃を含むこと")
        XCTAssertTrue(accountIds.contains("acct-utilities"), "水道光熱費を含むこと")
        XCTAssertTrue(accountIds.contains("acct-travel"), "旅費交通費を含むこと")
        XCTAssertTrue(accountIds.contains("acct-communication"), "通信費を含むこと")
        XCTAssertTrue(accountIds.contains("acct-advertising"), "広告宣伝費を含むこと")
        XCTAssertTrue(accountIds.contains("acct-entertainment"), "接待交際費を含むこと")
        XCTAssertTrue(accountIds.contains("acct-depreciation"), "減価償却費を含むこと")
        XCTAssertTrue(accountIds.contains("acct-repair"), "利子割引料を含むこと")
        XCTAssertTrue(accountIds.contains("acct-supplies"), "消耗品費を含むこと")
        XCTAssertTrue(accountIds.contains("acct-welfare"), "租税公課を含むこと")
        XCTAssertTrue(accountIds.contains("acct-insurance"), "損害保険料を含むこと")
        XCTAssertTrue(accountIds.contains("acct-outsourcing"), "外注工賃を含むこと")
        XCTAssertTrue(accountIds.contains("acct-misc"), "雑費を含むこと")

        // Should NOT include purchase/COGS related accounts
        XCTAssertFalse(accountIds.contains("acct-purchases"), "仕入高は経費帳から除外されること")
        XCTAssertFalse(accountIds.contains("acct-opening-inventory"), "期首商品棚卸高は経費帳から除外されること")
        XCTAssertFalse(accountIds.contains("acct-cogs"), "売上原価は経費帳から除外されること")

        // acct-closing-inventory is asset type, should not be included either
        XCTAssertFalse(accountIds.contains("acct-closing-inventory"), "期末商品棚卸高は資産型なので含まれないこと")

        // Should NOT include non-expense types
        XCTAssertFalse(accountIds.contains("acct-cash"), "現金（資産）は含まれないこと")
        XCTAssertFalse(accountIds.contains("acct-sales"), "売上高（収益）は含まれないこと")
        XCTAssertFalse(accountIds.contains("acct-bank"), "普通預金（資産）は含まれないこと")
    }

    // MARK: - 14. Tax Category Preserved

    func testExpenseBook_TaxCategoryPreserved() {
        // Use addTransaction which sets taxCategory and auto-generates journal entry
        let project = mutations(dataStore).addProject(name: "税区分テスト", description: "")
        let _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 10800,
            date: date(2025, 8, 1),
            categoryId: "cat-food",
            memo: "軽減税率の食品購入",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 800,
            taxRate: 8,
            isTaxIncluded: true,
            taxCategory: .reducedRate,
            counterparty: "スーパーマーケットA"
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)

        // The expense line for acct-entertainment (mapped from cat-food) should appear
        let expenseEntries = entries.filter { $0.accountId == "acct-entertainment" }
        XCTAssertFalse(expenseEntries.isEmpty, "接待交際費のエントリが存在すること")

        let entry = expenseEntries.first!
        XCTAssertEqual(entry.taxCategory, .reducedRate, "消費税区分が軽減税率として保持されること")
    }
}
