import XCTest
import SwiftData
@testable import ProjectProfit

// MARK: - RecurringProcessingTests

@MainActor
final class RecurringProcessingTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: DataStore!

    private let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self,
            configurations: config
        )
        context = ModelContext(container)
        dataStore = DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a project in the data store and returns it.
    private func makeProject(name: String = "TestProject") -> PPProject {
        dataStore.addProject(name: name, description: "desc")
    }

    /// Returns the current date components used by processRecurringTransactions.
    private var todayComponents: DateComponents {
        calendar.dateComponents([.year, .month, .day], from: todayDate())
    }

    /// A dayOfMonth value guaranteed to be in the past (relative to today).
    /// Falls back to 1 when today is already the 1st.
    private var pastDayOfMonth: Int {
        let day = todayComponents.day!
        return day >= 2 ? 1 : 1 // day 1 is always <= today when today >= 1
    }

    /// A dayOfMonth value guaranteed to be in the future within this month.
    /// Returns nil when today is the 28th (last valid dayOfMonth), meaning
    /// there is no future day available this month.
    private var futureDayOfMonth: Int? {
        let day = todayComponents.day!
        let candidate = min(day + 1, 28)
        return candidate > day ? candidate : nil
    }

    /// A month number guaranteed to have already passed this year.
    /// Returns nil when we are in January (no prior month).
    private var pastMonth: Int? {
        let month = todayComponents.month!
        return month >= 2 ? month - 1 : nil
    }

    /// A month number guaranteed to be in the future this year.
    /// Returns nil when we are in December.
    private var futureMonth: Int? {
        let month = todayComponents.month!
        return month <= 11 ? month + 1 : nil
    }

    /// Fetches all PPTransaction objects from the model context.
    private func fetchAllTransactions() -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>()
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetches the recurring transaction by ID from the model context.
    private func fetchRecurring(id: UUID) -> PPRecurringTransaction? {
        let descriptor = FetchDescriptor<PPRecurringTransaction>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.first { $0.id == id }
    }

    // MARK: - 1. Monthly Generation

    func testMonthlyGeneration_dayHasPassed_createsTransaction() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        let recurring = dataStore.addRecurring(
            name: "Monthly Fee",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "server",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 1, "Should generate exactly 1 transaction")

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1)

        let tx = transactions.first!
        XCTAssertEqual(tx.type, .expense)
        XCTAssertEqual(tx.amount, 10000)
        XCTAssertEqual(tx.categoryId, "cat-hosting")

        // Verify date matches target (year/month/dayOfMonth)
        let txComps = calendar.dateComponents([.year, .month, .day], from: tx.date)
        XCTAssertEqual(txComps.year, todayComponents.year)
        XCTAssertEqual(txComps.month, todayComponents.month)
        XCTAssertEqual(txComps.day, dayOfMonth)

        // Verify lastGeneratedDate was updated
        let updated = fetchRecurring(id: recurring.id)
        XCTAssertNotNil(updated?.lastGeneratedDate)
    }

    // MARK: - 2. Monthly Not Yet Due

    func testMonthlyNotYetDue_noTransactionCreated() {
        guard let futureDay = futureDayOfMonth else {
            // Today is the 28th; every valid dayOfMonth has passed. Skip gracefully.
            return
        }

        let project = makeProject()

        dataStore.addRecurring(
            name: "Future Monthly",
            type: .expense,
            amount: 5000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: futureDay
        )

        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 0, "Should not generate a transaction when dayOfMonth is in the future")
        XCTAssertTrue(fetchAllTransactions().isEmpty)
    }

    // MARK: - 3. Monthly Already Generated This Month

    func testMonthlyAlreadyGenerated_noDuplicate() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        let recurring = dataStore.addRecurring(
            name: "Already Done",
            type: .income,
            amount: 20000,
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        // Simulate that it was already generated this month by setting lastGeneratedDate
        let currentYear = todayComponents.year!
        let currentMonth = todayComponents.month!
        let alreadyGenDate = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: dayOfMonth))!
        recurring.lastGeneratedDate = alreadyGenDate
        try? context.save()

        // Reload so dataStore sees the updated recurring
        dataStore.loadData()

        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 0, "Should not generate a duplicate for the same month")
        XCTAssertTrue(fetchAllTransactions().isEmpty)
    }

    // MARK: - 4. Yearly Generation

    func testYearlyGeneration_monthHasPassed_createsTransaction() {
        guard let passedMonth = pastMonth else {
            // January -- no past month available. Skip gracefully.
            return
        }

        let project = makeProject()
        let dayOfMonth = 1

        let recurring = dataStore.addRecurring(
            name: "Annual License",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "license",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: dayOfMonth,
            monthOfYear: passedMonth
        )

        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 1, "Should generate 1 transaction for yearly recurring with past month")

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1)

        let tx = transactions.first!
        let txComps = calendar.dateComponents([.year, .month, .day], from: tx.date)
        XCTAssertEqual(txComps.year, todayComponents.year)
        XCTAssertEqual(txComps.month, passedMonth)
        XCTAssertEqual(txComps.day, dayOfMonth)

        let updated = fetchRecurring(id: recurring.id)
        XCTAssertNotNil(updated?.lastGeneratedDate)
    }

    // MARK: - 5. Yearly Not Yet Due

    func testYearlyNotYetDue_noTransactionCreated() {
        guard let upcoming = futureMonth else {
            // December -- no future month this year. Skip gracefully.
            return
        }

        let project = makeProject()

        dataStore.addRecurring(
            name: "Future Annual",
            type: .expense,
            amount: 60000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 15,
            monthOfYear: upcoming
        )

        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 0, "Should not generate when monthOfYear is in the future")
        XCTAssertTrue(fetchAllTransactions().isEmpty)
    }

    // MARK: - 6. Skip Dates

    func testSkipDates_matchingNextDate_skipsButUpdatesLastGenerated() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth
        let currentYear = todayComponents.year!
        let currentMonth = todayComponents.month!

        // The target date that processRecurringTransactions would generate
        let targetDate = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: dayOfMonth))!

        let recurring = dataStore.addRecurring(
            name: "Skippable",
            type: .expense,
            amount: 8000,
            categoryId: "cat-hosting",
            memo: "skip this",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        // Add the target date to skipDates
        recurring.skipDates = [targetDate]
        try? context.save()
        dataStore.loadData()

        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 0, "Should not count skipped transactions")
        XCTAssertTrue(fetchAllTransactions().isEmpty, "No transaction should be created for skipped date")

        // lastGeneratedDate should still be updated
        let updated = fetchRecurring(id: recurring.id)
        XCTAssertNotNil(updated?.lastGeneratedDate, "lastGeneratedDate should be set even when skipped")

        // The skip date should be removed from the list
        XCTAssertTrue(updated?.skipDates.isEmpty ?? false, "Used skip date should be removed")
    }

    // MARK: - 7. Inactive Recurring

    func testInactiveRecurring_noTransactionCreated() {
        let project = makeProject()

        let recurring = dataStore.addRecurring(
            name: "Inactive",
            type: .expense,
            amount: 3000,
            categoryId: "cat-ads",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth
        )

        // Deactivate
        recurring.isActive = false
        try? context.save()
        dataStore.loadData()

        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 0, "Inactive recurring should not generate transactions")
        XCTAssertTrue(fetchAllTransactions().isEmpty)
    }

    // MARK: - 8. Empty Allocations

    func testEmptyAllocations_skipped() {
        // Create recurring with no allocations
        let recurring = PPRecurringTransaction(
            name: "No Alloc",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth,
            isActive: true
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 0, "Recurring with empty allocations should be skipped")
        XCTAssertTrue(fetchAllTransactions().isEmpty)
    }

    // MARK: - 9. Multiple Recurring

    func testMultipleRecurring_allEligibleProcessed() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        // Eligible recurring 1
        dataStore.addRecurring(
            name: "Recurring A",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        // Eligible recurring 2
        dataStore.addRecurring(
            name: "Recurring B",
            type: .income,
            amount: 50000,
            categoryId: "cat-sales",
            memo: "sales",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        // Ineligible: inactive
        let inactive = dataStore.addRecurring(
            name: "Recurring C",
            type: .expense,
            amount: 2000,
            categoryId: "cat-ads",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )
        inactive.isActive = false
        try? context.save()
        dataStore.loadData()

        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 2, "Should process exactly 2 eligible recurring transactions")
        XCTAssertEqual(fetchAllTransactions().count, 2)
    }

    // MARK: - 10. Memo Format

    func testMemoFormat_withMemo() {
        let project = makeProject()

        dataStore.addRecurring(
            name: "Server Cost",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "AWS monthly",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth
        )

        dataStore.processRecurringTransactions()

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.memo, "[定期] Server Cost - AWS monthly")
    }

    func testMemoFormat_withoutMemo() {
        let project = makeProject()

        dataStore.addRecurring(
            name: "Domain",
            type: .expense,
            amount: 2000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth
        )

        dataStore.processRecurringTransactions()

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.memo, "[定期] Domain")
    }

    // MARK: - 11. recurringId Link

    func testRecurringIdLink_transactionLinkedToRecurring() {
        let project = makeProject()

        let recurring = dataStore.addRecurring(
            name: "Linked",
            type: .expense,
            amount: 7000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth
        )

        dataStore.processRecurringTransactions()

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.recurringId, recurring.id, "Generated transaction must reference the recurring transaction's ID")
    }
}
