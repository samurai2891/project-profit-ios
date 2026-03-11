import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DataRevisionQueryUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: DataRevisionQueryUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = DataRevisionQueryUseCase(modelContext: context)
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testTransactionProjectAndCategoryUpdatesChangeAllRevisionKeys() {
        let dashboardBefore = useCase.dashboardRevisionKey()
        let reportBefore = useCase.reportRevisionKey()
        let transactionsBefore = useCase.transactionsRevisionKey()

        let project = dataStore.addProject(name: "Revision Project", description: "")
        _ = dataStore.addTransaction(
            type: .expense,
            amount: 1_000,
            date: makeDate(2025, 4, 10),
            categoryId: "cat-tools",
            memo: "revision target",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        guard let category = dataStore.getCategory(id: "cat-tools") else {
            XCTFail("category should exist")
            return
        }
        category.name = "ツール更新"
        XCTAssertTrue(dataStore.save())

        XCTAssertNotEqual(useCase.dashboardRevisionKey(), dashboardBefore)
        XCTAssertNotEqual(useCase.reportRevisionKey(), reportBefore)
        XCTAssertNotEqual(useCase.transactionsRevisionKey(), transactionsBefore)
    }

    func testJournalUpdatesOnlyChangeDashboardAndReportRevisionKeys() throws {
        let dashboardBefore = useCase.dashboardRevisionKey()
        let reportBefore = useCase.reportRevisionKey()
        let transactionsBefore = useCase.transactionsRevisionKey()

        context.insert(
            PPJournalEntry(
                sourceKey: PPJournalEntry.manualSourceKey(UUID()),
                date: makeDate(2025, 5, 1),
                entryType: .manual,
                memo: "manual journal",
                updatedAt: makeDate(2025, 5, 2)
            )
        )
        try context.save()

        XCTAssertNotEqual(useCase.dashboardRevisionKey(), dashboardBefore)
        XCTAssertNotEqual(useCase.reportRevisionKey(), reportBefore)
        XCTAssertEqual(useCase.transactionsRevisionKey(), transactionsBefore)
    }

    func testCategorySignatureReflectsNameArchiveAndLinkedAccountChanges() {
        let before = useCase.transactionsRevisionKey()

        guard let category = dataStore.getCategory(id: "cat-tools") else {
            XCTFail("category should exist")
            return
        }

        category.name = "改名カテゴリ"
        category.archivedAt = makeDate(2025, 6, 1)
        category.linkedAccountId = "acct-expense"
        XCTAssertTrue(dataStore.save())

        XCTAssertNotEqual(useCase.transactionsRevisionKey(), before)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
