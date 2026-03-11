import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class TransactionsViewModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!
    var viewModel: TransactionsViewModel!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        viewModel = TransactionsViewModel(modelContext: context)
    }

    override func tearDown() {
        viewModel = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - incomeTotal without project filter uses full amount

    func testIncomeTotalWithoutProjectFilterUsesFullAmount() {
        let project = dataStore.addProject(name: "Project A", description: "")
        _ = dataStore.addTransaction(
            type: .income,
            amount: 10000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        _ = dataStore.addTransaction(
            type: .income,
            amount: 5000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        // No project filter set
        XCTAssertNil(viewModel.filter.projectId)
        XCTAssertEqual(viewModel.incomeTotal, 15000)
    }

    // MARK: - incomeTotal with project filter uses allocation amount

    func testIncomeTotalWithProjectFilterUsesAllocationAmount() {
        let projectA = dataStore.addProject(name: "Project A", description: "")
        let projectB = dataStore.addProject(name: "Project B", description: "")

        // Transaction allocated 60/40 across two projects (amount = 10000)
        _ = dataStore.addTransaction(
            type: .income,
            amount: 10000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 60),
                (projectId: projectB.id, ratio: 40),
            ]
        )

        // Filter to project A -> should show allocation amount (6000), not full 10000
        viewModel.filter = TransactionFilter(projectId: projectA.id)
        XCTAssertEqual(viewModel.incomeTotal, 6000)

        // Filter to project B -> should show allocation amount (4000)
        viewModel.filter = TransactionFilter(projectId: projectB.id)
        XCTAssertEqual(viewModel.incomeTotal, 4000)
    }

    // MARK: - expenseTotal with project filter uses allocation amount

    func testExpenseTotalWithProjectFilterUsesAllocationAmount() {
        let projectA = dataStore.addProject(name: "Project A", description: "")
        let projectB = dataStore.addProject(name: "Project B", description: "")

        _ = dataStore.addTransaction(
            type: .expense,
            amount: 8000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 75),
                (projectId: projectB.id, ratio: 25),
            ]
        )

        // Filter to project A -> allocation amount should be 6000 (75% of 8000)
        viewModel.filter = TransactionFilter(projectId: projectA.id)
        XCTAssertEqual(viewModel.expenseTotal, 6000)

        // Filter to project B -> allocation amount should be 2000 (25% of 8000)
        viewModel.filter = TransactionFilter(projectId: projectB.id)
        XCTAssertEqual(viewModel.expenseTotal, 2000)
    }

    // MARK: - netTotal with project filter = income allocation - expense allocation

    func testNetTotalWithProjectFilterUsesAllocationAmounts() {
        let projectA = dataStore.addProject(name: "Project A", description: "")
        let projectB = dataStore.addProject(name: "Project B", description: "")

        // Income: 10000, allocated 60/40
        _ = dataStore.addTransaction(
            type: .income,
            amount: 10000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 60),
                (projectId: projectB.id, ratio: 40),
            ]
        )

        // Expense: 4000, allocated 50/50
        _ = dataStore.addTransaction(
            type: .expense,
            amount: 4000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50),
            ]
        )

        // Project A: income allocation = 6000, expense allocation = 2000, net = 4000
        viewModel.filter = TransactionFilter(projectId: projectA.id)
        XCTAssertEqual(viewModel.incomeTotal, 6000)
        XCTAssertEqual(viewModel.expenseTotal, 2000)
        XCTAssertEqual(viewModel.netTotal, 4000)

        // Project B: income allocation = 4000, expense allocation = 2000, net = 2000
        viewModel.filter = TransactionFilter(projectId: projectB.id)
        XCTAssertEqual(viewModel.incomeTotal, 4000)
        XCTAssertEqual(viewModel.expenseTotal, 2000)
        XCTAssertEqual(viewModel.netTotal, 2000)
    }
}
