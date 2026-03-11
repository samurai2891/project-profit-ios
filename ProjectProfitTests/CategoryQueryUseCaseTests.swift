import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class CategoryQueryUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: CategoryQueryUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        dataStore = ProjectProfit.DataStore(modelContext: container.mainContext)
        dataStore.loadData()
        useCase = CategoryQueryUseCase(modelContext: container.mainContext)
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        container = nil
        super.tearDown()
    }

    func testSnapshotIncludesActiveAndArchivedCategories() {
        let active = dataStore.addCategory(name: "現役カテゴリ", type: .expense, icon: "tag")
        let archived = dataStore.addCategory(name: "旧カテゴリ", type: .income, icon: "archivebox")
        dataStore.archiveCategory(id: archived.id)

        let snapshot = useCase.snapshot()

        XCTAssertTrue(snapshot.categories.contains(where: { $0.id == active.id && $0.archivedAt == nil }))
        XCTAssertTrue(snapshot.categories.contains(where: { $0.id == archived.id && $0.archivedAt != nil }))
    }

    func testAccountsReturnsSortedActiveAccountsForCategoryType() {
        let expenseA = PPAccount(
            id: "acct-expense-a",
            code: "612",
            name: "経費A",
            accountType: .expense,
            subtype: .miscExpense,
            isSystem: false,
            displayOrder: 20
        )
        let expenseB = PPAccount(
            id: "acct-expense-b",
            code: "611",
            name: "経費B",
            accountType: .expense,
            subtype: .miscExpense,
            isSystem: false,
            displayOrder: 10
        )
        let revenueHidden = PPAccount(
            id: "acct-revenue-hidden",
            code: "501",
            name: "無効収益",
            accountType: .revenue,
            subtype: .salesRevenue,
            isSystem: false,
            isActive: false,
            displayOrder: 1
        )
        container.mainContext.insert(expenseA)
        container.mainContext.insert(expenseB)
        container.mainContext.insert(revenueHidden)
        try! container.mainContext.save()

        let snapshot = useCase.snapshot()
        let accounts = useCase.accounts(for: .expense, snapshot: snapshot)

        XCTAssertEqual(Array(accounts.map(\.id).prefix(2)), ["acct-expense-b", "acct-expense-a"])
        XCTAssertFalse(accounts.contains(where: { $0.id == revenueHidden.id }))
    }

    func testLinkedAccountResolvesFromSnapshot() throws {
        let account = PPAccount(
            id: "acct-expense-link",
            code: "615",
            name: "連携経費",
            accountType: .expense,
            subtype: .miscExpense,
            isSystem: false,
            displayOrder: 15
        )
        container.mainContext.insert(account)
        try! container.mainContext.save()

        let category = dataStore.addCategory(name: "リンク先カテゴリ", type: .expense, icon: "link")
        dataStore.updateCategoryLinkedAccount(categoryId: category.id, accountId: account.id)

        let snapshot = useCase.snapshot()
        let linkedCategory = try XCTUnwrap(snapshot.categories.first { $0.id == category.id })
        let linked = useCase.linkedAccount(for: linkedCategory, snapshot: snapshot)

        XCTAssertEqual(linked?.id, account.id)
        XCTAssertEqual(linked?.name, "連携経費")
    }
}
