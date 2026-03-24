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
        useCase = CategoryWorkflowUseCase(modelContext: container.mainContext)
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        container = nil
        super.tearDown()
    }

    func testCreateCategoryInsertsRecord() throws {
        let category = try useCase.createCategory(
            input: CategoryCreateInput(name: "外注費", type: .expense, icon: "wrench")
        )
        dataStore.refreshCategories()

        XCTAssertEqual(category.name, "外注費")
        XCTAssertEqual(dataStore.getCategory(id: category.id)?.icon, "wrench")
    }

    func testCreateCategoryReturnsExistingDuplicate() throws {
        let original = try useCase.createCategory(
            input: CategoryCreateInput(name: "旅費", type: .expense, icon: "airplane")
        )

        let duplicate = try useCase.createCategory(
            input: CategoryCreateInput(name: "旅費", type: .expense, icon: "tram")
        )
        dataStore.refreshCategories()

        XCTAssertEqual(original.id, duplicate.id)
        XCTAssertEqual(dataStore.categories.filter { $0.name == "旅費" && $0.type == .expense }.count, 1)
        XCTAssertEqual(dataStore.getCategory(id: original.id)?.icon, "airplane")
    }

    func testCreateCategorySaveFailureThrowsAndDoesNotPersistNewCategory() {
        let repository = FailingSaveCategoryRepository(
            seedCategories: [
                PPCategory(
                    id: "cat-other-expense",
                    name: "その他経費",
                    type: .expense,
                    icon: "tray",
                    isDefault: true
                )
            ]
        )
        let failingUseCase = CategoryWorkflowUseCase(
            modelContext: container.mainContext,
            categoryRepository: repository
        )

        XCTAssertThrowsError(try failingUseCase.createCategory(
            input: CategoryCreateInput(name: "保存失敗カテゴリ", type: .expense, icon: "xmark.circle")
        )) { error in
            guard case .saveFailed = error as? AppError else {
                XCTFail("Expected saveFailed error, got \(error)")
                return
            }
        }
        XCTAssertFalse(repository.containsCategory(name: "保存失敗カテゴリ", type: .expense))
    }

    func testUpdateCategoryRejectsDuplicateName() throws {
        _ = try useCase.createCategory(
            input: CategoryCreateInput(name: "会議費", type: .expense, icon: "person.2")
        )
        let editable = try useCase.createCategory(
            input: CategoryCreateInput(name: "雑費", type: .expense, icon: "star")
        )

        let updated = useCase.updateCategory(
            id: editable.id,
            input: CategoryUpdateInput(name: "会議費", type: nil, icon: nil)
        )
        dataStore.refreshCategories()

        XCTAssertFalse(updated)
        XCTAssertEqual(dataStore.getCategory(id: editable.id)?.name, "雑費")
    }

    func testArchiveAndUnarchiveCategoryToggleArchivedAt() throws {
        let category = try useCase.createCategory(
            input: CategoryCreateInput(name: "アーカイブ候補", type: .expense, icon: "archivebox")
        )

        XCTAssertTrue(useCase.archiveCategory(id: category.id))
        dataStore.refreshCategories()
        XCTAssertNotNil(dataStore.getCategory(id: category.id)?.archivedAt)

        XCTAssertTrue(useCase.unarchiveCategory(id: category.id))
        dataStore.refreshCategories()
        XCTAssertNil(dataStore.getCategory(id: category.id)?.archivedAt)
    }

    func testUpdateLinkedAccountPersistsValue() throws {
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

        let category = try useCase.createCategory(
            input: CategoryCreateInput(name: "紐付カテゴリ", type: .expense, icon: "link")
        )

        XCTAssertTrue(useCase.updateLinkedAccount(categoryId: category.id, accountId: accountId))
        dataStore.refreshCategories()
        XCTAssertEqual(dataStore.getCategory(id: category.id)?.linkedAccountId, accountId)
    }

    func testDeleteCategoryMigratesTransactionAndRecurringReferences() throws {
        let project = mutations(dataStore).addProject(name: "Category Workflow", description: "")
        let category = try useCase.createCategory(
            input: CategoryCreateInput(name: "削除カテゴリ", type: .expense, icon: "trash")
        )
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1_200,
            date: Date(),
            categoryId: category.id,
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        let recurring = mutations(dataStore).addRecurring(
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
        dataStore.refreshCategories()
        dataStore.refreshTransactions()
        dataStore.refreshRecurring()

        XCTAssertNil(dataStore.getCategory(id: category.id))
        XCTAssertEqual(dataStore.getTransaction(id: transaction.id)?.categoryId, "cat-other-expense")
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.categoryId, "cat-other-expense")
    }

    func testDeleteDefaultCategoryIsBlocked() {
        XCTAssertFalse(useCase.deleteCategory(id: "cat-other-expense"))
        XCTAssertNotNil(dataStore.getCategory(id: "cat-other-expense"))
    }
}

@MainActor
private final class FailingSaveCategoryRepository: CategoryRepository {
    private var categoriesStore: [PPCategory]
    private var shouldFailNextSave = true

    init(seedCategories: [PPCategory]) {
        categoriesStore = seedCategories
    }

    func categories() throws -> [PPCategory] {
        categoriesStore
    }

    func category(id: String) throws -> PPCategory? {
        categoriesStore.first { $0.id == id }
    }

    func transactions(categoryId: String) throws -> [PPTransaction] {
        []
    }

    func recurringTransactions(categoryId: String) throws -> [PPRecurringTransaction] {
        []
    }

    func insert(_ category: PPCategory) {
        categoriesStore.append(category)
    }

    func delete(_ category: PPCategory) {
        categoriesStore.removeAll { $0.id == category.id }
    }

    func saveChanges() throws {
        if shouldFailNextSave {
            shouldFailNextSave = false
            throw NSError(domain: "CategoryWorkflowUseCaseTests", code: 1)
        }
    }

    func containsCategory(name: String, type: CategoryType) -> Bool {
        categoriesStore.contains { $0.name == name && $0.type == type }
    }
}
