import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class AppShellWorkflowUseCaseTests: XCTestCase {
    func testReloadStoreStateMatchesDirectReloadSequence() throws {
        let container = try TestModelContainer.create()
        let context = ModelContext(container)
        let setupStore = ProjectProfit.DataStore(modelContext: context)
        setupStore.loadData()

        let projectA = setupStore.addProject(name: "Project A", description: "")
        let projectB = setupStore.addProject(name: "Project B", description: "")
        _ = setupStore.addTransaction(
            type: .expense,
            amount: 10_000,
            date: Self.makeDate(year: 2024, month: 2, day: 28),
            categoryId: "cat-hosting",
            memo: "shell reload",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        let storedProjectA = try XCTUnwrap(setupStore.getProject(id: projectA.id))
        storedProjectA.status = .completed
        storedProjectA.completedAt = Self.makeDate(year: 2024, month: 2, day: 15)
        try context.save()

        let workflowStore = ProjectProfit.DataStore(modelContext: context)
        let directStore = ProjectProfit.DataStore(modelContext: context)
        let useCase = AppShellWorkflowUseCase()

        useCase.reloadStoreState(dataStore: workflowStore)
        directStore.loadData()
        directStore.recalculateAllPartialPeriodProjects()

        XCTAssertEqual(workflowStore.projects.count, directStore.projects.count)
        XCTAssertEqual(workflowStore.transactions.count, directStore.transactions.count)
        XCTAssertEqual(workflowStore.recurringTransactions.count, directStore.recurringTransactions.count)

        let workflowTransaction = try XCTUnwrap(workflowStore.transactions.first)
        let directTransaction = try XCTUnwrap(directStore.transactions.first)
        XCTAssertEqual(workflowTransaction.allocations, directTransaction.allocations)
    }

    func testRefreshRecurringPreviewMatchesRecurringWorkflowUseCase() throws {
        let container = try TestModelContainer.create()
        let context = ModelContext(container)
        let store = ProjectProfit.DataStore(modelContext: context)
        store.loadData()

        let project = store.addProject(name: "Preview PJ", description: "")
        let recurring = PPRecurringTransaction(
            name: "毎月サーバー",
            type: .expense,
            amount: 5_000,
            categoryId: "cat-hosting",
            memo: "[定期] 毎月サーバー",
            allocationMode: .manual,
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 5_000)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        context.insert(recurring)
        try context.save()
        store.loadData()

        let useCase = AppShellWorkflowUseCase()
        let workflowItems = useCase.refreshRecurringPreview(dataStore: store)
        let directItems = RecurringWorkflowUseCase(modelContext: context).previewRecurringTransactions()

        XCTAssertEqual(workflowItems.map(\.recurringId), directItems.map(\.recurringId))
        XCTAssertEqual(workflowItems.map(\.scheduledDate), directItems.map(\.scheduledDate))
        XCTAssertEqual(workflowItems.map(\.amount), directItems.map(\.amount))
    }

    func testCurrentErrorAndDismissMirrorAlertState() throws {
        let container = try TestModelContainer.create()
        let store = ProjectProfit.DataStore(modelContext: ModelContext(container))
        let useCase = AppShellWorkflowUseCase()

        XCTAssertNil(useCase.currentError(dataStore: store))

        store.lastError = .invalidInput(message: "app shell error")
        XCTAssertEqual(useCase.currentError(dataStore: store)?.errorDescription, "app shell error")

        useCase.dismissCurrentError(dataStore: store)
        XCTAssertNil(useCase.currentError(dataStore: store))
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: year,
            month: month,
            day: day
        )
        return components.date!
    }
}
