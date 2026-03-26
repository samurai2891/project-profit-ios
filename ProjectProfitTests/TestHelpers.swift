import SwiftData
@testable import ProjectProfit

enum TestModelContainer {
    @MainActor
    static func create() throws -> ModelContainer {
        FeatureFlags.clearOverrides()
        FeatureFlags.useCanonicalPosting = false
        FeatureFlags.useCanonicalProfileOnly = false
        return try ModelContainerFactory.makeAppContainer(inMemory: true)
    }
}
