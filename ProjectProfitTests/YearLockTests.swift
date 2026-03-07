import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class YearLockTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!
    var previousFiscalStartMonth: Int!

    override func setUp() {
        super.setUp()
        previousFiscalStartMonth = UserDefaults.standard.integer(forKey: FiscalYearSettings.userDefaultsKey)
        UserDefaults.standard.set(1, forKey: FiscalYearSettings.userDefaultsKey)
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        context = nil
        container = nil
        if previousFiscalStartMonth == 0 {
            UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        } else {
            UserDefaults.standard.set(previousFiscalStartMonth, forKey: FiscalYearSettings.userDefaultsKey)
        }
        previousFiscalStartMonth = nil
        super.tearDown()
    }

    private func setupProfileAndLockYear(_ year: Int) {
        // ブートストラップで canonical プロファイルが作成される前提。
        // loadData() により businessProfile が確実にセットされた状態で lockFiscalYear を呼ぶ。
        dataStore.loadData()
        dataStore.lockFiscalYear(year)
    }

    private func makeProject() -> PPProject {
        dataStore.addProject(name: "TestProject", description: "desc")
    }

    // MARK: - Lock/Unlock

    func testLockAndUnlockYear() {
        setupProfileAndLockYear(2025)

        XCTAssertTrue(dataStore.isYearLocked(2025))
        XCTAssertEqual(persistedTaxYearProfile(2025)?.yearLockStateRaw, YearLockState.finalLock.rawValue)

        dataStore.unlockFiscalYear(2025)
        XCTAssertFalse(dataStore.isYearLocked(2025))
        XCTAssertEqual(persistedTaxYearProfile(2025)?.yearLockStateRaw, YearLockState.open.rawValue)
    }

    func testMultipleYearsLock() {
        setupProfileAndLockYear(2024)
        dataStore.lockFiscalYear(2025)

        XCTAssertTrue(dataStore.isYearLocked(2024))
        XCTAssertTrue(dataStore.isYearLocked(2025))
        XCTAssertFalse(dataStore.isYearLocked(2026))
        XCTAssertEqual(persistedTaxYearProfile(2024)?.yearLockStateRaw, YearLockState.finalLock.rawValue)
        XCTAssertEqual(persistedTaxYearProfile(2025)?.yearLockStateRaw, YearLockState.finalLock.rawValue)
    }

    func testUnlockYearUsesCanonicalState() {
        dataStore.lockFiscalYear(2025)
        XCTAssertTrue(dataStore.isYearLocked(2025))

        dataStore.unlockFiscalYear(2025)

        XCTAssertFalse(dataStore.isYearLocked(2025))
        XCTAssertEqual(persistedTaxYearProfile(2025)?.yearLockStateRaw, YearLockState.open.rawValue)
    }

    func testTransitionFiscalYearStateFollowsAllowedSequence() {
        XCTAssertTrue(dataStore.transitionFiscalYearState(.softClose, for: 2025))
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .softClose)

        XCTAssertTrue(dataStore.transitionFiscalYearState(.taxClose, for: 2025))
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .taxClose)

        XCTAssertTrue(dataStore.transitionFiscalYearState(.filed, for: 2025))
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .filed)

        XCTAssertTrue(dataStore.transitionFiscalYearState(.finalLock, for: 2025))
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .finalLock)
    }

    func testTransitionFiscalYearStateRejectsInvalidJump() {
        XCTAssertFalse(dataStore.transitionFiscalYearState(.finalLock, for: 2025))
        XCTAssertEqual(dataStore.yearLockState(for: 2025), .open)
        guard case .saveFailed(let underlying)? = dataStore.lastError else {
            return XCTFail("Expected saveFailed error, got \(String(describing: dataStore.lastError))")
        }
        XCTAssertEqual(
            underlying as? TaxYearStateUseCaseError,
            .validationFailed("年度状態を未締めから最終確定へ変更できません")
        )
    }

    func testIsYearLocked_usesCanonicalProfile() {
        dataStore.currentTaxYearProfile = TaxYearProfile(
            businessId: UUID(),
            taxYear: 2025,
            yearLockState: .finalLock
        )

        XCTAssertTrue(dataStore.isYearLocked(2025))
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("Expected canonical year lock to set yearLocked error")
        }
    }

    // MARK: - Add Transaction Guard

    func testAddTransaction_blockedByYearLock() {
        let _ = makeProject()
        setupProfileAndLockYear(2025)

        let lockedDate = dateFrom(year: 2025, month: 6, day: 15)

        let result = dataStore.addTransactionResult(
            type: .expense,
            amount: 1000,
            date: lockedDate,
            categoryId: "cat-expense",
            memo: "test",
            allocations: []
        )

        if case .success = result {
            XCTFail("locked year should return failure")
        }

        // トランザクションは挿入されず、lastErrorに年度ロックエラーが設定されること
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

        XCTAssertFalse(dataStore.isYearLocked(2025), "2025年は未ロックの前提: \(yearLockDiagnostics(for: 2025))")

        let result = dataStore.addTransactionResult(
            type: .expense,
            amount: 1000,
            date: unlockedDate,
            categoryId: "cat-expense",
            memo: "test",
            allocations: []
        )

        if case .failure(let error) = result {
            XCTFail("unlocked year should allow addTransactionResult: \(error.localizedDescription)")
        }
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

        let updated = dataStore.updateTransaction(id: tx.id, memo: "updated")

        // memoが変更されていないこと
        let found = dataStore.transactions.first { $0.id == tx.id }
        XCTAssertFalse(updated)
        XCTAssertEqual(found?.memo, "original")
        guard case .yearLocked(let year)? = dataStore.lastError else {
            return XCTFail("Expected yearLocked error, got \(String(describing: dataStore.lastError))")
        }
        XCTAssertEqual(year, 2025)
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
        dataStore.loadData()

        XCTAssertFalse(dataStore.isYearLocked(2025), "2025年は仕訳追加前に未ロックの前提: \(yearLockDiagnostics(for: 2025))")

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

    private func persistedTaxYearProfile(_ year: Int) -> TaxYearProfileEntity? {
        guard let businessId = dataStore.businessProfile?.id else {
            return nil
        }
        let descriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == year
            }
        )
        return try? context.fetch(descriptor).first
    }

    private func yearLockDiagnostics(for year: Int) -> String {
        let businessId = dataStore.businessProfile?.id.uuidString ?? "nil"
        let currentTaxYear = dataStore.currentTaxYearProfile?.taxYear.description ?? "nil"
        let currentLockState = dataStore.currentTaxYearProfile?.yearLockState.rawValue ?? "nil"

        let descriptor = FetchDescriptor<TaxYearProfileEntity>()
        let persistedProfiles = (try? context.fetch(descriptor)) ?? []
        let allTaxYears = persistedProfiles
            .map { "\($0.taxYear):\($0.yearLockStateRaw)" }
            .sorted()
            .joined(separator: ",")
        let persistedState = persistedTaxYearProfile(year)?.yearLockStateRaw ?? "nil"

        return "businessId=\(businessId) currentTaxYear=\(currentTaxYear) currentLockState=\(currentLockState) persistedState=\(persistedState) allTaxYearProfiles=[\(allTaxYears)]"
    }
}
