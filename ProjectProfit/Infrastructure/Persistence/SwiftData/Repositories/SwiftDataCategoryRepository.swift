import Foundation
import SwiftData

@MainActor
final class SwiftDataCategoryRepository: CategoryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func category(id: String) throws -> PPCategory? {
        let predicate = #Predicate<PPCategory> { $0.id == id }
        let descriptor = FetchDescriptor<PPCategory>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    func insert(_ category: PPCategory) {
        modelContext.insert(category)
    }

    func delete(_ category: PPCategory) {
        modelContext.delete(category)
    }
}
