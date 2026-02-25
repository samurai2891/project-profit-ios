import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class FiscalYearDataStoreTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self, PPAccount.self, PPJournalEntry.self, PPJournalLine.self, PPAccountingProfile.self,
            PPFixedAsset.self,
            configurations: config
        )
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

    // MARK: - getProjectSummary with date filters

    func testGetProjectSummary_withStartDate() {
        let project = dataStore.addProject(name: "P", description: "")

        dataStore.addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 1, day: 15),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2025, month: 5, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summary = dataStore.getProjectSummary(
            projectId: project.id,
            startDate: makeDate(year: 2025, month: 4, day: 1)
        )

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.totalIncome, 200_000, "Should exclude Jan transaction before startDate")
    }

    func testGetProjectSummary_withEndDate() {
        let project = dataStore.addProject(name: "P", description: "")

        dataStore.addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2025, month: 8, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summary = dataStore.getProjectSummary(
            projectId: project.id,
            endDate: makeDate(year: 2025, month: 6, day: 30)
        )

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.totalIncome, 100_000, "Should exclude Aug transaction after endDate")
    }

    func testGetProjectSummary_withBothDates() {
        let project = dataStore.addProject(name: "P", description: "")

        dataStore.addTransaction(
            type: .income, amount: 50_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 5, day: 15),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .expense, amount: 30_000, date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2026, month: 1, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summary = dataStore.getProjectSummary(
            projectId: project.id,
            startDate: makeDate(year: 2025, month: 4, day: 1),
            endDate: makeDate(year: 2025, month: 12, day: 31)
        )!

        XCTAssertEqual(summary.totalIncome, 100_000)
        XCTAssertEqual(summary.totalExpense, 30_000)
        XCTAssertEqual(summary.profit, 70_000)
    }

    func testGetProjectSummary_noDatesIsBackwardCompatible() {
        let project = dataStore.addProject(name: "P", description: "")

        dataStore.addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2024, month: 1, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2026, month: 12, day: 31),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summary = dataStore.getProjectSummary(projectId: project.id)!
        XCTAssertEqual(summary.totalIncome, 300_000, "No date filters should return all transactions")
    }

    // MARK: - getAllProjectSummaries with date filters

    func testGetAllProjectSummaries_withDateFilter() {
        let p1 = dataStore.addProject(name: "Alpha", description: "")
        let p2 = dataStore.addProject(name: "Beta", description: "")

        dataStore.addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 5, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: p1.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2025, month: 1, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: p2.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .income, amount: 50_000, date: makeDate(year: 2025, month: 7, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: p2.id, ratio: 100)]
        )

        let summaries = dataStore.getAllProjectSummaries(
            startDate: makeDate(year: 2025, month: 4, day: 1),
            endDate: makeDate(year: 2025, month: 12, day: 31)
        )

        let alpha = summaries.first { $0.id == p1.id }!
        let beta = summaries.first { $0.id == p2.id }!

        XCTAssertEqual(alpha.totalIncome, 100_000)
        XCTAssertEqual(beta.totalIncome, 50_000, "Should exclude Jan transaction")
    }

    // MARK: - getMonthlySummaries(fiscalYear:startMonth:)

    func testGetMonthlySummaries_fiscal_returns12Months() {
        let summaries = dataStore.getMonthlySummaries(fiscalYear: 2025, startMonth: 4)
        XCTAssertEqual(summaries.count, 12)
    }

    func testGetMonthlySummaries_fiscal_aprilStart_correctOrder() {
        let summaries = dataStore.getMonthlySummaries(fiscalYear: 2025, startMonth: 4)

        // First month should be April 2025
        XCTAssertEqual(summaries[0].month, "2025-04")
        // Last month should be March 2026
        XCTAssertEqual(summaries[11].month, "2026-03")
    }

    func testGetMonthlySummaries_fiscal_correctData() {
        let project = dataStore.addProject(name: "P", description: "")

        // In FY2025 (Apr 2025 - Mar 2026)
        dataStore.addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 5, day: 10),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .expense, amount: 30_000, date: makeDate(year: 2025, month: 5, day: 20),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2026, month: 1, day: 15),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        // Outside FY2025
        dataStore.addTransaction(
            type: .income, amount: 500_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getMonthlySummaries(fiscalYear: 2025, startMonth: 4)

        // May (index 1 in fiscal year starting from April)
        let may = summaries[1]
        XCTAssertEqual(may.month, "2025-05")
        XCTAssertEqual(may.income, 100_000)
        XCTAssertEqual(may.expense, 30_000)
        XCTAssertEqual(may.profit, 70_000)

        // January next year (index 9)
        let jan = summaries[9]
        XCTAssertEqual(jan.month, "2026-01")
        XCTAssertEqual(jan.income, 200_000)

        // March before fiscal year should not appear
        let march = summaries.first { $0.month == "2025-03" }
        XCTAssertNil(march, "March 2025 is not in FY2025 with April start")
    }

    func testGetMonthlySummaries_fiscal_januaryStart_sameAsCalendar() {
        let project = dataStore.addProject(name: "P", description: "")

        dataStore.addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let summaries = dataStore.getMonthlySummaries(fiscalYear: 2025, startMonth: 1)

        XCTAssertEqual(summaries[0].month, "2025-01")
        XCTAssertEqual(summaries[11].month, "2025-12")

        let march = summaries[2]
        XCTAssertEqual(march.month, "2025-03")
        XCTAssertEqual(march.income, 100_000)
    }

    func testGetMonthlySummaries_fiscal_allZeroWhenNoTransactions() {
        let summaries = dataStore.getMonthlySummaries(fiscalYear: 2025, startMonth: 4)

        for summary in summaries {
            XCTAssertEqual(summary.income, 0)
            XCTAssertEqual(summary.expense, 0)
            XCTAssertEqual(summary.profit, 0)
        }
    }

    // MARK: - getYearlyProjectSummaries

    func testGetYearlyProjectSummaries_emptyWhenNoTransactions() {
        let project = dataStore.addProject(name: "P", description: "")
        let result = dataStore.getYearlyProjectSummaries(projectId: project.id, startMonth: 4)
        XCTAssertTrue(result.isEmpty)
    }

    func testGetYearlyProjectSummaries_singleFiscalYear() {
        let project = dataStore.addProject(name: "P", description: "")

        dataStore.addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 5, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .expense, amount: 40_000, date: makeDate(year: 2025, month: 8, day: 1),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let result = dataStore.getYearlyProjectSummaries(projectId: project.id, startMonth: 4)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].fiscalYear, 2025)
        XCTAssertEqual(result[0].label, "2025年度")
        XCTAssertEqual(result[0].income, 100_000)
        XCTAssertEqual(result[0].expense, 40_000)
        XCTAssertEqual(result[0].profit, 60_000)
    }

    func testGetYearlyProjectSummaries_multipleFiscalYears() {
        let project = dataStore.addProject(name: "P", description: "")

        // FY2024: Apr 2024 - Mar 2025
        dataStore.addTransaction(
            type: .income, amount: 50_000, date: makeDate(year: 2024, month: 6, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        // FY2025: Apr 2025 - Mar 2026
        dataStore.addTransaction(
            type: .income, amount: 200_000, date: makeDate(year: 2025, month: 7, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .expense, amount: 80_000, date: makeDate(year: 2026, month: 2, day: 1),
            categoryId: "cat-hosting", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let result = dataStore.getYearlyProjectSummaries(projectId: project.id, startMonth: 4)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].fiscalYear, 2024)
        XCTAssertEqual(result[0].income, 50_000)
        XCTAssertEqual(result[0].expense, 0)

        XCTAssertEqual(result[1].fiscalYear, 2025)
        XCTAssertEqual(result[1].income, 200_000)
        XCTAssertEqual(result[1].expense, 80_000)
        XCTAssertEqual(result[1].profit, 120_000)
    }

    func testGetYearlyProjectSummaries_januaryStart() {
        let project = dataStore.addProject(name: "P", description: "")

        dataStore.addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let result = dataStore.getYearlyProjectSummaries(projectId: project.id, startMonth: 1)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].fiscalYear, 2025)
        XCTAssertEqual(result[0].label, "2025年")
        XCTAssertEqual(result[0].income, 100_000)
    }

    func testGetYearlyProjectSummaries_nonExistentProject() {
        let result = dataStore.getYearlyProjectSummaries(projectId: UUID(), startMonth: 4)
        XCTAssertTrue(result.isEmpty)
    }

    func testGetYearlyProjectSummaries_partialAllocations() {
        let projectA = dataStore.addProject(name: "A", description: "")
        let projectB = dataStore.addProject(name: "B", description: "")

        // 100,000 split 60/40
        dataStore.addTransaction(
            type: .income, amount: 100_000, date: makeDate(year: 2025, month: 5, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 60),
                (projectId: projectB.id, ratio: 40),
            ]
        )

        let resultA = dataStore.getYearlyProjectSummaries(projectId: projectA.id, startMonth: 4)
        XCTAssertEqual(resultA[0].income, 60_000)

        let resultB = dataStore.getYearlyProjectSummaries(projectId: projectB.id, startMonth: 4)
        XCTAssertEqual(resultB[0].income, 40_000)
    }

    func testGetYearlyProjectSummaries_sortedChronologically() {
        let project = dataStore.addProject(name: "P", description: "")

        // FY2023
        dataStore.addTransaction(
            type: .income, amount: 10_000, date: makeDate(year: 2023, month: 6, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        // FY2025
        dataStore.addTransaction(
            type: .income, amount: 30_000, date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        // FY2024
        dataStore.addTransaction(
            type: .income, amount: 20_000, date: makeDate(year: 2024, month: 6, day: 1),
            categoryId: "cat-sales", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let result = dataStore.getYearlyProjectSummaries(projectId: project.id, startMonth: 4)

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].fiscalYear, 2023)
        XCTAssertEqual(result[1].fiscalYear, 2024)
        XCTAssertEqual(result[2].fiscalYear, 2025)
    }
}
