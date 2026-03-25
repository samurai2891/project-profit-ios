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
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = ProjectQueryUseCase(modelContext: context)
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testListSnapshotMatchesProjectListsAndSummaries() {
        let active = mutations(dataStore).addProject(name: "進行中案件", description: "")
        let archived = mutations(dataStore).addProject(name: "アーカイブ案件", description: "")
        archived.isArchived = true
        let categoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .expense })?.id)
        _ = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "詳細案件", description: "")
        let expenseCategoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .expense })?.id)
        let incomeCategoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .income })?.id)
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5_000,
            date: makeDate(year: 2026, month: 5, day: 3),
            categoryId: expenseCategoryId,
            memo: "expense",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        _ = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "状態確認", description: "")

        let snapshot = useCase.detailSnapshot(projectId: project.id)

        XCTAssertEqual(snapshot.canMutateLegacyTransactions, dataStore.isLegacyTransactionEditingEnabled)
        XCTAssertEqual(snapshot.legacyTransactionMutationDisabledMessage, dataStore.legacyTransactionMutationDisabledMessage)
    }

    func testDetailSnapshotYearlyProfitLossUsesCanonicalProjectAllocations() async throws {
        FeatureFlags.useCanonicalPosting = true
        let project = mutations(dataStore).addProject(name: "Canonical案件", description: "")

        try await approveManualCandidate(
            type: .expense,
            amount: 12_000,
            date: makeDate(year: 2026, month: 5, day: 10),
            categoryId: "cat-tools",
            memo: "canonical supplemental",
            allocations: [(projectId: project.id, ratio: 100)],
            candidateSource: .manual
        )

        let snapshot = useCase.detailSnapshot(projectId: project.id)

        XCTAssertEqual(snapshot.summary?.totalExpense, 12_000)
        XCTAssertEqual(snapshot.yearlyProfitLoss.map(\.expense), [12_000])
        XCTAssertEqual(snapshot.yearlyProfitLoss.map(\.profit), [-12_000])
        XCTAssertTrue(snapshot.recentTransactions.isEmpty)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
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
            description: "approved for project query test"
        )
    }
}
