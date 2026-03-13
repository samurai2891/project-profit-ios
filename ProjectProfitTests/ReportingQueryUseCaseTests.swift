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
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = ReportingQueryUseCase(modelContext: context)
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testOverallCategoryAndProjectSummariesUseApprovedCanonicalJournals() async throws {
        FeatureFlags.useCanonicalPosting = true
        let project = mutations(dataStore).addProject(name: "Reporting Project", description: "")
        try await approveManualCandidate(
            type: .expense,
            amount: 4_000,
            date: makeDate(year: 2025, month: 5, day: 10),
            categoryId: "cat-tools",
            memo: "legacy expense",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        try await approveManualCandidate(
            type: .expense,
            amount: 12_000,
            date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-tools",
            memo: "canonical supplemental",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            candidateSource: .manual
        )

        let startDate = makeDate(year: 2025, month: 1, day: 1)
        let endDate = makeDate(year: 2025, month: 12, day: 31)

        let actualOverall = useCase.overallSummary(startDate: startDate, endDate: endDate)
        XCTAssertEqual(actualOverall.totalIncome, 0)
        XCTAssertEqual(actualOverall.totalExpense, 16_000)
        XCTAssertEqual(actualOverall.netProfit, -16_000)

        let actualCategories = useCase.categorySummaries(type: .expense, startDate: startDate, endDate: endDate)
        XCTAssertEqual(actualCategories.map(\.categoryId), ["cat-tools"])
        XCTAssertEqual(actualCategories.map(\.total), [16_000])

        let actualProjects = useCase.projectSummaries(startDate: startDate, endDate: endDate)
        XCTAssertEqual(actualProjects.map(\.id), [project.id])
        XCTAssertEqual(actualProjects.map(\.totalExpense), [16_000])
        XCTAssertEqual(actualProjects.map(\.profit), [-16_000])
    }

    func testMonthlySummariesUseApprovedCanonicalJournalsForFiscalYearOrdering() async throws {
        UserDefaults.standard.set(4, forKey: FiscalYearSettings.userDefaultsKey)
        FeatureFlags.useCanonicalPosting = true

        let project = mutations(dataStore).addProject(name: "FY Project", description: "")
        try await approveManualCandidate(
            type: .income,
            amount: 10_000,
            date: makeDate(year: 2025, month: 4, day: 10),
            categoryId: "cat-sales",
            memo: "april income",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        try await approveManualCandidate(
            type: .expense,
            amount: 3_000,
            date: makeDate(year: 2026, month: 3, day: 20),
            categoryId: "cat-tools",
            memo: "march expense",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let actual = useCase.monthlySummaries(fiscalYear: 2025, startMonth: 4)

        XCTAssertEqual(actual.map(\.month), [
            "2025-04", "2025-05", "2025-06", "2025-07", "2025-08", "2025-09",
            "2025-10", "2025-11", "2025-12", "2026-01", "2026-02", "2026-03",
        ])
        XCTAssertEqual(actual.map(\.income), [10_000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(actual.map(\.expense), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3_000])
        XCTAssertEqual(actual.map(\.profit), [10_000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, -3_000])
    }

    private func approveManualCandidate(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        paymentAccountId: String = "acct-cash",
        candidateSource: CandidateSource = .manual
    ) async throws {
        let result = await dataStore.saveManualPostingCandidate(
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocations,
            paymentAccountId: paymentAccountId,
            candidateSource: candidateSource
        )

        let candidate: PostingCandidate
        switch result {
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
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
