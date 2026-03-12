import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ReportingQueryUseCaseTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!
    var useCase: ReportingQueryUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = ReportingQueryUseCase(modelContext: context)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testOverallCategoryAndProjectSummariesMatchDataStoreIncludingCanonicalSupplemental() async throws {
        FeatureFlags.useCanonicalPosting = true
        let project = mutations(dataStore).addProject(name: "Reporting Project", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 4_000,
            date: makeDate(year: 2025, month: 5, day: 10),
            categoryId: "cat-tools",
            memo: "legacy expense",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let candidateResult = await dataStore.saveManualPostingCandidate(
            type: .expense,
            amount: 12_000,
            date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-tools",
            memo: "canonical supplemental",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxDeductibleRate: 100,
            taxAmount: 1_200,
            taxCodeId: TaxCode.standard10.rawValue,
            taxRate: 10,
            isTaxIncluded: false,
            taxCategory: .standardRate,
            candidateSource: .manual
        )

        let candidate: PostingCandidate
        switch candidateResult {
        case .success(let savedCandidate):
            candidate = savedCandidate
        case .failure(let error):
            XCTFail("manual candidate save should succeed: \(error.localizedDescription)")
            return
        }

        _ = try await dataStore.approvePostingCandidate(
            candidateId: candidate.id,
            description: "approved for reporting"
        )

        let startDate = makeDate(year: 2025, month: 1, day: 1)
        let endDate = makeDate(year: 2025, month: 12, day: 31)

        let expectedOverall = dataStore.getOverallSummary(startDate: startDate, endDate: endDate)
        let actualOverall = useCase.overallSummary(startDate: startDate, endDate: endDate)
        XCTAssertEqual(actualOverall.totalIncome, expectedOverall.totalIncome)
        XCTAssertEqual(actualOverall.totalExpense, expectedOverall.totalExpense)
        XCTAssertEqual(actualOverall.netProfit, expectedOverall.netProfit)

        let expectedCategories = dataStore.getCategorySummaries(type: .expense, startDate: startDate, endDate: endDate)
        let actualCategories = useCase.categorySummaries(type: .expense, startDate: startDate, endDate: endDate)
        XCTAssertEqual(actualCategories.map(\.categoryId), expectedCategories.map(\.categoryId))
        XCTAssertEqual(actualCategories.map(\.total), expectedCategories.map(\.total))

        let expectedProjects = dataStore.getAllProjectSummaries(startDate: startDate, endDate: endDate)
        let actualProjects = useCase.projectSummaries(startDate: startDate, endDate: endDate)
        XCTAssertEqual(actualProjects.map(\.id), expectedProjects.map(\.id))
        XCTAssertEqual(actualProjects.map(\.totalExpense), expectedProjects.map(\.totalExpense))
        XCTAssertEqual(actualProjects.map(\.profit), expectedProjects.map(\.profit))
    }

    func testMonthlySummariesMatchDataStoreForFiscalYearOrdering() {
        UserDefaults.standard.set(4, forKey: FiscalYearSettings.userDefaultsKey)

        let project = mutations(dataStore).addProject(name: "FY Project", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 10_000,
            date: makeDate(year: 2025, month: 4, day: 10),
            categoryId: "cat-sales",
            memo: "april income",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 3_000,
            date: makeDate(year: 2026, month: 3, day: 20),
            categoryId: "cat-tools",
            memo: "march expense",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let expected = dataStore.getMonthlySummaries(fiscalYear: 2025, startMonth: 4)
        let actual = useCase.monthlySummaries(fiscalYear: 2025, startMonth: 4)

        XCTAssertEqual(actual.map(\.month), expected.map(\.month))
        XCTAssertEqual(actual.map(\.income), expected.map(\.income))
        XCTAssertEqual(actual.map(\.expense), expected.map(\.expense))
        XCTAssertEqual(actual.map(\.profit), expected.map(\.profit))
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
