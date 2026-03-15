import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class ARBookTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

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

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - 1. Credit Sale creates Debit Entry

    func testARBook_CreditSale_DebitEntry() {
        // Dr acct-ar 100000 / Cr acct-sales 100000 with counterparty "上野商店"
        // → AR book entry should have debit = 100000 (売上金額)
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: date(2025, 1, 15),
            categoryId: "cat-sales", memo: "掛売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].debit, 100_000)
        XCTAssertEqual(entries[0].credit, 0)
        XCTAssertEqual(entries[0].counterparty, "上野商店")
    }

    // MARK: - 2. Payment Received creates Credit Entry

    func testARBook_PaymentReceived_CreditEntry() {
        // First, create the credit sale to set up the AR balance.
        // Then receive payment via transfer (Dr cash / Cr AR).
        // → AR book should show credit entry for the payment (受入金額).
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: date(2025, 1, 15),
            categoryId: "cat-sales", memo: "掛売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // Payment received: transfer from AR → cash
        let _ = mutations(dataStore).addTransaction(
            type: .transfer, amount: 100_000, date: date(2025, 2, 10),
            categoryId: "", memo: "上野商店入金",
            allocations: [],
            paymentAccountId: "acct-ar",
            transferToAccountId: "acct-cash",
            counterparty: "上野商店"
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31),
            counterpartyFilter: "上野商店"
        )

        XCTAssertEqual(entries.count, 2)
        // First entry: credit sale (debit)
        XCTAssertEqual(entries[0].debit, 100_000)
        XCTAssertEqual(entries[0].credit, 0)
        // Second entry: payment received (credit)
        XCTAssertEqual(entries[1].debit, 0)
        XCTAssertEqual(entries[1].credit, 100_000)
    }

    // MARK: - 3. Per-Counterparty Running Balance

    func testARBook_PerCounterpartyRunningBalance() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        // 上野商店: sale 100k
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: date(2025, 1, 10),
            categoryId: "cat-sales", memo: "上野商店掛売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // 上野商店: payment 60k
        let _ = mutations(dataStore).addTransaction(
            type: .transfer, amount: 60_000, date: date(2025, 1, 20),
            categoryId: "", memo: "上野商店入金",
            allocations: [],
            paymentAccountId: "acct-ar",
            transferToAccountId: "acct-cash",
            counterparty: "上野商店"
        )

        // 田中商店: sale 80k
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 80_000, date: date(2025, 1, 25),
            categoryId: "cat-sales", memo: "田中商店掛売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "田中商店"
        )

        // Check 上野商店 entries
        let uenoEntries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31),
            counterpartyFilter: "上野商店"
        )
        XCTAssertEqual(uenoEntries.count, 2)
        XCTAssertEqual(uenoEntries[0].runningBalance, 100_000, "上野商店: sale 100k → balance 100k")
        XCTAssertEqual(uenoEntries[1].runningBalance, 40_000, "上野商店: payment 60k → balance 40k")

        // Check 田中商店 entries
        let tanakaEntries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31),
            counterpartyFilter: "田中商店"
        )
        XCTAssertEqual(tanakaEntries.count, 1)
        XCTAssertEqual(tanakaEntries[0].runningBalance, 80_000, "田中商店: sale 80k → balance 80k (independent)")
    }

    // MARK: - 4. Counterparty Filter

    func testARBook_CounterpartyFilter() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        // Create AR entries for multiple counterparties
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 50_000, date: date(2025, 3, 1),
            categoryId: "cat-sales", memo: "上野商店売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 70_000, date: date(2025, 3, 5),
            categoryId: "cat-sales", memo: "田中商店売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "田中商店"
        )
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 30_000, date: date(2025, 3, 10),
            categoryId: "cat-sales", memo: "上野商店追加売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // Filter for 上野商店 only
        let uenoEntries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31),
            counterpartyFilter: "上野商店"
        )

        XCTAssertEqual(uenoEntries.count, 2)
        XCTAssertTrue(uenoEntries.allSatisfy { $0.counterparty == "上野商店" })
        XCTAssertEqual(uenoEntries[0].debit, 50_000)
        XCTAssertEqual(uenoEntries[1].debit, 30_000)
    }

    // MARK: - 5. Empty Counterparty Filter

    func testARBook_EmptyCounterpartyFilter() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        // AR entry with counterparty
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 50_000, date: date(2025, 4, 1),
            categoryId: "cat-sales", memo: "上野商店売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // AR entry without counterparty (nil)
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 20_000, date: date(2025, 4, 5),
            categoryId: "cat-sales", memo: "取引先不明売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: nil
        )

        // Filter for "" (empty/nil counterparty)
        let emptyEntries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31),
            counterpartyFilter: ""
        )

        XCTAssertEqual(emptyEntries.count, 1)
        XCTAssertEqual(emptyEntries[0].debit, 20_000)
        XCTAssertTrue(emptyEntries[0].counterparty == nil || emptyEntries[0].counterparty == "")
    }

    // MARK: - 6. Get Counterparties

    func testARBook_GetCounterparties() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 50_000, date: date(2025, 5, 1),
            categoryId: "cat-sales", memo: "上野商店売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 60_000, date: date(2025, 5, 10),
            categoryId: "cat-sales", memo: "田中商店売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "田中商店"
        )
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 30_000, date: date(2025, 5, 20),
            categoryId: "cat-sales", memo: "上野商店追加",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )
        // Entry with nil counterparty (should NOT appear in counterparties list)
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 10_000, date: date(2025, 5, 25),
            categoryId: "cat-sales", memo: "不明売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: nil
        )

        let counterparties = dataStore.getSubLedgerCounterparties(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        // Should return sorted, unique, non-empty counterparties
        XCTAssertEqual(counterparties, ["上野商店", "田中商店"])
    }

    // MARK: - 7. All Counterparties with Independent Balances

    func testARBook_AllCounterparties_IndependentBalances() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        // 上野商店: sale 100k
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: date(2025, 6, 1),
            categoryId: "cat-sales", memo: "上野商店掛売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // 田中商店: sale 80k
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 80_000, date: date(2025, 6, 5),
            categoryId: "cat-sales", memo: "田中商店掛売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "田中商店"
        )

        // 上野商店: payment 50k
        let _ = mutations(dataStore).addTransaction(
            type: .transfer, amount: 50_000, date: date(2025, 6, 10),
            categoryId: "", memo: "上野商店入金",
            allocations: [],
            paymentAccountId: "acct-ar",
            transferToAccountId: "acct-cash",
            counterparty: "上野商店"
        )

        // Without counterparty filter: all entries shown, each with independent balance
        let allEntries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 6, 1),
            endDate: date(2025, 6, 30)
        )

        XCTAssertEqual(allEntries.count, 3)

        // Entry 1: 上野商店 sale 100k → 上野商店 balance = 100k
        XCTAssertEqual(allEntries[0].counterparty, "上野商店")
        XCTAssertEqual(allEntries[0].debit, 100_000)
        XCTAssertEqual(allEntries[0].runningBalance, 100_000)

        // Entry 2: 田中商店 sale 80k → 田中商店 balance = 80k (independent)
        XCTAssertEqual(allEntries[1].counterparty, "田中商店")
        XCTAssertEqual(allEntries[1].debit, 80_000)
        XCTAssertEqual(allEntries[1].runningBalance, 80_000)

        // Entry 3: 上野商店 payment 50k → 上野商店 balance = 50k
        XCTAssertEqual(allEntries[2].counterparty, "上野商店")
        XCTAssertEqual(allEntries[2].credit, 50_000)
        XCTAssertEqual(allEntries[2].runningBalance, 50_000)
    }

    // MARK: - 8. Date Filter

    func testARBook_DateFilter() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        // January sale
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: date(2025, 1, 15),
            categoryId: "cat-sales", memo: "1月売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // March sale
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: date(2025, 3, 15),
            categoryId: "cat-sales", memo: "3月売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // May sale
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 150_000, date: date(2025, 5, 15),
            categoryId: "cat-sales", memo: "5月売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // Filter for Feb-Apr only → should only include March sale
        let entries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 2, 1),
            endDate: date(2025, 4, 30)
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].debit, 200_000)
        XCTAssertEqual(entries[0].memo, "3月売上")
    }

    // MARK: - 9. Empty AR Book

    func testARBook_Empty() {
        // No AR transactions at all
        let entries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - 10. Multiple Sales and Payments (Full Year Scenario)

    func testARBook_MultipleSalesAndPayments() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        // Jan: credit sale 100k
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: date(2025, 1, 15),
            categoryId: "cat-sales", memo: "1月掛売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // Feb: payment received 50k
        let _ = mutations(dataStore).addTransaction(
            type: .transfer, amount: 50_000, date: date(2025, 2, 10),
            categoryId: "", memo: "2月入金",
            allocations: [],
            paymentAccountId: "acct-ar",
            transferToAccountId: "acct-bank",
            counterparty: "上野商店"
        )

        // Mar: additional sale 80k
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 80_000, date: date(2025, 3, 15),
            categoryId: "cat-sales", memo: "3月掛売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // Apr: payment received 130k (clears remaining balance)
        let _ = mutations(dataStore).addTransaction(
            type: .transfer, amount: 130_000, date: date(2025, 4, 10),
            categoryId: "", memo: "4月入金",
            allocations: [],
            paymentAccountId: "acct-ar",
            transferToAccountId: "acct-bank",
            counterparty: "上野商店"
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31),
            counterpartyFilter: "上野商店"
        )

        XCTAssertEqual(entries.count, 4)

        // Jan sale: balance = 100k
        XCTAssertEqual(entries[0].debit, 100_000)
        XCTAssertEqual(entries[0].credit, 0)
        XCTAssertEqual(entries[0].runningBalance, 100_000)

        // Feb payment: balance = 100k - 50k = 50k
        XCTAssertEqual(entries[1].debit, 0)
        XCTAssertEqual(entries[1].credit, 50_000)
        XCTAssertEqual(entries[1].runningBalance, 50_000)

        // Mar sale: balance = 50k + 80k = 130k
        XCTAssertEqual(entries[2].debit, 80_000)
        XCTAssertEqual(entries[2].credit, 0)
        XCTAssertEqual(entries[2].runningBalance, 130_000)

        // Apr payment: balance = 130k - 130k = 0
        XCTAssertEqual(entries[3].debit, 0)
        XCTAssertEqual(entries[3].credit, 130_000)
        XCTAssertEqual(entries[3].runningBalance, 0)
    }

    // MARK: - 11. Tax Category Preserved

    func testARBook_TaxCategory_Preserved() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 108_000, date: date(2025, 7, 1),
            categoryId: "cat-sales", memo: "軽減税率掛売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            taxAmount: 8_000,
            taxCategory: .reducedRate,
            counterparty: "上野商店"
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 7, 1),
            endDate: date(2025, 7, 31)
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].taxCategory, .reducedRate)
        XCTAssertEqual(entries[0].counterparty, "上野商店")
    }

    // MARK: - 12. Counter Account ID

    func testARBook_CounterAccountId() {
        // Dr acct-ar / Cr acct-sales → counterAccountId = "acct-sales"
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: date(2025, 8, 1),
            categoryId: "cat-sales", memo: "掛売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 8, 1),
            endDate: date(2025, 8, 31)
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].counterAccountId, "acct-sales")
    }

    // MARK: - 13. Counterparties with Date Range

    func testARBook_GetCounterparties_WithDateRange() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        // Q1 counterparty
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 50_000, date: date(2025, 2, 15),
            categoryId: "cat-sales", memo: "Q1売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        // Q2 counterparty (different)
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 60_000, date: date(2025, 5, 15),
            categoryId: "cat-sales", memo: "Q2売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "田中商店"
        )

        // Only Q1 counterparties
        let q1Counterparties = dataStore.getSubLedgerCounterparties(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 3, 31)
        )

        XCTAssertEqual(q1Counterparties, ["上野商店"])

        // Full year counterparties
        let allCounterparties = dataStore.getSubLedgerCounterparties(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )

        XCTAssertEqual(allCounterparties, ["上野商店", "田中商店"])
    }

    // MARK: - 14. Running Balance resets per counterparty within unfiltered view

    func testARBook_UnfilteredView_RunningBalancePerCounterparty() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        // Interleaved transactions from different counterparties
        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 100_000, date: date(2025, 9, 1),
            categoryId: "cat-sales", memo: "上野商店売上1",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 200_000, date: date(2025, 9, 2),
            categoryId: "cat-sales", memo: "田中商店売上1",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "田中商店"
        )

        let _ = mutations(dataStore).addTransaction(
            type: .income, amount: 50_000, date: date(2025, 9, 3),
            categoryId: "cat-sales", memo: "上野商店売上2",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "上野商店"
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook,
            startDate: date(2025, 9, 1),
            endDate: date(2025, 9, 30)
        )

        XCTAssertEqual(entries.count, 3)

        // 上野商店: 100k → balance 100k
        XCTAssertEqual(entries[0].counterparty, "上野商店")
        XCTAssertEqual(entries[0].runningBalance, 100_000)

        // 田中商店: 200k → balance 200k (independent from 上野商店)
        XCTAssertEqual(entries[1].counterparty, "田中商店")
        XCTAssertEqual(entries[1].runningBalance, 200_000)

        // 上野商店: +50k → balance 150k (continues from 上野商店's 100k, not 200k)
        XCTAssertEqual(entries[2].counterparty, "上野商店")
        XCTAssertEqual(entries[2].runningBalance, 150_000)
    }
}
