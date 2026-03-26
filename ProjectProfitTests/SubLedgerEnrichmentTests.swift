import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class SubLedgerEnrichmentTests: XCTestCase {
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

    // MARK: - 1. counterAccountId（単純仕訳）

    func testCashBookEntry_HasCounterAccountId() {
        // Dr cash 10000 / Cr sales 10000 → 現金帳の相手勘定は売上高
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 6, 1),
            memo: "現金売上",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 10000, credit: 0, memo: "入金"),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 10000, memo: "売上")
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        XCTAssertEqual(entries.count, 1, "現金帳には現金行のみ1件")
        XCTAssertEqual(entries.first?.counterAccountId, AccountingConstants.salesAccountId)
    }

    // MARK: - 2. counterAccountId（複合仕訳・最大金額ヒューリスティック）

    func testCashBookEntry_CounterAccountId_MaxAmountHeuristic() {
        // Dr cash 10000 / Cr sales 7000 + Cr other-income 3000
        // → 相手勘定は最大金額の売上高（acct-sales）
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 6, 2),
            memo: "複合売上",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 10000, credit: 0, memo: "入金"),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 7000, memo: "売上"),
                (accountId: AccountingConstants.otherIncomeAccountId, debit: 0, credit: 3000, memo: "雑収入")
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            entries.first?.counterAccountId,
            AccountingConstants.salesAccountId,
            "複合仕訳では最大金額の行が相手勘定になるべき"
        )
    }

    // MARK: - 3. counterparty（取引から伝播）

    func testTransactionCounterparty_PropagatesFromTransaction() {
        let project = mutations(dataStore).addProject(name: "テストPJ", description: "取引先テスト")
        let _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5000,
            date: date(2025, 7, 1),
            categoryId: "cat-supplies",
            memo: "消耗品購入",
            allocations: [(projectId: project.id, ratio: 100)],
            counterparty: "田中商店"
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        let matching = entries.filter { $0.counterparty == "田中商店" }

        XCTAssertFalse(matching.isEmpty, "取引の取引先名が補助簿エントリに伝播されるべき")
        XCTAssertEqual(matching.first?.counterparty, "田中商店")
    }

    // MARK: - 4. taxCategory（軽減税率）

    func testTransactionTaxCategory_PropagatesFromTransaction() {
        let project = mutations(dataStore).addProject(name: "税率PJ", description: "軽減税率テスト")
        let _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1080,
            date: date(2025, 7, 2),
            categoryId: "cat-food",
            memo: "食品仕入",
            allocations: [(projectId: project.id, ratio: 100)],
            taxCategory: .reducedRate
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        let matching = entries.filter { $0.taxCategory == .reducedRate }
        XCTAssertFalse(matching.isEmpty, "軽減税率が補助簿エントリに伝播されるべき")
    }

    // MARK: - 5. taxCategory（標準税率）

    func testTransactionTaxCategory_StandardRate() {
        let project = mutations(dataStore).addProject(name: "標準税率PJ", description: "標準税率テスト")
        let _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 11000,
            date: date(2025, 7, 3),
            categoryId: "cat-tools",
            memo: "ソフトウェア購入",
            allocations: [(projectId: project.id, ratio: 100)],
            taxCategory: .standardRate
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        let matching = entries.filter { $0.taxCategory == .standardRate }
        XCTAssertFalse(matching.isEmpty, "標準税率が補助簿エントリに伝播されるべき")
        XCTAssertEqual(matching.first?.taxCategory, .standardRate)
    }

    // MARK: - 6. 手動仕訳は counterparty が nil

    func testManualJournalEntry_CounterpartyIsNil() {
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 8, 1),
            memo: "手動仕訳",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 20000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 20000, memo: "")
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        XCTAssertFalse(entries.isEmpty)
        XCTAssertNil(
            entries.first?.counterparty,
            "手動仕訳には元取引がないため、counterpartyはnilであるべき"
        )
    }

    // MARK: - 7. 手動仕訳は taxCategory が nil

    func testManualJournalEntry_TaxCategoryIsNil() {
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 8, 2),
            memo: "手動仕訳（税区分なし）",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 15000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 15000, memo: "")
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        XCTAssertFalse(entries.isEmpty)
        XCTAssertNil(
            entries.first?.taxCategory,
            "手動仕訳には元取引がないため、taxCategoryはnilであるべき"
        )
    }

    // MARK: - 8. 現金帳の残高計算（借方正常残高）

    func testCashBookRunningBalance_DebitNormal() {
        // 1件目: 借方 10000（残高 +10000）
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 9, 1),
            memo: "入金1",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 10000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 10000, memo: "")
            ]
        )
        // 2件目: 貸方 3000（残高 +7000）
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 9, 2),
            memo: "出金1",
            lines: [
                (accountId: AccountingConstants.miscExpenseAccountId, debit: 3000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 3000, memo: "")
            ]
        )
        // 3件目: 借方 5000（残高 +12000）
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 9, 3),
            memo: "入金2",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 5000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 5000, memo: "")
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        XCTAssertEqual(entries.count, 3)

        // 日付順にソートされているはず
        XCTAssertEqual(entries[0].runningBalance, 10000, "1件目: 借方10000 → 残高10000")
        XCTAssertEqual(entries[1].runningBalance, 7000, "2件目: 貸方3000 → 残高7000")
        XCTAssertEqual(entries[2].runningBalance, 12000, "3件目: 借方5000 → 残高12000")
    }

    // MARK: - 9. 経費帳の残高計算（借方正常残高）

    func testExpenseBookRunningBalance_DebitNormal() {
        // 同一経費科目に2件の借方仕訳
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 10, 1),
            memo: "消耗品1",
            lines: [
                (accountId: "acct-supplies", debit: 2000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 2000, memo: "")
            ]
        )
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 10, 2),
            memo: "消耗品2",
            lines: [
                (accountId: "acct-supplies", debit: 3000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 3000, memo: "")
            ]
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .expenseBook,
            accountFilter: "acct-supplies"
        )
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].runningBalance, 2000, "1件目: 借方2000 → 残高2000")
        XCTAssertEqual(entries[1].runningBalance, 5000, "2件目: 借方3000 → 残高5000")
    }

    // MARK: - 10. 現金帳は現金行のみフィルタ

    func testCashBook_OnlyFiltersCashAccountLines() {
        // 仕訳: Dr rent 50000 / Cr cash 50000
        // → 現金帳には cash 行のみ表示、rent 行は表示されない
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 11, 1),
            memo: "家賃支払",
            lines: [
                (accountId: "acct-rent", debit: 50000, credit: 0, memo: "地代家賃"),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 50000, memo: "現金支払")
            ]
        )

        let cashEntries = dataStore.getSubLedgerEntries(type: .cashBook)
        XCTAssertEqual(cashEntries.count, 1)
        XCTAssertTrue(
            cashEntries.allSatisfy { $0.accountId == AccountingConstants.cashAccountId },
            "現金帳には現金行のみ含まれるべき"
        )

        // 経費帳にはrent行が表示される
        let expenseEntries = dataStore.getSubLedgerEntries(
            type: .expenseBook,
            accountFilter: "acct-rent"
        )
        XCTAssertEqual(expenseEntries.count, 1)
        XCTAssertEqual(expenseEntries.first?.accountId, "acct-rent")
    }

    // MARK: - 11. 経費帳は全ての有効な費用科目をフィルタ

    func testExpenseBook_FiltersAllActiveExpenseAccounts() {
        // 複数の費用科目に仕訳を作成
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 11, 10),
            memo: "通信費",
            lines: [
                (accountId: "acct-communication", debit: 8000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 8000, memo: "")
            ]
        )
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 11, 11),
            memo: "旅費交通費",
            lines: [
                (accountId: "acct-travel", debit: 12000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 12000, memo: "")
            ]
        )
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 11, 12),
            memo: "広告宣伝費",
            lines: [
                (accountId: "acct-advertising", debit: 30000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 30000, memo: "")
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .expenseBook)
        let accountIds = Set(entries.map(\.accountId))
        XCTAssertTrue(accountIds.contains("acct-communication"), "通信費が経費帳に含まれるべき")
        XCTAssertTrue(accountIds.contains("acct-travel"), "旅費交通費が経費帳に含まれるべき")
        XCTAssertTrue(accountIds.contains("acct-advertising"), "広告宣伝費が経費帳に含まれるべき")
        XCTAssertFalse(
            accountIds.contains(AccountingConstants.cashAccountId),
            "現金は費用科目ではないため経費帳に含まれないべき"
        )
    }

    // MARK: - 12. accountCode と accountName の検証

    func testSubLedgerEntry_AccountCodeAndName() {
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 12, 1),
            memo: "科目コードテスト",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 50000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 50000, memo: "")
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        XCTAssertFalse(entries.isEmpty)

        let cashEntry = entries.first!
        // AccountingConstants.defaultAccounts で定義されている値と一致するべき
        XCTAssertEqual(cashEntry.accountCode, "101", "現金の科目コードは101")
        XCTAssertEqual(cashEntry.accountName, "現金", "現金の科目名は「現金」")
    }

    // MARK: - 13. 日付フィルタリング

    func testCashBook_DateFiltering() {
        // 3件の仕訳を異なる日付で作成
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 3, 1),
            memo: "3月",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 1000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 1000, memo: "")
            ]
        )
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 6, 15),
            memo: "6月",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 2000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 2000, memo: "")
            ]
        )
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 12, 31),
            memo: "12月",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 3000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 3000, memo: "")
            ]
        )

        // 全件
        let allEntries = dataStore.getSubLedgerEntries(type: .cashBook)
        XCTAssertEqual(allEntries.count, 3)

        // 4月〜11月のみ取得 → 6月の1件のみ
        let filtered = dataStore.getSubLedgerEntries(
            type: .cashBook,
            startDate: date(2025, 4, 1),
            endDate: date(2025, 11, 30)
        )
        XCTAssertEqual(filtered.count, 1, "4月〜11月の範囲には6月の仕訳のみ含まれるべき")
        XCTAssertEqual(filtered.first?.debit, 2000)
        XCTAssertEqual(filtered.first?.memo, "6月")
    }

    // MARK: - 14. 売掛帳のフィルタリング

    func testAccountsReceivableBook_FiltersCorrectly() {
        // Dr ar 30000 / Cr sales 30000
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 5, 1),
            memo: "売掛計上",
            lines: [
                (accountId: AccountingConstants.accountsReceivableAccountId, debit: 30000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 30000, memo: "")
            ]
        )

        let arEntries = dataStore.getSubLedgerEntries(type: .accountsReceivableBook)
        XCTAssertEqual(arEntries.count, 1)
        XCTAssertEqual(arEntries.first?.accountId, AccountingConstants.accountsReceivableAccountId)
        XCTAssertEqual(arEntries.first?.counterAccountId, AccountingConstants.salesAccountId)
        XCTAssertEqual(arEntries.first?.debit, 30000)
    }

    // MARK: - 15. 買掛帳のフィルタリング

    func testAccountsPayableBook_FiltersCorrectly() {
        // Dr purchases 20000 / Cr ap 20000
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 5, 10),
            memo: "買掛計上",
            lines: [
                (accountId: AccountingConstants.purchasesAccountId, debit: 20000, credit: 0, memo: ""),
                (accountId: AccountingConstants.accountsPayableAccountId, debit: 0, credit: 20000, memo: "")
            ]
        )

        let apEntries = dataStore.getSubLedgerEntries(type: .accountsPayableBook)
        XCTAssertEqual(apEntries.count, 1)
        XCTAssertEqual(apEntries.first?.accountId, AccountingConstants.accountsPayableAccountId)
        XCTAssertEqual(apEntries.first?.counterAccountId, AccountingConstants.purchasesAccountId)
        XCTAssertEqual(apEntries.first?.credit, 20000)
    }

    // MARK: - 16. 取引の counterparty と taxCategory が同時に伝播

    func testTransactionEnrichment_BothCounterpartyAndTaxCategory() {
        let project = mutations(dataStore).addProject(name: "統合テストPJ", description: "両方伝播")
        let _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 100000,
            date: date(2025, 8, 15),
            categoryId: "cat-sales",
            memo: "大口売上",
            allocations: [(projectId: project.id, ratio: 100)],
            taxCategory: .standardRate,
            counterparty: "株式会社山田"
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        let matching = entries.filter { $0.counterparty == "株式会社山田" }
        XCTAssertFalse(matching.isEmpty, "取引先名が伝播されるべき")

        let entry = matching.first!
        XCTAssertEqual(entry.counterparty, "株式会社山田")
        XCTAssertEqual(entry.taxCategory, .standardRate)
    }

    // MARK: - 17. 未転記仕訳は補助簿に含まれない

    func testUnpostedEntries_AreExcludedFromSubLedger() {
        // 借方・貸方が不一致の仕訳は isPosted = false のまま
        let _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 4, 1),
            memo: "不正仕訳（不一致）",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 10000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 9000, memo: "")
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        XCTAssertTrue(entries.isEmpty, "未転記（isPosted=false）の仕訳は補助簿に含まれないべき")
    }
}
