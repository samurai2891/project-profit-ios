import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class DataStoreSummaryTests: XCTestCase {
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

    // MARK: - Helpers

    private let calendar = Calendar.current

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @discardableResult
    private func addCategory(id: String, name: String, type: CategoryType) -> PPCategory {
        let category = PPCategory(id: id, name: name, type: type, icon: "circle")
        context.insert(category)
        try! context.save()
        dataStore.loadData()
        return category
    }

    // MARK: - getProjectSummary

    func testGetProjectSummary_returnsNilForNonExistentProject() {
        let result = dataStore.getProjectSummary(projectId: UUID())
        XCTAssertNil(result)
    }

    func testGetProjectSummary_emptyTransactions() {
        let project = mutations(dataStore).addProject(name: "Empty Project", description: "")

        let summary = dataStore.getProjectSummary(projectId: project.id)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.projectName, "Empty Project")
        XCTAssertEqual(summary?.totalIncome, 0)
        XCTAssertEqual(summary?.totalExpense, 0)
        XCTAssertEqual(summary?.profit, 0)
        XCTAssertEqual(summary?.profitMargin, 0)
        XCTAssertEqual(summary?.status, .active)
    }

    func testGetProjectSummary_incomeAndExpense() {
        let project = mutations(dataStore).addProject(name: "Web App", description: "Client project")

        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: Date(),
            categoryId: "cat-sales", memo: "Payment",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 30_000, date: Date(),
            categoryId: "cat-hosting", memo: "Server",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 20_000, date: Date(),
            categoryId: "cat-tools", memo: "Tools",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summary = dataStore.getProjectSummary(projectId: project.id)!

        XCTAssertEqual(summary.id, project.id)
        XCTAssertEqual(summary.projectName, "Web App")
        XCTAssertEqual(summary.totalIncome, 100_000)
        XCTAssertEqual(summary.totalExpense, 50_000)
        XCTAssertEqual(summary.profit, 50_000)
        XCTAssertEqual(summary.profitMargin, 50.0, accuracy: 0.01)
    }

    func testGetProjectSummary_partialAllocations() {
        let projectA = mutations(dataStore).addProject(name: "Project A", description: "")
        let projectB = mutations(dataStore).addProject(name: "Project B", description: "")

        // 100_000 split 60/40 between A and B
        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: Date(),
            categoryId: "cat-sales", memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 60),
                (projectId: projectB.id, ratio: 40),
            ]
        )

        let summaryA = dataStore.getProjectSummary(projectId: projectA.id)!
        let summaryB = dataStore.getProjectSummary(projectId: projectB.id)!

        XCTAssertEqual(summaryA.totalIncome, 60_000)
        XCTAssertEqual(summaryB.totalIncome, 40_000)
    }

    func testGetProjectSummary_negativeProfitMarginIsZeroWhenNoIncome() {
        let project = mutations(dataStore).addProject(name: "Loss Project", description: "")

        mutations(dataStore).addTransaction(
            type: .expense, amount: 50_000, date: Date(),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summary = dataStore.getProjectSummary(projectId: project.id)!

        XCTAssertEqual(summary.totalIncome, 0)
        XCTAssertEqual(summary.totalExpense, 50_000)
        XCTAssertEqual(summary.profit, -50_000)
        XCTAssertEqual(summary.profitMargin, 0, "Profit margin should be 0 when there is no income")
    }

    // MARK: - getAllProjectSummaries

    func testGetAllProjectSummaries_empty() {
        let summaries = dataStore.getAllProjectSummaries()
        XCTAssertTrue(summaries.isEmpty)
    }

    func testGetAllProjectSummaries_multipleProjects() {
        let p1 = mutations(dataStore).addProject(name: "Alpha", description: "")
        let p2 = mutations(dataStore).addProject(name: "Beta", description: "")
        let p3 = mutations(dataStore).addProject(name: "Gamma", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: Date(),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: p1.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 150_000, date: Date(),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: p2.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 90_000, date: Date(),
            categoryId: "cat-hosting", memo: "",
            allocations: [
                (projectId: p1.id, ratio: 50),
                (projectId: p3.id, ratio: 50),
            ]
        )

        let summaries = dataStore.getAllProjectSummaries()

        XCTAssertEqual(summaries.count, 3)

        let ids = Set(summaries.map(\.id))
        XCTAssertTrue(ids.contains(p1.id))
        XCTAssertTrue(ids.contains(p2.id))
        XCTAssertTrue(ids.contains(p3.id))

        let alphaSum = summaries.first { $0.id == p1.id }!
        XCTAssertEqual(alphaSum.totalIncome, 200_000)
        XCTAssertEqual(alphaSum.totalExpense, 45_000)

        let gammaSum = summaries.first { $0.id == p3.id }!
        XCTAssertEqual(gammaSum.totalIncome, 0)
        XCTAssertEqual(gammaSum.totalExpense, 45_000)
    }

    // MARK: - getOverallSummary

    func testGetOverallSummary_noTransactions() {
        let summary = dataStore.getOverallSummary()

        XCTAssertEqual(summary.totalIncome, 0)
        XCTAssertEqual(summary.totalExpense, 0)
        XCTAssertEqual(summary.netProfit, 0)
        XCTAssertEqual(summary.profitMargin, 0)
    }

    func testGetOverallSummary_withoutDateFilter() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 500_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 300_000, date: makeDate(year: 2025, month: 6, day: 15),
            categoryId: "cat-service", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 200_000, date: makeDate(year: 2025, month: 4, day: 10),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summary = dataStore.getOverallSummary()

        XCTAssertEqual(summary.totalIncome, 800_000)
        XCTAssertEqual(summary.totalExpense, 200_000)
        XCTAssertEqual(summary.netProfit, 600_000)
        XCTAssertEqual(summary.profitMargin, 75.0, accuracy: 0.01)
    }

    func testGetOverallSummary_withStartDateFilter() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 1, day: 15),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 50_000, date: makeDate(year: 2025, month: 4, day: 1),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summary = dataStore.getOverallSummary(startDate: makeDate(year: 2025, month: 2, day: 1))

        XCTAssertEqual(summary.totalIncome, 200_000, "Should exclude Jan transaction before startDate")
        XCTAssertEqual(summary.totalExpense, 50_000)
        XCTAssertEqual(summary.netProfit, 150_000)
    }

    func testGetOverallSummary_withEndDateFilter() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 1, day: 15),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summary = dataStore.getOverallSummary(endDate: makeDate(year: 2025, month: 3, day: 31))

        XCTAssertEqual(summary.totalIncome, 100_000, "Should exclude June transaction after endDate")
        XCTAssertEqual(summary.totalExpense, 0)
        XCTAssertEqual(summary.netProfit, 100_000)
    }

    func testGetOverallSummary_withBothDateFilters() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        // Before range
        mutations(dataStore).addTransaction(
            type: .income, amount: 10_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        // In range
        mutations(dataStore).addTransaction(
            type: .income, amount: 50_000, date: makeDate(year: 2025, month: 3, day: 15),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 20_000, date: makeDate(year: 2025, month: 4, day: 1),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        // After range
        mutations(dataStore).addTransaction(
            type: .income, amount: 90_000, date: makeDate(year: 2025, month: 12, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summary = dataStore.getOverallSummary(
            startDate: makeDate(year: 2025, month: 2, day: 1),
            endDate: makeDate(year: 2025, month: 6, day: 30)
        )

        XCTAssertEqual(summary.totalIncome, 50_000)
        XCTAssertEqual(summary.totalExpense, 20_000)
        XCTAssertEqual(summary.netProfit, 30_000)
    }

    // MARK: - getCategorySummaries

    func testGetCategorySummaries_empty() {
        let summaries = dataStore.getCategorySummaries(type: .income)
        XCTAssertTrue(summaries.isEmpty)
    }

    func testGetCategorySummaries_incomeCategories() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 300_000, date: Date(),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: Date(),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: Date(),
            categoryId: "cat-service", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        // Expense should be excluded
        mutations(dataStore).addTransaction(
            type: .expense, amount: 50_000, date: Date(),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getCategorySummaries(type: .income)

        XCTAssertEqual(summaries.count, 2)

        // Should be sorted by total descending
        XCTAssertEqual(summaries[0].categoryId, "cat-sales")
        XCTAssertEqual(summaries[0].total, 500_000)
        XCTAssertEqual(summaries[0].percentage, 500_000.0 / 600_000.0 * 100, accuracy: 0.01)

        XCTAssertEqual(summaries[1].categoryId, "cat-service")
        XCTAssertEqual(summaries[1].total, 100_000)
        XCTAssertEqual(summaries[1].percentage, 100_000.0 / 600_000.0 * 100, accuracy: 0.01)
    }

    func testGetCategorySummaries_expenseCategories() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .expense, amount: 80_000, date: Date(),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 20_000, date: Date(),
            categoryId: "cat-tools", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getCategorySummaries(type: .expense)

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].categoryId, "cat-hosting")
        XCTAssertEqual(summaries[0].total, 80_000)
        XCTAssertEqual(summaries[0].percentage, 80.0, accuracy: 0.01)
        XCTAssertEqual(summaries[1].categoryId, "cat-tools")
        XCTAssertEqual(summaries[1].total, 20_000)
        XCTAssertEqual(summaries[1].percentage, 20.0, accuracy: 0.01)
    }

    func testGetCategorySummaries_sortedByAmountDescending() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .expense, amount: 10_000, date: Date(),
            categoryId: "cat-tools", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 50_000, date: Date(),
            categoryId: "cat-ads", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 30_000, date: Date(),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getCategorySummaries(type: .expense)

        XCTAssertEqual(summaries.count, 3)
        XCTAssertEqual(summaries[0].total, 50_000)
        XCTAssertEqual(summaries[1].total, 30_000)
        XCTAssertEqual(summaries[2].total, 10_000)
    }

    func testGetCategorySummaries_percentagesAddUpTo100() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 333_333, date: Date(),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 333_333, date: Date(),
            categoryId: "cat-service", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 333_334, date: Date(),
            categoryId: "cat-other-income", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getCategorySummaries(type: .income)
        let totalPercentage = summaries.reduce(0.0) { $0 + $1.percentage }

        XCTAssertEqual(totalPercentage, 100.0, accuracy: 0.1)
    }

    func testGetCategorySummaries_withDateFilter() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .expense, amount: 10_000, date: makeDate(year: 2025, month: 1, day: 15),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 40_000, date: makeDate(year: 2025, month: 3, day: 15),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 20_000, date: makeDate(year: 2025, month: 3, day: 20),
            categoryId: "cat-tools", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getCategorySummaries(
            type: .expense,
            startDate: makeDate(year: 2025, month: 2, day: 1),
            endDate: makeDate(year: 2025, month: 4, day: 30)
        )

        XCTAssertEqual(summaries.count, 2)
        let hostingTotal = summaries.first { $0.categoryId == "cat-hosting" }?.total
        XCTAssertEqual(hostingTotal, 40_000, "Should exclude Jan transaction")
    }

    func testGetCategorySummaries_unknownCategoryShowsFallbackName() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .expense, amount: 5_000, date: Date(),
            categoryId: "non-existent-cat", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getCategorySummaries(type: .expense)

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].categoryName, "不明")
    }

    // MARK: - getMonthlySummaries

    func testGetMonthlySummaries_returns12Months() {
        let summaries = dataStore.getMonthlySummaries(year: 2025)

        XCTAssertEqual(summaries.count, 12)
        XCTAssertEqual(summaries[0].month, "2025-01")
        XCTAssertEqual(summaries[11].month, "2025-12")
    }

    func testGetMonthlySummaries_allZeroWhenNoTransactions() {
        let summaries = dataStore.getMonthlySummaries(year: 2025)

        for summary in summaries {
            XCTAssertEqual(summary.income, 0)
            XCTAssertEqual(summary.expense, 0)
            XCTAssertEqual(summary.profit, 0)
        }
    }

    func testGetMonthlySummaries_correctIncomeExpenseProfit() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        // January income
        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 1, day: 10),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        // January expense
        mutations(dataStore).addTransaction(
            type: .expense, amount: 30_000, date: makeDate(year: 2025, month: 1, day: 20),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        // March income
        mutations(dataStore).addTransaction(
            type: .income, amount: 250_000, date: makeDate(year: 2025, month: 3, day: 5),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        // March expense
        mutations(dataStore).addTransaction(
            type: .expense, amount: 70_000, date: makeDate(year: 2025, month: 3, day: 15),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        // December income
        mutations(dataStore).addTransaction(
            type: .income, amount: 500_000, date: makeDate(year: 2025, month: 12, day: 25),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getMonthlySummaries(year: 2025)

        // January (index 0)
        XCTAssertEqual(summaries[0].month, "2025-01")
        XCTAssertEqual(summaries[0].income, 100_000)
        XCTAssertEqual(summaries[0].expense, 30_000)
        XCTAssertEqual(summaries[0].profit, 70_000)

        // February (index 1) - no transactions
        XCTAssertEqual(summaries[1].month, "2025-02")
        XCTAssertEqual(summaries[1].income, 0)
        XCTAssertEqual(summaries[1].expense, 0)
        XCTAssertEqual(summaries[1].profit, 0)

        // March (index 2)
        XCTAssertEqual(summaries[2].month, "2025-03")
        XCTAssertEqual(summaries[2].income, 250_000)
        XCTAssertEqual(summaries[2].expense, 70_000)
        XCTAssertEqual(summaries[2].profit, 180_000)

        // December (index 11)
        XCTAssertEqual(summaries[11].month, "2025-12")
        XCTAssertEqual(summaries[11].income, 500_000)
        XCTAssertEqual(summaries[11].expense, 0)
        XCTAssertEqual(summaries[11].profit, 500_000)
    }

    func testGetMonthlySummaries_ignoresTransactionsFromOtherYears() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2024, month: 6, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2026, month: 6, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getMonthlySummaries(year: 2025)

        for summary in summaries {
            XCTAssertEqual(summary.income, 0, "Month \(summary.month) should have no income from other years")
        }
    }

    func testGetMonthlySummaries_monthsAreSortedChronologically() {
        let summaries = dataStore.getMonthlySummaries(year: 2025)

        for i in 0..<summaries.count - 1 {
            XCTAssertTrue(summaries[i].month < summaries[i + 1].month)
        }
    }

    func testGetMonthlySummaries_multipleTransactionsInSameMonth() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 5, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 150_000, date: makeDate(year: 2025, month: 5, day: 15),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 40_000, date: makeDate(year: 2025, month: 5, day: 20),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getMonthlySummaries(year: 2025)
        let may = summaries[4]

        XCTAssertEqual(may.income, 250_000)
        XCTAssertEqual(may.expense, 40_000)
        XCTAssertEqual(may.profit, 210_000)
    }

    // MARK: - getFilteredTransactions: startDate / endDate

    func testGetFilteredTransactions_filterByStartDate() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 10_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "Jan",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 20_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "Mar",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 30_000, date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-sales", memo: "Jun",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter(startDate: makeDate(year: 2025, month: 2, day: 1))
        let result = dataStore.getFilteredTransactions(filter: filter)

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.date >= makeDate(year: 2025, month: 2, day: 1) })
    }

    func testGetFilteredTransactions_filterByEndDate() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 10_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "Jan",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 20_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "Mar",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 30_000, date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-sales", memo: "Jun",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter(endDate: makeDate(year: 2025, month: 4, day: 30))
        let result = dataStore.getFilteredTransactions(filter: filter)

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.date <= makeDate(year: 2025, month: 4, day: 30) })
    }

    func testGetFilteredTransactions_filterByDateRange() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 10_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "Jan",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 20_000, date: makeDate(year: 2025, month: 3, day: 15),
            categoryId: "cat-sales", memo: "Mar",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 30_000, date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-sales", memo: "Jun",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 40_000, date: makeDate(year: 2025, month: 9, day: 1),
            categoryId: "cat-sales", memo: "Sep",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter(
            startDate: makeDate(year: 2025, month: 2, day: 1),
            endDate: makeDate(year: 2025, month: 7, day: 31)
        )
        let result = dataStore.getFilteredTransactions(filter: filter)

        XCTAssertEqual(result.count, 2)
        let memos = Set(result.map(\.memo))
        XCTAssertTrue(memos.contains("Mar"))
        XCTAssertTrue(memos.contains("Jun"))
    }

    // MARK: - getFilteredTransactions: projectId

    func testGetFilteredTransactions_filterByProjectId() {
        let p1 = mutations(dataStore).addProject(name: "Alpha", description: "")
        let p2 = mutations(dataStore).addProject(name: "Beta", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: Date(),
            categoryId: "cat-sales", memo: "Alpha only",
            allocations: [(projectId: p1.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: Date(),
            categoryId: "cat-sales", memo: "Beta only",
            allocations: [(projectId: p2.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 300_000, date: Date(),
            categoryId: "cat-sales", memo: "Both",
            allocations: [
                (projectId: p1.id, ratio: 50),
                (projectId: p2.id, ratio: 50),
            ]
        )

        let filterAlpha = TransactionFilter(projectId: p1.id)
        let resultAlpha = dataStore.getFilteredTransactions(filter: filterAlpha)

        XCTAssertEqual(resultAlpha.count, 2)
        let alphaMemeos = Set(resultAlpha.map(\.memo))
        XCTAssertTrue(alphaMemeos.contains("Alpha only"))
        XCTAssertTrue(alphaMemeos.contains("Both"))

        let filterBeta = TransactionFilter(projectId: p2.id)
        let resultBeta = dataStore.getFilteredTransactions(filter: filterBeta)

        XCTAssertEqual(resultBeta.count, 2)
        let betaMemos = Set(resultBeta.map(\.memo))
        XCTAssertTrue(betaMemos.contains("Beta only"))
        XCTAssertTrue(betaMemos.contains("Both"))
    }

    // MARK: - getFilteredTransactions: categoryId

    func testGetFilteredTransactions_filterByCategoryId() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: Date(),
            categoryId: "cat-sales", memo: "Sales",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: Date(),
            categoryId: "cat-service", memo: "Service",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 50_000, date: Date(),
            categoryId: "cat-hosting", memo: "Hosting",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter(categoryId: "cat-sales")
        let result = dataStore.getFilteredTransactions(filter: filter)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].categoryId, "cat-sales")
        XCTAssertEqual(result[0].memo, "Sales")
    }

    // MARK: - getFilteredTransactions: type

    func testGetFilteredTransactions_filterByIncomeType() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: Date(),
            categoryId: "cat-sales", memo: "Income 1",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: Date(),
            categoryId: "cat-sales", memo: "Income 2",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 50_000, date: Date(),
            categoryId: "cat-hosting", memo: "Expense 1",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter(type: .income)
        let result = dataStore.getFilteredTransactions(filter: filter)

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.type == .income })
    }

    func testGetFilteredTransactions_filterByExpenseType() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: Date(),
            categoryId: "cat-sales", memo: "Income",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 30_000, date: Date(),
            categoryId: "cat-hosting", memo: "Hosting",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 20_000, date: Date(),
            categoryId: "cat-tools", memo: "Tools",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter(type: .expense)
        let result = dataStore.getFilteredTransactions(filter: filter)

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.type == .expense })
    }

    // MARK: - getFilteredTransactions: combined filters

    func testGetFilteredTransactions_combinedFilters() {
        let p1 = mutations(dataStore).addProject(name: "Alpha", description: "")
        let p2 = mutations(dataStore).addProject(name: "Beta", description: "")

        // Matches: income + cat-sales + p1 + in date range
        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 3, day: 15),
            categoryId: "cat-sales", memo: "Match",
            allocations: [(projectId: p1.id, ratio: 100)]
        )
        // Wrong type
        mutations(dataStore).addTransaction(
            type: .expense, amount: 50_000, date: makeDate(year: 2025, month: 3, day: 15),
            categoryId: "cat-sales", memo: "Wrong type",
            allocations: [(projectId: p1.id, ratio: 100)]
        )
        // Wrong project
        mutations(dataStore).addTransaction(
            type: .income, amount: 80_000, date: makeDate(year: 2025, month: 3, day: 15),
            categoryId: "cat-sales", memo: "Wrong project",
            allocations: [(projectId: p2.id, ratio: 100)]
        )
        // Wrong category
        mutations(dataStore).addTransaction(
            type: .income, amount: 60_000, date: makeDate(year: 2025, month: 3, day: 15),
            categoryId: "cat-service", memo: "Wrong category",
            allocations: [(projectId: p1.id, ratio: 100)]
        )
        // Out of date range
        mutations(dataStore).addTransaction(
            type: .income, amount: 40_000, date: makeDate(year: 2025, month: 8, day: 1),
            categoryId: "cat-sales", memo: "Out of range",
            allocations: [(projectId: p1.id, ratio: 100)]
        )

        let filter = TransactionFilter(
            startDate: makeDate(year: 2025, month: 1, day: 1),
            endDate: makeDate(year: 2025, month: 6, day: 30),
            projectId: p1.id,
            categoryId: "cat-sales",
            type: .income
        )
        let result = dataStore.getFilteredTransactions(filter: filter)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].memo, "Match")
    }

    // MARK: - getFilteredTransactions: empty filter returns all

    func testGetFilteredTransactions_emptyFilterReturnsAll() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 10_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .expense, amount: 20_000, date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter()
        let result = dataStore.getFilteredTransactions(filter: filter)

        XCTAssertEqual(result.count, 2)
    }

    // MARK: - getFilteredTransactions: sort by date

    func testGetFilteredTransactions_sortByDateDescending() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 10_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "Jan",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 20_000, date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-sales", memo: "Jun",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 30_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "Mar",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter()
        let sort = TransactionSort(field: .date, order: .desc)
        let result = dataStore.getFilteredTransactions(filter: filter, sort: sort)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].memo, "Jun")
        XCTAssertEqual(result[1].memo, "Mar")
        XCTAssertEqual(result[2].memo, "Jan")
    }

    func testGetFilteredTransactions_sortByDateAscending() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 10_000, date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-sales", memo: "Jun",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 20_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "Jan",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 30_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "Mar",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter()
        let sort = TransactionSort(field: .date, order: .asc)
        let result = dataStore.getFilteredTransactions(filter: filter, sort: sort)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].memo, "Jan")
        XCTAssertEqual(result[1].memo, "Mar")
        XCTAssertEqual(result[2].memo, "Jun")
    }

    // MARK: - getFilteredTransactions: sort by amount

    func testGetFilteredTransactions_sortByAmountDescending() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 50_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "50k",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2025, month: 2, day: 1),
            categoryId: "cat-sales", memo: "200k",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "100k",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter()
        let sort = TransactionSort(field: .amount, order: .desc)
        let result = dataStore.getFilteredTransactions(filter: filter, sort: sort)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].amount, 200_000)
        XCTAssertEqual(result[1].amount, 100_000)
        XCTAssertEqual(result[2].amount, 50_000)
    }

    func testGetFilteredTransactions_sortByAmountAscending() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 50_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "50k",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2025, month: 2, day: 1),
            categoryId: "cat-sales", memo: "200k",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "100k",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter()
        let sort = TransactionSort(field: .amount, order: .asc)
        let result = dataStore.getFilteredTransactions(filter: filter, sort: sort)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].amount, 50_000)
        XCTAssertEqual(result[1].amount, 100_000)
        XCTAssertEqual(result[2].amount, 200_000)
    }

    // MARK: - getFilteredTransactions: default sort

    func testGetFilteredTransactions_defaultSortIsDateDescending() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 10_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "Jan",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 20_000, date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-sales", memo: "Jun",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
            type: .income, amount: 30_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "Mar",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter()
        let result = dataStore.getFilteredTransactions(filter: filter)

        XCTAssertEqual(result[0].memo, "Jun")
        XCTAssertEqual(result[1].memo, "Mar")
        XCTAssertEqual(result[2].memo, "Jan")
    }

    // MARK: - getFilteredTransactions: no matches

    func testGetFilteredTransactions_noMatchesReturnsEmpty() {
        let project = mutations(dataStore).addProject(name: "P", description: "")

        mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let filter = TransactionFilter(type: .expense)
        let result = dataStore.getFilteredTransactions(filter: filter)

        XCTAssertTrue(result.isEmpty)
    }
}
