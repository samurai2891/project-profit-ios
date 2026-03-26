import Foundation
import SwiftData

@MainActor
final class SwiftDataUserRuleRepository: UserRuleRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allRules() throws -> [PPUserRule] {
        let descriptor = FetchDescriptor<PPUserRule>(
            sortBy: [SortDescriptor(\.priority, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func saveChanges() throws {
        try modelContext.save()
    }
}
