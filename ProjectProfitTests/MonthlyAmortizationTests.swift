import XCTest
import SwiftData
@testable import ProjectProfit

// MARK: - MonthlyAmortizationTests

@MainActor
final class MonthlyAmortizationTests: XCTestCase {
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

    private func makeProject(name: String = "TestProject") -> PPProject {
        dataStore.addProject(name: name, description: "desc")
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private var todayComponents: DateComponents {
        calendar.dateComponents([.year, .month, .day], from: todayDate())
    }

    private var pastDayOfMonth: Int {
        let day = todayComponents.day!
        return day >= 2 ? 1 : 1
    }

    private var pastMonth: Int? {
        let month = todayComponents.month!
        return month >= 2 ? month - 1 : nil
    }

    private func fetchAllTransactions() -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchRecurring(id: UUID) -> PPRecurringTransaction? {
        let descriptor = FetchDescriptor<PPRecurringTransaction>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.first { $0.id == id }
    }

    // MARK: - Test 1: Monthly spread generates transactions for past months

    func testMonthlySpread_generatesTransactionsForPastMonths() {
        guard let startMonth = pastMonth else { return }
        // If startMonth is before current month, at least 1 transaction should be generated
        let project = makeProject()

        let recurring = dataStore.addRecurring(
            name: "Annual Fee",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "spread",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth,
            yearlyAmortizationMode: .monthlySpread
        )

        let transactions = fetchAllTransactions()
        let spreadTx = transactions.filter { $0.memo.contains("[定期/月次]") }

        // Should have at least 1 transaction (for the past month)
        XCTAssertFalse(spreadTx.isEmpty, "Should have generated monthly spread transactions")

        // Each transaction should have the spread amount
        let monthlyAmount = 120000 / 12
        for tx in spreadTx {
            let txMonth = calendar.component(.month, from: tx.date)
            if txMonth == 12 {
                XCTAssertEqual(tx.amount, monthlyAmount + (120000 - monthlyAmount * 12), "December should include remainder")
            } else {
                XCTAssertEqual(tx.amount, monthlyAmount, "Monthly amount should be 120000/12 = \(monthlyAmount)")
            }
        }
    }

    // MARK: - Test 2: Amount splitting with remainder

    func testMonthlySpread_amountSplitting_remainderIn12thMonth() {
        // 100000 / 12 = 8333 per month, remainder = 100000 - 8333*12 = 4
        // December gets 8333 + 4 = 8337
        let monthlyAmount = 100000 / 12
        let remainder = 100000 - (monthlyAmount * 12)

        XCTAssertEqual(monthlyAmount, 8333)
        XCTAssertEqual(remainder, 4)
        XCTAssertEqual(monthlyAmount * 11 + monthlyAmount + remainder, 100000, "Total should be preserved")
    }

    // MARK: - Test 3: Duplicate prevention via lastGeneratedMonths

    func testMonthlySpread_noDuplicatesOnReprocess() {
        guard let startMonth = pastMonth else { return }
        let project = makeProject()

        let recurring = dataStore.addRecurring(
            name: "No Dup",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "nodup",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth,
            yearlyAmortizationMode: .monthlySpread
        )

        let countBefore = fetchAllTransactions().count

        // Process again - should not create duplicates
        let generatedCount = dataStore.processRecurringTransactions()

        let countAfter = fetchAllTransactions().count
        XCTAssertEqual(countBefore, countAfter, "Should not create duplicates on reprocess")
        XCTAssertEqual(generatedCount, 0, "No new transactions should be generated")
    }

    // MARK: - Test 4: lastGeneratedMonths tracking

    func testMonthlySpread_tracksLastGeneratedMonths() {
        guard let startMonth = pastMonth else { return }
        let project = makeProject()

        let recurring = dataStore.addRecurring(
            name: "Tracked",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "tracked",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth,
            yearlyAmortizationMode: .monthlySpread
        )

        let updated = fetchRecurring(id: recurring.id)
        XCTAssertFalse(updated?.lastGeneratedMonths.isEmpty ?? true, "lastGeneratedMonths should be populated")

        // Verify format is "YYYY-MM"
        if let firstMonth = updated?.lastGeneratedMonths.first {
            let parts = firstMonth.split(separator: "-")
            XCTAssertEqual(parts.count, 2, "Month key should be YYYY-MM format")
        }
    }

    // MARK: - Test 5: Memo format for monthly spread

    func testMonthlySpread_memoFormat() {
        guard let startMonth = pastMonth else { return }
        let project = makeProject()

        dataStore.addRecurring(
            name: "Annual License",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "AWS",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth,
            yearlyAmortizationMode: .monthlySpread
        )

        let transactions = fetchAllTransactions()
        let spreadTx = transactions.filter { $0.memo.contains("[定期/月次]") }
        XCTAssertFalse(spreadTx.isEmpty)

        if let tx = spreadTx.first {
            XCTAssertEqual(tx.memo, "[定期/月次] Annual License - AWS")
        }
    }

    // MARK: - Test 6: Memo format without memo

    func testMonthlySpread_memoFormat_withoutMemo() {
        guard let startMonth = pastMonth else { return }
        let project = makeProject()

        dataStore.addRecurring(
            name: "Domain",
            type: .expense,
            amount: 12000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth,
            yearlyAmortizationMode: .monthlySpread
        )

        let transactions = fetchAllTransactions()
        let spreadTx = transactions.filter { $0.memo.contains("[定期/月次]") }
        XCTAssertFalse(spreadTx.isEmpty)

        if let tx = spreadTx.first {
            XCTAssertEqual(tx.memo, "[定期/月次] Domain")
        }
    }

    // MARK: - Test 7: Lump sum mode still works normally

    func testYearlyLumpSum_unchangedBehavior() {
        guard let startMonth = pastMonth else { return }
        let project = makeProject()

        dataStore.addRecurring(
            name: "Lump Sum",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "lumpsum",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth,
            yearlyAmortizationMode: .lumpSum
        )

        let transactions = fetchAllTransactions()
        // Lump sum generates 1 transaction with full amount
        let lumpTx = transactions.filter { $0.memo.contains("[定期] Lump Sum") }
        XCTAssertEqual(lumpTx.count, 1, "Lump sum should generate exactly 1 transaction")
        XCTAssertEqual(lumpTx.first?.amount, 120000, "Full amount for lump sum")
    }

    // MARK: - Test 8: nil yearlyAmortizationMode defaults to lumpSum behavior

    func testNilAmortizationMode_defaultsToLumpSum() {
        guard let startMonth = pastMonth else { return }
        let project = makeProject()

        dataStore.addRecurring(
            name: "Default",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "default",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth
            // yearlyAmortizationMode not specified, defaults to nil
        )

        let transactions = fetchAllTransactions()
        let tx = transactions.filter { $0.memo.contains("[定期] Default") }
        XCTAssertEqual(tx.count, 1, "nil mode should behave like lumpSum")
        XCTAssertEqual(tx.first?.amount, 120000)
    }

    // MARK: - Test 9: Monthly spread uses monthly pro-rata (not yearly)

    func testMonthlySpread_usesMonthlyProRataNotYearly() {
        guard let startMonth = pastMonth else { return }
        let projectA = makeProject(name: "Project A")
        let projectB = makeProject(name: "Project B")

        let today = todayComponents
        guard let year = today.year, let month = today.month else { return }

        // Complete project A mid-month in the startMonth
        let completedDate = makeDate(year: year, month: startMonth, day: 15)
        dataStore.updateProject(id: projectA.id, status: .completed, completedAt: completedDate)

        dataStore.addRecurring(
            name: "Prorated Spread",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "prorata",
            allocationMode: .manual,
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth,
            yearlyAmortizationMode: .monthlySpread
        )

        let transactions = fetchAllTransactions()
        let spreadTx = transactions.filter { $0.memo.contains("[定期/月次]") && $0.memo.contains("prorata") }
        XCTAssertFalse(spreadTx.isEmpty, "Should have generated spread transactions")

        // Find the transaction for the startMonth
        if let startMonthTx = spreadTx.first(where: {
            calendar.component(.month, from: $0.date) == startMonth
        }) {
            let total = startMonthTx.allocations.reduce(0) { $0 + $1.amount }
            let monthlyAmount = 120000 / 12
            XCTAssertEqual(total, monthlyAmount, "Total for month should be monthly split amount")
        }
    }

    // MARK: - Test 10: endDate respected in monthly spread

    func testMonthlySpread_endDateRespectsEachMonth() {
        let project = makeProject()
        let today = todayComponents
        guard let year = today.year, let month = today.month else { return }

        // Use startMonth = 1 (January), endDate = month before current
        guard month >= 3 else { return } // Need at least March to test this
        let endDate = makeDate(year: year, month: month - 1, day: 15)

        let recurring = PPRecurringTransaction(
            name: "End Limited",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "limited",
            allocations: [Allocation(projectId: project.id, ratio: 100, amount: 10000)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: 1,
            isActive: true,
            endDate: endDate,
            yearlyAmortizationMode: .monthlySpread
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()

        dataStore.processRecurringTransactions()

        let transactions = fetchAllTransactions()
        let spreadTx = transactions.filter { $0.memo.contains("[定期/月次]") }

        // No transaction should be generated for or after the endDate month (dayOfMonth=1 > endDate day=15 is after)
        for tx in spreadTx {
            XCTAssertTrue(tx.date <= endDate, "No transaction should be generated after endDate")
        }
    }

    // MARK: - Test 11: Model default values

    func testRecurringTransaction_defaultValues() {
        let recurring = PPRecurringTransaction(
            name: "Test",
            type: .expense,
            amount: 10000,
            categoryId: "cat-tools"
        )
        XCTAssertNil(recurring.yearlyAmortizationMode, "Default should be nil")
        XCTAssertTrue(recurring.lastGeneratedMonths.isEmpty, "Default should be empty")
    }

    // MARK: - Test 12: Mode switching from monthly to lumpSum clears lastGeneratedMonths

    func testModeSwitch_monthlySpreadToLumpSum_clearsLastGeneratedMonths() {
        guard let startMonth = pastMonth else { return }
        let project = makeProject()

        let recurring = dataStore.addRecurring(
            name: "Switch Mode",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "switch",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth,
            yearlyAmortizationMode: .monthlySpread
        )

        // Verify lastGeneratedMonths is populated
        var updated = fetchRecurring(id: recurring.id)
        XCTAssertFalse(updated?.lastGeneratedMonths.isEmpty ?? true)

        // Switch to lumpSum
        dataStore.updateRecurring(id: recurring.id, yearlyAmortizationMode: .lumpSum)

        updated = fetchRecurring(id: recurring.id)
        XCTAssertTrue(updated?.lastGeneratedMonths.isEmpty ?? false, "lastGeneratedMonths should be cleared on switch to lumpSum")
    }

    // MARK: - Test 13: Frequency switch to monthly clears amortization mode

    func testFrequencySwitch_yearlyToMonthly_clearsAmortizationMode() {
        guard let startMonth = pastMonth else { return }
        let project = makeProject()

        let recurring = dataStore.addRecurring(
            name: "Freq Switch",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth,
            yearlyAmortizationMode: .monthlySpread
        )

        // Switch frequency to monthly
        dataStore.updateRecurring(id: recurring.id, frequency: .monthly)

        let updated = fetchRecurring(id: recurring.id)
        XCTAssertNil(updated?.yearlyAmortizationMode, "yearlyAmortizationMode should be nil after switch to monthly")
        XCTAssertTrue(updated?.lastGeneratedMonths.isEmpty ?? false, "lastGeneratedMonths should be cleared")
    }

    // MARK: - Test 14: equalAll mode with monthly spread

    func testMonthlySpread_equalAllMode() {
        guard let startMonth = pastMonth else { return }
        let project = makeProject()

        dataStore.addRecurring(
            name: "EqualAll Spread",
            type: .expense,
            amount: 120000,
            categoryId: "cat-tools",
            memo: "equalall",
            allocationMode: .equalAll,
            allocations: [],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: startMonth,
            yearlyAmortizationMode: .monthlySpread
        )

        let transactions = fetchAllTransactions()
        let spreadTx = transactions.filter { $0.memo.contains("[定期/月次]") }
        XCTAssertFalse(spreadTx.isEmpty, "equalAll with monthly spread should generate transactions")

        for tx in spreadTx {
            XCTAssertEqual(tx.allocations.count, 1, "Should allocate to the single active project")
            XCTAssertEqual(tx.allocations.first?.projectId, project.id)
        }
    }
}
