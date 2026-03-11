import Foundation

struct CategoryCreateInput: Equatable, Sendable {
    let name: String
    let type: CategoryType
    let icon: String
}

struct CategoryUpdateInput: Equatable, Sendable {
    let name: String?
    let type: CategoryType?
    let icon: String?
}

@MainActor
struct CategoryWorkflowUseCase {
    private let dataStore: DataStore
    private let categoryRepository: any CategoryRepository

    init(
        dataStore: DataStore,
        categoryRepository: (any CategoryRepository)? = nil
    ) {
        self.dataStore = dataStore
        self.categoryRepository = categoryRepository ?? SwiftDataCategoryRepository(modelContext: dataStore.modelContext)
    }

    @discardableResult
    func createCategory(input: CategoryCreateInput) -> PPCategory {
        if let existing = dataStore.categories.first(where: {
            $0.type == input.type && $0.name == input.name
        }) {
            return existing
        }

        let category = PPCategory(
            id: UUID().uuidString,
            name: input.name,
            type: input.type,
            icon: input.icon
        )
        categoryRepository.insert(category)
        dataStore.save()
        dataStore.refreshCategories()
        return category
    }

    @discardableResult
    func updateCategory(id: String, input: CategoryUpdateInput) -> Bool {
        let category: PPCategory
        do {
            guard let fetched = try categoryRepository.category(id: id) else {
                return false
            }
            category = fetched
        } catch {
            return false
        }

        if let name = input.name {
            let targetType = input.type ?? category.type
            if dataStore.categories.contains(where: {
                $0.id != id && $0.type == targetType && $0.name == name
            }) {
                return false
            }
            category.name = name
        }
        if let type = input.type {
            category.type = type
        }
        if let icon = input.icon {
            category.icon = icon
        }

        guard dataStore.save() else {
            return false
        }
        dataStore.refreshCategories()
        return true
    }

    @discardableResult
    func updateLinkedAccount(categoryId: String, accountId: String?) -> Bool {
        let category: PPCategory
        do {
            guard let fetched = try categoryRepository.category(id: categoryId) else {
                return false
            }
            category = fetched
        } catch {
            return false
        }

        category.linkedAccountId = accountId
        guard dataStore.save() else {
            return false
        }
        dataStore.refreshCategories()
        return true
    }

    @discardableResult
    func archiveCategory(id: String) -> Bool {
        setArchived(id: id, archivedAt: Date())
    }

    @discardableResult
    func unarchiveCategory(id: String) -> Bool {
        setArchived(id: id, archivedAt: nil)
    }

    @discardableResult
    func deleteCategory(id: String) -> Bool {
        let category: PPCategory
        do {
            guard let fetched = try categoryRepository.category(id: id) else {
                return false
            }
            category = fetched
        } catch {
            return false
        }

        guard !category.isDefault else {
            return false
        }

        let fallbackId: String = switch category.type {
        case .expense:
            "cat-other-expense"
        case .income:
            "cat-other-income"
        }

        let now = Date()
        for transaction in dataStore.transactions where transaction.categoryId == id {
            transaction.categoryId = fallbackId
            transaction.updatedAt = now
        }
        for recurring in dataStore.recurringTransactions where recurring.categoryId == id {
            recurring.categoryId = fallbackId
            recurring.updatedAt = now
        }

        categoryRepository.delete(category)
        guard dataStore.save() else {
            return false
        }

        dataStore.refreshCategories()
        dataStore.refreshTransactions()
        dataStore.refreshRecurring()
        return true
    }

    @discardableResult
    private func setArchived(id: String, archivedAt: Date?) -> Bool {
        let category: PPCategory
        do {
            guard let fetched = try categoryRepository.category(id: id) else {
                return false
            }
            category = fetched
        } catch {
            return false
        }

        category.archivedAt = archivedAt
        guard dataStore.save() else {
            return false
        }
        dataStore.refreshCategories()
        return true
    }
}
