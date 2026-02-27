import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class TransactionLogTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!

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

    private func createProject() -> PPProject {
        dataStore.addProject(name: "Test Project", description: "")
    }

    private func createTransaction(projectId: UUID, amount: Int = 10000) -> PPTransaction {
        dataStore.addTransaction(
            type: .income,
            amount: amount,
            date: Date(),
            categoryId: "cat-sales",
            memo: "Test memo",
            allocations: [(projectId: projectId, ratio: 100)]
        )
    }

    // MARK: - testUpdateLogsAmountChange

    func testUpdateLogsAmountChange() {
        let project = createProject()
        let transaction = createTransaction(projectId: project.id, amount: 10000)

        dataStore.updateTransaction(id: transaction.id, amount: 20000)

        let logs = dataStore.getTransactionLogs(for: transaction.id)
        let amountLog = logs.first(where: { $0.fieldName == "amount" })

        XCTAssertNotNil(amountLog, "Expected a log entry for amount change")
        XCTAssertEqual(amountLog?.oldValue, "10000")
        XCTAssertEqual(amountLog?.newValue, "20000")
        XCTAssertEqual(amountLog?.transactionId, transaction.id)
    }

    // MARK: - testNoLogForUnchangedField

    func testNoLogForUnchangedField() {
        let project = createProject()
        let transaction = createTransaction(projectId: project.id, amount: 10000)

        // Update with the same amount value
        dataStore.updateTransaction(id: transaction.id, amount: 10000)

        let logs = dataStore.getTransactionLogs(for: transaction.id)
        let amountLogs = logs.filter { $0.fieldName == "amount" }

        XCTAssertTrue(amountLogs.isEmpty, "No log entry should be created when the value is unchanged")
    }

    // MARK: - testMultipleFieldChanges

    func testMultipleFieldChanges() {
        let project = createProject()
        let transaction = createTransaction(projectId: project.id, amount: 10000)
        let originalType = transaction.type
        let originalCategoryId = transaction.categoryId

        dataStore.updateTransaction(
            id: transaction.id,
            type: .expense,
            amount: 25000,
            categoryId: "cat-hosting"
        )

        let logs = dataStore.getTransactionLogs(for: transaction.id)

        let typeLog = logs.first(where: { $0.fieldName == "type" })
        XCTAssertNotNil(typeLog, "Expected a log entry for type change")
        XCTAssertEqual(typeLog?.oldValue, originalType.rawValue)
        XCTAssertEqual(typeLog?.newValue, TransactionType.expense.rawValue)

        let amountLog = logs.first(where: { $0.fieldName == "amount" })
        XCTAssertNotNil(amountLog, "Expected a log entry for amount change")
        XCTAssertEqual(amountLog?.oldValue, "10000")
        XCTAssertEqual(amountLog?.newValue, "25000")

        let categoryLog = logs.first(where: { $0.fieldName == "categoryId" })
        XCTAssertNotNil(categoryLog, "Expected a log entry for categoryId change")
        XCTAssertEqual(categoryLog?.oldValue, originalCategoryId)
        XCTAssertEqual(categoryLog?.newValue, "cat-hosting")

        XCTAssertEqual(logs.count, 3, "Expected exactly 3 log entries for 3 field changes")
    }

    // MARK: - testGetTransactionLogs

    func testGetTransactionLogs() {
        let project = createProject()
        let transaction = createTransaction(projectId: project.id, amount: 5000)

        // First update: change amount
        dataStore.updateTransaction(id: transaction.id, amount: 8000)

        // Small delay so changedAt timestamps differ
        Thread.sleep(forTimeInterval: 0.05)

        // Second update: change amount again
        dataStore.updateTransaction(id: transaction.id, amount: 12000)

        let logs = dataStore.getTransactionLogs(for: transaction.id)
        let amountLogs = logs.filter { $0.fieldName == "amount" }

        XCTAssertEqual(amountLogs.count, 2, "Expected 2 amount change log entries")

        // getTransactionLogs returns reverse chronological order (newest first)
        XCTAssertEqual(amountLogs[0].newValue, "12000", "Most recent log should be first")
        XCTAssertEqual(amountLogs[0].oldValue, "8000")
        XCTAssertEqual(amountLogs[1].newValue, "8000", "Older log should be second")
        XCTAssertEqual(amountLogs[1].oldValue, "5000")

        // Verify overall ordering: first log's changedAt >= second log's changedAt
        XCTAssertGreaterThanOrEqual(logs[0].changedAt, logs[1].changedAt,
            "Logs should be in reverse chronological order")
    }
}
