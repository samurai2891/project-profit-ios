import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class APBookTests: XCTestCase {
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

    // MARK: - Helper

    /// Create a project for allocation purposes.
    @discardableResult
    private func makeProject(name: String = "テストPJ") -> PPProject {
        mutations(dataStore).addProject(name: name, description: "")
    }

    /// Record a credit purchase (掛仕入): Dr 仕入高 / Cr 買掛金
    /// Uses addTransaction with paymentAccountId = acct-ap so counterparty propagates.
    @discardableResult
    private func addCreditPurchase(
        amount: Int,
        date: Date,
        counterparty: String? = nil,
        memo: String = "掛仕入",
        project: PPProject
    ) -> PPTransaction {
        mutations(dataStore).addTransaction(
            type: .expense,
            amount: amount,
            date: date,
            categoryId: "cat-other-expense",
            memo: memo,
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-ap",
            counterparty: counterparty
        )
    }

    /// Record a payment on AP (買掛金支払): Dr 買掛金 / Cr 現金
    /// Uses transfer type so counterparty propagates through the journal entry.
    @discardableResult
    private func addAPPayment(
        amount: Int,
        date: Date,
        counterparty: String? = nil,
        memo: String = "買掛金支払"
    ) -> PPTransaction {
        mutations(dataStore).addTransaction(
            type: .transfer,
            amount: amount,
            date: date,
            categoryId: "",
            memo: memo,
            allocations: [],
            paymentAccountId: "acct-cash",
            transferToAccountId: "acct-ap",
            counterparty: counterparty
        )
    }

    // MARK: - 1. Credit Purchase → AP Credit Entry (仕入金額)

    func testAPBook_CreditPurchase_CreditEntry() {
        let project = makeProject()
        addCreditPurchase(
            amount: 80000,
            date: date(2025, 1, 10),
            counterparty: "田町商店",
            project: project
        )

        let entries = dataStore.getSubLedgerEntries(type: .accountsPayableBook)
        XCTAssertFalse(entries.isEmpty, "AP book should have entries after a credit purchase")

        let apEntries = entries.filter { $0.accountId == AccountingConstants.accountsPayableAccountId }
        XCTAssertEqual(apEntries.count, 1)

        let entry = apEntries[0]
        // AP is a liability with credit normal balance.
        // Credit purchase increases AP → credit column = 仕入金額
        XCTAssertEqual(entry.credit, 80000, "仕入金額 (credit on AP) should be 80000")
        XCTAssertEqual(entry.debit, 0, "支払金額 (debit on AP) should be 0")
        XCTAssertEqual(entry.counterparty, "田町商店")
    }

    // MARK: - 2. Payment Made → AP Debit Entry (支払金額)

    func testAPBook_PaymentMade_DebitEntry() {
        let project = makeProject()
        // First create a credit purchase so AP has a balance
        addCreditPurchase(
            amount: 80000,
            date: date(2025, 1, 10),
            counterparty: "田町商店",
            project: project
        )
        // Then pay it off
        addAPPayment(
            amount: 80000,
            date: date(2025, 1, 20),
            counterparty: "田町商店"
        )

        let entries = dataStore.getSubLedgerEntries(type: .accountsPayableBook)
        let apEntries = entries.filter { $0.accountId == AccountingConstants.accountsPayableAccountId }
        XCTAssertEqual(apEntries.count, 2)

        // The payment entry (second chronologically)
        let paymentEntry = apEntries[1]
        // Payment decreases AP → debit column = 支払金額
        XCTAssertEqual(paymentEntry.debit, 80000, "支払金額 (debit on AP) should be 80000")
        XCTAssertEqual(paymentEntry.credit, 0, "仕入金額 (credit on AP) should be 0")
        XCTAssertEqual(paymentEntry.counterparty, "田町商店")
    }

    // MARK: - 3. Per-Counterparty Running Balance

    func testAPBook_PerCounterpartyRunningBalance() {
        let project = makeProject()

        // 田町商店: purchase 80k, then partial payment 50k
        addCreditPurchase(
            amount: 80000,
            date: date(2025, 1, 10),
            counterparty: "田町商店",
            project: project
        )
        addAPPayment(
            amount: 50000,
            date: date(2025, 1, 20),
            counterparty: "田町商店"
        )

        // 鈴木商事: purchase 60k
        addCreditPurchase(
            amount: 60000,
            date: date(2025, 1, 15),
            counterparty: "鈴木商事",
            project: project
        )

        // Filter for 田町商店
        let tamachi = dataStore.getSubLedgerEntries(
            type: .accountsPayableBook,
            counterpartyFilter: "田町商店"
        )
        XCTAssertEqual(tamachi.count, 2)
        // After purchase: balance = 80k
        XCTAssertEqual(tamachi[0].runningBalance, 80000)
        // After partial payment: balance = 80k - 50k = 30k
        XCTAssertEqual(tamachi[1].runningBalance, 30000)

        // Filter for 鈴木商事
        let suzuki = dataStore.getSubLedgerEntries(
            type: .accountsPayableBook,
            counterpartyFilter: "鈴木商事"
        )
        XCTAssertEqual(suzuki.count, 1)
        // After purchase: balance = 60k (independent of 田町商店)
        XCTAssertEqual(suzuki[0].runningBalance, 60000)
    }

    // MARK: - 4. Counterparty Filter

    func testAPBook_CounterpartyFilter() {
        let project = makeProject()

        addCreditPurchase(amount: 50000, date: date(2025, 2, 1), counterparty: "田町商店", project: project)
        addCreditPurchase(amount: 30000, date: date(2025, 2, 5), counterparty: "鈴木商事", project: project)
        addCreditPurchase(amount: 20000, date: date(2025, 2, 10), counterparty: "田町商店", project: project)

        let filtered = dataStore.getSubLedgerEntries(
            type: .accountsPayableBook,
            counterpartyFilter: "田町商店"
        )

        XCTAssertEqual(filtered.count, 2, "Only 田町商店 entries should appear")
        XCTAssertTrue(filtered.allSatisfy { $0.counterparty == "田町商店" })
    }

    // MARK: - 5. Empty Counterparty Filter

    func testAPBook_EmptyCounterpartyFilter() {
        let project = makeProject()

        // Entry with counterparty
        addCreditPurchase(amount: 50000, date: date(2025, 3, 1), counterparty: "田町商店", project: project)

        // Entry without counterparty (manual journal entry has no counterparty)
        _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 3, 5),
            memo: "取引先不明の仕入",
            lines: [
                (accountId: "acct-purchases", debit: 25000, credit: 0, memo: ""),
                (accountId: "acct-ap", debit: 0, credit: 25000, memo: ""),
            ]
        )

        // Filter for empty counterparty
        let noCounterparty = dataStore.getSubLedgerEntries(
            type: .accountsPayableBook,
            counterpartyFilter: ""
        )

        // Only the manual journal entry (nil counterparty) should appear
        XCTAssertEqual(noCounterparty.count, 1)
        let entry = noCounterparty[0]
        XCTAssertTrue(entry.counterparty == nil || entry.counterparty?.isEmpty == true)
        XCTAssertEqual(entry.credit, 25000)
    }

    // MARK: - 6. Get Counterparties

    func testAPBook_GetCounterparties() {
        let project = makeProject()

        addCreditPurchase(amount: 10000, date: date(2025, 4, 1), counterparty: "鈴木商事", project: project)
        addCreditPurchase(amount: 20000, date: date(2025, 4, 5), counterparty: "田町商店", project: project)
        addCreditPurchase(amount: 15000, date: date(2025, 4, 10), counterparty: "鈴木商事", project: project)

        let counterparties = dataStore.getSubLedgerCounterparties(type: .accountsPayableBook)

        // Should be sorted and unique
        XCTAssertEqual(counterparties, ["田町商店", "鈴木商事"])
    }

    // MARK: - 7. All Counterparties with Independent Balances

    func testAPBook_AllCounterparties_IndependentBalances() {
        let project = makeProject()

        // 田町商店: purchase 100k
        addCreditPurchase(amount: 100000, date: date(2025, 5, 1), counterparty: "田町商店", project: project)
        // 鈴木商事: purchase 60k
        addCreditPurchase(amount: 60000, date: date(2025, 5, 5), counterparty: "鈴木商事", project: project)
        // 田町商店: payment 40k
        addAPPayment(amount: 40000, date: date(2025, 5, 10), counterparty: "田町商店")

        // Without counterparty filter, all entries shown but balances are per-counterparty
        let allEntries = dataStore.getSubLedgerEntries(type: .accountsPayableBook)
        let apEntries = allEntries.filter { $0.accountId == AccountingConstants.accountsPayableAccountId }
        XCTAssertEqual(apEntries.count, 3)

        // Entry 1: 田町商店 purchase 100k → balance 100k
        XCTAssertEqual(apEntries[0].counterparty, "田町商店")
        XCTAssertEqual(apEntries[0].runningBalance, 100000)

        // Entry 2: 鈴木商事 purchase 60k → balance 60k (independent)
        XCTAssertEqual(apEntries[1].counterparty, "鈴木商事")
        XCTAssertEqual(apEntries[1].runningBalance, 60000)

        // Entry 3: 田町商店 payment 40k → balance 60k (100k - 40k)
        XCTAssertEqual(apEntries[2].counterparty, "田町商店")
        XCTAssertEqual(apEntries[2].runningBalance, 60000)
    }

    // MARK: - 8. Date Filter

    func testAPBook_DateFilter() {
        let project = makeProject()

        // Before range
        addCreditPurchase(amount: 10000, date: date(2025, 1, 15), counterparty: "田町商店", project: project)
        // In range
        addCreditPurchase(amount: 20000, date: date(2025, 2, 10), counterparty: "田町商店", project: project)
        addCreditPurchase(amount: 30000, date: date(2025, 2, 20), counterparty: "田町商店", project: project)
        // After range
        addCreditPurchase(amount: 40000, date: date(2025, 3, 5), counterparty: "田町商店", project: project)

        let entries = dataStore.getSubLedgerEntries(
            type: .accountsPayableBook,
            startDate: date(2025, 2, 1),
            endDate: date(2025, 2, 28)
        )

        XCTAssertEqual(entries.count, 2, "Only entries within Feb 2025 should appear")
        // Running balance starts fresh within the filtered range
        XCTAssertEqual(entries[0].credit, 20000)
        XCTAssertEqual(entries[1].credit, 30000)
    }

    // MARK: - 9. Empty AP Book

    func testAPBook_Empty() {
        // No transactions at all
        let entries = dataStore.getSubLedgerEntries(type: .accountsPayableBook)
        XCTAssertTrue(entries.isEmpty, "AP book should be empty when no AP transactions exist")
    }

    // MARK: - 10. Annual Purchase-Payment Cycle

    func testAPBook_AnnualPurchasePaymentCycle() {
        let project = makeProject()

        // Jan: purchase 200k from 田町商店
        addCreditPurchase(
            amount: 200000,
            date: date(2025, 1, 15),
            counterparty: "田町商店",
            memo: "1月仕入",
            project: project
        )

        // Feb: partial payment 100k
        addAPPayment(
            amount: 100000,
            date: date(2025, 2, 10),
            counterparty: "田町商店",
            memo: "2月支払"
        )

        // Mar: additional purchase 150k
        addCreditPurchase(
            amount: 150000,
            date: date(2025, 3, 15),
            counterparty: "田町商店",
            memo: "3月仕入",
            project: project
        )

        // Jun: full payment of remaining 250k (200k - 100k + 150k)
        addAPPayment(
            amount: 250000,
            date: date(2025, 6, 10),
            counterparty: "田町商店",
            memo: "6月全額支払"
        )

        let entries = dataStore.getSubLedgerEntries(
            type: .accountsPayableBook,
            counterpartyFilter: "田町商店"
        )
        XCTAssertEqual(entries.count, 4)

        // Jan purchase: balance = 200k
        XCTAssertEqual(entries[0].credit, 200000)
        XCTAssertEqual(entries[0].debit, 0)
        XCTAssertEqual(entries[0].runningBalance, 200000)

        // Feb payment: balance = 200k - 100k = 100k
        XCTAssertEqual(entries[1].debit, 100000)
        XCTAssertEqual(entries[1].credit, 0)
        XCTAssertEqual(entries[1].runningBalance, 100000)

        // Mar purchase: balance = 100k + 150k = 250k
        XCTAssertEqual(entries[2].credit, 150000)
        XCTAssertEqual(entries[2].debit, 0)
        XCTAssertEqual(entries[2].runningBalance, 250000)

        // Jun full payment: balance = 250k - 250k = 0
        XCTAssertEqual(entries[3].debit, 250000)
        XCTAssertEqual(entries[3].credit, 0)
        XCTAssertEqual(entries[3].runningBalance, 0, "Final balance should be 0 after full payment")
    }

    // MARK: - 11. Counter Account ID

    func testAPBook_CounterAccountId() {
        let project = makeProject()

        // Dr 仕入高(acct-purchases equivalent via category mapping) / Cr 買掛金
        // addTransaction with paymentAccountId: "acct-ap" generates:
        //   Dr expense-account / Cr acct-ap
        // The counter account for the AP line should be the expense account.
        addCreditPurchase(
            amount: 50000,
            date: date(2025, 7, 1),
            counterparty: "田町商店",
            project: project
        )

        let entries = dataStore.getSubLedgerEntries(type: .accountsPayableBook)
        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        // The counter account should be the expense account (from category mapping)
        XCTAssertNotNil(entry.counterAccountId, "Counter account should be identified from the sibling journal line")
        // The expense category "cat-other-expense" maps to "acct-misc" (雑費)
        XCTAssertEqual(entry.counterAccountId, AccountingConstants.miscExpenseAccountId)
    }

    // MARK: - 12. Manual Journal Entry Without Counterparty

    func testAPBook_ManualJournalEntry_NoCounterparty() {
        // Manual journal entries don't have a linked PPTransaction,
        // so counterparty will be nil.
        _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 8, 1),
            memo: "手動仕訳テスト",
            lines: [
                (accountId: "acct-purchases", debit: 45000, credit: 0, memo: ""),
                (accountId: "acct-ap", debit: 0, credit: 45000, memo: ""),
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .accountsPayableBook)
        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertNil(entry.counterparty, "Manual journal entries should have nil counterparty")
        XCTAssertEqual(entry.credit, 45000)
        XCTAssertEqual(entry.debit, 0)
        XCTAssertEqual(entry.runningBalance, 45000)
    }

    // MARK: - 13. Mixed Counterparties Date-Sorted

    func testAPBook_MixedCounterparties_DateSorted() {
        let project = makeProject()

        // Interleave transactions from different counterparties
        addCreditPurchase(amount: 10000, date: date(2025, 9, 1), counterparty: "A商店", project: project)
        addCreditPurchase(amount: 20000, date: date(2025, 9, 2), counterparty: "B商店", project: project)
        addCreditPurchase(amount: 30000, date: date(2025, 9, 3), counterparty: "A商店", project: project)

        let entries = dataStore.getSubLedgerEntries(type: .accountsPayableBook)
        XCTAssertEqual(entries.count, 3)

        // Entries should be date-sorted
        XCTAssertTrue(entries[0].date <= entries[1].date)
        XCTAssertTrue(entries[1].date <= entries[2].date)

        // Per-counterparty running balances
        // Entry 0: A商店 10k → A balance = 10k
        XCTAssertEqual(entries[0].counterparty, "A商店")
        XCTAssertEqual(entries[0].runningBalance, 10000)

        // Entry 1: B商店 20k → B balance = 20k (independent)
        XCTAssertEqual(entries[1].counterparty, "B商店")
        XCTAssertEqual(entries[1].runningBalance, 20000)

        // Entry 2: A商店 30k → A balance = 10k + 30k = 40k
        XCTAssertEqual(entries[2].counterparty, "A商店")
        XCTAssertEqual(entries[2].runningBalance, 40000)
    }
}
