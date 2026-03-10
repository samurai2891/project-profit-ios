import Foundation
import SwiftData

@MainActor
final class SwiftDataProjectRepository: ProjectRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func project(id: UUID) throws -> PPProject? {
        let predicate = #Predicate<PPProject> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    func projects(ids: Set<UUID>) throws -> [PPProject] {
        guard !ids.isEmpty else {
            return []
        }
        let descriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt)])
        return try modelContext.fetch(descriptor).filter { ids.contains($0.id) }
    }

    func insert(_ project: PPProject) {
        modelContext.insert(project)
    }

    func delete(_ project: PPProject) {
        modelContext.delete(project)
    }
}
