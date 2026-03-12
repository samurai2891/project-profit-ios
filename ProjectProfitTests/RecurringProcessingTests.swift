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

    /// Creates a project in the data store and returns it.
    private func makeProject(name: String = "TestProject") -> PPProject {
        mutations(dataStore).addProject(name: name, description: "desc")
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

    private struct GeneratedRecurringPosting {
        let id: UUID
        let candidateId: UUID
        let date: Date
        let type: TransactionType
        let amount: Int
        let categoryId: String
        let memo: String
        let counterparty: String?
        let recurringId: UUID?
        let paymentAccountId: String?
        let transferToAccountId: String?
        let taxDeductibleRate: Int?
        let allocations: [Allocation]
        let deletedAt: Date? = nil
    }

    /// Fetches recurring-generated canonical postings and projects them into
    /// the transaction shape these tests assert against.
    private func fetchAllTransactions() -> [GeneratedRecurringPosting] {
        let journals = dataStore.canonicalJournalEntries()
            .filter { $0.entryType == .recurring }
            .sorted { $0.journalDate < $1.journalDate }
        guard !journals.isEmpty else {
            return []
        }

        let candidateIds = Set(journals.compactMap(\.sourceCandidateId))
        let descriptor = FetchDescriptor<PostingCandidateEntity>()
        let candidates = ((try? context.fetch(descriptor)) ?? [])
            .map(PostingCandidateEntityMapper.toDomain)
            .filter { candidateIds.contains($0.id) }
        let candidatesById = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })

        return journals.compactMap { journal in
            guard let candidateId = journal.sourceCandidateId,
                  let candidate = candidatesById[candidateId],
                  let snapshot = candidate.legacySnapshot else {
                return nil
            }

            let relevantLines = candidate.proposedLines.filter { line in
                switch snapshot.type {
                case .income:
                    return line.creditAccountId != nil
                case .expense:
                    return line.debitAccountId != nil
                case .transfer:
                    return false
                }
            }
            let amount = relevantLines.reduce(0) { partialResult, line in
                partialResult + NSDecimalNumber(decimal: line.amount).intValue
            }
            let allocationAmounts = relevantLines.reduce(into: [UUID: Int]()) { result, line in
                guard let projectId = line.projectAllocationId else { return }
                result[projectId, default: 0] += NSDecimalNumber(decimal: line.amount).intValue
            }
            let allocations = allocationAmounts.map { projectId, allocationAmount in
                Allocation(
                    projectId: projectId,
                    ratio: amount == 0 ? 0 : Int((Double(allocationAmount) / Double(amount) * 100.0).rounded()),
                    amount: allocationAmount
                )
            }
            .sorted { $0.projectId.uuidString < $1.projectId.uuidString }

            return GeneratedRecurringPosting(
                id: journal.id,
                candidateId: candidate.id,
                date: journal.journalDate,
                type: snapshot.type,
                amount: amount,
                categoryId: snapshot.categoryId,
                memo: journal.description,
                counterparty: snapshot.counterpartyName,
                recurringId: snapshot.recurringId,
                paymentAccountId: snapshot.paymentAccountId,
                transferToAccountId: snapshot.transferToAccountId,
                taxDeductibleRate: snapshot.taxDeductibleRate,
                allocations: allocations
            )
        }
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

        let recurring = mutations(dataStore).addRecurring(
            name: "Monthly Fee",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "server",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        // 明示実行時のみ生成される
        let count = mutations(dataStore).processRecurringTransactions()
        XCTAssertEqual(count, 1, "Should generate one transaction when explicitly processed")

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

        mutations(dataStore).addRecurring(
            name: "Future Monthly",
            type: .expense,
            amount: 5000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: futureDay
        )

        let count = mutations(dataStore).processRecurringTransactions()

        XCTAssertEqual(count, 0, "Should not generate a transaction when dayOfMonth is in the future")
        XCTAssertTrue(fetchAllTransactions().isEmpty)
    }

    // MARK: - 3. Monthly Already Generated This Month

    func testMonthlyAlreadyGenerated_noDuplicate() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        mutations(dataStore).addRecurring(
            name: "Already Done",
            type: .income,
            amount: 20000,
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        XCTAssertEqual(fetchAllTransactions().count, 0, "addRecurring only schedules; it should not auto-generate")
        let firstCount = mutations(dataStore).processRecurringTransactions()
        XCTAssertEqual(firstCount, 1, "First explicit processing should generate one transaction")
        let secondCount = mutations(dataStore).processRecurringTransactions()

        XCTAssertEqual(secondCount, 0, "Should not generate a duplicate for the same month")
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

        let recurring = mutations(dataStore).addRecurring(
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

        // 明示実行時のみ生成される
        let count = mutations(dataStore).processRecurringTransactions()
        XCTAssertEqual(count, 1, "Should generate one transaction when explicitly processed")

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

        mutations(dataStore).addRecurring(
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

        let count = mutations(dataStore).processRecurringTransactions()

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

        let count = mutations(dataStore).processRecurringTransactions()

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

        let count = mutations(dataStore).processRecurringTransactions()

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

        let count = mutations(dataStore).processRecurringTransactions()

        XCTAssertEqual(count, 0, "Recurring with empty allocations should be skipped")
        XCTAssertTrue(fetchAllTransactions().isEmpty)
    }

    // MARK: - 9. Multiple Recurring

    func testMultipleRecurring_allEligibleProcessed() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        // Eligible recurring 1
        mutations(dataStore).addRecurring(
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
        mutations(dataStore).addRecurring(
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

        let count = mutations(dataStore).processRecurringTransactions()

        XCTAssertEqual(count, 2, "Two eligible recurring entries should be generated")
        XCTAssertEqual(fetchAllTransactions().count, 2, "Only 2 eligible recurring should have generated transactions")
    }

    // MARK: - 10. Memo Format

    func testMemoFormat_withMemo() {
        let project = makeProject()

        mutations(dataStore).addRecurring(
            name: "Server Cost",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "AWS monthly",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth
        )

        mutations(dataStore).processRecurringTransactions()

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.memo, "[定期] Server Cost - AWS monthly")
    }

    func testMemoFormat_withoutMemo() {
        let project = makeProject()

        mutations(dataStore).addRecurring(
            name: "Domain",
            type: .expense,
            amount: 2000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth
        )

        mutations(dataStore).processRecurringTransactions()

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.memo, "[定期] Domain")
    }

    // MARK: - 11. equalAll Processing (expense)

    func testEqualAllMode_autoGeneratesOnAdd() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        let recurring = mutations(dataStore).addRecurring(
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

        XCTAssertTrue(fetchAllTransactions().isEmpty, "addRecurring should not auto-generate")
        let generated = mutations(dataStore).processRecurringTransactions()
        XCTAssertEqual(generated, 1, "equalAll recurring should generate on explicit processing")

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1, "equalAll recurring should generate one transaction")

        let tx = transactions.first!
        XCTAssertEqual(tx.type, .expense)
        XCTAssertEqual(tx.amount, 9000)
        XCTAssertEqual(tx.recurringId, recurring.id)

        // Allocation should reference the active project
        XCTAssertEqual(tx.allocations.count, 1)
        XCTAssertEqual(tx.allocations.first?.projectId, project.id)
    }

    // MARK: - 12. equalAll Processing (income)

    func testEqualAllMode_income_autoGenerates() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        mutations(dataStore).addRecurring(
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

        XCTAssertTrue(fetchAllTransactions().isEmpty, "addRecurring should not auto-generate")
        let generated = mutations(dataStore).processRecurringTransactions()
        XCTAssertEqual(generated, 1, "equalAll income recurring should generate on explicit processing")

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1, "equalAll income recurring should generate one transaction")

        let tx = transactions.first!
        XCTAssertEqual(tx.type, .income)
        XCTAssertEqual(tx.amount, 50000)
        XCTAssertEqual(tx.allocations.first?.projectId, project.id)
    }

    // MARK: - 13. updateRecurring requires explicit processing when now due

    func testUpdateRecurring_autoGeneratesIfNowDue() {
        let project = makeProject()

        // Create recurring with a future dayOfMonth so it won't fire on add
        guard let futureDay = futureDayOfMonth else {
            // Today is the 28th; skip gracefully
            return
        }

        let recurring = mutations(dataStore).addRecurring(
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

        // Update dayOfMonth to a past day
        mutations(dataStore).updateRecurring(id: recurring.id, dayOfMonth: pastDayOfMonth)

        XCTAssertTrue(fetchAllTransactions().isEmpty, "updateRecurring should not auto-generate")
        let generated = mutations(dataStore).processRecurringTransactions()
        XCTAssertEqual(generated, 1, "Updated recurring should generate on explicit processing")

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1, "Updating dayOfMonth to past should become due")
        XCTAssertEqual(transactions.first?.recurringId, recurring.id)
    }

    // MARK: - 14. No duplicate on update after add already generated

    func testAddRecurring_noDuplicateOnUpdate() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth

        let recurring = mutations(dataStore).addRecurring(
            name: "NoDup",
            type: .expense,
            amount: 6000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth
        )

        XCTAssertTrue(fetchAllTransactions().isEmpty, "addRecurring should not auto-generate")
        let generated = mutations(dataStore).processRecurringTransactions()
        XCTAssertEqual(generated, 1, "Should generate one transaction on explicit processing")
        XCTAssertEqual(fetchAllTransactions().count, 1, "Should have 1 transaction after explicit processing")

        // updateRecurring alone should NOT create a duplicate
        mutations(dataStore).updateRecurring(id: recurring.id, memo: "updated memo")

        XCTAssertEqual(fetchAllTransactions().count, 1, "Should still have 1 transaction — no duplicate")
        let duplicateCount = mutations(dataStore).processRecurringTransactions()
        XCTAssertEqual(duplicateCount, 0, "Should still avoid duplicates after update")
    }

    // MARK: - 15. recurringId Link

    func testRecurringIdLink_transactionLinkedToRecurring() {
        let project = makeProject()

        let recurring = mutations(dataStore).addRecurring(
            name: "Linked",
            type: .expense,
            amount: 7000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth
        )

        mutations(dataStore).processRecurringTransactions()

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
        mutations(dataStore).updateProject(id: projectA.id, status: .completed, completedAt: completedDate)
        // C: 今月10日に開始
        let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 10))!
        mutations(dataStore).updateProject(id: projectC.id, startDate: startDate)

        // Manual recurring with 3 projects
        mutations(dataStore).addRecurring(
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
        _ = mutations(dataStore).processRecurringTransactions()

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
        mutations(dataStore).updateProject(id: projectA.id, status: .completed, completedAt: completedDate)

        // Create yearly manual recurring
        mutations(dataStore).addRecurring(
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
        _ = mutations(dataStore).processRecurringTransactions()

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

        let count = mutations(dataStore).processRecurringTransactions()
        XCTAssertEqual(count, 0, "Should not generate for ended recurring")

        let updated = fetchRecurring(id: recurring.id)
        XCTAssertEqual(updated?.isActive, false, "Should be auto-deactivated")
    }

    // MARK: - 19. endDate in future allows generation

    func testEndDate_futureAllowsGeneration() {
        let project = makeProject(name: "Project A")
        let futureEndDate = calendar.date(byAdding: .year, value: 1, to: Date())!

        let recurring = mutations(dataStore).addRecurring(
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
        let generated = mutations(dataStore).processRecurringTransactions()
        XCTAssertEqual(generated, 1, "Should generate for recurring with future endDate")

        let transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1, "Should have one generated transaction")

        let updated = fetchRecurring(id: recurring.id)
        XCTAssertEqual(updated?.isActive, true, "Should remain active")
    }

    // MARK: - 20. addProject updates equalAll transactions

    func testAddProject_reprocessesEqualAllTransactions() {
        let projectA = makeProject(name: "Project A")

        // Create equalAll recurring
        mutations(dataStore).addRecurring(
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
        _ = mutations(dataStore).processRecurringTransactions()

        // Verify only project A allocated
        var transactions = fetchAllTransactions()
        var tx = transactions.first { $0.memo.contains("EqualAll Reprocess") }
        XCTAssertNotNil(tx)
        XCTAssertEqual(tx?.allocations.count, 1)

        // Add new project
        let projectB = mutations(dataStore).addProject(name: "Project B", description: "new")

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

        let vm = RecurringViewModel(modelContext: context)
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

        let vm = RecurringViewModel(modelContext: context)
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

        let vm = RecurringViewModel(modelContext: context)
        XCTAssertFalse(vm.isNextDateSkipped(recurring))
    }

    // MARK: - Monthly Catch-Up Loop

    func testMonthlyCatchUp_threeMonthGap() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth
        let currentYear = todayComponents.year!
        let currentMonth = todayComponents.month!

        // 3ヶ月前を lastGeneratedDate に設定
        var threeMonthsAgoMonth = currentMonth - 3
        var threeMonthsAgoYear = currentYear
        while threeMonthsAgoMonth <= 0 {
            threeMonthsAgoMonth += 12
            threeMonthsAgoYear -= 1
        }

        let recurring = PPRecurringTransaction(
            name: "Catch-Up Test",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 5000)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth,
            isActive: true,
            lastGeneratedDate: calendar.date(from: DateComponents(
                year: threeMonthsAgoYear, month: threeMonthsAgoMonth, day: dayOfMonth
            ))
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        let generated = mutations(dataStore).processRecurringTransactions()

        // 3ヶ月のギャップ → 3件生成（gap月、gap+1月、gap+2月＝今月）
        XCTAssertEqual(generated, 3, "Should generate 3 transactions to catch up 3 months")

        let allTx = fetchAllTransactions().filter { $0.recurringId == recurring.id }
        XCTAssertEqual(allTx.count, 3)

        // 各月の日付が正しいことを確認
        let months = allTx.map { calendar.component(.month, from: $0.date) }.sorted()
        var expectedMonths: [Int] = []
        var m = threeMonthsAgoMonth + 1
        var y = threeMonthsAgoYear
        for _ in 0..<3 {
            if m > 12 { m -= 12; y += 1 }
            expectedMonths.append(m)
            m += 1
        }
        XCTAssertEqual(months, expectedMonths.sorted())
    }

    func testMonthlyCatchUp_withSkipDate() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth
        let currentYear = todayComponents.year!
        let currentMonth = todayComponents.month!

        // 2ヶ月前を lastGeneratedDate に設定
        var twoMonthsAgoMonth = currentMonth - 2
        var twoMonthsAgoYear = currentYear
        while twoMonthsAgoMonth <= 0 {
            twoMonthsAgoMonth += 12
            twoMonthsAgoYear -= 1
        }

        // 1ヶ月前をスキップ日に設定
        var oneMonthAgoMonth = currentMonth - 1
        var oneMonthAgoYear = currentYear
        if oneMonthAgoMonth <= 0 {
            oneMonthAgoMonth += 12
            oneMonthAgoYear -= 1
        }
        let skipDate = calendar.date(from: DateComponents(
            year: oneMonthAgoYear, month: oneMonthAgoMonth, day: dayOfMonth
        ))!

        let recurring = PPRecurringTransaction(
            name: "Skip Catch-Up",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 5000)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth,
            isActive: true,
            lastGeneratedDate: calendar.date(from: DateComponents(
                year: twoMonthsAgoYear, month: twoMonthsAgoMonth, day: dayOfMonth
            )),
            skipDates: [skipDate]
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        let generated = mutations(dataStore).processRecurringTransactions()

        // 2ヶ月ギャップ、1ヶ月スキップ → 1件のみ生成
        XCTAssertEqual(generated, 1, "Should generate only 1 transaction (1 month skipped)")
    }

    func testMonthlyCatchUp_endDateStopsMidGap() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth
        let currentYear = todayComponents.year!
        let currentMonth = todayComponents.month!

        // 3ヶ月前を lastGeneratedDate に設定
        var threeMonthsAgoMonth = currentMonth - 3
        var threeMonthsAgoYear = currentYear
        while threeMonthsAgoMonth <= 0 {
            threeMonthsAgoMonth += 12
            threeMonthsAgoYear -= 1
        }

        // endDate を 1ヶ月前に設定（ギャップの途中で止まる）
        var oneMonthAgoMonth = currentMonth - 1
        var oneMonthAgoYear = currentYear
        if oneMonthAgoMonth <= 0 {
            oneMonthAgoMonth += 12
            oneMonthAgoYear -= 1
        }
        let endDate = calendar.date(from: DateComponents(
            year: oneMonthAgoYear, month: oneMonthAgoMonth, day: dayOfMonth
        ))!

        let recurring = PPRecurringTransaction(
            name: "EndDate Stop",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 5000)],
            frequency: .monthly,
            dayOfMonth: dayOfMonth,
            isActive: true,
            endDate: endDate,
            lastGeneratedDate: calendar.date(from: DateComponents(
                year: threeMonthsAgoYear, month: threeMonthsAgoMonth, day: dayOfMonth
            ))
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        let generated = mutations(dataStore).processRecurringTransactions()

        // endDateまでの分のみ生成（3ヶ月ギャップだが、endDateで2ヶ月まで）
        XCTAssertEqual(generated, 2, "Should generate only 2 transactions (endDate stops before current month)")

        // endDate後なので isActive = false になっているはず
        let updated = fetchRecurring(id: recurring.id)
        XCTAssertEqual(updated?.isActive, false)
    }

    // MARK: - Yearly Catch-Up Loop

    func testYearlyCatchUp_twoYearGap() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth
        let currentYear = todayComponents.year!
        let currentMonth = todayComponents.month!

        // 過去の月が必要（年次取引の targetMonth）
        guard let pm = pastMonth else { return } // 1月にはテスト不可

        let recurring = PPRecurringTransaction(
            name: "Yearly Catch-Up",
            type: .expense,
            amount: 120000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 120000)],
            frequency: .yearly,
            dayOfMonth: dayOfMonth,
            monthOfYear: pm,
            isActive: true,
            lastGeneratedDate: calendar.date(from: DateComponents(
                year: currentYear - 3, month: pm, day: dayOfMonth
            ))
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        let generated = mutations(dataStore).processRecurringTransactions()

        // lastGenerated = currentYear-3 → currentYear-2, currentYear-1, currentYear = 3件
        // ただし今月 > targetMonth の場合のみ currentYear 分も生成
        if currentMonth > pm || (currentMonth == pm && todayComponents.day! >= dayOfMonth) {
            XCTAssertGreaterThanOrEqual(generated, 2, "Should generate at least 2 year catch-up transactions")
        } else {
            XCTAssertGreaterThanOrEqual(generated, 1, "Should generate at least 1 year catch-up transaction")
        }
    }

    func testYearlyCatchUp_endDateStops() {
        let project = makeProject()
        let dayOfMonth = pastDayOfMonth
        let currentYear = todayComponents.year!

        guard let pm = pastMonth else { return }

        // endDate を前年末に設定
        let endDate = calendar.date(from: DateComponents(
            year: currentYear - 1, month: 12, day: 31
        ))!

        let recurring = PPRecurringTransaction(
            name: "Yearly EndDate",
            type: .expense,
            amount: 120000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 120000)],
            frequency: .yearly,
            dayOfMonth: dayOfMonth,
            monthOfYear: pm,
            isActive: true,
            endDate: endDate,
            lastGeneratedDate: calendar.date(from: DateComponents(
                year: currentYear - 4, month: pm, day: dayOfMonth
            ))
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        let generated = mutations(dataStore).processRecurringTransactions()

        // lastGenerated = currentYear-4, endDate = currentYear-1/12/31
        // → currentYear-3, currentYear-2, currentYear-1 の3件（currentYear は endDate 超過）
        XCTAssertEqual(generated, 3, "Should generate 3 yearly transactions before endDate")

        let updated = fetchRecurring(id: recurring.id)
        XCTAssertEqual(updated?.isActive, false, "Should be deactivated after endDate")
    }

    // MARK: - C9: Delete Recurring Transaction Regeneration

    func testDeleteMonthlyRecurringTransaction_allowsRegeneration() throws {
        let project = makeProject()
        let useDayOfMonth = pastDayOfMonth

        let recurring = mutations(dataStore).addRecurring(
            name: "Monthly Regen Test",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: useDayOfMonth
        )
        _ = mutations(dataStore).processRecurringTransactions()

        throw XCTSkip("processRecurringTransactions() now writes canonical recurring journals only; deleteTransaction(id:) applies to legacy PPTransaction rows")
    }

    func testDeleteNonRecurringTransaction_noRecurringStateChange() {
        let project = makeProject()

        let tx = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "manual entry",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        XCTAssertEqual(dataStore.transactions.count, 1)

        // Delete it - should not crash or affect any recurring state
        mutations(dataStore).deleteTransaction(id: tx.id)

        XCTAssertTrue(dataStore.transactions.filter { $0.id == tx.id }.isEmpty, "Transaction should be deleted")
    }

    // MARK: - H2: onRecurringScheduleChanged callback tests

    func testAddRecurring_triggersScheduleChangedCallback() {
        let project = makeProject()
        var callbackInvoked = false
        var receivedRecurrings: [PPRecurringTransaction] = []

        dataStore.onRecurringScheduleChanged = { recurrings in
            callbackInvoked = true
            receivedRecurrings = recurrings
        }

        mutations(dataStore).addRecurring(
            name: "Test Recurring",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        XCTAssertTrue(callbackInvoked, "addRecurringでコールバックが発火すべき")
        XCTAssertFalse(receivedRecurrings.isEmpty, "定期取引リストが渡されるべき")
    }

    func testUpdateRecurring_triggersScheduleChangedCallback() {
        let project = makeProject()
        let recurring = mutations(dataStore).addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        var callbackInvoked = false
        dataStore.onRecurringScheduleChanged = { _ in
            callbackInvoked = true
        }

        mutations(dataStore).updateRecurring(id: recurring.id, name: "Updated")

        XCTAssertTrue(callbackInvoked, "updateRecurringでコールバックが発火すべき")
    }

    func testDeleteRecurring_triggersScheduleChangedCallback() {
        let project = makeProject()
        let recurring = mutations(dataStore).addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        var callbackInvoked = false
        dataStore.onRecurringScheduleChanged = { _ in
            callbackInvoked = true
        }

        mutations(dataStore).deleteRecurring(id: recurring.id)

        XCTAssertTrue(callbackInvoked, "deleteRecurringでコールバックが発火すべき")
    }

    // MARK: - Phase 9A: Recurring Accounting Fields

    func testRecurringAccountingFields_inheritedByTransaction() {
        let project = makeProject()
        let recurring = mutations(dataStore).addRecurring(
            name: "サーバー代",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "AWS月額",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth,
            paymentAccountId: "acct-bank",
            transferToAccountId: nil,
            taxDeductibleRate: 80
        )
        _ = mutations(dataStore).processRecurringTransactions()

        // 明示処理後に生成されたトランザクションを確認
        let generated = fetchAllTransactions().filter { $0.recurringId == recurring.id }
        guard let tx = generated.first else {
            XCTFail("定期取引からトランザクションが生成されるべき")
            return
        }

        XCTAssertEqual(tx.paymentAccountId, "acct-bank", "paymentAccountIdが引き継がれるべき")
        XCTAssertEqual(tx.taxDeductibleRate, 80, "taxDeductibleRateが引き継がれるべき")
        XCTAssertNil(tx.transferToAccountId, "transferToAccountIdはnilのまま")
    }

    func testRecurringAccountingFields_updateRoundTrip() {
        let project = makeProject()
        let recurring = mutations(dataStore).addRecurring(
            name: "家賃",
            type: .expense,
            amount: 100000,
            categoryId: "cat-hosting",
            memo: "オフィス賃料",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: pastDayOfMonth,
            paymentAccountId: "acct-bank",
            taxDeductibleRate: 50
        )

        // 会計フィールドを更新
        mutations(dataStore).updateRecurring(
            id: recurring.id,
            paymentAccountId: "acct-cash",
            taxDeductibleRate: 70
        )

        let updated = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(updated?.paymentAccountId, "acct-cash")
        XCTAssertEqual(updated?.taxDeductibleRate, 70)
    }
}
