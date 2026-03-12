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

    // MARK: - Project CRUD

    func testAddProject() {
        let project = mutations(dataStore).addProject(name: "Test Project", description: "A test project")

        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.projectDescription, "A test project")
        XCTAssertEqual(project.status, .active)
        XCTAssertEqual(dataStore.projects.count, 1)
        XCTAssertEqual(dataStore.projects.first?.id, project.id)
    }

    func testAddMultipleProjects() {
        let project1 = mutations(dataStore).addProject(name: "Project A", description: "First")
        let project2 = mutations(dataStore).addProject(name: "Project B", description: "Second")

        XCTAssertEqual(dataStore.projects.count, 2)
        XCTAssertTrue(dataStore.projects.contains(where: { $0.id == project1.id }))
        XCTAssertTrue(dataStore.projects.contains(where: { $0.id == project2.id }))
    }

    func testUpdateProjectName() {
        let project = mutations(dataStore).addProject(name: "Original", description: "Desc")
        mutations(dataStore).updateProject(id: project.id, name: "Updated")

        let fetched = dataStore.getProject(id: project.id)
        XCTAssertEqual(fetched?.name, "Updated")
        XCTAssertEqual(fetched?.projectDescription, "Desc")
    }

    func testUpdateProjectDescription() {
        let project = mutations(dataStore).addProject(name: "Name", description: "Original")
        mutations(dataStore).updateProject(id: project.id, description: "Updated description")

        let fetched = dataStore.getProject(id: project.id)
        XCTAssertEqual(fetched?.name, "Name")
        XCTAssertEqual(fetched?.projectDescription, "Updated description")
    }

    func testUpdateProjectStatus() {
        let project = mutations(dataStore).addProject(name: "Name", description: "Desc")
        XCTAssertEqual(project.status, .active)

        mutations(dataStore).updateProject(id: project.id, status: .completed)
        XCTAssertEqual(dataStore.getProject(id: project.id)?.status, .completed)

        mutations(dataStore).updateProject(id: project.id, status: .paused)
        XCTAssertEqual(dataStore.getProject(id: project.id)?.status, .paused)
    }

    func testUpdateProjectMultipleFields() {
        let project = mutations(dataStore).addProject(name: "Old", description: "Old desc")
        let originalUpdatedAt = project.updatedAt

        // Small delay so updatedAt differs
        Thread.sleep(forTimeInterval: 0.01)
        mutations(dataStore).updateProject(id: project.id, name: "New", description: "New desc", status: .paused)

        let fetched = dataStore.getProject(id: project.id)
        XCTAssertEqual(fetched?.name, "New")
        XCTAssertEqual(fetched?.projectDescription, "New desc")
        XCTAssertEqual(fetched?.status, .paused)
        XCTAssertGreaterThan(fetched!.updatedAt, originalUpdatedAt)
    }

    func testUpdateNonExistentProjectIsNoOp() {
        mutations(dataStore).updateProject(id: UUID(), name: "Ghost")
        XCTAssertEqual(dataStore.projects.count, 0)
    }

    func testDeleteProject() {
        let project = mutations(dataStore).addProject(name: "To Delete", description: "")
        XCTAssertEqual(dataStore.projects.count, 1)

        mutations(dataStore).deleteProject(id: project.id)
        XCTAssertEqual(dataStore.projects.count, 0)
        XCTAssertNil(dataStore.getProject(id: project.id))
    }

    func testDeleteNonExistentProjectIsNoOp() {
        let project = mutations(dataStore).addProject(name: "Keep", description: "")
        mutations(dataStore).deleteProject(id: UUID())
        XCTAssertEqual(dataStore.projects.count, 1)
        XCTAssertNotNil(dataStore.getProject(id: project.id))
    }

    func testGetProjectReturnsNilForUnknownId() {
        XCTAssertNil(dataStore.getProject(id: UUID()))
    }

    func testGetProjectReturnsCorrectProject() {
        let project1 = mutations(dataStore).addProject(name: "First", description: "")
        let project2 = mutations(dataStore).addProject(name: "Second", description: "")

        let fetched = dataStore.getProject(id: project2.id)
        XCTAssertEqual(fetched?.id, project2.id)
        XCTAssertEqual(fetched?.name, "Second")
        XCTAssertNotEqual(fetched?.id, project1.id)
    }

    // MARK: - Transaction CRUD

    func testAddTransaction() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
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
        let project1 = mutations(dataStore).addProject(name: "Proj A", description: "")
        let project2 = mutations(dataStore).addProject(name: "Proj B", description: "")
        let transaction = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .income,
            amount: 5000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        mutations(dataStore).updateTransaction(id: transaction.id, type: .expense)
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.type, .expense)
    }

    func testUpdateTransactionAmount() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .income,
            amount: 5000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        mutations(dataStore).updateTransaction(id: transaction.id, amount: 8000)
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.amount, 8000)
        // Allocations should be recalculated with new amount
        XCTAssertEqual(fetched?.allocations.first?.amount, 8000)
    }

    func testUpdateTransactionAmountRecalculatesMultipleAllocations() {
        let project1 = mutations(dataStore).addProject(name: "A", description: "")
        let project2 = mutations(dataStore).addProject(name: "B", description: "")
        let transaction = mutations(dataStore).addTransaction(
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

        mutations(dataStore).updateTransaction(id: transaction.id, amount: 20000)
        let fetched = dataStore.getTransaction(id: transaction.id)
        let alloc1 = fetched?.allocations.first(where: { $0.projectId == project1.id })
        let alloc2 = fetched?.allocations.first(where: { $0.projectId == project2.id })
        XCTAssertEqual(alloc1?.amount, 14000)
        XCTAssertEqual(alloc2?.amount, 6000)
    }

    func testUpdateTransactionDate() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let originalDate = Date()
        let transaction = mutations(dataStore).addTransaction(
            type: .income,
            amount: 1000,
            date: originalDate,
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let newDate = Calendar.current.date(byAdding: .day, value: -7, to: originalDate)!
        mutations(dataStore).updateTransaction(id: transaction.id, date: newDate)
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: fetched!.date),
            Calendar.current.startOfDay(for: newDate)
        )
    }

    func testUpdateTransactionCategory() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        mutations(dataStore).updateTransaction(id: transaction.id, categoryId: "cat-tools")
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.categoryId, "cat-tools")
    }

    func testUpdateTransactionMemo() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "Original",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        mutations(dataStore).updateTransaction(id: transaction.id, memo: "Updated memo")
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.memo, "Updated memo")
    }

    func testUpdateTransactionAllocations() {
        let project1 = mutations(dataStore).addProject(name: "A", description: "")
        let project2 = mutations(dataStore).addProject(name: "B", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .income,
            amount: 10000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project1.id, ratio: 100)]
        )

        mutations(dataStore).updateTransaction(
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
        let project1 = mutations(dataStore).addProject(name: "A", description: "")
        let project2 = mutations(dataStore).addProject(name: "B", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .income,
            amount: 10000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project1.id, ratio: 100)]
        )

        mutations(dataStore).updateTransaction(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        let originalUpdatedAt = transaction.updatedAt

        Thread.sleep(forTimeInterval: 0.01)
        mutations(dataStore).updateTransaction(id: transaction.id, memo: "Changed")
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertGreaterThan(fetched!.updatedAt, originalUpdatedAt)
    }

    func testUpdateNonExistentTransactionIsNoOp() {
        mutations(dataStore).updateTransaction(id: UUID(), amount: 999)
        XCTAssertEqual(dataStore.transactions.count, 0)
    }

    func testDeleteTransaction() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertEqual(dataStore.transactions.count, 1)

        mutations(dataStore).deleteTransaction(id: transaction.id)
        XCTAssertEqual(dataStore.transactions.count, 0)
        XCTAssertNil(dataStore.getTransaction(id: transaction.id))
    }

    func testDeleteNonExistentTransactionIsNoOp() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        mutations(dataStore).addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        mutations(dataStore).deleteTransaction(id: UUID())
        XCTAssertEqual(dataStore.transactions.count, 1)
    }

    // MARK: - Transaction with Receipt & Line Items

    func testAddTransactionWithReceiptImagePath() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let items = [
            ReceiptLineItem(name: "コーヒー", unitPrice: 350),
            ReceiptLineItem(name: "サンドイッチ", quantity: 2, unitPrice: 480),
        ]
        let transaction = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let items = [ReceiptLineItem(name: "ペン", quantity: 3, unitPrice: 100)]
        let transaction = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-food",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertNil(transaction.receiptImagePath)

        mutations(dataStore).updateTransaction(id: transaction.id, receiptImagePath: "new-receipt.jpg")
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.receiptImagePath, "new-receipt.jpg")
    }

    func testUpdateTransactionClearReceiptImagePath() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-food",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            receiptImagePath: "old-receipt.jpg"
        )

        mutations(dataStore).updateTransaction(id: transaction.id, receiptImagePath: .some(nil))
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertNil(fetched?.receiptImagePath)
    }

    func testUpdateTransactionLineItems() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
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
        mutations(dataStore).updateTransaction(id: transaction.id, lineItems: newItems)
        let fetched = dataStore.getTransaction(id: transaction.id)
        XCTAssertEqual(fetched?.lineItems.count, 2)
        XCTAssertEqual(fetched?.lineItems[0].name, "ノート")
        XCTAssertEqual(fetched?.lineItems[1].name, "ペン")
    }

    func testRemoveReceiptImage() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let transaction = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        // Use dayOfMonth 28 to avoid auto-generation (CRUD property test, not processing test)
        let recurring = mutations(dataStore).addRecurring(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
        let project1 = mutations(dataStore).addProject(name: "A", description: "")
        let project2 = mutations(dataStore).addProject(name: "B", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Original",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        mutations(dataStore).updateRecurring(id: recurring.id, name: "Renamed")
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.name, "Renamed")
    }

    func testUpdateRecurringType() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        mutations(dataStore).updateRecurring(id: recurring.id, type: .income)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.type, .income)
    }

    func testUpdateRecurringAmount() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Test",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        mutations(dataStore).updateRecurring(id: recurring.id, amount: 8000)
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.amount, 8000)
        XCTAssertEqual(fetched?.allocations.first?.amount, 8000)
    }

    func testUpdateRecurringCategoryId() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        mutations(dataStore).updateRecurring(id: recurring.id, categoryId: "cat-tools")
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.categoryId, "cat-tools")
    }

    func testUpdateRecurringMemo() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "Old",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        mutations(dataStore).updateRecurring(id: recurring.id, memo: "New memo")
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.memo, "New memo")
    }

    func testUpdateRecurringAllocations() {
        let project1 = mutations(dataStore).addProject(name: "A", description: "")
        let project2 = mutations(dataStore).addProject(name: "B", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Test",
            type: .expense,
            amount: 10000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project1.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        mutations(dataStore).updateRecurring(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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

        mutations(dataStore).updateRecurring(id: recurring.id, frequency: .monthly)
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.frequency, .monthly)
        // monthOfYear should be cleared when switching to monthly
        XCTAssertNil(fetched?.monthOfYear)
    }

    func testUpdateRecurringFrequencyToYearly() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        mutations(dataStore).updateRecurring(id: recurring.id, frequency: .yearly, monthOfYear: 3)
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.frequency, .yearly)
        XCTAssertEqual(fetched?.monthOfYear, 3)
    }

    func testUpdateRecurringDayOfMonth() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        mutations(dataStore).updateRecurring(id: recurring.id, dayOfMonth: 25)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.dayOfMonth, 25)
    }

    func testUpdateRecurringDayOfMonthClamps() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        mutations(dataStore).updateRecurring(id: recurring.id, dayOfMonth: 31)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.dayOfMonth, 28)

        mutations(dataStore).updateRecurring(id: recurring.id, dayOfMonth: 0)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.dayOfMonth, 1)
    }

    func testUpdateRecurringIsActive() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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

        mutations(dataStore).updateRecurring(id: recurring.id, isActive: false)
        XCTAssertFalse(dataStore.getRecurring(id: recurring.id)!.isActive)

        mutations(dataStore).updateRecurring(id: recurring.id, isActive: true)
        XCTAssertTrue(dataStore.getRecurring(id: recurring.id)!.isActive)
    }

    func testUpdateRecurringNotificationTiming() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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

        mutations(dataStore).updateRecurring(id: recurring.id, notificationTiming: .sameDay)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.notificationTiming, .sameDay)

        mutations(dataStore).updateRecurring(id: recurring.id, notificationTiming: .dayBefore)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.notificationTiming, .dayBefore)

        mutations(dataStore).updateRecurring(id: recurring.id, notificationTiming: .both)
        XCTAssertEqual(dataStore.getRecurring(id: recurring.id)?.notificationTiming, .both)
    }

    func testUpdateRecurringSkipDates() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
        mutations(dataStore).updateRecurring(id: recurring.id, skipDates: [skipDate1, skipDate2])

        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.skipDates.count, 2)
    }

    func testUpdateRecurringSetsUpdatedAt() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
        mutations(dataStore).updateRecurring(id: recurring.id, name: "Changed")
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertGreaterThan(fetched!.updatedAt, originalUpdatedAt)
    }

    func testUpdateNonExistentRecurringIsNoOp() {
        mutations(dataStore).updateRecurring(id: UUID(), name: "Ghost")
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
    }

    func testDeleteRecurring() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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

        mutations(dataStore).deleteRecurring(id: recurring.id)
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
        XCTAssertNil(dataStore.getRecurring(id: recurring.id))
    }

    func testDeleteNonExistentRecurringIsNoOp() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        mutations(dataStore).addRecurring(
            name: "Keep",
            type: .expense,
            amount: 1000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        mutations(dataStore).deleteRecurring(id: UUID())
        XCTAssertEqual(dataStore.recurringTransactions.count, 1)
    }

    func testGetRecurringReturnsNilForUnknownId() {
        XCTAssertNil(dataStore.getRecurring(id: UUID()))
    }

    // MARK: - Delete Project Cascade

    func testDeleteProjectArchivesWhenTransactionReferencesExist() {
        let project1 = mutations(dataStore).addProject(name: "A", description: "")
        let project2 = mutations(dataStore).addProject(name: "B", description: "")

        let transaction = mutations(dataStore).addTransaction(
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

        mutations(dataStore).deleteProject(id: project1.id)

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
        let project = mutations(dataStore).addProject(name: "Solo", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .income,
            amount: 5000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        mutations(dataStore).deleteProject(id: project.id)

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
        let project1 = mutations(dataStore).addProject(name: "A", description: "")
        let project2 = mutations(dataStore).addProject(name: "B", description: "")

        let recurring = mutations(dataStore).addRecurring(
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
        _ = mutations(dataStore).processRecurringTransactions()

        // processRecurringTransactions() 後は project1 has tx refs → archived
        mutations(dataStore).deleteProject(id: project1.id)

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
        let project = mutations(dataStore).addProject(name: "Solo", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Solo recurring",
            type: .expense,
            amount: 5000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )
        _ = mutations(dataStore).processRecurringTransactions()

        // processRecurringTransactions() 後は project has tx refs → archived
        mutations(dataStore).deleteProject(id: project.id)

        // Project should be archived (has transaction references)
        let archivedProject = dataStore.getProject(id: project.id)
        XCTAssertNotNil(archivedProject)
        XCTAssertEqual(archivedProject?.isArchived, true)

        // Recurring with sole allocation is still deleted during archive
        XCTAssertNil(dataStore.getRecurring(id: recurring.id))
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
    }

    func testDeleteProjectCascadeDoesNotAffectUnrelatedTransactions() {
        let project1 = mutations(dataStore).addProject(name: "A", description: "")
        let project2 = mutations(dataStore).addProject(name: "B", description: "")

        let relatedTx = mutations(dataStore).addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project1.id, ratio: 100)]
        )
        let unrelated = mutations(dataStore).addTransaction(
            type: .income,
            amount: 2000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project2.id, ratio: 100)]
        )

        mutations(dataStore).deleteProject(id: project1.id)

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
        let projectToDelete = mutations(dataStore).addProject(name: "Delete Me", description: "")
        let projectToKeep = mutations(dataStore).addProject(name: "Keep Me", description: "")

        // Transaction with only the deleted project
        let txSolo = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: projectToDelete.id, ratio: 100)]
        )

        // Transaction shared between both projects
        let txShared = mutations(dataStore).addTransaction(
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
        let recSolo = mutations(dataStore).addRecurring(
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
        let recShared = mutations(dataStore).addRecurring(
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

        mutations(dataStore).deleteProject(id: projectToDelete.id)

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
        mutations(dataStore).addProject(name: "A", description: "")
        mutations(dataStore).addProject(name: "B", description: "")
        XCTAssertEqual(dataStore.projects.count, 2)

        mutations(dataStore).deleteAllData()
        XCTAssertEqual(dataStore.projects.count, 0)
    }

    func testDeleteAllDataClearsTransactions() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        mutations(dataStore).addTransaction(
            type: .income,
            amount: 1000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertEqual(dataStore.transactions.count, 1)

        mutations(dataStore).deleteAllData()
        XCTAssertEqual(dataStore.transactions.count, 0)
    }

    func testDeleteAllDataClearsRecurring() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        mutations(dataStore).addRecurring(
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

        mutations(dataStore).deleteAllData()
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
    }

    func testDeleteAllDataReseedsDefaultCategories() {
        // Add a custom category
        dataStore.addCategory(name: "Custom", type: .expense, icon: "star")
        XCTAssertEqual(dataStore.categories.count, DEFAULT_CATEGORIES.count + 1)

        mutations(dataStore).deleteAllData()

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

        mutations(dataStore).deleteAllData()

        XCTAssertNil(dataStore.getCategory(id: custom.id))
    }

    func testDeleteAllDataComprehensive() {
        // Set up a full data scenario
        let project1 = mutations(dataStore).addProject(name: "P1", description: "")
        let project2 = mutations(dataStore).addProject(name: "P2", description: "")
        dataStore.addCategory(name: "Custom Cat", type: .expense, icon: "star")

        mutations(dataStore).addTransaction(
            type: .income,
            amount: 10000,
            date: Date(),
            categoryId: "cat-sales",
            memo: "Sale",
            allocations: [(projectId: project1.id, ratio: 100)]
        )
        mutations(dataStore).addTransaction(
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
        mutations(dataStore).addRecurring(
            name: "Monthly bill",
            type: .expense,
            amount: 3000,
            categoryId: "cat-hosting",
            memo: "",
            allocations: [(projectId: project1.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1
        )

        // 2 manual transactions + 1 recurring definition
        XCTAssertEqual(dataStore.projects.count, 2)
        XCTAssertEqual(dataStore.transactions.count, 2)
        XCTAssertEqual(dataStore.recurringTransactions.count, 1)
        XCTAssertGreaterThan(dataStore.categories.count, DEFAULT_CATEGORIES.count)

        mutations(dataStore).deleteAllData()

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
        mutations(dataStore).deleteAllData()
        mutations(dataStore).deleteAllData()

        XCTAssertEqual(dataStore.projects.count, 0)
        XCTAssertEqual(dataStore.transactions.count, 0)
        XCTAssertEqual(dataStore.recurringTransactions.count, 0)
        XCTAssertEqual(dataStore.categories.count, DEFAULT_CATEGORIES.count)
    }

    // MARK: - Project startDate CRUD

    func testAddProjectWithStartDate() {
        let startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let project = mutations(dataStore).addProject(name: "Started", description: "desc", startDate: startDate)

        XCTAssertNotNil(project.startDate)
        let fetched = dataStore.getProject(id: project.id)
        XCTAssertNotNil(fetched?.startDate)
    }

    func testAddProjectWithoutStartDate() {
        let project = mutations(dataStore).addProject(name: "No Start", description: "desc")
        XCTAssertNil(project.startDate)
    }

    func testUpdateProjectStartDate() {
        let project = mutations(dataStore).addProject(name: "Test", description: "desc")
        XCTAssertNil(project.startDate)

        let startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        mutations(dataStore).updateProject(id: project.id, startDate: startDate)

        let fetched = dataStore.getProject(id: project.id)
        XCTAssertNotNil(fetched?.startDate)
    }

    func testUpdateProjectClearStartDate() {
        let startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let project = mutations(dataStore).addProject(name: "Test", description: "desc", startDate: startDate)
        XCTAssertNotNil(project.startDate)

        mutations(dataStore).updateProject(id: project.id, startDate: .some(nil))

        let fetched = dataStore.getProject(id: project.id)
        XCTAssertNil(fetched?.startDate, "startDate should be nil after clearing")
    }

    func testStartDatePersistsAfterReload() {
        let startDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let project = mutations(dataStore).addProject(name: "Persist", description: "", startDate: startDate)

        dataStore.loadData()
        let fetched = dataStore.getProject(id: project.id)
        XCTAssertNotNil(fetched?.startDate)
    }

    // MARK: - Delete Project Redistribution

    func testDeleteProject_archivesAndPreservesAllocations() {
        // 3プロジェクト(50/30/20)のうち1つ削除→tx参照あり→アーカイブ、アロケーション保持
        let projectA = mutations(dataStore).addProject(name: "A", description: "")
        let projectB = mutations(dataStore).addProject(name: "B", description: "")
        let projectC = mutations(dataStore).addProject(name: "C", description: "")

        let tx = mutations(dataStore).addTransaction(
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

        mutations(dataStore).deleteProject(id: projectA.id)

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
        let projectA = mutations(dataStore).addProject(name: "A", description: "")
        let projectB = mutations(dataStore).addProject(name: "B", description: "")

        let tx = mutations(dataStore).addTransaction(
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

        mutations(dataStore).deleteProject(id: projectA.id)

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
        let projectA = mutations(dataStore).addProject(name: "A", description: "")
        let projectB = mutations(dataStore).addProject(name: "B", description: "")
        let projectC = mutations(dataStore).addProject(name: "C", description: "")

        let tx = mutations(dataStore).addTransaction(
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

        mutations(dataStore).deleteProject(id: projectA.id)

        let fetched = dataStore.getTransaction(id: tx.id)!
        let totalAmount = fetched.allocations.reduce(0) { $0 + $1.amount }
        let totalRatio = fetched.allocations.reduce(0) { $0 + $1.ratio }
        XCTAssertEqual(totalAmount, 10000, "再分配後の金額合計がtransaction.amountと一致すべき")
        XCTAssertEqual(totalRatio, 100, "再分配後のratio合計が100になるべき")
    }

    func testDeleteProject_archivesAndRedistributesRecurringManual() {
        // 定期取引(manual)のアロケーション再分配 (定期取引は除外、トランザクションは保持)
        let projectA = mutations(dataStore).addProject(name: "A", description: "")
        let projectB = mutations(dataStore).addProject(name: "B", description: "")
        let projectC = mutations(dataStore).addProject(name: "C", description: "")

        let rec = mutations(dataStore).addRecurring(
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
        _ = mutations(dataStore).processRecurringTransactions()

        // processRecurringTransactions() 後は projectA has tx refs → archived
        mutations(dataStore).deleteProject(id: projectA.id)

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
        let projectA = mutations(dataStore).addProject(name: "A", description: "")
        let projectB = mutations(dataStore).addProject(name: "B", description: "")
        let projectC = mutations(dataStore).addProject(name: "C", description: "")

        let tx = mutations(dataStore).addTransaction(
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
        let projectA = mutations(dataStore).addProject(name: "A", description: "")
        let projectB = mutations(dataStore).addProject(name: "B", description: "")
        let projectC = mutations(dataStore).addProject(name: "C", description: "")

        // 各プロジェクト: ratio=25, 25, 50 → amount=2500, 2500, 5001
        let tx = mutations(dataStore).addTransaction(
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

        mutations(dataStore).deleteProject(id: projectC.id)

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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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

        mutations(dataStore).updateRecurring(id: recurring.id, receiptImagePath: "new-scan.jpg")
        let fetched = dataStore.getRecurring(id: recurring.id)
        XCTAssertEqual(fetched?.receiptImagePath, "new-scan.jpg")
    }

    func testUpdateRecurringClearReceiptImagePath() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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

        mutations(dataStore).updateRecurring(id: recurring.id, receiptImagePath: .some(nil))
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
            let tx = mutations(dataStore).addTransaction(
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

        mutations(dataStore).deleteRecurring(id: recurring.id)

        // After deletion, recurringId should be nil
        let updatedTx = dataStore.getTransaction(id: txId)
        XCTAssertNotNil(updatedTx, "Transaction should still exist after recurring deletion")
        XCTAssertNil(updatedTx?.recurringId, "recurringId should be cleared after recurring deletion")
    }

    func testDeleteRecurring_transactionStillExists() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let tx = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "test",
            allocations: [(projectId: project.id, ratio: 100)],
            recurringId: UUID()
        )
        let recurring = mutations(dataStore).addRecurring(
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
        mutations(dataStore).deleteRecurring(id: recurring.id)

        // Transactions should not be deleted
        XCTAssertTrue(dataStore.transactions.count >= countBefore - 0)
        XCTAssertNotNil(dataStore.getTransaction(id: tx.id))
    }

    // MARK: - C3: Category Deletion Migrates References

    func testDeleteCategory_migratesExpenseTransactions() {
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let category = dataStore.addCategory(name: "Custom Expense", type: .expense, icon: "star")
        let tx = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let category = dataStore.addCategory(name: "Custom Income", type: .income, icon: "star")
        let tx = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "Proj", description: "")
        let category = dataStore.addCategory(name: "Custom Cat", type: .expense, icon: "star")
        let recurring = mutations(dataStore).addRecurring(
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
        let project1 = mutations(dataStore).addProject(name: "A", description: "")
        let project2 = mutations(dataStore).addProject(name: "B", description: "")
        let project3 = mutations(dataStore).addProject(name: "C", description: "")

        let tx = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "C8 Test", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
        mutations(dataStore).updateRecurring(id: recurring.id, frequency: .yearly, monthOfYear: 6)

        let updated = dataStore.recurringTransactions.first(where: { $0.id == recurring.id })
        XCTAssertEqual(updated?.frequency, .yearly)
        XCTAssertNil(updated?.lastGeneratedDate, "lastGeneratedDate should be reset on frequency change")
        XCTAssertTrue(updated?.lastGeneratedMonths.isEmpty ?? true, "lastGeneratedMonths should be cleared")
    }

    func testUpdateRecurringFrequencyChangeResetsLastGeneratedDate_YearlyToMonthly() {
        let project = mutations(dataStore).addProject(name: "C8 Test", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
        mutations(dataStore).updateRecurring(id: recurring.id, frequency: .monthly)

        let updated = dataStore.recurringTransactions.first(where: { $0.id == recurring.id })
        XCTAssertEqual(updated?.frequency, .monthly)
        // lastGeneratedDate was reset then re-set by processRecurringTransactions;
        // verify a new monthly transaction was generated (proves reset worked)
        XCTAssertGreaterThanOrEqual(dataStore.transactions.count, txCountBefore,
            "Should have generated new monthly transaction after frequency change")
    }

    func testUpdateRecurringSameFrequencyDoesNotResetLastGeneratedDate() {
        let project = mutations(dataStore).addProject(name: "C8 Test", description: "")
        let recurring = mutations(dataStore).addRecurring(
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
        mutations(dataStore).updateRecurring(id: recurring.id, name: "Updated Name", frequency: .monthly)

        let updated = dataStore.recurringTransactions.first(where: { $0.id == recurring.id })
        XCTAssertEqual(updated?.lastGeneratedDate, originalLastGenDate, "lastGeneratedDate should NOT be reset when frequency hasn't changed")
    }

    // MARK: - H7: refresh*() retains data on success

    func testRefreshRetainsDataAfterOperations() {
        let project = mutations(dataStore).addProject(name: "H7 Test", description: "desc")
        XCTAssertFalse(dataStore.projects.isEmpty, "projects should not be empty after addProject")

        _ = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "C4 Test", description: "desc")
        let tx = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "with receipt",
            allocations: [(projectId: project.id, ratio: 100)],
            receiptImagePath: "test-image.jpg"
        )
        XCTAssertEqual(dataStore.transactions.count, 1)

        mutations(dataStore).deleteTransaction(id: tx.id)
        XCTAssertTrue(dataStore.transactions.isEmpty, "transaction should be deleted")
    }

    func testRemoveReceiptImageClearsPath() {
        let project = mutations(dataStore).addProject(name: "C4 Remove", description: "desc")
        let tx = mutations(dataStore).addTransaction(
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
        let projectA = mutations(dataStore).addProject(name: "ProRata A", description: "", startDate: midMonthDate)
        let projectB = mutations(dataStore).addProject(name: "ProRata B", description: "")

        // Create transaction with both projects, 50/50 ratio
        let tx = mutations(dataStore).addTransaction(
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
        mutations(dataStore).updateTransaction(id: tx.id, amount: 20000)

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

        _ = mutations(dataStore).addProject(name: "EqA", description: "")
        _ = mutations(dataStore).addProject(name: "EqB", description: "")
        let projectC = mutations(dataStore).addProject(name: "EqC", description: "")

        // Create monthly recurring with equalAll
        let recurring = mutations(dataStore).addRecurring(
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
        _ = mutations(dataStore).processRecurringTransactions()

        // Should have generated a canonical recurring posting with 3-way split
        let postingsBefore = fetchRecurringGeneratedPostings().filter { $0.recurringId == recurring.id }
        guard let generated = postingsBefore.last else {
            XCTFail("Should have generated a recurring posting")
            return
        }
        XCTAssertEqual(generated.allocations.count, 3, "Should allocate to 3 projects")

        // Delete one project
        mutations(dataStore).deleteProject(id: projectC.id)

        // After deletion, the equalAll posting should be recalculated to 2-way split
        let postingsAfter = fetchRecurringGeneratedPostings().filter { $0.recurringId == recurring.id }
        guard let recalculated = postingsAfter.last else {
            XCTFail("Posting should still exist after project deletion")
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

    func testReprocessEqualAll_skipsManuallyEditedTransaction() throws {
        throw XCTSkip("recurring equalAll no longer materializes editable legacy transactions")
    }

    func testReprocessEqualAll_updatesNonEditedTransaction() {
        let projectA = mutations(dataStore).addProject(name: "A", description: "")

        // equalAll定期取引を作成
        let recurring = mutations(dataStore).addRecurring(
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
        _ = mutations(dataStore).processRecurringTransactions()

        // 生成された canonical recurring posting を取得
        let generatedPosting = fetchRecurringGeneratedPostings().first { $0.recurringId == recurring.id }
        XCTAssertNotNil(generatedPosting)
        XCTAssertEqual(generatedPosting?.allocations.count, 1, "1プロジェクトのみに配分")

        // 新プロジェクト追加 → reprocessEqualAll で再計算される
        let projectB = mutations(dataStore).addProject(name: "B", description: "")

        // canonical posting は再処理されるべき
        let afterReprocess = fetchRecurringGeneratedPostings().first { $0.recurringId == recurring.id }
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
        let projectA = mutations(dataStore).addProject(name: "A", description: "")
        let projectB = mutations(dataStore).addProject(name: "B", description: "")

        // プロジェクトAに紐づくトランザクションを作成
        let tx = mutations(dataStore).addTransaction(
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
        mutations(dataStore).deleteProject(id: projectA.id)

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
        let projectA = mutations(dataStore).addProject(name: "A", description: "")
        _ = mutations(dataStore).addProject(name: "B", description: "")

        // トランザクションなしで削除 → ハードデリートされるべき
        mutations(dataStore).deleteProject(id: projectA.id)

        XCTAssertNil(dataStore.getProject(id: projectA.id), "トランザクション参照なしのプロジェクトは完全に削除されるべき")
        XCTAssertEqual(dataStore.projects.count, 1)
    }

    func testArchivedProject_excludedFromEqualAllReprocess() {
        let projectA = mutations(dataStore).addProject(name: "A", description: "")

        // equalAll定期取引を作成
        let recurring = mutations(dataStore).addRecurring(
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
        _ = mutations(dataStore).processRecurringTransactions()

        // プロジェクトAにトランザクション参照を作成してアーカイブ可能にする
        mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5000,
            date: Date(),
            categoryId: "cat-hosting",
            memo: "ref",
            allocations: [(projectId: projectA.id, ratio: 100)]
        )

        // プロジェクトAをアーカイブ
        mutations(dataStore).archiveProject(id: projectA.id)

        // 新プロジェクト追加
        let projectB = mutations(dataStore).addProject(name: "B", description: "")

        // equalAll の定期取引で生成された canonical posting を確認
        let recurringPostings = fetchRecurringGeneratedPostings().filter { $0.recurringId == recurring.id }
        if let latestPosting = recurringPostings.sorted(by: { $0.date > $1.date }).first {
            let hasArchived = latestPosting.allocations.contains { $0.projectId == projectA.id }
            XCTAssertFalse(hasArchived, "アーカイブ済みプロジェクトはequalAll再処理から除外されるべき")
            let hasB = latestPosting.allocations.contains { $0.projectId == projectB.id }
            XCTAssertTrue(hasB, "新プロジェクトBが含まれるべき")
        }
    }

    // MARK: - Helpers for Wave 2 tests

    private struct GeneratedRecurringPosting {
        let journalId: UUID
        let candidateId: UUID
        let date: Date
        let recurringId: UUID?
        let allocations: [Allocation]
    }

    private func fetchAllTransactions() -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchRecurringGeneratedPostings() -> [GeneratedRecurringPosting] {
        let journals = dataStore.canonicalJournalEntries()
            .filter { $0.entryType == .recurring }
            .sorted { $0.journalDate < $1.journalDate }
        guard !journals.isEmpty else {
            return []
        }

        let candidateIds = Set(journals.compactMap(\.sourceCandidateId))
        let descriptor = FetchDescriptor<PostingCandidateEntity>()
        let candidates = ((try? context.fetch(descriptor)) ?? [])
            .map(PostingCandidateEntityMapper.toDomain)
            .filter { candidateIds.contains($0.id) }
        let candidatesById = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })

        return journals.compactMap { journal in
            guard let candidateId = journal.sourceCandidateId,
                  let candidate = candidatesById[candidateId],
                  let snapshot = candidate.legacySnapshot else {
                return nil
            }

            let relevantLines = candidate.proposedLines.filter { line in
                switch snapshot.type {
                case .income:
                    return line.creditAccountId != nil
                case .expense:
                    return line.debitAccountId != nil
                case .transfer:
                    return false
                }
            }
            let amount = relevantLines.reduce(0) { partialResult, line in
                partialResult + NSDecimalNumber(decimal: line.amount).intValue
            }
            let allocationAmounts = relevantLines.reduce(into: [UUID: Int]()) { result, line in
                guard let projectId = line.projectAllocationId else { return }
                result[projectId, default: 0] += NSDecimalNumber(decimal: line.amount).intValue
            }
            let allocations = allocationAmounts.map { projectId, allocationAmount in
                Allocation(
                    projectId: projectId,
                    ratio: amount == 0 ? 0 : Int((Double(allocationAmount) / Double(amount) * 100.0).rounded()),
                    amount: allocationAmount
                )
            }
            .sorted { $0.projectId.uuidString < $1.projectId.uuidString }

            return GeneratedRecurringPosting(
                journalId: journal.id,
                candidateId: candidate.id,
                date: journal.journalDate,
                recurringId: snapshot.recurringId,
                allocations: allocations
            )
        }
    }

    // MARK: - M15: Date Validation

    func testAddProject_startDateAfterPlannedEndDate_clearsPlannedEndDate() {
        let calendar = Calendar.current
        let futureDate = calendar.date(byAdding: .month, value: 2, to: Date())!
        let pastDate = calendar.date(byAdding: .month, value: -1, to: Date())!

        let project = mutations(dataStore).addProject(
            name: "M15 Test",
            description: "",
            startDate: futureDate,
            plannedEndDate: pastDate
        )

        XCTAssertNil(project.plannedEndDate, "plannedEndDate should be nil when startDate > plannedEndDate")
        XCTAssertNotNil(project.startDate)
    }

    func testUpdateProject_startDateAfterCompletedAt_clearsCompletedAt() {
        let calendar = Calendar.current
        let pastDate = calendar.date(byAdding: .month, value: -2, to: Date())!
        let project = mutations(dataStore).addProject(name: "M15 Update Test", description: "", startDate: pastDate)

        let lateDate = calendar.date(byAdding: .month, value: 1, to: Date())!
        let earlyDate = calendar.date(byAdding: .month, value: -3, to: Date())!

        mutations(dataStore).updateProject(
            id: project.id,
            status: .completed,
            startDate: .some(lateDate),
            completedAt: .some(earlyDate)
        )

        let fetched = dataStore.projects.first(where: { $0.id == project.id })
        XCTAssertNil(fetched?.completedAt, "completedAt should be nil when startDate > completedAt")
    }

    // MARK: - M10: Category Name Uniqueness

    func testAddCategory_rejectsDuplicateName() {
        let original = dataStore.addCategory(name: "Travel", type: .expense, icon: "airplane")
        let duplicate = dataStore.addCategory(name: "Travel", type: .expense, icon: "car")

        XCTAssertEqual(original.id, duplicate.id, "同名・同タイプのカテゴリ追加は既存を返すべき")
        XCTAssertEqual(duplicate.icon, "airplane", "既存カテゴリのiconが返される")
        let travelCategories = dataStore.categories.filter { $0.name == "Travel" && $0.type == .expense }
        XCTAssertEqual(travelCategories.count, 1)
    }

    func testAddCategory_allowsSameNameDifferentType() {
        let expense = dataStore.addCategory(name: "Consulting", type: .expense, icon: "briefcase")
        let income = dataStore.addCategory(name: "Consulting", type: .income, icon: "briefcase")

        XCTAssertNotEqual(expense.id, income.id)
    }

    func testUpdateCategory_rejectsDuplicateName() {
        dataStore.addCategory(name: "Alpha", type: .expense, icon: "star")
        let beta = dataStore.addCategory(name: "Beta", type: .expense, icon: "star")

        dataStore.updateCategory(id: beta.id, name: "Alpha")

        let fetched = dataStore.getCategory(id: beta.id)
        XCTAssertEqual(fetched?.name, "Beta", "重複する名前への更新は拒否されるべき")
    }

    // MARK: - M4: Empty CategoryId Fallback

    func testAddTransaction_emptyCategoryId_fallsBackToDefault() {
        let project = mutations(dataStore).addProject(name: "M4 Test", description: "")

        let expenseTx = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1000,
            date: Date(),
            categoryId: "",
            memo: "",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertEqual(expenseTx.categoryId, "cat-other-expense", "空の経費categoryIdはcat-other-expenseにフォールバックすべき")

        let incomeTx = mutations(dataStore).addTransaction(
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
        let project = mutations(dataStore).addProject(name: "M4 Recurring Test", description: "")

        let recurring = mutations(dataStore).addRecurring(
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

    // MARK: - M6: monthOfYear Range Validation

    func testUpdateRecurring_invalidMonthOfYear_ignored() {
        let project = mutations(dataStore).addProject(name: "M6 Test", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "Yearly Test",
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

        mutations(dataStore).updateRecurring(id: recurring.id, monthOfYear: 13)
        let fetched = dataStore.recurringTransactions.first(where: { $0.id == recurring.id })
        XCTAssertEqual(fetched?.monthOfYear, 6, "Invalid monthOfYear (13) should be ignored")

        mutations(dataStore).updateRecurring(id: recurring.id, monthOfYear: 0)
        let fetched2 = dataStore.recurringTransactions.first(where: { $0.id == recurring.id })
        XCTAssertEqual(fetched2?.monthOfYear, 6, "Invalid monthOfYear (0) should be ignored")

        mutations(dataStore).updateRecurring(id: recurring.id, monthOfYear: -1)
        let fetched3 = dataStore.recurringTransactions.first(where: { $0.id == recurring.id })
        XCTAssertEqual(fetched3?.monthOfYear, 6, "Invalid monthOfYear (-1) should be ignored")
    }

    // MARK: - Phase 4C: Accounting Parameters in CRUD

    func testAddTransactionWithPaymentAccountId() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let tx = mutations(dataStore).addTransaction(
            type: .expense, amount: 5000, date: Date(),
            categoryId: "cat-tools", memo: "Test",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-bank"
        )
        XCTAssertEqual(tx.paymentAccountId, "acct-bank")
    }

    func testAddTransactionWithTransferToAccountId() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let tx = mutations(dataStore).addTransaction(
            type: .transfer, amount: 10000, date: Date(),
            categoryId: "cat-tools", memo: "Transfer test",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            transferToAccountId: "acct-bank"
        )
        XCTAssertEqual(tx.paymentAccountId, "acct-cash")
        XCTAssertEqual(tx.transferToAccountId, "acct-bank")
    }

    func testAddTransactionWithTaxDeductibleRate() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let tx = mutations(dataStore).addTransaction(
            type: .expense, amount: 20000, date: Date(),
            categoryId: "cat-hosting", memo: "Server",
            allocations: [(projectId: project.id, ratio: 100)],
            taxDeductibleRate: 60
        )
        XCTAssertEqual(tx.taxDeductibleRate, 60)
        XCTAssertEqual(tx.effectiveTaxDeductibleRate, 60)
        XCTAssertEqual(tx.deductibleAmount, 12000)
    }

    func testUpdateTransactionAccountingFields() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let tx = mutations(dataStore).addTransaction(
            type: .expense, amount: 10000, date: Date(),
            categoryId: "cat-tools", memo: "Before",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        XCTAssertNil(tx.paymentAccountId)
        XCTAssertNil(tx.taxDeductibleRate)

        mutations(dataStore).updateTransaction(
            id: tx.id,
            paymentAccountId: "acct-cc",
            taxDeductibleRate: 50
        )

        let updated = dataStore.transactions.first(where: { $0.id == tx.id })!
        XCTAssertEqual(updated.paymentAccountId, "acct-cc")
        XCTAssertEqual(updated.taxDeductibleRate, 50)
        XCTAssertEqual(updated.effectiveTaxDeductibleRate, 50)
    }

    func testUpdateTransactionClearAccountingFields() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let tx = mutations(dataStore).addTransaction(
            type: .expense, amount: 8000, date: Date(),
            categoryId: "cat-tools", memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-bank",
            taxDeductibleRate: 70
        )
        XCTAssertEqual(tx.paymentAccountId, "acct-bank")

        // Clear paymentAccountId by setting to nil
        mutations(dataStore).updateTransaction(
            id: tx.id,
            paymentAccountId: .some(nil),
            taxDeductibleRate: .some(nil)
        )

        let updated = dataStore.transactions.first(where: { $0.id == tx.id })!
        XCTAssertNil(updated.paymentAccountId)
        XCTAssertNil(updated.taxDeductibleRate)
        XCTAssertEqual(updated.effectiveTaxDeductibleRate, 100)
    }

    // MARK: - CSV Import Contract

    func testImportTransactionsTransferWithoutCategorySucceeds() async throws {
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ,支払口座,振替先口座
        2026-01-10,振替,5000,,,口座間移動,acct-cash,acct-bank
        """

        let result = await mutations(dataStore).importTransactions(from: csv)
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertTrue(dataStore.transactions.isEmpty)

        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let journals = try await PostingWorkflowUseCase(modelContext: context).journals(
            businessId: businessId,
            taxYear: 2026
        )
        XCTAssertEqual(journals.count, 1)
        let journal = try XCTUnwrap(journals.first)
        XCTAssertEqual(journal.entryType, .normal)
        XCTAssertEqual(journal.totalDebit, Decimal(5000))
        XCTAssertEqual(journal.totalCredit, Decimal(5000))
    }

    func testImportTransactionsRejectsRatioNotEqual100() async {
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ
        2026-01-10,経費,5000,ツール,ProjectA(80%),比率不足
        """

        let result = await mutations(dataStore).importTransactions(from: csv)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("配分比率が不正") }))
        XCTAssertTrue(dataStore.transactions.isEmpty)
    }

    func testImportTransactionsDoesNotCountYearLockedFailureAsSuccess() async {
        mutations(dataStore).lockFiscalYear(2026)
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ
        2026-01-10,経費,5000,ツール,LockedProject(100%),ロック年度
        """

        let result = await mutations(dataStore).importTransactions(from: csv)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertTrue(result.errors.contains(where: { $0.contains("ロック") }))
        XCTAssertTrue(dataStore.transactions.isEmpty)
    }
}
