import Foundation

@MainActor
protocol ProjectRepository {
    func project(id: UUID) throws -> PPProject?
    func projects(ids: Set<UUID>) throws -> [PPProject]
    func allProjects() throws -> [PPProject]
    func insert(_ project: PPProject)
    func delete(_ project: PPProject)
    func saveChanges() throws
}
