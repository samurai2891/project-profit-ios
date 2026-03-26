import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ReportViewModelTests: XCTestCase {
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

    func testNavigatePreviousYearUpdatesOverallSummaryAndPreviousYearComparison() {
        let project = mutations(dataStore).addProject(name: "YoY Project", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 20_000,
            date: makeDate(year: 2024, month: 6, day: 10),
            categoryId: "cat-sales",
            memo: "2024 income",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 35_000,
            date: makeDate(year: 2025, month: 6, day: 10),
            categoryId: "cat-sales",
            memo: "2025 income",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let viewModel = ReportViewModel(modelContext: context)
        viewModel.selectedFiscalYear = 2025

        XCTAssertEqual(viewModel.overallSummary.totalIncome, 35_000)
        XCTAssertEqual(viewModel.previousYearSummary.totalIncome, 20_000)
        XCTAssertEqual(viewModel.yoyIncomeChange, 15_000)

        viewModel.navigatePreviousYear()

        XCTAssertEqual(viewModel.selectedFiscalYear, 2024)
        XCTAssertEqual(viewModel.overallSummary.totalIncome, 20_000)
        XCTAssertEqual(viewModel.previousYearSummary.totalIncome, 0)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
