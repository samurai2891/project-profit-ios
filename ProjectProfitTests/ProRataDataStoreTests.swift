import XCTest
import SwiftData
@testable import ProjectProfit

// MARK: - ProRataDataStoreTests

@MainActor
final class ProRataDataStoreTests: XCTestCase {
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
        dataStore.addProject(name: name, description: "desc")
    }

    /// Fetches all PPTransaction objects from the model context.
    private func fetchAllTransactions() -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private struct GeneratedRecurringPosting {
        let id: UUID
        let candidateId: UUID
        let date: Date
        let type: TransactionType
        let amount: Int
        let categoryId: String
        let memo: String
        let recurringId: UUID?
        let allocations: [Allocation]
    }

    /// Fetches recurring-generated canonical postings and projects them into
    /// the transaction shape these tests assert against.
    private func fetchGeneratedRecurringTransactions() -> [GeneratedRecurringPosting] {
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
                recurringId: snapshot.recurringId,
                allocations: allocations
            )
        }
    }

    /// Creates a date from year, month, day components.
    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Returns today's year, month, day components.
    private var todayComponents: DateComponents {
        calendar.dateComponents([.year, .month, .day], from: todayDate())
    }

    // MARK: - Test 1: updateProject_completedWithDate_recalculatesAllocations

    func testUpdateProject_completedWithDate_recalculatesAllocations() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        let transactionDate = makeDate(year: 2024, month: 2, day: 28)
        dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "test expense",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        // Verify original allocations: 5000 each
        var transactions = fetchAllTransactions()
        XCTAssertEqual(transactions.count, 1)
        let allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        let allocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!
        XCTAssertEqual(allocA.amount, 5000)
        XCTAssertEqual(allocB.amount, 5000)

        // Complete project A on Feb 15, 2024 (leap year, 29 days)
        let completedDate = makeDate(year: 2024, month: 2, day: 15)
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: completedDate)

        // Project A: 5000 * 15 / 29 = 2586
        // Project B: 5000 + (5000 - 2586) = 7414
        transactions = fetchAllTransactions()
        let newAllocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        let newAllocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!

        XCTAssertEqual(newAllocA.amount, 2586, "Project A should get pro-rated amount for 15 days")
        XCTAssertEqual(newAllocB.amount, 7414, "Project B should get original + redistributed")
        XCTAssertEqual(newAllocA.amount + newAllocB.amount, 10000)
    }

    // MARK: - Test 2: updateProject_completedAutoSetsDate

    func testUpdateProject_completedAutoSetsDate() {
        let project = makeProject(name: "Auto Complete")

        dataStore.updateProject(id: project.id, status: .completed)

        let updated = dataStore.getProject(id: project.id)!
        XCTAssertNotNil(updated.completedAt, "completedAt should be auto-set")

        let today = todayDate()
        let completedDate = updated.completedAt!
        let todayComps = calendar.dateComponents([.year, .month, .day], from: today)
        let completedComps = calendar.dateComponents([.year, .month, .day], from: completedDate)

        XCTAssertEqual(todayComps.year, completedComps.year)
        XCTAssertEqual(todayComps.month, completedComps.month)
        XCTAssertEqual(todayComps.day, completedComps.day)
    }

    // MARK: - Test 3: updateProject_reactivated_clearsCompletedAt

    func testUpdateProject_reactivated_clearsCompletedAt() {
        let project = makeProject(name: "Reactivate")

        let completedDate = makeDate(year: 2024, month: 2, day: 15)
        dataStore.updateProject(id: project.id, status: .completed, completedAt: completedDate)

        var updated = dataStore.getProject(id: project.id)!
        XCTAssertEqual(updated.status, .completed)
        XCTAssertNotNil(updated.completedAt)

        dataStore.updateProject(id: project.id, status: .active)

        updated = dataStore.getProject(id: project.id)!
        XCTAssertEqual(updated.status, .active)
        XCTAssertNil(updated.completedAt, "completedAt should be nil when status is not .completed")
    }

    // MARK: - Test 4: updateProject_changeCompletedAt_recalculates

    func testUpdateProject_changeCompletedAt_recalculates() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        let transactionDate = makeDate(year: 2024, month: 2, day: 28)
        dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "test",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        // Complete on Feb 15 first
        let firstCompletedDate = makeDate(year: 2024, month: 2, day: 15)
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: firstCompletedDate)

        var transactions = fetchAllTransactions()
        var allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        XCTAssertEqual(allocA.amount, 2586, "First: 5000 * 15 / 29")

        // Change to Feb 10
        let secondCompletedDate = makeDate(year: 2024, month: 2, day: 10)
        dataStore.updateProject(id: projectA.id, completedAt: secondCompletedDate)

        transactions = fetchAllTransactions()
        allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        let allocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!

        XCTAssertEqual(allocA.amount, 1724, "Second: 5000 * 10 / 29")
        XCTAssertEqual(allocB.amount, 8276, "Project B gets remainder")
        XCTAssertEqual(allocA.amount + allocB.amount, 10000)
    }

    // MARK: - Test 5: Recurring equalAll via processRecurringTransactions

    func testRecurringEqualAll_processRecurringTransactions_excludesCompletedProject() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        // Get today's info to set up recurring that will generate
        let today = todayComponents
        guard let year = today.year, let month = today.month, let day = today.day else {
            XCTFail("Cannot get today's components")
            return
        }

        // Complete project A last month
        let lastMonth = month == 1 ? 12 : month - 1
        let lastMonthYear = month == 1 ? year - 1 : year
        let completedDate = makeDate(year: lastMonthYear, month: lastMonth, day: 15)
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: completedDate)

        // Create equalAll recurring with dayOfMonth = 1 (already passed or is today for day>=1)
        dataStore.addRecurring(
            name: "EqualAll Monthly",
            type: .expense,
            amount: 9000,
            categoryId: "cat-hosting",
            memo: "test",
            allocationMode: .equalAll,
            allocations: [],
            frequency: .monthly,
            dayOfMonth: 1
        )

        XCTAssertEqual(dataStore.processRecurringTransactions(), 1, "Should generate one recurring posting")

        let transactions = fetchGeneratedRecurringTransactions()
        let recurringTx = transactions.filter { $0.memo.contains("[定期]") }

        XCTAssertFalse(recurringTx.isEmpty, "Should have generated a recurring transaction")

        if let tx = recurringTx.first {
            // Project A is completed (last month), only project B should be allocated
            let hasProjectA = tx.allocations.contains { $0.projectId == projectA.id }
            XCTAssertFalse(hasProjectA, "Completed project A should be excluded from equalAll")

            let allocB = tx.allocations.first { $0.projectId == projectB.id }
            XCTAssertNotNil(allocB, "Project B should be in allocations")
            XCTAssertEqual(allocB?.amount, 9000, "Project B should get full amount")
        }
    }

    // MARK: - Test 6: Recurring manual via processRecurringTransactions (Bug 1 fix)

    func testRecurringManual_processRecurringTransactions_proRatesCompletedProject() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        let today = todayComponents
        guard let year = today.year, let month = today.month else {
            XCTFail("Cannot get today's components")
            return
        }

        // Complete project A last month (so it's after completion month for this month's tx)
        let lastMonth = month == 1 ? 12 : month - 1
        let lastMonthYear = month == 1 ? year - 1 : year
        let completedDate = makeDate(year: lastMonthYear, month: lastMonth, day: 15)
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: completedDate)

        // Create manual recurring with 50/50 to both projects, dayOfMonth = 1
        dataStore.addRecurring(
            name: "Manual Monthly",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "manual",
            allocationMode: .manual,
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ],
            frequency: .monthly,
            dayOfMonth: 1
        )

        XCTAssertEqual(dataStore.processRecurringTransactions(), 1, "Should generate one recurring posting")

        let transactions = fetchGeneratedRecurringTransactions()
        let recurringTx = transactions.filter { $0.memo.contains("[定期]") }

        XCTAssertFalse(recurringTx.isEmpty, "Should have generated a recurring transaction")

        if let tx = recurringTx.first {
            let allocA = tx.allocations.first { $0.projectId == projectA.id }
            let allocB = tx.allocations.first { $0.projectId == projectB.id }

            // Project A completed last month, so for this month it should not be allocated.
            XCTAssertNil(allocA, "Project A should be excluded once its active days reach 0")
            XCTAssertNotNil(allocB, "Project B should remain allocated")
            XCTAssertEqual(allocB?.amount, 10000, "Project B should get full amount")
        }
    }

    // MARK: - Test 7: recalculateAllPartialPeriodProjects at startup

    func testRecalculateAllPartialPeriodProjects_fixesExistingTransactions() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        // Add a transaction for Feb 2024 with 50/50 allocation
        let transactionDate = makeDate(year: 2024, month: 2, day: 28)
        dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "test",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        // Manually set project A as completed without triggering recalculation
        // (simulating state that exists before the fix was deployed)
        let project = dataStore.getProject(id: projectA.id)!
        project.status = .completed
        project.completedAt = makeDate(year: 2024, month: 2, day: 15)
        try? context.save()
        dataStore.loadData()

        // Verify allocations are still original (not yet recalculated)
        var transactions = fetchAllTransactions()
        var allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        XCTAssertEqual(allocA.amount, 5000, "Before recalculation, should be original amount")

        // Call recalculateAllPartialPeriodProjects (simulating app startup)
        dataStore.recalculateAllPartialPeriodProjects()

        // Verify pro-rata was applied
        transactions = fetchAllTransactions()
        allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        let allocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!

        XCTAssertEqual(allocA.amount, 2586, "After startup recalc: 5000 * 15 / 29")
        XCTAssertEqual(allocB.amount, 7414, "Project B gets redistributed amount")
        XCTAssertEqual(allocA.amount + allocB.amount, 10000)
    }

    // MARK: - Test 8: Post-completion month transactions get 0 allocation

    func testUpdateProject_completedRecalculatesFutureMonthTransactions() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        // Add transactions in Feb and March 2024
        let febDate = makeDate(year: 2024, month: 2, day: 28)
        let marchDate = makeDate(year: 2024, month: 3, day: 15)
        dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: febDate,
            categoryId: "cat-hosting",
            memo: "feb expense",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )
        dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: marchDate,
            categoryId: "cat-hosting",
            memo: "march expense",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        // Complete project A on Feb 15, 2024
        let completedDate = makeDate(year: 2024, month: 2, day: 15)
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: completedDate)

        let transactions = fetchAllTransactions()
        let febTx = transactions.first { $0.memo == "feb expense" }!
        let marchTx = transactions.first { $0.memo == "march expense" }!

        // Feb: same month as completion, pro-rated
        let febAllocA = febTx.allocations.first { $0.projectId == projectA.id }!
        XCTAssertEqual(febAllocA.amount, 2586, "Feb: 5000 * 15 / 29")

        // March: after completion month, 0 active days
        let marchAllocA = marchTx.allocations.first { $0.projectId == projectA.id }!
        let marchAllocB = marchTx.allocations.first { $0.projectId == projectB.id }!
        XCTAssertEqual(marchAllocA.amount, 0, "March: project A should get 0 after completion month")
        XCTAssertEqual(marchAllocB.amount, 10000, "March: project B gets full amount")
    }

    // MARK: - Test 9: Yearly pro-rata utility function

    func testRedistributeAllocationsForYearlyCompletion_midYear() {
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 60000),
            Allocation(projectId: projectB, ratio: 50, amount: 60000),
        ]

        // Project A completes on Jun 30, 2026 (181st day of year, non-leap)
        // 2026 has 365 days
        // Active days = 181 (Jan 1 through Jun 30)
        // Pro-rated: 60000 * 181 / 365 = 29753
        let result = redistributeAllocationsForYearlyCompletion(
            totalAmount: 120000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2026, month: 6, day: 30),
            transactionYear: 2026,
            originalAllocations: allocations,
            activeProjectIds: Set([projectB])
        )

        let allocA = result.first { $0.projectId == projectA }!
        let allocB = result.first { $0.projectId == projectB }!

        // 60000 * 181 / 365 = 29753
        XCTAssertEqual(allocA.amount, 29753, "Yearly pro-rata for 181 days")
        XCTAssertEqual(allocA.amount + allocB.amount, 120000, "Total should be preserved")
    }

    // MARK: - Test 10: Yearly pro-rata before year returns full

    func testRedistributeAllocationsForYearlyCompletion_completedNextYear() {
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 60000),
            Allocation(projectId: projectB, ratio: 50, amount: 60000),
        ]

        // Project completes in 2027, transaction year is 2026 → full allocation
        let result = redistributeAllocationsForYearlyCompletion(
            totalAmount: 120000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2027, month: 3, day: 1),
            transactionYear: 2026,
            originalAllocations: allocations,
            activeProjectIds: Set([projectB])
        )

        XCTAssertEqual(result[0].amount, 60000, "Should be unchanged")
        XCTAssertEqual(result[1].amount, 60000, "Should be unchanged")
    }

    // MARK: - Test 11: Yearly pro-rata previous year returns 0

    func testRedistributeAllocationsForYearlyCompletion_completedPreviousYear() {
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 60000),
            Allocation(projectId: projectB, ratio: 50, amount: 60000),
        ]

        // Project completed in 2025, transaction year is 2026 → 0 active days
        let result = redistributeAllocationsForYearlyCompletion(
            totalAmount: 120000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2025, month: 12, day: 31),
            transactionYear: 2026,
            originalAllocations: allocations,
            activeProjectIds: Set([projectB])
        )

        let allocA = result.first { $0.projectId == projectA }!
        let allocB = result.first { $0.projectId == projectB }!

        XCTAssertEqual(allocA.amount, 0, "Completed before year: 0 allocation")
        XCTAssertEqual(allocB.amount, 120000, "Project B gets full amount")
    }

    // MARK: - Test 12: daysInYear

    func testDaysInYear_nonLeap() {
        XCTAssertEqual(daysInYear(2026), 365)
    }

    func testDaysInYear_leap() {
        XCTAssertEqual(daysInYear(2024), 366)
    }

    // MARK: - Test 13: addProject with startDate

    func testAddProject_withStartDate() {
        let startDate = makeDate(year: 2026, month: 3, day: 15)
        let project = dataStore.addProject(name: "Started Project", description: "desc", startDate: startDate)

        XCTAssertEqual(project.name, "Started Project")
        XCTAssertNotNil(project.startDate)

        let comps = calendar.dateComponents([.year, .month, .day], from: project.startDate!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 15)
    }

    // MARK: - Test 14: updateProject with startDate triggers recalculation

    func testUpdateProject_startDate_recalculatesAllocations() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        // Add a transaction for March 2026 (31 days)
        let transactionDate = makeDate(year: 2026, month: 3, day: 15)
        dataStore.addTransaction(
            type: .expense,
            amount: 31000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "test",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        // Set startDate to March 15 for project A
        let startDate = makeDate(year: 2026, month: 3, day: 15)
        dataStore.updateProject(id: projectA.id, startDate: startDate)

        let transactions = fetchAllTransactions()
        let allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        let allocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!

        // Project A: 15500 * 17 / 31 = 8500
        XCTAssertEqual(allocA.amount, 8500, "Project A should get pro-rated amount for 17 days")
        XCTAssertEqual(allocA.amount + allocB.amount, 31000)
    }

    // MARK: - Test 15: startDate change triggers recalculation

    func testUpdateProject_changeStartDate_recalculates() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        let transactionDate = makeDate(year: 2026, month: 3, day: 15)
        dataStore.addTransaction(
            type: .expense,
            amount: 31000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "test",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        // First set startDate to March 15
        dataStore.updateProject(id: projectA.id, startDate: makeDate(year: 2026, month: 3, day: 15))

        var transactions = fetchAllTransactions()
        var allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        XCTAssertEqual(allocA.amount, 8500, "First: 15500 * 17 / 31")

        // Change startDate to March 20 (12 days active)
        dataStore.updateProject(id: projectA.id, startDate: makeDate(year: 2026, month: 3, day: 20))

        transactions = fetchAllTransactions()
        allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        // 15500 * 12 / 31 = 6000
        XCTAssertEqual(allocA.amount, 6000, "Second: 15500 * 12 / 31")
        let allocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!
        XCTAssertEqual(allocA.amount + allocB.amount, 31000, "Total should be preserved")
    }

    // MARK: - Test 16: startDate and completedAt in same month

    func testUpdateProject_startDateAndCompletedAt_sameMonth() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        let transactionDate = makeDate(year: 2026, month: 3, day: 15)
        dataStore.addTransaction(
            type: .expense,
            amount: 31000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "test",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        // Set startDate to March 10 and completedAt to March 20
        dataStore.updateProject(
            id: projectA.id,
            status: .completed,
            startDate: makeDate(year: 2026, month: 3, day: 10),
            completedAt: makeDate(year: 2026, month: 3, day: 20)
        )

        let transactions = fetchAllTransactions()
        let allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!

        // Active days: Mar 10..20 = 11 days, 15500 * 11 / 31 = 5500
        XCTAssertEqual(allocA.amount, 5500, "Should be pro-rated for 11 days")
        let total = transactions.first!.allocations.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 31000)
    }

    // MARK: - Test 17: Multiple partial projects holistic calculation

    func testMultiplePartialProjects_holisticCalculation_totalPreserved() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")
        let projectC = makeProject(name: "Project C")

        // April 2026 (30 days)
        let transactionDate = makeDate(year: 2026, month: 4, day: 1)
        dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "holistic test",
            allocations: [
                (projectId: projectA.id, ratio: 33),
                (projectId: projectB.id, ratio: 33),
                (projectId: projectC.id, ratio: 34)
            ]
        )

        // A: 完了日=4月15日（15日稼働）
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: makeDate(year: 2026, month: 4, day: 15))
        // C: 開始日=4月10日（21日稼働）
        dataStore.updateProject(id: projectC.id, startDate: makeDate(year: 2026, month: 4, day: 10))

        let transactions = fetchAllTransactions()
        let tx = transactions.first { $0.memo == "holistic test" }!
        let allocA = tx.allocations.first { $0.projectId == projectA.id }!
        let allocB = tx.allocations.first { $0.projectId == projectB.id }!
        let allocC = tx.allocations.first { $0.projectId == projectC.id }!

        let total = allocA.amount + allocB.amount + allocC.amount
        XCTAssertEqual(total, 10000, "Total must be exactly preserved with multiple partial projects")

        // A: 3300 * 15/30 = 1650
        XCTAssertEqual(allocA.amount, 1650, "Project A should be pro-rated for 15 days")
        // C: 3400 * 21/30 = 2380
        XCTAssertEqual(allocC.amount, 2380, "Project C should be pro-rated for 21 days")
        // B gets the remainder: 10000 - 1650 - 2380 = 5970
        XCTAssertEqual(allocB.amount, 5970, "Project B (full days) should absorb the freed amount")
    }

    // MARK: - Test 18: Startup recalculation with multiple partial projects

    func testRecalculateAllPartialPeriodProjects_multiplePartialProjects_totalPreserved() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")
        let projectC = makeProject(name: "Project C")

        // April 2026 (30 days)
        let transactionDate = makeDate(year: 2026, month: 4, day: 1)
        dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "startup test",
            allocations: [
                (projectId: projectA.id, ratio: 33),
                (projectId: projectB.id, ratio: 33),
                (projectId: projectC.id, ratio: 34)
            ]
        )

        // Manually set project states without triggering recalculation
        let pA = dataStore.getProject(id: projectA.id)!
        pA.status = .completed
        pA.completedAt = makeDate(year: 2026, month: 4, day: 15)
        let pC = dataStore.getProject(id: projectC.id)!
        pC.startDate = makeDate(year: 2026, month: 4, day: 10)
        try? context.save()
        dataStore.loadData()

        // Verify allocations are still ratio-based
        var transactions = fetchAllTransactions()
        var allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        XCTAssertEqual(allocA.amount, 3300, "Before recalculation, should be ratio-based")

        // Simulate startup recalculation
        dataStore.recalculateAllPartialPeriodProjects()

        transactions = fetchAllTransactions()
        allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        let allocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!
        let allocC = transactions.first!.allocations.first { $0.projectId == projectC.id }!

        let total = allocA.amount + allocB.amount + allocC.amount
        XCTAssertEqual(total, 10000, "Total must be preserved after startup recalc with multiple partial projects")
        XCTAssertEqual(allocA.amount, 1650)
        XCTAssertEqual(allocC.amount, 2380)
        XCTAssertEqual(allocB.amount, 5970)
    }

    // MARK: - Test 19: recalculateAllPartialPeriodProjects includes startDate projects

    func testRecalculateAllPartialPeriodProjects_includesStartDateProjects() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        // Add a transaction for March 2026
        let transactionDate = makeDate(year: 2026, month: 3, day: 15)
        dataStore.addTransaction(
            type: .expense,
            amount: 31000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "test",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        // Manually set startDate without triggering recalculation
        let project = dataStore.getProject(id: projectA.id)!
        project.startDate = makeDate(year: 2026, month: 3, day: 15)
        try? context.save()
        dataStore.loadData()

        // Verify allocations are still original
        var transactions = fetchAllTransactions()
        var allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        XCTAssertEqual(allocA.amount, 15500)

        // Call recalculateAllPartialPeriodProjects
        dataStore.recalculateAllPartialPeriodProjects()

        transactions = fetchAllTransactions()
        allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        // 15500 * 17 / 31 = 8500
        XCTAssertEqual(allocA.amount, 8500, "Should be pro-rated after startup recalc")
    }

    // MARK: - Test 20: isYearly detection in recalculateAllocationsForProject

    func testRecalculateAllocationsForProject_yearlyTransaction_usesYearDays() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        let today = todayComponents
        guard let year = today.year else {
            XCTFail("Cannot get year")
            return
        }

        // Create a yearly recurring transaction
        let pastMonth: Int? = (today.month ?? 1) >= 2 ? (today.month! - 1) : nil
        guard let pMonth = pastMonth else { return } // Skip if January

        let recurring = dataStore.addRecurring(
            name: "Annual License",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "yearly",
            allocationMode: .manual,
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: pMonth
        )

        XCTAssertEqual(dataStore.processRecurringTransactions(), 1, "Should generate one yearly recurring posting")

        // Verify transaction was generated
        let transactions = fetchGeneratedRecurringTransactions()
        let yearlyTx = transactions.filter { $0.recurringId == recurring.id }
        XCTAssertFalse(yearlyTx.isEmpty, "Should have generated yearly transaction")

        guard let tx = yearlyTx.first else { return }

        // Now complete project A mid-year
        let completedDate = makeDate(year: year, month: 6, day: 30)
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: completedDate)

        // Verify the yearly transaction was recalculated with yearly days (365/366)
        let updatedTransactions = fetchGeneratedRecurringTransactions()
        let updatedTx = updatedTransactions.first { $0.recurringId == recurring.id }!
        let allocA = updatedTx.allocations.first { $0.projectId == projectA.id }!
        let allocB = updatedTx.allocations.first { $0.projectId == projectB.id }!

        // allocA should use yearly days, not monthly
        // If monthly was used incorrectly, amount would be much higher or much lower
        let totalDays = daysInYear(year)
        let activeDays = calculateActiveDaysInYear(startDate: nil, completedAt: completedDate, year: year)
        let expectedA = 60000 * activeDays / totalDays
        XCTAssertEqual(allocA.amount, expectedA, "Should use yearly day count, not monthly")
        XCTAssertEqual(allocA.amount + allocB.amount, 120000, "Total must be preserved")
    }

    // MARK: - Test 21: addProject triggers equalAll reprocessing

    func testAddProject_updatesEqualAllCurrentPeriodTransactions() {
        let projectA = makeProject(name: "Project A")

        // Create equalAll monthly recurring
        dataStore.addRecurring(
            name: "EqualAll Fee",
            type: .expense,
            amount: 12000,
            categoryId: "cat-hosting",
            memo: "equalall",
            allocationMode: .equalAll,
            allocations: [],
            frequency: .monthly,
            dayOfMonth: 1
        )

        XCTAssertEqual(dataStore.processRecurringTransactions(), 1, "Should generate one equalAll recurring posting")

        // Verify: only project A gets the full amount
        var transactions = fetchGeneratedRecurringTransactions()
        var recurringTx = transactions.filter { $0.memo.contains("[定期]") && $0.memo.contains("EqualAll Fee") }
        XCTAssertFalse(recurringTx.isEmpty, "Should have generated equalAll transaction")
        if let tx = recurringTx.first {
            XCTAssertEqual(tx.allocations.count, 1, "Should allocate to 1 project")
            XCTAssertEqual(tx.allocations.first?.projectId, projectA.id)
            XCTAssertEqual(tx.allocations.first?.amount, 12000)
        }

        // Add a new project
        let projectB = dataStore.addProject(name: "Project B", description: "new")

        // Verify: the existing transaction now includes project B
        transactions = fetchGeneratedRecurringTransactions()
        recurringTx = transactions.filter { $0.memo.contains("[定期]") && $0.memo.contains("EqualAll Fee") }
        if let tx = recurringTx.first {
            XCTAssertEqual(tx.allocations.count, 2, "Should now allocate to 2 projects")
            let hasA = tx.allocations.contains { $0.projectId == projectA.id }
            let hasB = tx.allocations.contains { $0.projectId == projectB.id }
            XCTAssertTrue(hasA, "Project A should still be allocated")
            XCTAssertTrue(hasB, "New Project B should be allocated")
            let total = tx.allocations.reduce(0) { $0 + $1.amount }
            XCTAssertEqual(total, 12000, "Total must be preserved")
        }
    }

    // MARK: - Test 22: endDate auto-deactivates recurring

    func testProcessRecurring_endDatePassed_deactivatesRecurring() {
        let project = makeProject(name: "Project A")

        // Insert recurring directly with endDate in the past
        let pastDate = makeDate(year: 2020, month: 1, day: 1)
        let recurring = PPRecurringTransaction(
            name: "Ended Recurring",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "ended",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 5000)],
            frequency: .monthly,
            dayOfMonth: 1,
            isActive: true,
            endDate: pastDate
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        // Process should deactivate
        dataStore.processRecurringTransactions()

        let updated = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(updated?.isActive, false, "Recurring with past endDate should be deactivated")
        XCTAssertTrue(fetchGeneratedRecurringTransactions().isEmpty, "No transaction should be generated for deactivated recurring")
    }

    // MARK: - Test 23: reverseCompletionAllocations rounding remainder

    func testReverseCompletionAllocations_roundingRemainder() {
        // 10,000円を33%/33%/34%の3プロジェクト配分 → 完了 → 再活性化 → 合計=10,000を検証
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")
        let projectC = makeProject(name: "Project C")

        let transactionDate = makeDate(year: 2024, month: 6, day: 15)
        dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "rounding test",
            allocations: [
                (projectId: projectA.id, ratio: 33),
                (projectId: projectB.id, ratio: 33),
                (projectId: projectC.id, ratio: 34)
            ]
        )

        // 完了 → 日割り適用
        let completedDate = makeDate(year: 2024, month: 6, day: 20)
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: completedDate)

        // 再活性化 → reverseCompletionAllocations が呼ばれ比率ベースに復元
        dataStore.updateProject(id: projectA.id, status: .active)

        let transactions = fetchAllTransactions()
        let tx = transactions.first { $0.memo == "rounding test" }!
        let allocA = tx.allocations.first { $0.projectId == projectA.id }!
        let allocB = tx.allocations.first { $0.projectId == projectB.id }!
        let allocC = tx.allocations.first { $0.projectId == projectC.id }!

        // 33% of 10000 = 3300, 33% = 3300, 34% = 3400 → sum = 10000
        // recalculateAllocationAmounts applies remainder to last allocation
        let total = allocA.amount + allocB.amount + allocC.amount
        XCTAssertEqual(total, 10000, "端数処理後も合計=10,000円であるべき")
        XCTAssertEqual(allocA.ratio, 33)
        XCTAssertEqual(allocB.ratio, 33)
        XCTAssertEqual(allocC.ratio, 34)
    }

    // MARK: - Test 24: reverseCompletionAllocations recalculates remaining partials

    func testReverseCompletion_recalculatesRemainingPartialProjects() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        // Add a transaction for March 2026 (31 days)
        let transactionDate = makeDate(year: 2026, month: 3, day: 15)
        dataStore.addTransaction(
            type: .expense,
            amount: 31000,
            date: transactionDate,
            categoryId: "cat-hosting",
            memo: "reverse test",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        // Set project B startDate to March 15 (17 days active)
        dataStore.updateProject(id: projectB.id, startDate: makeDate(year: 2026, month: 3, day: 15))

        var transactions = fetchAllTransactions()
        var allocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!
        // B should be pro-rated: 15500 * 17/31 = 8500
        XCTAssertEqual(allocB.amount, 8500, "B should be pro-rated initially")

        // Complete project A on March 20
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: makeDate(year: 2026, month: 3, day: 20))

        // Now reactivate project A
        dataStore.updateProject(id: projectA.id, status: .active)

        // After reactivation, A's allocations are restored to ratio-based first,
        // then B's pro-rata should be re-applied
        transactions = fetchAllTransactions()
        allocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!
        let allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!

        // B still has startDate Mar 15, so should still be pro-rated
        XCTAssertEqual(allocB.amount, 8500, "B should still be pro-rated after A reactivation")
        XCTAssertEqual(allocA.amount + allocB.amount, 31000, "Total must be preserved")
    }

}
