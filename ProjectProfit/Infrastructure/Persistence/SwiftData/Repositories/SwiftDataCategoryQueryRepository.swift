import Foundation
import SwiftData

@MainActor
final class SwiftDataCategoryQueryRepository: CategoryQueryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func snapshot() throws -> CategorySnapshot {
        let categories = try modelContext.fetch(FetchDescriptor<PPCategory>())
        let accounts = try modelContext.fetch(FetchDescriptor<PPAccount>())
        return CategorySnapshot(
            categories: categories,
            accounts: accounts
        )
    }
}
