import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class DataStoreCRUDTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self,
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

    // MARK: - Project CRUD

    func testAddProject() {
        let project = dataStore.addProject(name: "Test Project", description: "A test project")

        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.projectDescription, "A test project")
        XCTAssertEqual(project.status, .active)
        XCTAssertEqual(dataStore.projects.count, 1)
        XCTAssertEqual(dataStore.projects.first?.id, project.id)
    }

    func testAddMultipleProjects() {
        let project1 = dataStore.addProject(name: "Project A", description: "First")
        let project2 = dataStore.addProject(name: "Project B", description: "Second")

        XCTAssertEqual(dataStore.projects.count, 2)
        XCTAssertTrue(dataStore.projects.contains(where: { $0.id == project1.id }))
        XCTAssertTrue(dataStore.projects.contains(where: { $0.id == project2.id }))
    }

    func testUpdateProjectName() {
        let project = dataStore.addProject(name: "Original", description: "Desc")
        dataStore.updateProject(id: project.id, name: "Updated")

        let fetched = dataStore.getProject(id: project.id)
        XCTAssertEqual(fetched?.name, "Updated")
        XCTAssertEqual(fetched?.projectDescription, "Desc")
    }

    func testUpdateProjectDescription() {
        let project = dataStore.addProject(name: "Name", description: "Original")
        dataStore.updateProject(id: project.id, description: "Updated description")

        let fetched = dataStore.getProject(id: project.id)
        XCTAssertEqual(fetched?.name, "Name")
        XCTAssertEqual(fetched?.projectDescription, "Updated description")
    }

    func testUpdateProjectStatus() {
        let project = dataStore.addProject(name: "Name", description: "Desc")
        XCTAssertEqual(project.status, .active)

        dataStore.updateProject(id: project.id, status: .completed)
        XCTAssertEqual(dataStore.getProject(id: project.id)?.status, .completed)

        dataStore.updateProject(id: project.id, status: .paused)
        XCTAssertEqual(dataStore.getProject(id: project.id)?.status, .paused)
    }

    func testUpdateProjectMultipleFields() {
        let project = dataStore.addProject(name: "Old", description: "Old desc")
        let originalUpdatedAt = project.updatedAt

        // Small delay so updatedAt differs
        Thread.sleep(forTimeInterval: 0.01)
        dataStore.updateProject(id: project.id, name: "New", description: "New desc", status: .paused)

        let fetched = dataStore.getProject(id: project.id)
        XCTAssertEqual(fetched?.name, "New")
        XCTAssertEqual(fetched?.projectDescription, "New desc")
        XCTAssertEqual(fetched?.status, .paused)
        XCTAssertGreaterThan(fetched!.updatedAt, originalUpdatedAt)
    }

    func testUpdateNonExistentProjectIsNoOp() {
        dataStore.updateProject(id: UUID(), name: "Ghost")
        XCTAssertEqual(dataStore.projects.count, 0)
    }

    func testDeleteProject() {
        let project = dataStore.addProject(name: "To Delete", description: "")
        XCTAssertEqual(dataStore.projects.count, 1)

        dataStore.deleteProject(id: project.id)
        XCTAssertEqual(dataStore.projects.count, 0)
        XCTAssertNil(dataStore.getProject(id: project.id))
    }

    func testDeleteNonExistentProjectIsNoOp() {
        let project = dataStore.addProject(name: "Keep", description: "")
        dataStore.deleteProject(id: UUID())
        XCTAssertEqual(dataStore.projects.count, 1)
        XCTAssertNotNil(dataStore.getProject(id: project.id))
    }

    func testGetProjectReturnsNilForUnknownId() {
        XCTAssertNil(dataStore.getProject(id: UUID()))
    }

    func testGetProjectReturnsCorrectProject() {
        let project1 = dataStore.addProject(name: "First", description: "")
        let project2 = dataStore.addProject(name: "Second", description: "")

        let fetched = dataStore.getProject(id: project2.id)
        XCTAssertEqual(fetched?.id, project2.id)
        XCTAssertEqual(fetched?.name, "Second")
        XCTAssertNotEqual(fetched?.id, project1.id)
    }

    // MARK: - Transaction CRUD

    func testAddTransaction() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 10000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "Test memo",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        XCTAssertEqual(transaction.type, .income)
        XCTAssertEqual(transaction.amount, 10000)
        XCTAssertEqual(transaction.categoryId, "cat-sales")
        XCTAssertEqual(transaction.memo, "Test memo")
        XCTAssertEqual(transaction.allocations.count, 1)
        XCTAssertEqual(transaction.allocations.first?.projectId, project.id)
        XCTAssertEqual(transaction.allocations.first?.ratio, 100)
        XCTAssertEqual(transaction.allocations.first?.amount, 10000)
        XCTAssertNil(transaction.recurringId)
        XCTAssertEqual(dataStore.transactions.count, 1)
    }

    func testAddTransactionWithMultipleAllocations() {
        let project1 = dataStore.addProject(name: "Proj A", description: "")
        let project2 = dataStore.addProject(name: "Proj B", description: "")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: project1.id, ratio: 60),
                (projectId: project2.id, ratio: 40),
            ]
        )

        XCTAssertEqual(transaction.allocations.count, 2)

        let alloc1 = transaction.allocations.first(where: { $0.projectId == project1.id })
        XCTAssertEqual(alloc1?.ratio, 60)
        XCTAssertEqual(alloc1?.amount, 6000)

        let alloc2 = transaction.allocations.first(where: { $0.projectId == project2.id })
        XCTAssertEqual(alloc2?.ratio, 40)
        XCTAssertEqual(alloc2?.amount, 4000)
    }

    func testAddTransactionWithRecurringId() {
        let recurringId = UUID()
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 5000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            recurringId: recurringId
        )

        XCTAssertEqual(transaction.recurringId, recurringId)
    }

    func testUpdateTransactionType() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 5000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        dataStore.updateTransaction(id: transaction.id, type: .expense)
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.type, .expense)
    }

    func testUpdateTransactionAmount() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 5000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        dataStore.updateTransaction(id: transaction.id, amount: 8000)
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.amount, 8000)
        // Allocations should be recalculated with new amount
        XCTAssertEqual(fetched?.allocations.first?.amount, 8000)
    }

    func testUpdateTransactionAmountRecalculatesMultipleAllocations() {
        let project1 = dataStore.addProject(name: "A", description: "")
        let project2 = dataStore.addProject(name: "B", description: "")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: project1.id, ratio: 70),
                (projectId: project2.id, ratio: 30),
            ]
        )

        dataStore.updateTransaction(id: transaction.id, amount: 20000)
        let fetched = dataStore.getTransaction(id: transaction.id)
        let alloc1 = fetched?.allocations.first(where: { $0.projectId == project1.id })
        let alloc2 = fetched?.allocations.first(where: { $0.projectId == project2.id })
        XCTAssertEqual(alloc1?.amount, 14000)
        XCTAssertEqual(alloc2?.amount, 6000)
    }

    func testUpdateTransactionDate() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let originalDate = Date()
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 1000,
            date: originalDate,
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let newDate = Calendar.current.date(byAdding: .day, value: -7, to: originalDate)!
        dataStore.updateTransaction(id: transaction.id, date: newDate)
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: fetched!.date),
            Calendar.current.startOfDay(for: newDate)
        )
    }

    func testUpdateTransactionCategory() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        dataStore.updateTransaction(id: transaction.id, categoryId: "cat-tools")
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.categoryId, "cat-tools")
    }

    func testUpdateTransactionMemo() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "Original",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        dataStore.updateTransaction(id: transaction.id, memo: "Updated memo")
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.memo, "Updated memo")
    }

    func testUpdateTransactionAllocations() {
        let project1 = dataStore.addProject(name: "A", description: "")
        let project2 = dataStore.addProject(name: "B", description: "")
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 10000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project1.id, ratio: 100)]
        )

        dataStore.updateTransaction(
            id: transaction.id,
            allocations: [
                (projectId: project1.id, ratio: 50),
                (projectId: project2.id, ratio: 50),
            ]
        )

        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.allocations.count, 2)
        let alloc1 = fetched?.allocations.first(where: { $0.projectId == project1.id })
        let alloc2 = fetched?.allocations.first(where: { $0.projectId == project2.id })
        XCTAssertEqual(alloc1?.ratio, 50)
        XCTAssertEqual(alloc1?.amount, 5000)
        XCTAssertEqual(alloc2?.ratio, 50)
        XCTAssertEqual(alloc2?.amount, 5000)
    }

    func testUpdateTransactionAmountAndAllocations() {
        let project1 = dataStore.addProject(name: "A", description: "")
        let project2 = dataStore.addProject(name: "B", description: "")
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 10000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project1.id, ratio: 100)]
        )

        dataStore.updateTransaction(
            id: transaction.id,
            amount: 20000,
            allocations: [
                (projectId: project1.id, ratio: 60),
                (projectId: project2.id, ratio: 40),
            ]
        )

        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.amount, 20000)
        let alloc1 = fetched?.allocations.first(where: { $0.projectId == project1.id })
        let alloc2 = fetched?.allocations.first(where: { $0.projectId == project2.id })
        XCTAssertEqual(alloc1?.amount, 12000)
        XCTAssertEqual(alloc2?.amount, 8000)
    }

    func testUpdateTransactionSetsUpdatedAt() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        let originalUpdatedAt = transaction.updatedAt

        Thread.sleep(forTimeInterval: 0.01)
        dataStore.updateTransaction(id: transaction.id, memo: "Changed")
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertGreaterThan(fetched!.updatedAt, originalUpdatedAt)
    }

    func testUpdateNonExistentTransactionIsNoOp() {
        dataStore.updateTransaction(id: UUID(), amount: 999)
        XCTAssertEqual(dataStore.transactions.count, 0)
    }

    func testDeleteTransaction() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertEqual(dataStore.transactions.count, 1)

        dataStore.deleteTransaction(id: transaction.id)
        XCTAssertEqual(dataStore.transactions.count, 0)
        XCTAssertNil(dataStore.getTransaction(id: transaction.id))
    }

    func testDeleteNonExistentTransactionIsNoOp() {
        let project = dataStore.addProject(name: "Proj", description: "")
        dataStore.addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        dataStore.deleteTransaction(id: UUID())
        XCTAssertEqual(dataStore.transactions.count, 1)
    }

    // MARK: - Transaction with Receipt & Line Items

    func testAddTransactionWithReceiptImagePath() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 1500,
            date: Date(),
            categoryId: "cat-food",
            memo: "Lunch",
            allocations: [(projectId: project.id, ratio: 100)],
            receiptImagePath: "test-receipt-123.jpg"
        )

        XCTAssertEqual(transaction.receiptImagePath, "test-receipt-123.jpg")
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.receiptImagePath, "test-receipt-123.jpg")
    }

    func testAddTransactionWithLineItems() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let items = [
            ReceiptLineItem(name: "コーヒー", unitPrice: 350),
            ReceiptLineItem(name: "サンドイッチ", quantity: 2, unitPrice: 480),
        ]
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 1310,
            date: Date(),
            categoryId: "cat-food",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            lineItems: items
        )

        XCTAssertEqual(transaction.lineItems.count, 2)
        XCTAssertEqual(transaction.lineItems[0].name, "コーヒー")
        XCTAssertEqual(transaction.lineItems[0].subtotal, 350)
        XCTAssertEqual(transaction.lineItems[1].name, "サンドイッチ")
        XCTAssertEqual(transaction.lineItems[1].quantity, 2)
        XCTAssertEqual(transaction.lineItems[1].subtotal, 960)
    }

    func testAddTransactionWithReceiptAndLineItems() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let items = [ReceiptLineItem(name: "ペン", quantity: 3, unitPrice: 100)]
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 300,
            date: Date(),
            categoryId: "cat-supplies",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            receiptImagePath: "receipt-abc.jpg",
            lineItems: items
        )

        XCTAssertEqual(transaction.receiptImagePath, "receipt-abc.jpg")
        XCTAssertEqual(transaction.lineItems.count, 1)
        XCTAssertEqual(transaction.lineItems[0].subtotal, 300)
    }

    func testAddTransactionDefaultsNoReceiptNoLineItems() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 5000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        XCTAssertNil(transaction.receiptImagePath)
        XCTAssertTrue(transaction.lineItems.isEmpty)
    }

    func testUpdateTransactionReceiptImagePath() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-food",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertNil(transaction.receiptImagePath)

        dataStore.updateTransaction(id: transaction.id, receiptImagePath: "new-receipt.jpg")
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.receiptImagePath, "new-receipt.jpg")
    }

    func testUpdateTransactionClearReceiptImagePath() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-food",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            receiptImagePath: "old-receipt.jpg"
        )

        dataStore.updateTransaction(id: transaction.id, receiptImagePath: .some(nil))
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertNil(fetched?.receiptImagePath)
    }

    func testUpdateTransactionLineItems() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 500,
            date: Date(),
            categoryId: "cat-supplies",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertTrue(transaction.lineItems.isEmpty)

        let newItems = [
            ReceiptLineItem(name: "ノート", unitPrice: 200),
            ReceiptLineItem(name: "ペン", unitPrice: 300),
        ]
        dataStore.updateTransaction(id: transaction.id, lineItems: newItems)
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.lineItems.count, 2)
        XCTAssertEqual(fetched?.lineItems[0].name, "ノート")
        XCTAssertEqual(fetched?.lineItems[1].name, "ペン")
    }

    func testRemoveReceiptImage() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-food",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            receiptImagePath: "to-remove.jpg"
        )
        XCTAssertNotNil(transaction.receiptImagePath)

        dataStore.removeReceiptImage(transactionId: transaction.id)
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertNil(fetched?.receiptImagePath)
    }

    func testRemoveReceiptImageNonExistentTransactionIsNoOp() {
        dataStore.removeReceiptImage(transactionId: UUID())
        // Should not crash or error
        XCTAssertEqual(dataStore.transactions.count, 0)
    }

    // MARK: - Category CRUD

    func testDefaultCategoriesAreSeeded() {
        XCTAssertEqual(dataStore.categories.count, DEFAULT_CATEGORIES.count)

        for defaultCat in DEFAULT_CATEGORIES {
            let found = dataStore.categories.first(where: { $0.id == defaultCat.id })
            XCTAssertNotNil(found, "Default category \(defaultCat.id) should exist")
            XCTAssertEqual(found?.name, defaultCat.name)
            XCTAssertEqual(found?.type, defaultCat.type)
            XCTAssertEqual(found?.icon, defaultCat.icon)
            XCTAssertTrue(found?.isDefault == true)
        }
    }

    func testAddCategory() {
        let category = dataStore.addCategory(name: "Custom", type: .expense, icon: "star")

        XCTAssertEqual(category.name, "Custom")
        XCTAssertEqual(category.type, .expense)
        XCTAssertEqual(category.icon, "star")
        XCTAssertFalse(category.isDefault)
        XCTAssertEqual(dataStore.categories.count, DEFAULT_CATEGORIES.count + 1)
    }

    func testAddIncomeCategory() {
        let category = dataStore.addCategory(name: "Freelance", type: .income, icon: "laptop")

        XCTAssertEqual(category.type, .income)
        XCTAssertFalse(category.isDefault)
    }

    func testUpdateCategoryName() {
        let category = dataStore.addCategory(name: "Original", type: .expense, icon: "star")
        dataStore.updateCategory(id: category.id, name: "Renamed")

        let fetched = dataStore.getCategory(id: category.id)
        XCTAssertEqual(fetched?.name, "Renamed")
        XCTAssertEqual(fetched?.icon, "star")
    }

    func testUpdateCategoryType() {
        let category = dataStore.addCategory(name: "Flexible", type: .expense, icon: "arrow.left.arrow.right")
        dataStore.updateCategory(id: category.id, type: .income)

        let fetched = dataStore.getCategory(id: category.id)
        XCTAssertEqual(fetched?.type, .income)
    }

    func testUpdateCategoryIcon() {
        let category = dataStore.addCategory(name: "Cat", type: .expense, icon: "star")
        dataStore.updateCategory(id: category.id, icon: "heart")

        let fetched = dataStore.getCategory(id: category.id)
        XCTAssertEqual(fetched?.icon, "heart")
    }

    func testUpdateNonExistentCategoryIsNoOp() {
        let initialCount = dataStore.categories.count
        dataStore.updateCategory(id: "non-existent-id", name: "Ghost")
        XCTAssertEqual(dataStore.categories.count, initialCount)
    }

    func testDeleteCustomCategory() {
        let category = dataStore.addCategory(name: "Deletable", type: .expense, icon: "trash")
        let countBeforeDelete = dataStore.categories.count

        dataStore.deleteCategory(id: category.id)
        XCTAssertEqual(dataStore.categories.count, countBeforeDelete - 1)
        XCTAssertNil(dataStore.getCategory(id: category.id))
    }

    func testDeleteDefaultCategoryIsBlocked() {
        let defaultCatId = DEFAULT_CATEGORIES[0].id
        let countBefore = dataStore.categories.count

        dataStore.deleteCategory(id: defaultCatId)
        XCTAssertEqual(dataStore.categories.count, countBefore)
        XCTAssertNotNil(dataStore.getCategory(id: defaultCatId))
    }

    func testDeleteAllDefaultCategoriesAreBlocked() {
        let countBefore = dataStore.categories.count

        for defaultCat in DEFAULT_CATEGORIES {
            dataStore.deleteCategory(id: defaultCat.id)
        }

        XCTAssertEqual(dataStore.categories.count, countBefore)
    }

    func testDeleteNonExistentCategoryIsNoOp() {
        let countBefore = dataStore.categories.count
        dataStore.deleteCategory(id: "non-existent")
        XCTAssertEqual(dataStore.categories.count, countBefore)
    }

    func testGetCategoryReturnsNilForUnknownId() {
        XCTAssertNil(dataStore.getCategory(id: "unknown-cat"))
    }

    // MARK: - Recurring CRUD

    func testAddRecurringMonthly() {
        let project = dataStore.addProject(name: "Proj", description: "")
        // Use dayOfMonth 28 to avoid auto-generation (CRUD property test, not processing test)
        let recurring = dataStore.addRecurring(
            name: "Monthly hosting",
            type: .expense,
            amount: 3000,
            categoryId: "cat-hosting",
            memo: "Server bill",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 28
        )

        XCTAssertEqual(recurring.name, "Monthly hosting")
        XCTAssertEqual(recurring.type, .expense)
        XCTAssertEqual(recurring.amount, 3000)
        XCTAssertEqual(recurring.categoryId, "cat-hosting")
        XCTAssertEqual(recurring.memo, "Server bill")
        XCTAssertEqual(recurring.frequency, .monthly)
        XCTAssertEqual(recurring.dayOfMonth, 28)
        XCTAssertNil(recurring.monthOfYear)
        XCTAssertTrue(recurring.isActive)
        XCTAssertEqual(recurring.skipDates, [])
        XCTAssertEqual(recurring.notificationTiming, .none)
        XCTAssertEqual(recurring.allocations.count, 1)
        XCTAssertEqual(recurring.allocations.first?.amount, 3000)
        XCTAssertEqual(dataStore.recurringTransactions.count, 1)
    }

    func testAddRecurringYearly() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Annual license",
            type: .expense,
            amount: 12000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: 4
        )

        XCTAssertEqual(recurring.frequency, .yearly)
        XCTAssertEqual(recurring.dayOfMonth, 1)
        XCTAssertEqual(recurring.monthOfYear, 4)
    }

    func testAddRecurringWithMultipleAllocations() {
        let project1 = dataStore.addProject(name: "A", description: "")
        let project2 = dataStore.addProject(name: "B", description: "")
        let recurring = dataStore.addRecurring(
            name: "Shared expense",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: project1.id, ratio: 60),
                (projectId: project2.id, ratio: 40),
            ],
            frequency: .monthly,
            dayOfMonth: 1
        )

        XCTAssertEqual(recurring.allocations.count, 2)
        let alloc1 = recurring.allocations.first(where: { $0.projectId == project1.id })
        let alloc2 = recurring.allocations.first(where: { $0.projectId == project2.id })
        XCTAssertEqual(alloc1?.amount, 6000)
        XCTAssertEqual(alloc2?.amount, 4000)
    }

    func testAddRecurringClampsDayOfMonth() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Clamped",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 31
        )

        // dayOfMonth is clamped to 28 max in the model init
        XCTAssertEqual(recurring.dayOfMonth, 28)
    }

    func testUpdateRecurringName() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Original",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.updateRecurring(id: recurring.id, name: "Renamed")
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.name, "Renamed")
    }

    func testUpdateRecurringType() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.updateRecurring(id: recurring.id, type: .income)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.type, .income)
    }

    func testUpdateRecurringAmount() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.updateRecurring(id: recurring.id, amount: 8000)
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.amount, 8000)
        XCTAssertEqual(fetched?.allocations.first?.amount, 8000)
    }

    func testUpdateRecurringCategoryId() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.updateRecurring(id: recurring.id, categoryId: "cat-tools")
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.categoryId, "cat-tools")
    }

    func testUpdateRecurringMemo() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "Old",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.updateRecurring(id: recurring.id, memo: "New memo")
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.memo, "New memo")
    }

    func testUpdateRecurringAllocations() {
        let project1 = dataStore.addProject(name: "A", description: "")
        let project2 = dataStore.addProject(name: "B", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project1.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.updateRecurring(
            id: recurring.id,
            allocations: [
                (projectId: project1.id, ratio: 50),
                (projectId: project2.id, ratio: 50),
            ]
        )

        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.allocations.count, 2)
        let alloc1 = fetched?.allocations.first(where: { $0.projectId == project1.id })
        let alloc2 = fetched?.allocations.first(where: { $0.projectId == project2.id })
        XCTAssertEqual(alloc1?.amount, 5000)
        XCTAssertEqual(alloc2?.amount, 5000)
    }

    func testUpdateRecurringFrequencyToMonthly() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: 6
        )
        XCTAssertEqual(recurring.monthOfYear, 6)

        dataStore.updateRecurring(id: recurring.id, frequency: .monthly)
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.frequency, .monthly)
        // monthOfYear should be cleared when switching to monthly
        XCTAssertNil(fetched?.monthOfYear)
    }

    func testUpdateRecurringFrequencyToYearly() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.updateRecurring(id: recurring.id, frequency: .yearly, monthOfYear: 3)
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.frequency, .yearly)
        XCTAssertEqual(fetched?.monthOfYear, 3)
    }

    func testUpdateRecurringDayOfMonth() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.updateRecurring(id: recurring.id, dayOfMonth: 25)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.dayOfMonth, 25)
    }

    func testUpdateRecurringDayOfMonthClamps() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.updateRecurring(id: recurring.id, dayOfMonth: 31)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.dayOfMonth, 28)

        dataStore.updateRecurring(id: recurring.id, dayOfMonth: 0)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.dayOfMonth, 1)
    }

    func testUpdateRecurringIsActive() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        XCTAssertTrue(recurring.isActive)

        dataStore.updateRecurring(id: recurring.id, isActive: false)
        XCTAssertFalse(dataStore.getRecurring(id: recurring.id)!.isActive)

        dataStore.updateRecurring(id: recurring.id, isActive: true)
        XCTAssertTrue(dataStore.getRecurring(id: recurring.id)!.isActive)
    }

    func testUpdateRecurringNotificationTiming() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        XCTAssertEqual(recurring.notificationTiming, .none)

        dataStore.updateRecurring(id: recurring.id, notificationTiming: .sameDay)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.notificationTiming, .sameDay)

        dataStore.updateRecurring(id: recurring.id, notificationTiming: .dayBefore)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.notificationTiming, .dayBefore)

        dataStore.updateRecurring(id: recurring.id, notificationTiming: .both)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.notificationTiming, .both)
    }

    func testUpdateRecurringSkipDates() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        let skipDate1 = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let skipDate2 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        dataStore.updateRecurring(id: recurring.id, skipDates: [skipDate1, skipDate2])

        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.skipDates.count, 2)
    }

    func testUpdateRecurringSetsUpdatedAt() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        let originalUpdatedAt = recurring.updatedAt

        Thread.sleep(forTimeInterval: 0.01)
        dataStore.updateRecurring(id: recurring.id, name: "Changed")
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertGreaterThan(fetched!.updatedAt, originalUpdatedAt)
    }

    func testUpdateNonExistentRecurringIsNoOp() {
        dataStore.updateRecurring(id: UUID(), name: "Ghost")
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
    }

    func testDeleteRecurring() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        XCTAssertEqual(dataStore.recurringTransactions.count, 1)

        dataStore.deleteRecurring(id: recurring.id)
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
        XCTAssertNil(dataStore.getRecurring(id: recurring.id))
    }

    func testDeleteNonExistentRecurringIsNoOp() {
        let project = dataStore.addProject(name: "Proj", description: "")
        dataStore.addRecurring(
            name: "Keep",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        dataStore.deleteRecurring(id: UUID())
        XCTAssertEqual(dataStore.recurringTransactions.count, 1)
    }

    func testGetRecurringReturnsNilForUnknownId() {
        XCTAssertNil(dataStore.getRecurring(id: UUID()))
    }

    // MARK: - Delete Project Cascade

    func testDeleteProjectRemovesAllocationsFromTransactions() {
        let project1 = dataStore.addProject(name: "A", description: "")
        let project2 = dataStore.addProject(name: "B", description: "")

        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: project1.id, ratio: 50),
                (projectId: project2.id, ratio: 50),
            ]
        )

        dataStore.deleteProject(id: project1.id)

        // Transaction should still exist with only project2's allocation
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.allocations.count, 1)
        XCTAssertEqual(fetched?.allocations.first?.projectId, project2.id)
    }

    func testDeleteProjectDeletesTransactionWhenSoleAllocation() {
        let project = dataStore.addProject(name: "Solo", description: "")
        let transaction = dataStore.addTransaction(
            type: .income,
            amount: 5000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        dataStore.deleteProject(id: project.id)

        // Transaction with no remaining allocations should be deleted
        XCTAssertNil(dataStore.getTransaction(id: transaction.id))
        XCTAssertEqual(dataStore.transactions.count, 0)
    }

    func testDeleteProjectRemovesAllocationsFromRecurring() {
        let project1 = dataStore.addProject(name: "A", description: "")
        let project2 = dataStore.addProject(name: "B", description: "")

        let recurring = dataStore.addRecurring(
            name: "Shared",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: project1.id, ratio: 50),
                (projectId: project2.id, ratio: 50),
            ],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.deleteProject(id: project1.id)

        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.allocations.count, 1)
        XCTAssertEqual(fetched?.allocations.first?.projectId, project2.id)
    }

    func testDeleteProjectDeletesRecurringWhenSoleAllocation() {
        let project = dataStore.addProject(name: "Solo", description: "")
        let recurring = dataStore.addRecurring(
            name: "Solo recurring",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 15
        )

        dataStore.deleteProject(id: project.id)

        XCTAssertNil(dataStore.getRecurring(id: recurring.id))
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
    }

    func testDeleteProjectCascadeDoesNotAffectUnrelatedTransactions() {
        let project1 = dataStore.addProject(name: "A", description: "")
        let project2 = dataStore.addProject(name: "B", description: "")

        dataStore.addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project1.id, ratio: 100)]
        )
        let unrelated = dataStore.addTransaction(
            type: .income,
            amount: 2000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project2.id, ratio: 100)]
        )

        dataStore.deleteProject(id: project1.id)

        // Unrelated transaction should remain intact
        let fetched = dataStore.getTransaction(id: unrelated.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.allocations.count, 1)
        XCTAssertEqual(fetched?.allocations.first?.projectId, project2.id)
    }

    func testDeleteProjectCascadeWithMixedTransactionsAndRecurring() {
        let projectToDelete = dataStore.addProject(name: "Delete Me", description: "")
        let projectToKeep = dataStore.addProject(name: "Keep Me", description: "")

        // Transaction with only the deleted project
        let txSolo = dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: projectToDelete.id, ratio: 100)]
        )

        // Transaction shared between both projects
        let txShared = dataStore.addTransaction(
            type: .expense,
            amount: 2000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "",
            allocations: [
                (projectId: projectToDelete.id, ratio: 60),
                (projectId: projectToKeep.id, ratio: 40),
            ]
        )

        // Recurring with only the deleted project
        let recSolo = dataStore.addRecurring(
            name: "Solo rec",
            type: .expense,
            amount: 3000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: projectToDelete.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        // Recurring shared between both projects
        let recShared = dataStore.addRecurring(
            name: "Shared rec",
            type: .expense,
            amount: 4000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [
                (projectId: projectToDelete.id, ratio: 50),
                (projectId: projectToKeep.id, ratio: 50),
            ],
            frequency: .monthly,
            dayOfMonth: 15
        )

        dataStore.deleteProject(id: projectToDelete.id)

        // Solo transaction should be deleted
        XCTAssertNil(dataStore.getTransaction(id: txSolo.id))

        // Shared transaction should remain with one allocation
        let fetchedTx = dataStore.getTransaction(id: txShared.id)
        XCTAssertNotNil(fetchedTx)
        XCTAssertEqual(fetchedTx?.allocations.count, 1)
        XCTAssertEqual(fetchedTx?.allocations.first?.projectId, projectToKeep.id)

        // Solo recurring should be deleted
        XCTAssertNil(dataStore.getRecurring(id: recSolo.id))

        // Shared recurring should remain with one allocation
        let fetchedRec = dataStore.getRecurring(id: recShared.id)
        XCTAssertNotNil(fetchedRec)
        XCTAssertEqual(fetchedRec?.allocations.count, 1)
        XCTAssertEqual(fetchedRec?.allocations.first?.projectId, projectToKeep.id)

        // The kept project should still exist
        XCTAssertNotNil(dataStore.getProject(id: projectToKeep.id))
        XCTAssertEqual(dataStore.projects.count, 1)
    }

    // MARK: - Delete All Data

    func testDeleteAllDataClearsProjects() {
        dataStore.addProject(name: "A", description: "")
        dataStore.addProject(name: "B", description: "")
        XCTAssertEqual(dataStore.projects.count, 2)

        dataStore.deleteAllData()
        XCTAssertEqual(dataStore.projects.count, 0)
    }

    func testDeleteAllDataClearsTransactions() {
        let project = dataStore.addProject(name: "Proj", description: "")
        dataStore.addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertEqual(dataStore.transactions.count, 1)

        dataStore.deleteAllData()
        XCTAssertEqual(dataStore.transactions.count, 0)
    }

    func testDeleteAllDataClearsRecurring() {
        let project = dataStore.addProject(name: "Proj", description: "")
        dataStore.addRecurring(
            name: "Rec",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        XCTAssertEqual(dataStore.recurringTransactions.count, 1)

        dataStore.deleteAllData()
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
    }

    func testDeleteAllDataReseedsDefaultCategories() {
        // Add a custom category
        dataStore.addCategory(name: "Custom", type: .expense, icon: "star")
        XCTAssertEqual(dataStore.categories.count, DEFAULT_CATEGORIES.count + 1)

        dataStore.deleteAllData()

        // Only default categories should remain
        XCTAssertEqual(dataStore.categories.count, DEFAULT_CATEGORIES.count)
        for defaultCat in DEFAULT_CATEGORIES {
            let found = dataStore.categories.first(where: { $0.id == defaultCat.id })
            XCTAssertNotNil(found, "Default category \(defaultCat.id) should be re-seeded")
            XCTAssertTrue(found?.isDefault == true)
        }
    }

    func testDeleteAllDataCustomCategoriesAreRemoved() {
        let custom = dataStore.addCategory(name: "Custom", type: .income, icon: "star")

        dataStore.deleteAllData()

        XCTAssertNil(dataStore.getCategory(id: custom.id))
    }

    func testDeleteAllDataComprehensive() {
        // Set up a full data scenario
        let project1 = dataStore.addProject(name: "P1", description: "")
        let project2 = dataStore.addProject(name: "P2", description: "")
        dataStore.addCategory(name: "Custom Cat", type: .expense, icon: "star")

        dataStore.addTransaction(
            type: .income,
            amount: 10000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "Sale",
            allocations: [(projectId: project1.id, ratio: 100)]
        )
        dataStore.addTransaction(
            type: .expense,
            amount: 5000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "Server",
            allocations: [
                (projectId: project1.id, ratio: 50),
                (projectId: project2.id, ratio: 50),
            ]
        )
        dataStore.addRecurring(
            name: "Monthly bill",
            type: .expense,
            amount: 3000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project1.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        // 2 manual transactions + 1 auto-generated by addRecurring (dayOfMonth 1 is in the past)
        XCTAssertEqual(dataStore.projects.count, 2)
        XCTAssertEqual(dataStore.transactions.count, 3)
        XCTAssertEqual(dataStore.recurringTransactions.count, 1)
        XCTAssertGreaterThan(dataStore.categories.count, DEFAULT_CATEGORIES.count)

        dataStore.deleteAllData()

        XCTAssertEqual(dataStore.projects.count, 0)
        XCTAssertEqual(dataStore.transactions.count, 0)
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
        XCTAssertEqual(dataStore.categories.count, DEFAULT_CATEGORIES.count)

        // Verify all default categories are present and correct
        for defaultCat in DEFAULT_CATEGORIES {
            let found = dataStore.getCategory(id: defaultCat.id)
            XCTAssertNotNil(found)
            XCTAssertEqual(found?.name, defaultCat.name)
            XCTAssertEqual(found?.type, defaultCat.type)
            XCTAssertEqual(found?.icon, defaultCat.icon)
            XCTAssertTrue(found?.isDefault == true)
        }
    }

    func testDeleteAllDataIsIdempotent() {
        dataStore.deleteAllData()
        dataStore.deleteAllData()

        XCTAssertEqual(dataStore.projects.count, 0)
        XCTAssertEqual(dataStore.transactions.count, 0)
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
        XCTAssertEqual(dataStore.categories.count, DEFAULT_CATEGORIES.count)
    }
}
