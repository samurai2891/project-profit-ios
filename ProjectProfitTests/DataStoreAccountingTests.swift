import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class DataStoreAccountingTests: XCTestCase {
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

    // MARK: - Manual Journal Entry CRUD

    func testAddManualJournalEntry() {
        let entry = dataStore.addManualJournalEntry(
            date: Date(),
            memo: "決算整理仕訳",
            lines: [
                (accountId: "acct-rent", debit: 10000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 10000, memo: ""),
            ]
        )

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.entryType, .manual)
        XCTAssertEqual(entry?.memo, "決算整理仕訳")
        XCTAssertTrue(entry?.isPosted ?? false, "Balanced entry should be posted")
    }

    func testAddManualJournalEntryUnbalanced() {
        let entry = dataStore.addManualJournalEntry(
            date: Date(),
            memo: "不均衡仕訳",
            lines: [
                (accountId: "acct-rent", debit: 10000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 5000, memo: ""),
            ]
        )

        XCTAssertNotNil(entry)
        XCTAssertFalse(entry?.isPosted ?? true, "Unbalanced entry should NOT be posted")
    }

    func testAddManualJournalEntryEmptyLines() {
        let entry = dataStore.addManualJournalEntry(
            date: Date(),
            memo: "空",
            lines: []
        )

        XCTAssertNil(entry, "Empty lines should return nil")
    }

    func testDeleteManualJournalEntry() {
        let entry = dataStore.addManualJournalEntry(
            date: Date(),
            memo: "削除テスト",
            lines: [
                (accountId: "acct-rent", debit: 5000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 5000, memo: ""),
            ]
        )
        let entryId = entry!.id

        XCTAssertTrue(dataStore.journalEntries.contains { $0.id == entryId })

        dataStore.deleteManualJournalEntry(id: entryId)

        XCTAssertFalse(dataStore.journalEntries.contains { $0.id == entryId })
        XCTAssertTrue(dataStore.journalLines.filter { $0.entryId == entryId }.isEmpty)
    }

    func testDeleteAutoJournalEntryIsIgnored() {
        // Auto entries should not be deletable via manual delete
        let project = dataStore.addProject(name: "P1", description: "")
        let tx = dataStore.addTransaction(
            type: .expense, amount: 1000, date: Date(),
            categoryId: "cat-tools", memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        guard let journalId = tx.journalEntryId else {
            XCTFail("Transaction should have journal entry")
            return
        }

        let countBefore = dataStore.journalEntries.count
        dataStore.deleteManualJournalEntry(id: journalId)
        XCTAssertEqual(dataStore.journalEntries.count, countBefore, "Auto entry should not be deleted")
    }

    // MARK: - Account Balance

    func testGetAccountBalance() {
        let project = dataStore.addProject(name: "P1", description: "")
        _ = dataStore.addTransaction(
            type: .expense, amount: 3000, date: Date(),
            categoryId: "cat-tools", memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        // 経費仕訳: 借方=acct-supplies(3000), 貸方=acct-cash(3000)
        // acct-cash は資産=借方正常 → 残高 = 0-3000 = -3000
        let cashBalance = dataStore.getAccountBalance(accountId: "acct-cash")
        XCTAssertEqual(cashBalance.credit, 3000)
        XCTAssertEqual(cashBalance.balance, -3000)
    }

    func testGetAccountBalanceWithMultipleTransactions() {
        let project = dataStore.addProject(name: "P1", description: "")

        _ = dataStore.addTransaction(
            type: .income, amount: 50000, date: Date(),
            categoryId: "cat-project-income", memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        _ = dataStore.addTransaction(
            type: .expense, amount: 10000, date: Date(),
            categoryId: "cat-tools", memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        // 収入: 借方=acct-cash(50000)
        // 経費: 貸方=acct-cash(10000)
        // 残高 = 50000 - 10000 = 40000 (debit normal)
        let cashBalance = dataStore.getAccountBalance(accountId: "acct-cash")
        XCTAssertEqual(cashBalance.debit, 50000)
        XCTAssertEqual(cashBalance.credit, 10000)
        XCTAssertEqual(cashBalance.balance, 40000)
    }

    // MARK: - Ledger Entries

    func testGetLedgerEntries() {
        let project = dataStore.addProject(name: "P1", description: "")

        _ = dataStore.addTransaction(
            type: .income, amount: 20000, date: Date(),
            categoryId: "cat-project-income", memo: "売上1",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        _ = dataStore.addTransaction(
            type: .expense, amount: 5000, date: Date(),
            categoryId: "cat-tools", memo: "ツール代",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertEqual(entries.count, 2)

        // 最初の取引で残高が正（入金）
        if let first = entries.first {
            XCTAssertEqual(first.debit, 20000)
            XCTAssertEqual(first.runningBalance, 20000)
        }

        // 2番目の取引で残高が減少（出金）
        if entries.count >= 2 {
            XCTAssertEqual(entries[1].credit, 5000)
            XCTAssertEqual(entries[1].runningBalance, 15000)
        }
    }

    func testGetLedgerEntriesEmpty() {
        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertTrue(entries.isEmpty)
    }
}
