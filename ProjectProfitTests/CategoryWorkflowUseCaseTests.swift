import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class CategoryWorkflowUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: CategoryWorkflowUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        dataStore = ProjectProfit.DataStore(modelContext: container.mainContext)
        dataStore.loadData()
        useCase = CategoryWorkflowUseCase(dataStore: dataStore)
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        container = nil
        super.tearDown()
    }

    func testCreateCategoryInsertsRecord() {
        let category = useCase.createCategory(
            input: CategoryCreateInput(name: "外注費", type: .expense, icon: "wrench")
        )

        XCTAssertEqual(category.name, "外注費")
        XCTAssertEqual(dataStore.getCategory(id: category.id)?.icon, "wrench")
    }

    func testCreateCategoryReturnsExistingDuplicate() {
        let original = useCase.createCategory(
            input: CategoryCreateInput(name: "旅費", type: .expense, icon: "airplane")
        )

        let duplicate = useCase.createCategory(
            input: CategoryCreateInput(name: "旅費", type: .expense, icon: "tram")
        )

        XCTAssertEqual(original.id, duplicate.id)
        XCTAssertEqual(dataStore.categories.filter { $0.name == "旅費" && $0.type == .expense }.count, 1)
        XCTAssertEqual(dataStore.getCategory(id: original.id)?.icon, "airplane")
    }

    func testUpdateCategoryRejectsDuplicateName() {
        _ = useCase.createCategory(
            input: CategoryCreateInput(name: "会議費", type: .expense, icon: "person.2")
        )
        let editable = useCase.createCategory(
            input: CategoryCreateInput(name: "雑費", type: .expense, icon: "star")
        )

        let updated = useCase.updateCategory(
            id: editable.id,
            input: CategoryUpdateInput(name: "会議費", type: nil, icon: nil)
        )

        XCTAssertFalse(updated)
        XCTAssertEqual(dataStore.getCategory(id: editable.id)?.name, "雑費")
    }

    func testArchiveAndUnarchiveCategoryToggleArchivedAt() {
        let category = useCase.createCategory(
            input: CategoryCreateInput(name: "アーカイブ候補", type: .expense, icon: "archivebox")
        )

        XCTAssertTrue(useCase.archiveCategory(id: category.id))
        XCTAssertNotNil(dataStore.getCategory(id: category.id)?.archivedAt)

        XCTAssertTrue(useCase.unarchiveCategory(id: category.id))
        XCTAssertNil(dataStore.getCategory(id: category.id)?.archivedAt)
    }

    func testUpdateLinkedAccountPersistsValue() {
        let accountId = "acct-expense-test"
        dataStore.modelContext.insert(
            PPAccount(
                id: accountId,
                code: "611",
                name: "テスト経費",
                accountType: .expense,
                subtype: .miscExpense,
                isSystem: false,
                displayOrder: 611
            )
        )
        try! dataStore.modelContext.save()
        dataStore.loadData()

        let category = useCase.createCategory(
            input: CategoryCreateInput(name: "紐付カテゴリ", type: .expense, icon: "link")
        )

        XCTAssertTrue(useCase.updateLinkedAccount(categoryId: category.id, accountId: accountId))
        XCTAssertEqual(dataStore.getCategory(id: category.id)?.linkedAccountId, accountId)
    }

    func testDeleteCategoryMigratesTransactionAndRecurringReferences() {
        let project = dataStore.addProject(name: "Category Workflow", description: "")
        let category = useCase.createCategory(
            input: CategoryCreateInput(name: "削除カテゴリ", type: .expense, icon: "trash")
        )
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 1_200,
            date: Date(),
            categoryId: category.id,
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        let recurring = dataStore.addRecurring(
            name: "月次費用",
            type: .expense,
            amount: 1_200,
            categoryId: category.id,
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        XCTAssertTrue(useCase.deleteCategory(id: category.id))

        XCTAssertNil(dataStore.getCategory(id: category.id))
        XCTAssertEqual(dataStore.getTransaction(id: transaction.id)?.categoryId, "cat-other-expense")
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.categoryId, "cat-other-expense")
    }

    func testDeleteDefaultCategoryIsBlocked() {
        XCTAssertFalse(useCase.deleteCategory(id: "cat-other-expense"))
        XCTAssertNotNil(dataStore.getCategory(id: "cat-other-expense"))
    }
}
