import Foundation
import SwiftData

@MainActor
struct CategoryQueryUseCase {
    private let repository: any CategoryQueryRepository

    init(
        modelContext: ModelContext,
        repository: (any CategoryQueryRepository)? = nil
    ) {
        self.repository = repository ?? SwiftDataCategoryQueryRepository(modelContext: modelContext)
    }

    func snapshot() -> CategorySnapshot {
        (try? repository.snapshot()) ?? .empty
    }

    func categories(
        type: CategoryType,
        archived: Bool,
        searchText: String = "",
        snapshot: CategorySnapshot
    ) -> [PPCategory] {
        let filtered = snapshot.categories.filter {
            $0.type == type && (archived ? $0.archivedAt != nil : $0.archivedAt == nil)
        }
        guard !searchText.isEmpty else { return filtered }
        let query = searchText.lowercased()
        return filtered.filter { $0.name.lowercased().contains(query) }
    }

    func archivedCategories(searchText: String = "", snapshot: CategorySnapshot) -> [PPCategory] {
        let archived = snapshot.categories.filter { $0.archivedAt != nil }
        guard !searchText.isEmpty else { return archived }
        let query = searchText.lowercased()
        return archived.filter { $0.name.lowercased().contains(query) }
    }

    func hasDuplicateName(
        _ name: String,
        type: CategoryType,
        excluding categoryId: String? = nil,
        snapshot: CategorySnapshot
    ) -> Bool {
        snapshot.categories.contains {
            $0.type == type && $0.name == name && $0.id != categoryId
        }
    }

    func accounts(for type: CategoryType, snapshot: CategorySnapshot) -> [PPAccount] {
        let accountType: AccountType = switch type {
        case .expense: .expense
        case .income: .revenue
        }
        return snapshot.accounts
            .filter { $0.accountType == accountType && $0.isActive }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    func linkedAccount(for category: PPCategory, snapshot: CategorySnapshot) -> PPAccount? {
        guard let linkedId = category.linkedAccountId else { return nil }
        return snapshot.accounts.first { $0.id == linkedId }
    }
}
