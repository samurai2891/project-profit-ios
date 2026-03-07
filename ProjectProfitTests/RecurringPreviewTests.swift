import XCTest
import SwiftData
@testable import ProjectProfit

/// previewRecurringTransactions のロジックをテストする
@MainActor
final class RecurringPreviewTests: XCTestCase {
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

    /// 今日の日付コンポーネント
    private var todayComponents: DateComponents {
        calendar.dateComponents([.year, .month, .day], from: todayDate())
    }

    /// 今日以前に確実に来る dayOfMonth (1日)
    private var pastDayOfMonth: Int { 1 }

    /// DataStore.addRecurring は内部で processRecurringTransactions を呼ぶため、
    /// lastGeneratedDate が設定されてしまう。preview のテストには、
    /// 直接モデルを挿入して loadData で再読み込みする方式を使う。
    private func insertRecurringDirectly(
        name: String,
        type: TransactionType,
        amount: Int,
        categoryId: String,
        projectId: UUID,
        dayOfMonth: Int,
        isActive: Bool = true,
        endDate: Date? = nil,
        skipDates: [Date] = [],
        lastGeneratedDate: Date? = nil
    ) -> PPRecurringTransaction {
        let allocations = [Allocation(projectId: projectId, ratio: 100, amount: amount)]
        let recurring = PPRecurringTransaction(
            name: name,
            type: type,
            amount: amount,
            categoryId: categoryId,
            memo: "[定期] \(name)",
            allocationMode: .manual,
            allocations: allocations,
            frequency: .monthly,
            dayOfMonth: dayOfMonth,
            isActive: isActive,
            endDate: endDate,
            lastGeneratedDate: lastGeneratedDate,
            skipDates: skipDates
        )
        context.insert(recurring)
        try? context.save()
        dataStore.loadData()
        return recurring
    }

    // MARK: - Tests

    /// アクティブで期限内の定期取引に対してプレビューが生成される
    func testPreviewReturnsItemsForDueRecurring() {
        let project = makeProject()
        let day = pastDayOfMonth
        let todayComps = todayComponents

        guard todayComps.day! >= day else { return }

        let recurring = insertRecurringDirectly(
            name: "月額サーバー代",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            projectId: project.id,
            dayOfMonth: day
        )

        let preview = dataStore.previewRecurringTransactions()

        let matchingItems = preview.filter { $0.recurringId == recurring.id }
        XCTAssertFalse(matchingItems.isEmpty, "期限内のアクティブな定期取引にはプレビューが生成されるべき")
        XCTAssertEqual(matchingItems.first?.recurringName, "月額サーバー代")
        XCTAssertEqual(matchingItems.first?.amount, 5000)
    }

    /// 非アクティブな定期取引はプレビューに含まれない
    func testPreviewSkipsInactiveRecurring() {
        let project = makeProject()
        let day = pastDayOfMonth

        let recurring = insertRecurringDirectly(
            name: "停止済み経費",
            type: .expense,
            amount: 3000,
            categoryId: "cat-tools",
            projectId: project.id,
            dayOfMonth: day,
            isActive: false
        )

        let preview = dataStore.previewRecurringTransactions()

        let matchingItems = preview.filter { $0.recurringId == recurring.id }
        XCTAssertTrue(matchingItems.isEmpty, "非アクティブな定期取引はプレビューに含まれないべき")
    }

    /// スキップ日に設定された日付はプレビューに含まれない
    func testPreviewSkipsSkippedDates() {
        let project = makeProject()
        let day = pastDayOfMonth
        let todayComps = todayComponents

        guard todayComps.day! >= day else { return }

        let currentYear = todayComps.year!
        let currentMonth = todayComps.month!
        let skipDate = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: day))!

        let recurring = insertRecurringDirectly(
            name: "スキップ経費",
            type: .expense,
            amount: 4000,
            categoryId: "cat-tools",
            projectId: project.id,
            dayOfMonth: day,
            skipDates: [skipDate]
        )

        let preview = dataStore.previewRecurringTransactions()

        let skippedItems = preview.filter { item in
            item.recurringId == recurring.id
                && calendar.component(.month, from: item.scheduledDate) == currentMonth
                && calendar.component(.year, from: item.scheduledDate) == currentYear
        }
        XCTAssertTrue(skippedItems.isEmpty, "スキップ日に設定された日付はプレビューに含まれないべき")
    }

    /// endDate を過ぎた定期取引はプレビューに含まれない
    func testPreviewRespectsEndDate() {
        let project = makeProject()
        let today = todayDate()

        // endDate を2ヶ月前に設定（すでに終了済み）
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: today)!

        let recurring = insertRecurringDirectly(
            name: "終了済み経費",
            type: .expense,
            amount: 2000,
            categoryId: "cat-tools",
            projectId: project.id,
            dayOfMonth: pastDayOfMonth,
            endDate: twoMonthsAgo
        )

        let preview = dataStore.previewRecurringTransactions()

        let matchingItems = preview.filter { $0.recurringId == recurring.id }
        let itemsAfterEnd = matchingItems.filter { $0.scheduledDate > twoMonthsAgo }
        XCTAssertTrue(itemsAfterEnd.isEmpty, "endDate後の日付はプレビューに含まれないべき")
    }

    /// 定期取引が存在しない場合、プレビューは空
    func testPreviewEmptyWhenNothingDue() {
        let preview = dataStore.previewRecurringTransactions()

        XCTAssertTrue(preview.isEmpty, "定期取引がない場合プレビューは空であるべき")
    }

    // MARK: - Allocation Info Tests

    /// プレビュー項目にアロケーション情報が含まれる
    func testPreviewItemContainsAllocationInfo() {
        let project = makeProject(name: "テストPJ")
        let day = pastDayOfMonth
        let todayComps = todayComponents
        guard todayComps.day! >= day else { return }

        insertRecurringDirectly(
            name: "配賦テスト",
            type: .expense,
            amount: 10000,
            categoryId: "cat-test",
            projectId: project.id,
            dayOfMonth: day
        )

        let preview = dataStore.previewRecurringTransactions()
        let item = preview.first { $0.recurringName == "配賦テスト" }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.projectName, "テストPJ")
        XCTAssertEqual(item?.allocationMode, .manual)
    }

    // MARK: - Year Lock Tests

    private func setupProfileAndLockYear(_ year: Int) {
        if dataStore.accountingProfile == nil {
            let profile = PPAccountingProfile(fiscalYear: year)
            context.insert(profile)
            try? context.save()
            dataStore.loadData()
        }
        dataStore.lockFiscalYear(year)
    }

    /// 年度ロック中の日付はプレビューからスキップされる
    func testPreviewSkipsYearLockedDates() {
        let project = makeProject()
        let todayComps = todayComponents
        let currentYear = todayComps.year!

        setupProfileAndLockYear(currentYear)

        insertRecurringDirectly(
            name: "ロック年度テスト",
            type: .expense,
            amount: 5000,
            categoryId: "cat-test",
            projectId: project.id,
            dayOfMonth: pastDayOfMonth
        )

        let preview = dataStore.previewRecurringTransactions()
        let lockedItems = preview.filter { item in
            calendar.component(.year, from: item.scheduledDate) == currentYear
                && item.recurringName == "ロック年度テスト"
        }
        XCTAssertTrue(lockedItems.isEmpty, "年度ロック中の日付はプレビューに含まれないべき")

        // Unlock for cleanup
        dataStore.unlockFiscalYear(currentYear)
    }
}
