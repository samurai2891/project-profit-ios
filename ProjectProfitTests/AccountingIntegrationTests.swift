import XCTest
import SwiftData
@testable import ProjectProfit

/// エンドツーエンド統合テスト: トランザクション入力→仕訳生成→レポート→e-Tax出力の全フロー
@MainActor
final class AccountingIntegrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!
    var engine: AccountingEngine!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self,
            PPAccount.self, PPJournalEntry.self, PPJournalLine.self, PPAccountingProfile.self,
            PPUserRule.self,
            PPFixedAsset.self,
            configurations: config
        )
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        engine = AccountingEngine(modelContext: context)
    }

    override func tearDown() {
        engine = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Scenario 1: 基本的な収入/経費フロー

    func testScenario1_BasicIncomeExpenseFlow() {
        // 1. 収入トランザクション追加
        let incomeTx = dataStore.addTransaction(
            type: .income,
            amount: 500_000,
            date: makeDate(2025, 6, 15),
            categoryId: "cat-sales",
            memo: "Web制作代金",
            allocations: []
        )

        // 2. 経費トランザクション追加
        let expenseTx = dataStore.addTransaction(
            type: .expense,
            amount: 30_000,
            date: makeDate(2025, 6, 20),
            categoryId: "cat-hosting",
            memo: "AWSサーバー代",
            allocations: []
        )

        // 3. 仕訳を生成

        engine.upsertJournalEntry(for: incomeTx, categories: dataStore.categories, accounts: dataStore.accounts)
        engine.upsertJournalEntry(for: expenseTx, categories: dataStore.categories, accounts: dataStore.accounts)
        try? context.save()
        dataStore.refreshJournalEntries()
        dataStore.refreshJournalLines()

        // 4. 仕訳が生成されているか確認
        XCTAssertEqual(dataStore.journalEntries.count, 2)

        // 5. 全仕訳の貸借が一致しているか確認
        for entry in dataStore.journalEntries {
            let lines = dataStore.journalLines.filter { $0.entryId == entry.id }
            let totalDebit = lines.reduce(0) { $0 + $1.debit }
            let totalCredit = lines.reduce(0) { $0 + $1.credit }
            XCTAssertEqual(totalDebit, totalCredit, "仕訳 \(entry.memo) の貸借不一致")
            XCTAssertTrue(entry.isPosted, "仕訳 \(entry.memo) が未投稿")
        }

        // 6. 試算表の貸借一致を確認
        let tb = AccountingReportService.generateTrialBalance(
            fiscalYear: 2025,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines
        )
        XCTAssertTrue(tb.isBalanced, "試算表の貸借不一致: 借方=\(tb.debitTotal), 貸方=\(tb.creditTotal)")

        // 7. P&L の所得金額が正しいか確認
        let pl = AccountingReportService.generateProfitLoss(
            fiscalYear: 2025,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines
        )
        XCTAssertEqual(pl.totalRevenue, 500_000)
        XCTAssertEqual(pl.totalExpenses, 30_000)
        XCTAssertEqual(pl.netIncome, 470_000)

        // 8. B/S の資産=負債+資本を確認
        let bs = AccountingReportService.generateBalanceSheet(
            fiscalYear: 2025,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines
        )
        XCTAssertTrue(bs.isBalanced, "B/S不均衡: 資産=\(bs.totalAssets), 負債+資本=\(bs.liabilitiesAndEquity)")

        // 9. e-Tax出力が正常に生成されるか確認
        let form = EtaxFieldPopulator.populate(
            fiscalYear: 2025,
            profitLoss: pl,
            balanceSheet: bs,
            accounts: dataStore.accounts
        )
        let xtxResult = EtaxXtxExporter.generateXtx(form: form)
        switch xtxResult {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<税務申告データ>"))
            XCTAssertTrue(xml.contains("<金額>500000</金額>"))
        case .failure(let error):
            XCTFail("e-Tax出力失敗: \(error)")
        }
    }

    // MARK: - Scenario 2: 家事按分ありの経費フロー

    func testScenario2_TaxDeductibleRateExpense() {
        // 1. 家事按分50%の経費を追加
        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 100_000,
            date: makeDate(2025, 3, 1),
            categoryId: "cat-hosting",
            memo: "インターネット回線費（年額）",
            allocations: [],
            taxDeductibleRate: 50
        )
        XCTAssertEqual(tx.taxDeductibleRate, 50)

        // 2. 仕訳生成 → 3行仕訳になるはず（経費50% + 事業主貸50% / 現金）
        engine.upsertJournalEntry(for: tx, categories: dataStore.categories, accounts: dataStore.accounts)
        try? context.save()
        dataStore.refreshJournalEntries()
        dataStore.refreshJournalLines()

        let entry = dataStore.journalEntries.first!
        let lines = dataStore.journalLines.filter { $0.entryId == entry.id }

        XCTAssertEqual(lines.count, 3, "家事按分仕訳は3行のはず")
        XCTAssertTrue(entry.isPosted)

        // 3. 貸借一致確認
        let totalDebit = lines.reduce(0) { $0 + $1.debit }
        let totalCredit = lines.reduce(0) { $0 + $1.credit }
        XCTAssertEqual(totalDebit, totalCredit)
        XCTAssertEqual(totalDebit, 100_000)

        // 4. 経費勘定は50,000円、事業主貸は50,000円
        let expenseLine = lines.first { $0.accountId == "acct-communication" }
        XCTAssertNotNil(expenseLine)
        XCTAssertEqual(expenseLine?.debit, 50_000)

        let drawingsLine = lines.first { $0.accountId == AccountingConstants.ownerDrawingsAccountId }
        XCTAssertNotNil(drawingsLine)
        XCTAssertEqual(drawingsLine?.debit, 50_000)
    }

    // MARK: - Scenario 3: 自動分類→e-Tax出力

    func testScenario3_ClassificationToEtaxExport() {
        // 1. 複数トランザクション追加
        let memos = [
            ("AWS月額", "cat-hosting", TransactionType.expense, 12_000),
            ("JR交通費", "cat-transport", TransactionType.expense, 3_500),
            ("家賃3月分", "cat-other-expense", TransactionType.expense, 80_000),
            ("Web制作売上", "cat-sales", TransactionType.income, 300_000),
        ]

        for (memo, catId, type, amount) in memos {
            dataStore.addTransaction(
                type: type,
                amount: amount,
                date: makeDate(2025, 3, 15),
                categoryId: catId,
                memo: memo,
                allocations: []
            )
        }

        // 2. 自動分類
        let results = ClassificationEngine.classifyBatch(
            transactions: dataStore.transactions,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )

        // AWS → 通信費
        let awsResult = results.first { $0.transaction.memo.contains("AWS") }
        XCTAssertEqual(awsResult?.result.taxLine, .communicationExpense)

        // JR → 旅費交通費
        let jrResult = results.first { $0.transaction.memo.contains("JR") }
        XCTAssertEqual(jrResult?.result.taxLine, .travelExpense)

        // 家賃 → 地代家賃
        let rentResult = results.first { $0.transaction.memo.contains("家賃") }
        XCTAssertEqual(rentResult?.result.taxLine, .rentExpense)

        // 3. 仕訳生成
        for tx in dataStore.transactions {
            engine.upsertJournalEntry(for: tx, categories: dataStore.categories, accounts: dataStore.accounts)
        }
        try? context.save()
        dataStore.refreshJournalEntries()
        dataStore.refreshJournalLines()

        // 4. 全仕訳の貸借一致
        let tb = AccountingReportService.generateTrialBalance(
            fiscalYear: 2025,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines
        )
        XCTAssertTrue(tb.isBalanced)

        // 5. P&L → e-Tax
        let pl = AccountingReportService.generateProfitLoss(
            fiscalYear: 2025,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines
        )
        XCTAssertEqual(pl.totalRevenue, 300_000)
        XCTAssertEqual(pl.totalExpenses, 95_500)

        let form = EtaxFieldPopulator.populate(
            fiscalYear: 2025,
            profitLoss: pl,
            balanceSheet: nil,
            accounts: dataStore.accounts
        )
        XCTAssertFalse(form.fields.isEmpty)

        // CSV出力テスト
        let csvResult = EtaxXtxExporter.generateCsv(form: form)
        if case .failure(let error) = csvResult {
            XCTFail("CSV出力失敗: \(error)")
        }
    }

    // MARK: - Scenario 4: 白色申告フロー

    func testScenario4_WhiteReturnFlow() {
        // 1. トランザクション追加
        dataStore.addTransaction(
            type: .income, amount: 1_000_000,
            date: makeDate(2025, 1, 15), categoryId: "cat-sales",
            memo: "コンサル収入", allocations: []
        )
        dataStore.addTransaction(
            type: .expense, amount: 50_000,
            date: makeDate(2025, 2, 1), categoryId: "cat-tools",
            memo: "開発ツール", allocations: []
        )

        // 2. 仕訳生成
        for tx in dataStore.transactions {
            engine.upsertJournalEntry(for: tx, categories: dataStore.categories, accounts: dataStore.accounts)
        }
        try? context.save()
        dataStore.refreshJournalEntries()
        dataStore.refreshJournalLines()

        // 3. P&L生成
        let pl = AccountingReportService.generateProfitLoss(
            fiscalYear: 2025,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines
        )

        // 4. 白色申告 収支内訳書ビルド
        let form = ShushiNaiyakushoBuilder.build(
            fiscalYear: 2025,
            profitLoss: pl,
            accounts: dataStore.accounts
        )
        XCTAssertEqual(form.formType, .whiteReturn)

        let revenueField = form.fields.first { $0.id == "shushi_revenue_total" }
        XCTAssertEqual(revenueField?.value, 1_000_000)

        let netIncomeField = form.fields.first { $0.id == "shushi_income_net" }
        XCTAssertEqual(netIncomeField?.value, 950_000)

        // 5. XTX出力
        let xtxResult = EtaxXtxExporter.generateXtx(form: form)
        switch xtxResult {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("白色収支内訳書"))
        case .failure(let error):
            XCTFail("白色申告XTX出力失敗: \(error)")
        }
    }

    // MARK: - Helper

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
