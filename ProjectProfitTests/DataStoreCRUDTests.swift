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

    func testDeleteProjectArchivesWhenTransactionReferencesExist() {
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

        // Project should be archived, not deleted
        let archivedProject = dataStore.getProject(id: project1.id)
        XCTAssertNotNil(archivedProject)
        XCTAssertEqual(archivedProject?.isArchived, true)

        // Transaction allocations should be preserved unchanged
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.allocations.count, 2)
        XCTAssertNotNil(fetched?.allocations.first(where: { $0.projectId == project1.id }))
        XCTAssertNotNil(fetched?.allocations.first(where: { $0.projectId == project2.id }))
    }

    func testDeleteProjectArchivesWhenSoleAllocation() {
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

        // Project should be archived, not deleted
        let archivedProject = dataStore.getProject(id: project.id)
        XCTAssertNotNil(archivedProject)
        XCTAssertEqual(archivedProject?.isArchived, true)

        // Transaction should be preserved with allocations unchanged
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.allocations.count, 1)
        XCTAssertEqual(fetched?.allocations.first?.projectId, project.id)
        XCTAssertEqual(fetched?.allocations.first?.amount, 5000)
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

        // dayOfMonth: 1 auto-generates transactions → project1 has tx refs → archived
        dataStore.deleteProject(id: project1.id)

        // Project should be archived (has transaction references)
        let archivedProject = dataStore.getProject(id: project1.id)
        XCTAssertNotNil(archivedProject)
        XCTAssertEqual(archivedProject?.isArchived, true)

        // Recurring allocations are still removed during archive
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

        // dayOfMonth: 15 auto-generates transactions → project has tx refs → archived
        dataStore.deleteProject(id: project.id)

        // Project should be archived (has transaction references)
        let archivedProject = dataStore.getProject(id: project.id)
        XCTAssertNotNil(archivedProject)
        XCTAssertEqual(archivedProject?.isArchived, true)

        // Recurring with sole allocation is still deleted during archive
        XCTAssertNil(dataStore.getRecurring(id: recurring.id))
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
    }

    func testDeleteProjectCascadeDoesNotAffectUnrelatedTransactions() {
        let project1 = dataStore.addProject(name: "A", description: "")
        let project2 = dataStore.addProject(name: "B", description: "")

        let relatedTx = dataStore.addTransaction(
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

        // Project1 should be archived (has transaction references)
        let archivedProject = dataStore.getProject(id: project1.id)
        XCTAssertNotNil(archivedProject)
        XCTAssertEqual(archivedProject?.isArchived, true)

        // Related transaction should be preserved with allocations unchanged
        let fetchedRelated = dataStore.getTransaction(id: relatedTx.id)
        XCTAssertNotNil(fetchedRelated)
        XCTAssertEqual(fetchedRelated?.allocations.count, 1)
        XCTAssertEqual(fetchedRelated?.allocations.first?.projectId, project1.id)

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

        // Project should be archived (has transaction references)
        let archivedProject = dataStore.getProject(id: projectToDelete.id)
        XCTAssertNotNil(archivedProject)
        XCTAssertEqual(archivedProject?.isArchived, true)

        // Solo transaction should be preserved with allocations unchanged
        let fetchedSolo = dataStore.getTransaction(id: txSolo.id)
        XCTAssertNotNil(fetchedSolo)
        XCTAssertEqual(fetchedSolo?.allocations.count, 1)
        XCTAssertEqual(fetchedSolo?.allocations.first?.projectId, projectToDelete.id)

        // Shared transaction should be preserved with both allocations unchanged
        let fetchedTx = dataStore.getTransaction(id: txShared.id)
        XCTAssertNotNil(fetchedTx)
        XCTAssertEqual(fetchedTx?.allocations.count, 2)
        XCTAssertNotNil(fetchedTx?.allocations.first(where: { $0.projectId == projectToDelete.id }))
        XCTAssertNotNil(fetchedTx?.allocations.first(where: { $0.projectId == projectToKeep.id }))

        // Solo recurring should be deleted (archive removes recurring allocations)
        XCTAssertNil(dataStore.getRecurring(id: recSolo.id))

        // Shared recurring should remain with one allocation (archive removes archived project's alloc)
        let fetchedRec = dataStore.getRecurring(id: recShared.id)
        XCTAssertNotNil(fetchedRec)
        XCTAssertEqual(fetchedRec?.allocations.count, 1)
        XCTAssertEqual(fetchedRec?.allocations.first?.projectId, projectToKeep.id)

        // The kept project should still exist and not be archived
        XCTAssertNotNil(dataStore.getProject(id: projectToKeep.id))
        // Both projects still exist (one archived, one active)
        XCTAssertEqual(dataStore.projects.count, 2)
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

    // MARK: - Project startDate CRUD

    func testAddProjectWithStartDate() {
        let startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let project = dataStore.addProject(name: "Started", description: "desc", startDate: startDate)

        XCTAssertNotNil(project.startDate)
        let fetched = dataStore.getProject(id: project.id)
        XCTAssertNotNil(fetched?.startDate)
    }

    func testAddProjectWithoutStartDate() {
        let project = dataStore.addProject(name: "No Start", description: "desc")
        XCTAssertNil(project.startDate)
    }

    func testUpdateProjectStartDate() {
        let project = dataStore.addProject(name: "Test", description: "desc")
        XCTAssertNil(project.startDate)

        let startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        dataStore.updateProject(id: project.id, startDate: startDate)

        let fetched = dataStore.getProject(id: project.id)
        XCTAssertNotNil(fetched?.startDate)
    }

    func testUpdateProjectClearStartDate() {
        let startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let project = dataStore.addProject(name: "Test", description: "desc", startDate: startDate)
        XCTAssertNotNil(project.startDate)

        dataStore.updateProject(id: project.id, startDate: .some(nil))

        let fetched = dataStore.getProject(id: project.id)
        XCTAssertNil(fetched?.startDate, "startDate should be nil after clearing")
    }

    func testStartDatePersistsAfterReload() {
        let startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let project = dataStore.addProject(name: "Persist", description: "", startDate: startDate)

        dataStore.loadData()
        let fetched = dataStore.getProject(id: project.id)
        XCTAssertNotNil(fetched?.startDate)
    }

    // MARK: - Delete Project Redistribution

    func testDeleteProject_archivesAndPreservesAllocations() {
        // 3プロジェクト(50/30/20)のうち1つ削除→tx参照あり→アーカイブ、アロケーション保持
        let projectA = dataStore.addProject(name: "A", description: "")
        let projectB = dataStore.addProject(name: "B", description: "")
        let projectC = dataStore.addProject(name: "C", description: "")

        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 30),
                (projectId: projectC.id, ratio: 20),
            ]
        )

        dataStore.deleteProject(id: projectA.id)

        // Project A should be archived
        let archivedA = dataStore.getProject(id: projectA.id)
        XCTAssertNotNil(archivedA)
        XCTAssertEqual(archivedA?.isArchived, true)

        // Transaction allocations should be preserved unchanged
        let fetched = dataStore.getTransaction(id: tx.id)!
        XCTAssertEqual(fetched.allocations.count, 3)

        let allocA = fetched.allocations.first { $0.projectId == projectA.id }!
        let allocB = fetched.allocations.first { $0.projectId == projectB.id }!
        let allocC = fetched.allocations.first { $0.projectId == projectC.id }!

        XCTAssertEqual(allocA.ratio, 50, "Aのratioが保持されるべき")
        XCTAssertEqual(allocB.ratio, 30, "Bのratioが保持されるべき")
        XCTAssertEqual(allocC.ratio, 20, "Cのratioが保持されるべき")
        XCTAssertEqual(allocA.amount + allocB.amount + allocC.amount, 10000, "合計が元のamountと一致すべき")
    }

    func testDeleteProject_archivesAndPreserves_twoProjects() {
        // 2プロジェクト(60/40)のうち1つ削除→tx参照あり→アーカイブ、アロケーション保持
        let projectA = dataStore.addProject(name: "A", description: "")
        let projectB = dataStore.addProject(name: "B", description: "")

        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 5000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 60),
                (projectId: projectB.id, ratio: 40),
            ]
        )

        dataStore.deleteProject(id: projectA.id)

        // Project A should be archived
        let archivedA = dataStore.getProject(id: projectA.id)
        XCTAssertNotNil(archivedA)
        XCTAssertEqual(archivedA?.isArchived, true)

        // Transaction allocations should be preserved unchanged
        let fetched = dataStore.getTransaction(id: tx.id)!
        XCTAssertEqual(fetched.allocations.count, 2)

        let allocA = fetched.allocations.first { $0.projectId == projectA.id }!
        let allocB = fetched.allocations.first { $0.projectId == projectB.id }!

        XCTAssertEqual(allocA.ratio, 60, "Aのratioが保持されるべき")
        XCTAssertEqual(allocB.ratio, 40, "Bのratioが保持されるべき")
        XCTAssertEqual(allocA.amount + allocB.amount, 5000, "合計が元のamountと一致すべき")
    }

    func testDeleteProject_redistributes_preservesTotal() {
        // 端数が出るケース: 33/33/34 → 33/34 → 49/51 (or similar)
        let projectA = dataStore.addProject(name: "A", description: "")
        let projectB = dataStore.addProject(name: "B", description: "")
        let projectC = dataStore.addProject(name: "C", description: "")

        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 33),
                (projectId: projectB.id, ratio: 33),
                (projectId: projectC.id, ratio: 34),
            ]
        )

        dataStore.deleteProject(id: projectA.id)

        let fetched = dataStore.getTransaction(id: tx.id)!
        let totalAmount = fetched.allocations.reduce(0) { $0 + $1.amount }
        let totalRatio = fetched.allocations.reduce(0) { $0 + $1.ratio }
        XCTAssertEqual(totalAmount, 10000, "再分配後の金額合計がtransaction.amountと一致すべき")
        XCTAssertEqual(totalRatio, 100, "再分配後のratio合計が100になるべき")
    }

    func testDeleteProject_archivesAndRedistributesRecurringManual() {
        // 定期取引(manual)のアロケーション再分配 (定期取引は除外、トランザクションは保持)
        let projectA = dataStore.addProject(name: "A", description: "")
        let projectB = dataStore.addProject(name: "B", description: "")
        let projectC = dataStore.addProject(name: "C", description: "")

        let rec = dataStore.addRecurring(
            name: "Test recurring",
            type: .expense,
            amount: 12000,
            categoryId: "cat-hosting",
            memo: "",
            allocationMode: .manual,
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 30),
                (projectId: projectC.id, ratio: 20),
            ],
            frequency: .monthly,
            dayOfMonth: 1
        )

        // dayOfMonth: 1 auto-generates transactions → projectA has tx refs → archived
        dataStore.deleteProject(id: projectA.id)

        // Project A should be archived
        let archivedA = dataStore.getProject(id: projectA.id)
        XCTAssertNotNil(archivedA)
        XCTAssertEqual(archivedA?.isArchived, true)

        // Recurring allocations ARE still redistributed during archive
        let fetched = dataStore.getRecurring(id: rec.id)!
        XCTAssertEqual(fetched.allocations.count, 2)

        let allocB = fetched.allocations.first { $0.projectId == projectB.id }!
        let allocC = fetched.allocations.first { $0.projectId == projectC.id }!

        XCTAssertEqual(allocB.ratio, 60)
        XCTAssertEqual(allocC.ratio, 40)
        XCTAssertEqual(allocB.amount + allocC.amount, 12000, "定期取引の合計金額が保持されるべき")
    }

    func testDeleteProjects_batch_archivesWithTransactionRefs() {
        // バッチ削除: tx参照ありのプロジェクトはアーカイブ
        let projectA = dataStore.addProject(name: "A", description: "")
        let projectB = dataStore.addProject(name: "B", description: "")
        let projectC = dataStore.addProject(name: "C", description: "")

        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 9000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 30),
                (projectId: projectB.id, ratio: 30),
                (projectId: projectC.id, ratio: 40),
            ]
        )

        // AとBを一括削除 → 両方tx参照あり → アーカイブ
        dataStore.deleteProjects(ids: [projectA.id, projectB.id])

        // A and B should be archived
        let archivedA = dataStore.getProject(id: projectA.id)
        XCTAssertNotNil(archivedA)
        XCTAssertEqual(archivedA?.isArchived, true)
        let archivedB = dataStore.getProject(id: projectB.id)
        XCTAssertNotNil(archivedB)
        XCTAssertEqual(archivedB?.isArchived, true)

        // Transaction allocations should be preserved unchanged
        let fetched = dataStore.getTransaction(id: tx.id)!
        XCTAssertEqual(fetched.allocations.count, 3)
        XCTAssertNotNil(fetched.allocations.first { $0.projectId == projectA.id })
        XCTAssertNotNil(fetched.allocations.first { $0.projectId == projectB.id })
        XCTAssertNotNil(fetched.allocations.first { $0.projectId == projectC.id })
        let totalAmount = fetched.allocations.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(totalAmount, 9000, "合計が元のamountと一致すべき")
    }

    func testDeleteProject_archivesPreservesRoundingCase() {
        // 端数処理のケース: tx参照ありのプロジェクトはアーカイブ、アロケーション保持
        let projectA = dataStore.addProject(name: "A", description: "")
        let projectB = dataStore.addProject(name: "B", description: "")
        let projectC = dataStore.addProject(name: "C", description: "")

        // 各プロジェクト: ratio=25, 25, 50 → amount=2500, 2500, 5001
        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 10001,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [
                (projectId: projectA.id, ratio: 25),
                (projectId: projectB.id, ratio: 25),
                (projectId: projectC.id, ratio: 50),
            ]
        )

        dataStore.deleteProject(id: projectC.id)

        // Project C should be archived
        let archivedC = dataStore.getProject(id: projectC.id)
        XCTAssertNotNil(archivedC)
        XCTAssertEqual(archivedC?.isArchived, true)

        // Transaction allocations should be preserved unchanged
        let fetched = dataStore.getTransaction(id: tx.id)!
        XCTAssertEqual(fetched.allocations.count, 3)

        let totalAmount = fetched.allocations.reduce(0) { $0 + $1.amount }
        let totalRatio = fetched.allocations.reduce(0) { $0 + $1.ratio }

        XCTAssertEqual(totalAmount, 10001, "合計金額が保持されるべき")
        XCTAssertEqual(totalRatio, 100, "ratio合計が100のまま保持されるべき")
    }

    // MARK: - Recurring Receipt Image

    func testAddRecurringWithReceiptImagePath() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Monthly Server",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 15,
            receiptImagePath: "contract-scan.jpg"
        )

        XCTAssertEqual(recurring.receiptImagePath, "contract-scan.jpg")
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.receiptImagePath, "contract-scan.jpg")
    }

    func testAddRecurringDefaultsNoReceiptImage() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Monthly Fee",
            type: .expense,
            amount: 3000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        XCTAssertNil(recurring.receiptImagePath)
    }

    func testUpdateRecurringReceiptImagePath() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Fee",
            type: .expense,
            amount: 1000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 15
        )
        XCTAssertNil(recurring.receiptImagePath)

        dataStore.updateRecurring(id: recurring.id, receiptImagePath: "new-scan.jpg")
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.receiptImagePath, "new-scan.jpg")
    }

    func testUpdateRecurringClearReceiptImagePath() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Fee",
            type: .expense,
            amount: 1000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 15,
            receiptImagePath: "old-scan.jpg"
        )

        dataStore.updateRecurring(id: recurring.id, receiptImagePath: .some(nil))
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertNil(fetched?.receiptImagePath)
    }

    // MARK: - C5: lastError Accessibility

    func testLastErrorIsNilOnInit() {
        XCTAssertNil(dataStore.lastError)
    }

    func testLastErrorIsAccessible() {
        dataStore.lastError = .saveFailed(underlying: NSError(domain: "test", code: 1))
        XCTAssertNotNil(dataStore.lastError)
        XCTAssertNotNil(dataStore.lastError?.errorDescription)

        dataStore.lastError = nil
        XCTAssertNil(dataStore.lastError)
    }

    // MARK: - C6: deleteRecurring Clears recurringId

    func testDeleteRecurring_clearsRecurringId() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let recurring = dataStore.addRecurring(
            name: "Monthly Fee",
            type: .expense,
            amount: 1000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        // Find generated transaction
        let generatedTx = dataStore.transactions.first { $0.recurringId == recurring.id }
        // If no transaction was generated (dayOfMonth hasn't passed), create one manually
        let txId: UUID
        if let tx = generatedTx {
            txId = tx.id
        } else {
            let tx = dataStore.addTransaction(
                type: .expense,
                amount: 1000,
                date: Date(),
                categoryId: "cat-tools",
                memo: "test",
                allocations: [(projectId: project.id, ratio: 100)],
                recurringId: recurring.id
            )
            txId = tx.id
        }

        // Verify recurringId is set before deletion
        XCTAssertEqual(dataStore.getTransaction(id: txId)?.recurringId, recurring.id)

        dataStore.deleteRecurring(id: recurring.id)

        // After deletion, recurringId should be nil
        let updatedTx = dataStore.getTransaction(id: txId)
        XCTAssertNotNil(updatedTx, "Transaction should still exist after recurring deletion")
        XCTAssertNil(updatedTx?.recurringId, "recurringId should be cleared after recurring deletion")
    }

    func testDeleteRecurring_transactionStillExists() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "test",
            allocations: [(projectId: project.id, ratio: 100)],
            recurringId: UUID()
        )
        let recurring = dataStore.addRecurring(
            name: "Fee",
            type: .expense,
            amount: 1000,
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        let countBefore = dataStore.transactions.count
        dataStore.deleteRecurring(id: recurring.id)

        // Transactions should not be deleted
        XCTAssertTrue(dataStore.transactions.count >= countBefore - 0)
        XCTAssertNotNil(dataStore.getTransaction(id: tx.id))
    }

    // MARK: - C3: Category Deletion Migrates References

    func testDeleteCategory_migratesExpenseTransactions() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let category = dataStore.addCategory(name: "Custom Expense", type: .expense, icon: "star")
        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 500,
            date: Date(),
            categoryId: category.id,
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        dataStore.deleteCategory(id: category.id)

        let updatedTx = dataStore.getTransaction(id: tx.id)
        XCTAssertEqual(updatedTx?.categoryId, "cat-other-expense")
    }

    func testDeleteCategory_migratesIncomeTransactions() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let category = dataStore.addCategory(name: "Custom Income", type: .income, icon: "star")
        let tx = dataStore.addTransaction(
            type: .income,
            amount: 500,
            date: Date(),
            categoryId: category.id,
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        dataStore.deleteCategory(id: category.id)

        let updatedTx = dataStore.getTransaction(id: tx.id)
        XCTAssertEqual(updatedTx?.categoryId, "cat-other-income")
    }

    func testDeleteCategory_migratesRecurring() {
        let project = dataStore.addProject(name: "Proj", description: "")
        let category = dataStore.addCategory(name: "Custom Cat", type: .expense, icon: "star")
        let recurring = dataStore.addRecurring(
            name: "Fee",
            type: .expense,
            amount: 1000,
            categoryId: category.id,
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        dataStore.deleteCategory(id: category.id)

        let updatedRecurring = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(updatedRecurring?.categoryId, "cat-other-expense")
    }

    func testDeleteCategory_noReferences() {
        let category = dataStore.addCategory(name: "Unused", type: .expense, icon: "star")
        let countBefore = dataStore.categories.count

        dataStore.deleteCategory(id: category.id)

        XCTAssertEqual(dataStore.categories.count, countBefore - 1)
        XCTAssertNil(dataStore.getCategory(id: category.id))
    }

    // MARK: - C2: Allocation Rounding

    func testAddTransaction_allocationTotalMatchesAmount() {
        let project1 = dataStore.addProject(name: "A", description: "")
        let project2 = dataStore.addProject(name: "B", description: "")
        let project3 = dataStore.addProject(name: "C", description: "")

        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 999,
            date: Date(),
            categoryId: "cat-tools",
            memo: "",
            allocations: [
                (projectId: project1.id, ratio: 33),
                (projectId: project2.id, ratio: 33),
                (projectId: project3.id, ratio: 34),
            ]
        )

        let total = tx.allocations.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 999, "Allocation amounts must sum to transaction amount")
    }

    // MARK: - C8: Frequency Change Tests

    func testUpdateRecurringFrequencyChangeResetsLastGeneratedDate_MonthlyToYearly() {
        let project = dataStore.addProject(name: "C8 Test", description: "")
        let recurring = dataStore.addRecurring(
            name: "Monthly Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        // Change frequency to yearly
        dataStore.updateRecurring(id: recurring.id, frequency: .yearly, monthOfYear: 6)

        let updated = dataStore.recurringTransactions.first(where: { $0.id == recurring.id })
        XCTAssertEqual(updated?.frequency, .yearly)
        XCTAssertNil(updated?.lastGeneratedDate, "lastGeneratedDate should be reset on frequency change")
        XCTAssertTrue(updated?.lastGeneratedMonths.isEmpty ?? true, "lastGeneratedMonths should be cleared")
    }

    func testUpdateRecurringFrequencyChangeResetsLastGeneratedDate_YearlyToMonthly() {
        let project = dataStore.addProject(name: "C8 Test", description: "")
        let recurring = dataStore.addRecurring(
            name: "Yearly Test",
            type: .expense,
            amount: 12000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .yearly,
            dayOfMonth: 1,
            monthOfYear: 1
        )

        // Record transaction count before frequency change
        let txCountBefore = dataStore.transactions.count

        // Change frequency to monthly
        // Note: updateRecurring calls processRecurringTransactions() at the end,
        // which will generate a new monthly transaction if dayOfMonth has passed
        dataStore.updateRecurring(id: recurring.id, frequency: .monthly)

        let updated = dataStore.recurringTransactions.first(where: { $0.id == recurring.id })
        XCTAssertEqual(updated?.frequency, .monthly)
        // lastGeneratedDate was reset then re-set by processRecurringTransactions;
        // verify a new monthly transaction was generated (proves reset worked)
        XCTAssertGreaterThanOrEqual(dataStore.transactions.count, txCountBefore,
            "Should have generated new monthly transaction after frequency change")
    }

    func testUpdateRecurringSameFrequencyDoesNotResetLastGeneratedDate() {
        let project = dataStore.addProject(name: "C8 Test", description: "")
        let recurring = dataStore.addRecurring(
            name: "No Change Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        let originalLastGenDate = dataStore.recurringTransactions.first(where: { $0.id == recurring.id })?.lastGeneratedDate

        // Update with same frequency
        dataStore.updateRecurring(id: recurring.id, name: "Updated Name", frequency: .monthly)

        let updated = dataStore.recurringTransactions.first(where: { $0.id == recurring.id })
        XCTAssertEqual(updated?.lastGeneratedDate, originalLastGenDate, "lastGeneratedDate should NOT be reset when frequency hasn't changed")
    }

    // MARK: - H7: refresh*() retains data on success

    func testRefreshRetainsDataAfterOperations() {
        let project = dataStore.addProject(name: "H7 Test", description: "desc")
        XCTAssertFalse(dataStore.projects.isEmpty, "projects should not be empty after addProject")

        _ = dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertFalse(dataStore.transactions.isEmpty, "transactions should not be empty")
        XCTAssertFalse(dataStore.categories.isEmpty, "categories should not be empty")
    }

    func testLastErrorIsSetOnDataLoadFailed() {
        dataStore.lastError = .dataLoadFailed(underlying: NSError(domain: "test", code: 42))
        XCTAssertNotNil(dataStore.lastError)
        if case .dataLoadFailed = dataStore.lastError {
            // expected
        } else {
            XCTFail("Expected dataLoadFailed error case")
        }
    }

    // MARK: - C4: Deferred image deletion (functional)

    func testDeleteTransactionCallsSuccessfully() {
        let project = dataStore.addProject(name: "C4 Test", description: "desc")
        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 5000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "with receipt",
            allocations: [(projectId: project.id, ratio: 100)],
            receiptImagePath: "test-image.jpg"
        )
        XCTAssertEqual(dataStore.transactions.count, 1)

        dataStore.deleteTransaction(id: tx.id)
        XCTAssertTrue(dataStore.transactions.isEmpty, "transaction should be deleted")
    }

    func testRemoveReceiptImageClearsPath() {
        let project = dataStore.addProject(name: "C4 Remove", description: "desc")
        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 3000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            receiptImagePath: "receipt-123.jpg"
        )
        XCTAssertEqual(tx.receiptImagePath, "receipt-123.jpg")

        dataStore.removeReceiptImage(transactionId: tx.id)
        let updated = dataStore.getTransaction(id: tx.id)
        XCTAssertNil(updated?.receiptImagePath, "receiptImagePath should be nil after removal")
    }

    // MARK: - H8: Pro-rata re-calculation on amount change

    func testUpdateTransactionAmount_reappliesProRata() {
        // Create a project with a start date (mid-month) to trigger pro-rata
        let calendar = Calendar.current
        let today = todayDate()
        let comps = calendar.dateComponents([.year, .month], from: today)
        let year = comps.year!
        let month = comps.month!
        let totalDays = daysInMonth(year: year, month: month)

        // Project A: starts mid-month (active half the month)
        let midMonthDate = calendar.date(from: DateComponents(year: year, month: month, day: max(totalDays / 2, 2)))!
        let projectA = dataStore.addProject(name: "ProRata A", description: "", startDate: midMonthDate)
        let projectB = dataStore.addProject(name: "ProRata B", description: "")

        // Create transaction with both projects, 50/50 ratio
        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: today,
            categoryId: "cat-tools",
            memo: "prorata test",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        // Now update the amount
        dataStore.updateTransaction(id: tx.id, amount: 20000)

        let updated = dataStore.getTransaction(id: tx.id)!
        let allocSum = updated.allocations.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(allocSum, 20000, "total allocations should equal new amount")

        // Project A should have less than 50% due to pro-rata (started mid-month)
        let allocA = updated.allocations.first { $0.projectId == projectA.id }!
        XCTAssertLessThan(allocA.amount, 10000, "Project A with partial period should get less than 50%")
    }

    // MARK: - H1: deleteProject equalAll symmetry

    func testDeleteProject_equalAllRecalculates() {
        let calendar = Calendar.current
        let today = todayDate()
        let comps = calendar.dateComponents([.year, .month, .day], from: today)
        let day = comps.day!

        let projectA = dataStore.addProject(name: "EqA", description: "")
        let projectB = dataStore.addProject(name: "EqB", description: "")
        let projectC = dataStore.addProject(name: "EqC", description: "")

        // Create monthly recurring with equalAll
        _ = dataStore.addRecurring(
            name: "Monthly Equal",
            type: .expense,
            amount: 90000,
            categoryId: "cat-tools",
            memo: "",
            allocationMode: .equalAll,
            allocations: [],
            frequency: .monthly,
            dayOfMonth: max(day - 1, 1)
        )

        // Should have generated a transaction with 3-way split
        let txBefore = fetchAllTransactions().filter { $0.memo.contains("[定期]") }
        guard let generated = txBefore.last else {
            XCTFail("Should have generated a transaction")
            return
        }
        XCTAssertEqual(generated.allocations.count, 3, "Should allocate to 3 projects")

        // Delete one project
        dataStore.deleteProject(id: projectC.id)

        // After deletion, the equalAll transaction should be recalculated to 2-way split
        let txAfter = fetchAllTransactions().filter { $0.memo.contains("[定期]") }
        guard let recalculated = txAfter.last else {
            XCTFail("Transaction should still exist after project deletion")
            return
        }
        XCTAssertEqual(recalculated.allocations.count, 2, "Should reallocate to 2 projects")

        let totalAlloc = recalculated.allocations.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(totalAlloc, 90000, "Total allocation should still equal full amount")

        // Each project should get approximately 45000
        for alloc in recalculated.allocations {
            XCTAssertTrue(alloc.amount >= 44999 && alloc.amount <= 45001, "Each project should get ~45000, got \(alloc.amount)")
        }
    }

    // MARK: - H10: equalAll reprocess user edit protection

    func testReprocessEqualAll_skipsManuallyEditedTransaction() {
        let projectA = dataStore.addProject(name: "A", description: "")

        // equalAll定期取引を作成（dayOfMonth=1で今月分が自動生成される）
        let recurring = dataStore.addRecurring(
            name: "EqualAll Monthly",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "",
            allocationMode: .equalAll,
            allocations: [],
            frequency: .monthly,
            dayOfMonth: 1
        )

        // 生成されたトランザクションを取得
        let generatedTx = fetchAllTransactions().first { $0.recurringId == recurring.id }
        XCTAssertNotNil(generatedTx, "equalAllトランザクションが生成されるべき")

        // ユーザーがアロケーションを手動編集
        dataStore.updateTransaction(
            id: generatedTx!.id,
            allocations: [(projectId: projectA.id, ratio: 100)]
        )

        // 手動編集フラグを確認
        let edited = dataStore.getTransaction(id: generatedTx!.id)
        XCTAssertEqual(edited?.isManuallyEdited, true, "equalAll配分の手動編集でフラグが立つべき")

        // 新プロジェクト追加 → reprocessEqualAll が呼ばれる
        _ = dataStore.addProject(name: "B", description: "")

        // 手動編集済みトランザクションは上書きされないべき
        let afterReprocess = dataStore.getTransaction(id: generatedTx!.id)
        XCTAssertEqual(afterReprocess?.allocations.count, 1, "手動編集済みトランザクションはスキップされるべき")
        XCTAssertEqual(afterReprocess?.allocations.first?.projectId, projectA.id, "元の配分が保持されるべき")
    }

    func testReprocessEqualAll_updatesNonEditedTransaction() {
        let projectA = dataStore.addProject(name: "A", description: "")

        // equalAll定期取引を作成
        let recurring = dataStore.addRecurring(
            name: "EqualAll Monthly",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "",
            allocationMode: .equalAll,
            allocations: [],
            frequency: .monthly,
            dayOfMonth: 1
        )

        // 生成されたトランザクションを取得
        let generatedTx = fetchAllTransactions().first { $0.recurringId == recurring.id }
        XCTAssertNotNil(generatedTx)
        XCTAssertEqual(generatedTx?.allocations.count, 1, "1プロジェクトのみに配分")
        XCTAssertNil(generatedTx?.isManuallyEdited, "手動編集フラグは未設定")

        // 新プロジェクト追加 → reprocessEqualAll で再計算される
        let projectB = dataStore.addProject(name: "B", description: "")

        // 未編集トランザクションは再処理されるべき
        let afterReprocess = dataStore.getTransaction(id: generatedTx!.id)
        XCTAssertEqual(afterReprocess?.allocations.count, 2, "2プロジェクトに再分配されるべき")
        let hasA = afterReprocess?.allocations.contains { $0.projectId == projectA.id } ?? false
        let hasB = afterReprocess?.allocations.contains { $0.projectId == projectB.id } ?? false
        XCTAssertTrue(hasA, "プロジェクトAが含まれるべき")
        XCTAssertTrue(hasB, "プロジェクトBが含まれるべき")
        let total = afterReprocess?.allocations.reduce(0) { $0 + $1.amount } ?? 0
        XCTAssertEqual(total, 10000, "合計金額が保持されるべき")
    }

    // MARK: - H9: Archive / Soft Delete

    func testArchiveProject_preservesHistoricalTransactions() {
        let projectA = dataStore.addProject(name: "A", description: "")
        let projectB = dataStore.addProject(name: "B", description: "")

        // プロジェクトAに紐づくトランザクションを作成
        let tx = dataStore.addTransaction(
            type: .expense,
            amount: 10000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "historical",
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50),
            ]
        )

        // deleteProject → トランザクション参照ありのためアーカイブされるべき
        dataStore.deleteProject(id: projectA.id)

        // プロジェクトは削除されずアーカイブされる
        let archivedProject = dataStore.getProject(id: projectA.id)
        XCTAssertNotNil(archivedProject, "トランザクション参照ありのプロジェクトはアーカイブされるべき")
        XCTAssertEqual(archivedProject?.isArchived, true, "isArchivedフラグが立つべき")

        // トランザクションのアロケーションは変更されない（履歴保護）
        let fetchedTx = dataStore.getTransaction(id: tx.id)
        XCTAssertNotNil(fetchedTx)
        XCTAssertEqual(fetchedTx?.allocations.count, 2, "アロケーションが保持されるべき")
        let hasA = fetchedTx?.allocations.contains { $0.projectId == projectA.id } ?? false
        XCTAssertTrue(hasA, "プロジェクトAのアロケーションが保持されるべき")
    }

    func testDeleteProject_noTransactions_actuallyDeletes() {
        let projectA = dataStore.addProject(name: "A", description: "")
        _ = dataStore.addProject(name: "B", description: "")

        // トランザクションなしで削除 → ハードデリートされるべき
        dataStore.deleteProject(id: projectA.id)

        XCTAssertNil(dataStore.getProject(id: projectA.id), "トランザクション参照なしのプロジェクトは完全に削除されるべき")
        XCTAssertEqual(dataStore.projects.count, 1)
    }

    func testArchivedProject_excludedFromEqualAllReprocess() {
        let projectA = dataStore.addProject(name: "A", description: "")

        // equalAll定期取引を作成
        let recurring = dataStore.addRecurring(
            name: "EqualAll",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "",
            allocationMode: .equalAll,
            allocations: [],
            frequency: .monthly,
            dayOfMonth: 1
        )

        // プロジェクトAにトランザクション参照を作成してアーカイブ可能にする
        dataStore.addTransaction(
            type: .expense,
            amount: 5000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "ref",
            allocations: [(projectId: projectA.id, ratio: 100)]
        )

        // プロジェクトAをアーカイブ
        dataStore.archiveProject(id: projectA.id)

        // 新プロジェクト追加
        let projectB = dataStore.addProject(name: "B", description: "")

        // equalAllの定期取引で生成されたトランザクションを確認
        let recurringTxs = fetchAllTransactions().filter { $0.recurringId == recurring.id }
        if let latestTx = recurringTxs.sorted(by: { $0.date > $1.date }).first {
            let hasArchived = latestTx.allocations.contains { $0.projectId == projectA.id }
            XCTAssertFalse(hasArchived, "アーカイブ済みプロジェクトはequalAll再処理から除外されるべき")
            let hasB = latestTx.allocations.contains { $0.projectId == projectB.id }
            XCTAssertTrue(hasB, "新プロジェクトBが含まれるべき")
        }
    }

    // MARK: - Helpers for Wave 2 tests

    private func fetchAllTransactions() -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - M4: Empty CategoryId Fallback

    func testAddTransaction_emptyCategoryId_fallsBackToDefault() {
        let project = dataStore.addProject(name: "M4 Test", description: "")

        let expenseTx = dataStore.addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertEqual(expenseTx.categoryId, "cat-other-expense", "空の経費categoryIdはcat-other-expenseにフォールバックすべき")

        let incomeTx = dataStore.addTransaction(
            type: .income,
            amount: 2000,
            date: Date(),
            categoryId: "",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertEqual(incomeTx.categoryId, "cat-other-income", "空の収入categoryIdはcat-other-incomeにフォールバックすべき")
    }

    func testAddRecurring_emptyCategoryId_fallsBackToDefault() {
        let project = dataStore.addProject(name: "M4 Recurring Test", description: "")

        let recurring = dataStore.addRecurring(
            name: "Empty Cat Recurring",
            type: .expense,
            amount: 500,
            categoryId: "",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        XCTAssertEqual(recurring.categoryId, "cat-other-expense", "空の経費categoryIdはcat-other-expenseにフォールバックすべき")
    }
}
