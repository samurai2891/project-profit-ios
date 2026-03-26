import SwiftUI
import SwiftData

// MARK: - ProjectsViewModel

@MainActor
@Observable
final class ProjectsViewModel {
    var filterStatus: FilterStatus = .all
    private let projectQueryUseCase: ProjectQueryUseCase
    private let projectWorkflowUseCase: ProjectWorkflowUseCase
    private(set) var listSnapshot: ProjectListSnapshot = .empty

    init(modelContext: ModelContext) {
        self.projectQueryUseCase = ProjectQueryUseCase(modelContext: modelContext)
        self.projectWorkflowUseCase = ProjectWorkflowUseCase(modelContext: modelContext)
        self.listSnapshot = projectQueryUseCase.listSnapshot()
    }

    // MARK: - Computed Properties

    /// アーカイブ済み以外のプロジェクト
    private var activeProjects: [PPProject] {
        listSnapshot.activeProjects
    }

    /// アーカイブ済みプロジェクト
    private var archivedProjects: [PPProject] {
        listSnapshot.archivedProjects
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
        reload()
    }

    func deleteProjects(ids: Set<UUID>) {
        projectWorkflowUseCase.deleteProjects(ids: ids)
        reload()
    }

    func getProjectSummary(projectId: UUID) -> ProjectSummary? {
        listSnapshot.summariesById[projectId]
    }

    func reload() {
        listSnapshot = projectQueryUseCase.listSnapshot()
    }
}
