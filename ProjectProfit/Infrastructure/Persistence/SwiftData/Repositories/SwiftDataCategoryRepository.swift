import Foundation
import SwiftData

@MainActor
final class SwiftDataCategoryRepository: CategoryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func categories() throws -> [PPCategory] {
        try modelContext.fetch(FetchDescriptor<PPCategory>())
    }

    func category(id: String) throws -> PPCategory? {
        let predicate = #Predicate<PPCategory> { $0.id == id }
        let descriptor = FetchDescriptor<PPCategory>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    func transactions(categoryId: String) throws -> [PPTransaction] {
        let predicate = #Predicate<PPTransaction> { $0.categoryId == categoryId }
        let descriptor = FetchDescriptor<PPTransaction>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }

    func recurringTransactions(categoryId: String) throws -> [PPRecurringTransaction] {
        let predicate = #Predicate<PPRecurringTransaction> { $0.categoryId == categoryId }
        let descriptor = FetchDescriptor<PPRecurringTransaction>(predicate: predicate)
        return try modelContext.fetch(descriptor)
    }

    func insert(_ category: PPCategory) {
        modelContext.insert(category)
    }

    func delete(_ category: PPCategory) {
        modelContext.delete(category)
    }

    func saveChanges() throws {
        try modelContext.save()
    }
}
