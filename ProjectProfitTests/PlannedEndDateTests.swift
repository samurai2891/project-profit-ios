import XCTest
import SwiftData
@testable import ProjectProfit

// MARK: - PlannedEndDateTests

@MainActor
final class PlannedEndDateTests: XCTestCase {
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

    private func makeProject(name: String = "TestProject") -> PPProject {
        dataStore.addProject(name: name, description: "desc")
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func fetchAllTransactions() -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private struct GeneratedRecurringPosting {
        let id: UUID
        let date: Date
        let memo: String
        let recurringId: UUID?
        let allocations: [Allocation]
    }

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
            let amount = relevantLines.reduce(into: [UUID: Int]()) { result, line in
                guard let projectId = line.projectAllocationId else { return }
                result[projectId, default: 0] += NSDecimalNumber(decimal: line.amount).intValue
            }
            let allocations = amount.map { projectId, allocationAmount in
                Allocation(projectId: projectId, ratio: 0, amount: allocationAmount)
            }
            .sorted { $0.projectId.uuidString < $1.projectId.uuidString }

            return GeneratedRecurringPosting(
                id: journal.id,
                date: journal.journalDate,
                memo: journal.description,
                recurringId: snapshot.recurringId,
                allocations: allocations
            )
        }
    }

    // MARK: - Test 1: effectiveEndDate returns completedAt when both set

    func testEffectiveEndDate_completedAtTakesPrecedence() {
        let project = makeProject()
        let completedAt = makeDate(year: 2026, month: 6, day: 30)
        let plannedEndDate = makeDate(year: 2026, month: 9, day: 30)
        dataStore.updateProject(
            id: project.id,
            status: .completed,
            completedAt: completedAt,
            plannedEndDate: plannedEndDate
        )

        let updated = dataStore.getProject(id: project.id)!
        XCTAssertEqual(updated.effectiveEndDate, completedAt, "completedAt should take precedence over plannedEndDate")
        XCTAssertFalse(updated.isUsingPlannedEndDate)
    }

    // MARK: - Test 2: effectiveEndDate returns plannedEndDate when no completedAt

    func testEffectiveEndDate_usesPlannedEndDateWhenNoCompletedAt() {
        let project = makeProject()
        let plannedEndDate = makeDate(year: 2026, month: 9, day: 30)
        dataStore.updateProject(id: project.id, plannedEndDate: plannedEndDate)

        let updated = dataStore.getProject(id: project.id)!
        XCTAssertEqual(updated.effectiveEndDate, plannedEndDate)
        XCTAssertTrue(updated.isUsingPlannedEndDate)
    }

    // MARK: - Test 3: effectiveEndDate is nil when neither set

    func testEffectiveEndDate_nilWhenNeitherSet() {
        let project = makeProject()
        let updated = dataStore.getProject(id: project.id)!
        XCTAssertNil(updated.effectiveEndDate)
        XCTAssertFalse(updated.isUsingPlannedEndDate)
    }

    // MARK: - Test 4: Pro-rata uses plannedEndDate

    func testPlannedEndDate_triggersProRataCalculation() {
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

        // Set plannedEndDate to March 15 for project A (15 days active)
        let plannedEndDate = makeDate(year: 2026, month: 3, day: 15)
        dataStore.updateProject(id: projectA.id, plannedEndDate: plannedEndDate)

        let transactions = fetchAllTransactions()
        let allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        let allocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!

        // Project A: 15500 * 15 / 31 = 7500
        XCTAssertEqual(allocA.amount, 7500, "Project A should get pro-rated amount based on plannedEndDate")
        XCTAssertEqual(allocA.amount + allocB.amount, 31000, "Total must be preserved")
    }

    // MARK: - Test 5: Changing plannedEndDate triggers recalculation

    func testChangePlannedEndDate_recalculates() {
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

        // First set plannedEndDate to March 15
        dataStore.updateProject(id: projectA.id, plannedEndDate: makeDate(year: 2026, month: 3, day: 15))

        var transactions = fetchAllTransactions()
        var allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        XCTAssertEqual(allocA.amount, 7500, "First: 15500 * 15 / 31")

        // Change to March 20
        dataStore.updateProject(id: projectA.id, plannedEndDate: makeDate(year: 2026, month: 3, day: 20))

        transactions = fetchAllTransactions()
        allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        let allocB = transactions.first!.allocations.first { $0.projectId == projectB.id }!

        // 15500 * 20 / 31 = 10000
        XCTAssertEqual(allocA.amount, 10000, "Second: 15500 * 20 / 31")
        XCTAssertEqual(allocA.amount + allocB.amount, 31000, "Total must be preserved")
    }

    // MARK: - Test 6: Clearing plannedEndDate restores ratio-based allocation

    func testClearPlannedEndDate_restoresRatioBasedAllocation() {
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

        // Set plannedEndDate
        dataStore.updateProject(id: projectA.id, plannedEndDate: makeDate(year: 2026, month: 3, day: 15))

        var transactions = fetchAllTransactions()
        var allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        XCTAssertNotEqual(allocA.amount, 15500, "Should be pro-rated, not original")

        // Clear plannedEndDate
        dataStore.updateProject(id: projectA.id, plannedEndDate: .some(nil))

        transactions = fetchAllTransactions()
        allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        XCTAssertEqual(allocA.amount, 15500, "Should restore to ratio-based allocation")
    }

    // MARK: - Test 7: recalculateAllPartialPeriodProjects includes plannedEndDate projects

    func testRecalculateAllPartialPeriodProjects_includesPlannedEndDateProjects() {
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

        // Manually set plannedEndDate without triggering recalculation
        let project = dataStore.getProject(id: projectA.id)!
        project.plannedEndDate = makeDate(year: 2026, month: 3, day: 15)
        try? context.save()
        dataStore.loadData()

        // Verify allocations are still original
        var transactions = fetchAllTransactions()
        var allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        XCTAssertEqual(allocA.amount, 15500)

        // Simulate startup recalculation
        dataStore.recalculateAllPartialPeriodProjects()

        transactions = fetchAllTransactions()
        allocA = transactions.first!.allocations.first { $0.projectId == projectA.id }!
        XCTAssertEqual(allocA.amount, 7500, "Should be pro-rated after startup recalc: 15500 * 15 / 31")
    }

    // MARK: - Test 8: addProject with plannedEndDate

    func testAddProject_withPlannedEndDate() {
        let plannedEndDate = makeDate(year: 2026, month: 12, day: 31)
        let project = dataStore.addProject(name: "Planned Project", description: "desc", plannedEndDate: plannedEndDate)

        XCTAssertNotNil(project.plannedEndDate)
        let comps = calendar.dateComponents([.year, .month, .day], from: project.plannedEndDate!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 12)
        XCTAssertEqual(comps.day, 31)
    }

    // MARK: - Test 9: Recurring manual pro-rata uses effectiveEndDate

    func testRecurringManual_usesPlannedEndDateForProRata() {
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        let today = calendar.dateComponents([.year, .month, .day], from: todayDate())
        guard let year = today.year, let month = today.month else {
            XCTFail("Cannot get today's components")
            return
        }

        // Set plannedEndDate for project A to last month
        let lastMonth = month == 1 ? 12 : month - 1
        let lastMonthYear = month == 1 ? year - 1 : year
        let plannedEndDate = makeDate(year: lastMonthYear, month: lastMonth, day: 15)
        dataStore.updateProject(id: projectA.id, plannedEndDate: plannedEndDate)

        // Create manual recurring
        dataStore.addRecurring(
            name: "Manual Monthly",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "planned",
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
            XCTAssertNil(allocA, "Project A should be excluded once plannedEndDate leaves it with 0 active days")
            XCTAssertEqual(allocB?.amount, 10000, "Project B should receive the full amount")
        }
    }
}
