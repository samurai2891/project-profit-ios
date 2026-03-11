import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ProjectQueryUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: ProjectQueryUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = ProjectQueryUseCase(modelContext: context)
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testListSnapshotMatchesProjectListsAndSummaries() {
        let active = dataStore.addProject(name: "進行中案件", description: "")
        let archived = dataStore.addProject(name: "アーカイブ案件", description: "")
        archived.isArchived = true
        let categoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .expense })?.id)
        _ = dataStore.addTransaction(
            type: .expense,
            amount: 9_000,
            date: makeDate(year: 2026, month: 4, day: 1),
            categoryId: categoryId,
            memo: "project summary",
            allocations: [(projectId: active.id, ratio: 100)]
        )
        dataStore.loadData()

        let snapshot = useCase.listSnapshot()

        XCTAssertEqual(snapshot.activeProjects.map(\.id), [active.id])
        XCTAssertEqual(snapshot.archivedProjects.map(\.id), [archived.id])
        XCTAssertEqual(snapshot.summariesById[active.id]?.totalExpense, 9_000)
    }

    func testDetailSnapshotMatchesRecentTransactionsAndYearlyProfitLoss() {
        let project = dataStore.addProject(name: "詳細案件", description: "")
        let expenseCategoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .expense })?.id)
        let incomeCategoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .income })?.id)
        _ = dataStore.addTransaction(
            type: .expense,
            amount: 5_000,
            date: makeDate(year: 2026, month: 5, day: 3),
            categoryId: expenseCategoryId,
            memo: "expense",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        _ = dataStore.addTransaction(
            type: .income,
            amount: 12_000,
            date: makeDate(year: 2026, month: 5, day: 4),
            categoryId: incomeCategoryId,
            memo: "income",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.loadData()

        let snapshot = useCase.detailSnapshot(projectId: project.id)

        XCTAssertEqual(snapshot.project?.id, project.id)
        XCTAssertEqual(snapshot.summary?.totalIncome, 12_000)
        XCTAssertEqual(snapshot.summary?.totalExpense, 5_000)
        XCTAssertEqual(snapshot.recentTransactions.map(\.amount), [12_000, 5_000])
        XCTAssertEqual(snapshot.yearlyProfitLoss.first?.profit, 7_000)
        XCTAssertEqual(snapshot.categoryNamesById[expenseCategoryId], dataStore.getCategory(id: expenseCategoryId)?.name)
    }

    func testDetailSnapshotIncludesLegacyMutationState() {
        let project = dataStore.addProject(name: "状態確認", description: "")

        let snapshot = useCase.detailSnapshot(projectId: project.id)

        XCTAssertEqual(snapshot.canMutateLegacyTransactions, dataStore.isLegacyTransactionEditingEnabled)
        XCTAssertEqual(snapshot.legacyTransactionMutationDisabledMessage, dataStore.legacyTransactionMutationDisabledMessage)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
