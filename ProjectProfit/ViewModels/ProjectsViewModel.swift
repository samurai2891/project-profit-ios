import SwiftUI

// MARK: - ProjectsViewModel

@MainActor
@Observable
final class ProjectsViewModel {
    let dataStore: DataStore
    var filterStatus: FilterStatus = .all

    private var projectWorkflowUseCase: ProjectWorkflowUseCase {
        ProjectWorkflowUseCase(dataStore: dataStore)
    }

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    // MARK: - Computed Properties

    /// アーカイブ済み以外のプロジェクト
    private var activeProjects: [PPProject] {
        dataStore.projects.filter { $0.isArchived != true }
    }

    /// アーカイブ済みプロジェクト
    private var archivedProjects: [PPProject] {
        dataStore.projects.filter { $0.isArchived == true }
    }

    var filteredProjects: [PPProject] {
        switch filterStatus {
        case .all:
            return activeProjects
        case .active:
            return activeProjects.filter { $0.status == .active }
        case .completed:
            return activeProjects.filter { $0.status == .completed }
        case .paused:
            return activeProjects.filter { $0.status == .paused }
        case .archived:
            return archivedProjects
        }
    }

    var projectCount: Int {
        filteredProjects.count
    }

    var hasProjects: Bool {
        !activeProjects.isEmpty || !archivedProjects.isEmpty
    }

    // MARK: - Actions

    func deleteProject(id: UUID) {
        projectWorkflowUseCase.deleteProject(id: id)
    }

    func deleteProjects(ids: Set<UUID>) {
        projectWorkflowUseCase.deleteProjects(ids: ids)
    }

    func getProjectSummary(projectId: UUID) -> ProjectSummary? {
        dataStore.getProjectSummary(projectId: projectId)
    }
}
