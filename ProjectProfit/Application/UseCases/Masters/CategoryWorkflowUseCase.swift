import Foundation
import SwiftData

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
    private let categoryRepository: any CategoryRepository

    init(
        modelContext: ModelContext,
        categoryRepository: (any CategoryRepository)? = nil
    ) {
        self.categoryRepository = categoryRepository ?? SwiftDataCategoryRepository(modelContext: modelContext)
    }

    @discardableResult
    func createCategory(input: CategoryCreateInput) throws -> PPCategory {
        do {
            if let existing = try categoryRepository.categories().first(where: {
                $0.type == input.type && $0.name == input.name
            }) {
                return existing
            }
        } catch {
            throw AppError.dataLoadFailed(underlying: error)
        }

        let category = PPCategory(
            id: UUID().uuidString,
            name: input.name,
            type: input.type,
            icon: input.icon
        )
        categoryRepository.insert(category)
        do {
            try categoryRepository.saveChanges()
            return category
        } catch {
            AppLogger.dataStore.error("Failed to save category create: \(error.localizedDescription)")
            categoryRepository.delete(category)
            do {
                try categoryRepository.saveChanges()
            } catch let rollbackError {
                AppLogger.dataStore.error("Failed to rollback category create: \(rollbackError.localizedDescription)")
                throw AppError.saveFailed(underlying: rollbackSaveError(saveError: error, rollbackError: rollbackError))
            }
            throw AppError.saveFailed(underlying: error)
        }
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
            let categories = (try? categoryRepository.categories()) ?? []
            if categories.contains(where: {
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

        do {
            try categoryRepository.saveChanges()
        } catch {
            return false
        }
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
        do {
            try categoryRepository.saveChanges()
        } catch {
            return false
        }
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
        let transactions = (try? categoryRepository.transactions(categoryId: id)) ?? []
        for transaction in transactions {
            transaction.categoryId = fallbackId
            transaction.updatedAt = now
        }
        let recurrings = (try? categoryRepository.recurringTransactions(categoryId: id)) ?? []
        for recurring in recurrings {
            recurring.categoryId = fallbackId
            recurring.updatedAt = now
        }

        categoryRepository.delete(category)
        do {
            try categoryRepository.saveChanges()
        } catch {
            return false
        }
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
        do {
            try categoryRepository.saveChanges()
        } catch {
            return false
        }
        return true
    }

    private func rollbackSaveError(saveError: Error, rollbackError: Error) -> NSError {
        NSError(
            domain: "CategoryWorkflowUseCase",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "category save failed and rollback failed",
                NSUnderlyingErrorKey: rollbackError,
                "saveError": saveError,
            ]
        )
    }
}
