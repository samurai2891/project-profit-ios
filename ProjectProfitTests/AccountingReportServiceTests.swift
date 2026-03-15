import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class AccountingReportServiceTests: XCTestCase {
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

    private func addTestData() {
        let project = mutations(dataStore).addProject(name: "TestProject", description: "")
        let year = Calendar.current.component(.year, from: Date())

        // 収入: 100,000円
        _ = mutations(dataStore).addTransaction(
            type: .income, amount: 100000,
            date: Calendar.current.date(from: DateComponents(year: year, month: 3, day: 15))!,
            categoryId: "cat-project-income", memo: "売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        // 経費: 30,000円 (全額経費)
        _ = mutations(dataStore).addTransaction(
            type: .expense, amount: 30000,
            date: Calendar.current.date(from: DateComponents(year: year, month: 4, day: 1))!,
            categoryId: "cat-tools", memo: "ツール",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxDeductibleRate: 100
        )

        // 経費: 20,000円 (家事按分50%)
        _ = mutations(dataStore).addTransaction(
            type: .expense, amount: 20000,
            date: Calendar.current.date(from: DateComponents(year: year, month: 5, day: 1))!,
            categoryId: "cat-hosting", memo: "サーバー",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxDeductibleRate: 50
        )
    }

    private func projectedJournals(for fiscalYear: Int) -> (entries: [PPJournalEntry], lines: [PPJournalLine]) {
        dataStore.projectedCanonicalJournals(fiscalYear: fiscalYear)
    }

    // MARK: - Trial Balance

    func testTrialBalanceIsBalanced() {
        addTestData()
        let fiscalYear = Calendar.current.component(.year, from: Date())
        let projected = projectedJournals(for: fiscalYear)

        let report = AccountingReportService.generateTrialBalance(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines
        )

        XCTAssertTrue(report.isBalanced, "Trial balance should be balanced: debit=\(report.debitTotal), credit=\(report.creditTotal)")
        XCTAssertEqual(report.debitTotal, report.creditTotal)
        XCTAssertFalse(report.rows.isEmpty)
    }

    func testTrialBalanceEmpty() {
        let fiscalYear = Calendar.current.component(.year, from: Date())
        let projected = projectedJournals(for: fiscalYear)
        let report = AccountingReportService.generateTrialBalance(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines
        )

        XCTAssertTrue(report.rows.isEmpty)
        XCTAssertTrue(report.isBalanced)
    }

    // MARK: - Profit & Loss

    func testProfitLossNetIncome() {
        addTestData()
        let fiscalYear = Calendar.current.component(.year, from: Date())
        let projected = projectedJournals(for: fiscalYear)

        let report = AccountingReportService.generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines
        )

        XCTAssertEqual(report.totalRevenue, 100000)
        // 経費: 30000 (全額) + 10000 (20000の50%) = 40000
        XCTAssertEqual(report.totalExpenses, 40000)
        // 所得 = 100000 - 40000 = 60000
        XCTAssertEqual(report.netIncome, 60000)
    }

    func testProfitLossRevenueMinusExpensesEqualsNetIncome() {
        addTestData()
        let fiscalYear = Calendar.current.component(.year, from: Date())
        let projected = projectedJournals(for: fiscalYear)

        let report = AccountingReportService.generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines
        )

        XCTAssertEqual(report.totalRevenue - report.totalExpenses, report.netIncome)
    }

    // MARK: - Balance Sheet

    func testBalanceSheetEquation() {
        addTestData()
        let fiscalYear = Calendar.current.component(.year, from: Date())
        let projected = projectedJournals(for: fiscalYear)

        let report = AccountingReportService.generateBalanceSheet(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines
        )

        // 資産 = 負債 + 資本（当期純利益含む）
        XCTAssertEqual(
            report.totalAssets, report.liabilitiesAndEquity,
            "Assets(\(report.totalAssets)) should equal Liabilities(\(report.totalLiabilities)) + Equity(\(report.totalEquity))"
        )
        XCTAssertTrue(report.isBalanced)
    }

    // MARK: - Date Filter

    func testReportFiltersbyFiscalYear() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let year = Calendar.current.component(.year, from: Date())

        // 今年のトランザクション
        _ = mutations(dataStore).addTransaction(
            type: .income, amount: 50000,
            date: Calendar.current.date(from: DateComponents(year: year, month: 6, day: 1))!,
            categoryId: "cat-project-income", memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        let thisYearProjected = projectedJournals(for: year)
        let lastYearProjected = projectedJournals(for: year - 1)

        // 前年のレポートは空になるべき
        let lastYearReport = AccountingReportService.generateProfitLoss(
            fiscalYear: year - 1,
            accounts: dataStore.accounts,
            journalEntries: lastYearProjected.entries,
            journalLines: lastYearProjected.lines
        )

        XCTAssertEqual(lastYearReport.totalRevenue, 0)
        XCTAssertEqual(lastYearReport.totalExpenses, 0)

        // 今年のレポートにはデータがある
        let thisYearReport = AccountingReportService.generateProfitLoss(
            fiscalYear: year,
            accounts: dataStore.accounts,
            journalEntries: thisYearProjected.entries,
            journalLines: thisYearProjected.lines
        )

        XCTAssertEqual(thisYearReport.totalRevenue, 50000)
    }

    // MARK: - Cross-Report Consistency

    func testTrialBalancePLBSConsistency() {
        addTestData()
        let year = Calendar.current.component(.year, from: Date())
        let projected = projectedJournals(for: year)

        let tb = AccountingReportService.generateTrialBalance(
            fiscalYear: year, accounts: dataStore.accounts,
            journalEntries: projected.entries, journalLines: projected.lines
        )
        let pl = AccountingReportService.generateProfitLoss(
            fiscalYear: year, accounts: dataStore.accounts,
            journalEntries: projected.entries, journalLines: projected.lines
        )
        let bs = AccountingReportService.generateBalanceSheet(
            fiscalYear: year, accounts: dataStore.accounts,
            journalEntries: projected.entries, journalLines: projected.lines
        )

        // 試算表の貸借一致
        XCTAssertTrue(tb.isBalanced)
        // B/S等式
        XCTAssertTrue(bs.isBalanced)
        // P&Lの所得がB/Sの当期純利益と一致
        let retainedEarnings = bs.equityItems.first { $0.id == "retained-earnings" }
        XCTAssertEqual(retainedEarnings?.balance, pl.netIncome)
    }
}
