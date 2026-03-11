import Foundation
import SwiftData

struct ProjectUpsertInput: Equatable, Sendable {
    let name: String
    let description: String
    let status: ProjectStatus
    let startDate: Date?
    let completedAt: Date?
    let plannedEndDate: Date?
}

@MainActor
struct ProjectWorkflowUseCase {
    private let workflowStore: ProjectWorkflowStore

    init(
        modelContext: ModelContext,
        projectRepository: (any ProjectRepository)? = nil,
        calendar: Calendar = .current
    ) {
        let projectRepository = projectRepository ?? SwiftDataProjectRepository(modelContext: modelContext)
        self.workflowStore = ProjectWorkflowStore(
            modelContext: modelContext,
            projectRepository: projectRepository,
            calendar: calendar
        )
    }

    @discardableResult
    func createProject(input: ProjectUpsertInput) -> PPProject {
        workflowStore.createProject(input: input)
    }

    func updateProject(id: UUID, input: ProjectUpsertInput) {
        workflowStore.updateProject(id: id, input: input)
    }

    func deleteProject(id: UUID) {
        workflowStore.deleteProject(id: id)
    }

    func deleteProjects(ids: Set<UUID>) {
        workflowStore.deleteProjects(ids: ids)
    }
}
