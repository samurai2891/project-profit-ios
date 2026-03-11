import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DashboardViewModelTests: XCTestCase {
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
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testSelectedMonthUpdatesSummaryForMonthlyMode() {
        let project = dataStore.addProject(name: "Monthly Project", description: "")
        _ = dataStore.addTransaction(
            type: .income,
            amount: 11_000,
            date: makeDate(year: 2025, month: 1, day: 15),
            categoryId: "cat-sales",
            memo: "jan income",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        _ = dataStore.addTransaction(
            type: .income,
            amount: 7_000,
            date: makeDate(year: 2025, month: 2, day: 15),
            categoryId: "cat-sales",
            memo: "feb income",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let viewModel = DashboardViewModel(modelContext: context)
        viewModel.viewMode = .monthly
        viewModel.selectedFiscalYear = 2025
        viewModel.selectedMonth = 1

        XCTAssertEqual(viewModel.summary.totalIncome, 11_000)

        viewModel.selectedMonth = 2

        XCTAssertEqual(viewModel.summary.totalIncome, 7_000)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
