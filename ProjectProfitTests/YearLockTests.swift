import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class YearLockTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self,
            PPAccount.self, PPJournalEntry.self, PPJournalLine.self, PPAccountingProfile.self,
            PPUserRule.self,
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

    private func setupProfileAndLockYear(_ year: Int) {
        // ブートストラップでプロファイルが作成されるが、確実にプロファイルがある状態にする
        if dataStore.accountingProfile == nil {
            let profile = PPAccountingProfile(fiscalYear: year)
            context.insert(profile)
            try? context.save()
            dataStore.loadData()
        }
        dataStore.lockFiscalYear(year)
    }

    private func makeProject() -> PPProject {
        dataStore.addProject(name: "TestProject", description: "desc")
    }

    // MARK: - Lock/Unlock

    func testLockAndUnlockYear() {
        setupProfileAndLockYear(2025)

        XCTAssertTrue(dataStore.accountingProfile?.isYearLocked(2025) == true)

        dataStore.unlockFiscalYear(2025)
        XCTAssertFalse(dataStore.accountingProfile?.isYearLocked(2025) == true)
    }

    func testMultipleYearsLock() {
        setupProfileAndLockYear(2024)
        dataStore.lockFiscalYear(2025)

        XCTAssertTrue(dataStore.accountingProfile?.isYearLocked(2024) == true)
        XCTAssertTrue(dataStore.accountingProfile?.isYearLocked(2025) == true)
        XCTAssertFalse(dataStore.accountingProfile?.isYearLocked(2026) == true)
    }

    // MARK: - Add Transaction Guard

    func testAddTransaction_blockedByYearLock() {
        let _ = makeProject()
        setupProfileAndLockYear(2025)

        let lockedDate = dateFrom(year: 2025, month: 6, day: 15)
        let countBefore = dataStore.transactions.count

        dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: lockedDate,
            categoryId: "cat-expense",
            memo: "test",
            allocations: []
        )

        // トランザクションは挿入されないはず（ガードで返されたダミーは未挿入）
        // lastErrorに年度ロックエラーが設定されること
        XCTAssertNotNil(dataStore.lastError)
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("Expected yearLocked error")
        }
    }

    func testAddTransaction_allowedForUnlockedYear() {
        let _ = makeProject()
        setupProfileAndLockYear(2024)

        let unlockedDate = dateFrom(year: 2025, month: 6, day: 15)
        let countBefore = dataStore.transactions.count

        dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: unlockedDate,
            categoryId: "cat-expense",
            memo: "test",
            allocations: []
        )

        XCTAssertEqual(dataStore.transactions.count, countBefore + 1)
    }

    // MARK: - Update Transaction Guard

    func testUpdateTransaction_blockedByYearLock() {
        let _ = makeProject()
        let date2025 = dateFrom(year: 2025, month: 3, day: 1)
        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: date2025,
            categoryId: "cat-expense",
            memo: "original",
            allocations: []
        )

        setupProfileAndLockYear(2025)

        dataStore.updateTransaction(id: tx.id, memo: "updated")

        // memoが変更されていないこと
        let found = dataStore.transactions.first { $0.id == tx.id }
        XCTAssertEqual(found?.memo, "original")
    }

    // MARK: - Delete Transaction Guard

    func testDeleteTransaction_blockedByYearLock() {
        let _ = makeProject()
        let date2025 = dateFrom(year: 2025, month: 3, day: 1)
        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: date2025,
            categoryId: "cat-expense",
            memo: "test",
            allocations: []
        )

        setupProfileAndLockYear(2025)
        let countBefore = dataStore.transactions.count

        dataStore.deleteTransaction(id: tx.id)

        XCTAssertEqual(dataStore.transactions.count, countBefore, "Transaction should not be deleted in locked year")
    }

    // MARK: - Manual Journal Entry Guard

    func testAddManualJournalEntry_blockedByYearLock() {
        setupProfileAndLockYear(2025)

        let lockedDate = dateFrom(year: 2025, month: 6, day: 15)
        let entry = dataStore.addManualJournalEntry(
            date: lockedDate,
            memo: "manual entry",
            lines: [
                (accountId: "acct-cash", debit: 1000, credit: 0, memo: "test"),
                (accountId: "acct-sales", debit: 0, credit: 1000, memo: "test")
            ]
        )

        XCTAssertNil(entry, "Manual journal entry should be blocked for locked year")
    }

    func testDeleteManualJournalEntry_blockedByYearLock() {
        // まず未ロック状態で仕訳追加
        let date2025 = dateFrom(year: 2025, month: 3, day: 1)
        if dataStore.accountingProfile == nil {
            let profile = PPAccountingProfile(fiscalYear: 2025)
            context.insert(profile)
            try? context.save()
            dataStore.loadData()
        }

        let entry = dataStore.addManualJournalEntry(
            date: date2025,
            memo: "test entry",
            lines: [
                (accountId: "acct-cash", debit: 1000, credit: 0, memo: "test"),
                (accountId: "acct-sales", debit: 0, credit: 1000, memo: "test")
            ]
        )
        guard let entryId = entry?.id else {
            XCTFail("Should have created journal entry")
            return
        }

        let countBefore = dataStore.journalEntries.count

        // ロックしてから削除試行
        dataStore.lockFiscalYear(2025)
        dataStore.deleteManualJournalEntry(id: entryId)

        XCTAssertEqual(dataStore.journalEntries.count, countBefore, "Journal entry should not be deleted in locked year")
    }

    // MARK: - Helpers

    private func dateFrom(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps)!
    }
}
