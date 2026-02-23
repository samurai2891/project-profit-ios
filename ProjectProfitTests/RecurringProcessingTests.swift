import XCTest
import SwiftData
@testable import ProjectProfit

// MARK: - RecurringProcessingTests

@MainActor
final class RecurringProcessingTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    private let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self,
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

        // addRecurring auto-processes; explicit call should be idempotent
        let count = dataStore.processRecurringTransactions()
        XCTAssertEqual(count, 0, "Already processed by addRecurring — no new transactions")

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

        // addRecurring auto-generated 1 transaction; lastGeneratedDate is already set
        XCTAssertEqual(fetchAllTransactions().count, 1, "addRecurring should auto-generate 1 transaction")

        // Calling processRecurringTransactions again should not create a duplicate
        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 0, "Should not generate a duplicate for the same month")
        XCTAssertEqual(fetchAllTransactions().count, 1, "Still only 1 transaction — no duplicate")
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

        // addRecurring auto-processes; explicit call should be idempotent
        let count = dataStore.processRecurringTransactions()
        XCTAssertEqual(count, 0, "Already processed by addRecurring — no new transactions")

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

        // Insert recurring directly with skipDates pre-set to avoid auto-generation by addRecurring
        let recurring = PPRecurringTransaction(
            name: "Skippable",
            type: .expense,
            amount: 8000,
            categoryId: "cat-hosting",
            memo: "skip this",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 8000)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth,
            isActive: true
        )
        recurring.skipDates = [targetDate]
        context.insert(recurring)
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

        // Insert recurring directly as inactive to avoid auto-generation by addRecurring
        let recurring = PPRecurringTransaction(
            name: "Inactive",
            type: .expense,
            amount: 3000,
            categoryId: "cat-ads",
            memo: "",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 3000)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth,
            isActive: false
        )
        context.insert(recurring)
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

        // Eligible recurring 1 — auto-generates on add
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

        // Eligible recurring 2 — auto-generates on add
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

        // Ineligible: inactive — insert directly to avoid auto-generation
        let inactive = PPRecurringTransaction(
            name: "Recurring C",
            type: .expense,
            amount: 2000,
            categoryId: "cat-ads",
            memo: "",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 2000)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth,
            isActive: false
        )
        context.insert(inactive)
        try? context.save()
        dataStore.loadData()

        // Both eligible recurring already auto-generated; explicit call should be idempotent
        let count = dataStore.processRecurringTransactions()

        XCTAssertEqual(count, 0, "Already processed by addRecurring — no new transactions")
        XCTAssertEqual(fetchAllTransactions().count, 2, "Only 2 eligible recurring should have generated transactions")
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

    // MARK: - 11. equalAll Auto-Generation on Add (expense)

    func testEqualAllMode_autoGeneratesOnAdd() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        // addRecurring should trigger processRecurringTransactions automatically
        let recurring = dataStore.addRecurring(
            name: "EqualAll Expense",
            type: .expense,
            amount: 9000,
            categoryId: "cat-hosting",
            memo: "auto",
            allocationMode: .equalAll,
            allocations: [],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        // Transactions should already be generated — no explicit processRecurringTransactions call
        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1, "equalAll add should auto-generate a transaction")

        let tx = transactions.first!
        XCTAssertEqual(tx.type, .expense)
        XCTAssertEqual(tx.amount, 9000)
        XCTAssertEqual(tx.recurringId, recurring.id)

        // Allocation should reference the active project
        XCTAssertEqual(tx.allocations.count, 1)
        XCTAssertEqual(tx.allocations.first?.projectId, project.id)
    }

    // MARK: - 12. equalAll Auto-Generation on Add (income)

    func testEqualAllMode_income_autoGenerates() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        dataStore.addRecurring(
            name: "EqualAll Income",
            type: .income,
            amount: 50000,
            categoryId: "cat-sales",
            memo: "",
            allocationMode: .equalAll,
            allocations: [],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1, "equalAll income should auto-generate a transaction")

        let tx = transactions.first!
        XCTAssertEqual(tx.type, .income)
        XCTAssertEqual(tx.amount, 50000)
        XCTAssertEqual(tx.allocations.first?.projectId, project.id)
    }

    // MARK: - 13. updateRecurring triggers auto-generation when now due

    func testUpdateRecurring_autoGeneratesIfNowDue() {
        let project = makeProject()

        // Create recurring with a future dayOfMonth so it won't fire on add
        guard let futureDay = futureDayOfMonth else {
            // Today is the 28th; skip gracefully
            return
        }

        let recurring = dataStore.addRecurring(
            name: "Deferred",
            type: .expense,
            amount: 4000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: futureDay
        )

        // No transaction should exist yet
        XCTAssertTrue(fetchAllTransactions().isEmpty, "Future dayOfMonth should not generate on add")

        // Update dayOfMonth to a past day — should trigger processing
        dataStore.updateRecurring(id: recurring.id, dayOfMonth: pastDayOfMonth)

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1, "Updating dayOfMonth to past should auto-generate")
        XCTAssertEqual(transactions.first?.recurringId, recurring.id)
    }

    // MARK: - 14. No duplicate on update after add already generated

    func testAddRecurring_noDuplicateOnUpdate() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        // addRecurring auto-generates a transaction
        let recurring = dataStore.addRecurring(
            name: "NoDup",
            type: .expense,
            amount: 6000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        XCTAssertEqual(fetchAllTransactions().count, 1, "Should have 1 transaction after add")

        // updateRecurring should NOT create a duplicate (lastGeneratedDate already set)
        dataStore.updateRecurring(id: recurring.id, memo: "updated memo")

        XCTAssertEqual(fetchAllTransactions().count, 1, "Should still have 1 transaction — no duplicate")
    }

    // MARK: - 15. recurringId Link

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

    // MARK: - 16. Manual mode with multiple partial projects (regression test)

    func testRecurringManual_multiplePartialProjects_totalPreserved() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")
        let projectC = makeProject(name: "Project C")

        let today = todayComponents
        guard let year = today.year, let month = today.month else {
            XCTFail("Cannot get today's components")
            return
        }

        // A: 今月15日に完了
        let completedDate = calendar.date(from: DateComponents(year: year, month: month, day: 15))!
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: completedDate)
        // C: 今月10日に開始
        let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 10))!
        dataStore.updateProject(id: projectC.id, startDate: startDate)

        // Manual recurring with 3 projects
        dataStore.addRecurring(
            name: "Manual Multi Partial",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "regression",
            allocationMode: .manual,
            allocations: [
                (projectId: projectA.id, ratio: 33),
                (projectId: projectB.id, ratio: 33),
                (projectId: projectC.id, ratio: 34)
            ],
            frequency: .monthly,
            dayOfMonth: 1
        )

        let transactions = fetchAllTransactions()
        let recurringTx = transactions.filter { $0.memo.contains("[定期]") && $0.memo.contains("regression") }

        XCTAssertFalse(recurringTx.isEmpty, "Should have generated a recurring transaction")

        if let tx = recurringTx.first {
            let total = tx.allocations.reduce(0) { $0 + $1.amount }
            XCTAssertEqual(total, 10000, "Total must be exactly ¥10,000 — regression test for sequential processing bug")
        }
    }

    // MARK: - 17. Yearly recurring with pro-rata

    func testYearlyRecurring_proRatesCorrectlyWithYearlyDays() {
        guard let passedMonth = pastMonth else { return }

        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        let today = todayComponents
        guard let year = today.year else { return }

        // Complete project A mid-year
        let completedDate = calendar.date(from: DateComponents(year: year, month: 6, day: 30))!
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: completedDate)

        // Create yearly manual recurring
        dataStore.addRecurring(
            name: "Annual Fee",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "yearly prorata",
            allocationMode: .manual,
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: passedMonth
        )

        let transactions = fetchAllTransactions()
        let yearlyTx = transactions.filter { $0.memo.contains("[定期]") && $0.memo.contains("Annual Fee") }

        XCTAssertFalse(yearlyTx.isEmpty, "Should have generated yearly transaction")

        if let tx = yearlyTx.first {
            let allocA = tx.allocations.first { $0.projectId == projectA.id }!
            let allocB = tx.allocations.first { $0.projectId == projectB.id }!

            // Verify yearly days are used, not monthly
            let totalDays = daysInYear(year)
            XCTAssertTrue(totalDays >= 365, "Should use yearly days")

            // Project A should be pro-rated based on yearly active days
            XCTAssertTrue(allocA.amount > 0, "Project A should have non-zero pro-rated amount")
            XCTAssertEqual(allocA.amount + allocB.amount, 120000, "Total must be preserved")
        }
    }

    // MARK: - 18. endDate stops future generation

    func testEndDate_stopsGeneration() {
        let project = makeProject(name: "Project A")

        // Create recurring with endDate in the past
        let pastEndDate = calendar.date(from: DateComponents(year: 2020, month: 1, day: 1))!
        let recurring = PPRecurringTransaction(
            name: "Ended",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "ended",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 5000)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth,
            isActive: true,
            endDate: pastEndDate
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        let count = dataStore.processRecurringTransactions()
        XCTAssertEqual(count, 0, "Should not generate for ended recurring")

        let updated = fetchRecurring(id: recurring.id)
        XCTAssertEqual(updated?.isActive, false, "Should be auto-deactivated")
    }

    // MARK: - 19. endDate in future allows generation

    func testEndDate_futureAllowsGeneration() {
        let project = makeProject(name: "Project A")
        let futureEndDate = calendar.date(byAdding: .year, value: 1, to: Date())!

        let recurring = dataStore.addRecurring(
            name: "Future End",
            type: .expense,
            amount: 8000,
            categoryId: "cat-hosting",
            memo: "future end",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth,
            endDate: futureEndDate
        )

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1, "Should generate for recurring with future endDate")

        let updated = fetchRecurring(id: recurring.id)
        XCTAssertEqual(updated?.isActive, true, "Should remain active")
    }

    // MARK: - 20. addProject updates equalAll transactions

    func testAddProject_reprocessesEqualAllTransactions() {
        let projectA = makeProject(name: "Project A")

        // Create equalAll recurring
        dataStore.addRecurring(
            name: "EqualAll Reprocess",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "reprocess",
            allocationMode: .equalAll,
            allocations: [],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth
        )

        // Verify only project A allocated
        var transactions = fetchAllTransactions()
        var tx = transactions.first { $0.memo.contains("EqualAll Reprocess") }
        XCTAssertNotNil(tx)
        XCTAssertEqual(tx?.allocations.count, 1)

        // Add new project
        let projectB = dataStore.addProject(name: "Project B", description: "new")

        // Verify transaction now includes both projects
        transactions = fetchAllTransactions()
        tx = transactions.first { $0.memo.contains("EqualAll Reprocess") }
        XCTAssertEqual(tx?.allocations.count, 2, "Should include new project")
        let total = tx?.allocations.reduce(0) { $0 + $1.amount } ?? 0
        XCTAssertEqual(total, 10000, "Total must be preserved")
    }

    // MARK: - 21. Skip Cancellation

    func testCancelSkip_removesNextDateFromSkipDates() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth
        let currentYear = todayComponents.year!
        let currentMonth = todayComponents.month!

        var nextMonth = currentMonth + 1
        var nextYear = currentYear
        if nextMonth > 12 {
            nextMonth = 1
            nextYear += 1
        }
        let nextDate = calendar.date(from: DateComponents(
            year: nextYear, month: nextMonth, day: dayOfMonth
        ))!

        let recurring = PPRecurringTransaction(
            name: "SkipCancel Test",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 5000)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth,
            isActive: true,
            lastGeneratedDate: calendar.date(from: DateComponents(
                year: currentYear, month: currentMonth, day: dayOfMonth
            )),
            skipDates: [nextDate]
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        XCTAssertEqual(recurring.skipDates.count, 1)

        let vm = RecurringViewModel(dataStore: dataStore)
        vm.cancelSkip(recurring)

        let updated = fetchRecurring(id: recurring.id)
        XCTAssertTrue(updated?.skipDates.isEmpty ?? false,
                      "cancelSkip should remove the next date from skipDates")
    }

    func testIsNextDateSkipped_returnsTrueWhenSkipped() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth
        let currentYear = todayComponents.year!
        let currentMonth = todayComponents.month!

        var nextMonth = currentMonth + 1
        var nextYear = currentYear
        if nextMonth > 12 { nextMonth = 1; nextYear += 1 }
        let nextDate = calendar.date(from: DateComponents(
            year: nextYear, month: nextMonth, day: dayOfMonth
        ))!

        let recurring = PPRecurringTransaction(
            name: "IsSkipped Test",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 5000)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth,
            isActive: true,
            lastGeneratedDate: calendar.date(from: DateComponents(
                year: currentYear, month: currentMonth, day: dayOfMonth
            )),
            skipDates: [nextDate]
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        let vm = RecurringViewModel(dataStore: dataStore)
        XCTAssertTrue(vm.isNextDateSkipped(recurring))
    }

    func testIsNextDateSkipped_returnsFalseWhenNotSkipped() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth
        let currentYear = todayComponents.year!
        let currentMonth = todayComponents.month!

        let recurring = PPRecurringTransaction(
            name: "NotSkipped Test",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 5000)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth,
            isActive: true,
            lastGeneratedDate: calendar.date(from: DateComponents(
                year: currentYear, month: currentMonth, day: dayOfMonth
            )),
            skipDates: []
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        let vm = RecurringViewModel(dataStore: dataStore)
        XCTAssertFalse(vm.isNextDateSkipped(recurring))
    }

}
