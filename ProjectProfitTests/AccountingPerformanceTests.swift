import XCTest
import SwiftData
@testable import ProjectProfit

/// 会計機能のパフォーマンステスト
@MainActor
final class AccountingPerformanceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!
    var engine: AccountingEngine!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
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

    // MARK: - Classification Performance

    func testClassifyBatch1000Transactions() {
        let transactions = (0..<1000).map { i in
            PPTransaction(
                type: i % 3 == 0 ? .income : .expense,
                amount: Int.random(in: 1000...100_000),
                date: Date(),
                categoryId: "cat-tools",
                memo: "テスト取引\(i) AWS JR 家賃".prefix(i % 10 == 0 ? 20 : 10).description
            )
        }

        measure {
            _ = ClassificationEngineCompatibilityAdapter.classifyBatch(
                transactions: transactions,
                categories: dataStore.categories,
                accounts: dataStore.accounts,
                userRules: []
            )
        }
    }

    // MARK: - Report Generation Performance

    func testTrialBalanceWith500Entries() {
        // 500件の仕訳を生成
        let categories = ["cat-sales", "cat-hosting", "cat-tools", "cat-transport", "cat-other-expense"]
        for i in 0..<500 {
            let catId = categories[i % categories.count]
            let type: TransactionType = i % 4 == 0 ? .income : .expense
            mutations(dataStore).addTransaction(
                type: type,
                amount: Int.random(in: 1000...50_000),
                date: Date(),
                categoryId: catId,
                memo: "パフォーマンステスト\(i)",
                allocations: []
            )
        }

        for tx in dataStore.transactions {
            engine.upsertJournalEntry(for: tx, categories: dataStore.categories, accounts: dataStore.accounts)
        }
        try? context.save()
        dataStore.refreshJournalEntries()
        dataStore.refreshJournalLines()

        let currentYear = Calendar.current.component(.year, from: Date())

        measure {
            _ = AccountingReportService.generateTrialBalance(
                fiscalYear: currentYear,
                accounts: dataStore.accounts,
                journalEntries: dataStore.journalEntries,
                journalLines: dataStore.journalLines
            )
        }
    }

    func testProfitLossAndBalanceSheetWith500Entries() {
        let categories = ["cat-sales", "cat-hosting", "cat-tools", "cat-transport"]
        for i in 0..<500 {
            let catId = categories[i % categories.count]
            let type: TransactionType = i % 3 == 0 ? .income : .expense
            mutations(dataStore).addTransaction(
                type: type,
                amount: Int.random(in: 1000...50_000),
                date: Date(),
                categoryId: catId,
                memo: "PL/BSパフォーマンス\(i)",
                allocations: []
            )
        }

        for tx in dataStore.transactions {
            engine.upsertJournalEntry(for: tx, categories: dataStore.categories, accounts: dataStore.accounts)
        }
        try? context.save()
        dataStore.refreshJournalEntries()
        dataStore.refreshJournalLines()

        let currentYear = Calendar.current.component(.year, from: Date())

        measure {
            let pl = AccountingReportService.generateProfitLoss(
                fiscalYear: currentYear,
                accounts: dataStore.accounts,
                journalEntries: dataStore.journalEntries,
                journalLines: dataStore.journalLines
            )
            _ = AccountingReportService.generateBalanceSheet(
                fiscalYear: currentYear,
                accounts: dataStore.accounts,
                journalEntries: dataStore.journalEntries,
                journalLines: dataStore.journalLines
            )
            _ = EtaxFieldPopulator.populate(
                fiscalYear: currentYear,
                profitLoss: pl,
                balanceSheet: nil,
                accounts: dataStore.accounts
            )
        }
    }

    // MARK: - E-Tax Export Performance

    func testEtaxXtxExportPerformance() {
        let fields = (0..<50).map { i in
            EtaxField(
                id: "perf_field_\(i)",
                fieldLabel: "テストフィールド\(i)",
                taxLine: i < 2 ? .salesRevenue : .communicationExpense,
                value: Int.random(in: 10_000...1_000_000),
                section: i < 10 ? .revenue : (i < 40 ? .expenses : .income)
            )
        }
        let form = EtaxForm(
            fiscalYear: 2025,
            formType: .blueReturn,
            fields: fields,
            generatedAt: Date()
        )

        measure {
            _ = EtaxXtxExporter.generateXtx(form: form)
            _ = EtaxXtxExporter.generateCsv(form: form)
        }
    }
}
