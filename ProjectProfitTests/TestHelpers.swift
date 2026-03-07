import SwiftData
@testable import ProjectProfit

enum TestModelContainer {
    @MainActor
    static func create() throws -> ModelContainer {
        try ModelContainerFactory.makeAppContainer(inMemory: true)
    }
}
