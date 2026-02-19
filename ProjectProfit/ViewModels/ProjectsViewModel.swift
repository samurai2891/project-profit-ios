import SwiftUI

// MARK: - ProjectsViewModel

@MainActor
@Observable
final class ProjectsViewModel {
    let dataStore: DataStore
    var filterStatus: FilterStatus = .all

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    // MARK: - Computed Properties

    var filteredProjects: [PPProject] {
        switch filterStatus {
        case .all:
            return dataStore.projects
        case .active:
            return dataStore.projects.filter { $0.status == .active }
        case .completed:
            return dataStore.projects.filter { $0.status == .completed }
        case .paused:
            return dataStore.projects.filter { $0.status == .paused }
        }
    }

    var projectCount: Int {
        filteredProjects.count
    }

    var hasProjects: Bool {
        !dataStore.projects.isEmpty
    }

    // MARK: - Actions

    func deleteProject(id: UUID) {
        dataStore.deleteProject(id: id)
    }

    func getProjectSummary(projectId: UUID) -> ProjectSummary? {
        dataStore.getProjectSummary(projectId: projectId)
    }
}
