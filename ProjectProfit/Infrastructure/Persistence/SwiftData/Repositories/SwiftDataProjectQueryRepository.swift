import Foundation
import SwiftData

@MainActor
final class SwiftDataProjectQueryRepository: ProjectQueryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func listSnapshot() -> ProjectListSnapshot {
        let dataStore = configuredDataStore()
        let activeProjects = dataStore.projects.filter { $0.isArchived != true }
        let archivedProjects = dataStore.projects.filter { $0.isArchived == true }
        let summariesById: [UUID: ProjectSummary] = Dictionary(
            uniqueKeysWithValues: dataStore.projects.compactMap { project in
                guard let summary = dataStore.getProjectSummary(projectId: project.id) else {
                    return nil
                }
                return (project.id, summary)
            }
        )

        return ProjectListSnapshot(
            activeProjects: activeProjects,
            archivedProjects: archivedProjects,
            summariesById: summariesById
        )
    }

    func detailSnapshot(projectId: UUID, startMonth: Int) -> ProjectDetailSnapshot {
        let dataStore = configuredDataStore()
        let project = dataStore.getProject(id: projectId)
        let recentTransactions = dataStore.transactions
            .filter { transaction in
                transaction.allocations.contains(where: { $0.projectId == projectId })
            }
            .sorted { $0.date > $1.date }
        let categoryNamesById = Dictionary(
            uniqueKeysWithValues: dataStore.categories.map { ($0.id, $0.name) }
        )

        return ProjectDetailSnapshot(
            project: project,
            summary: dataStore.getProjectSummary(projectId: projectId),
            recentTransactions: recentTransactions,
            yearlyProfitLoss: dataStore.getYearlyProjectSummaries(projectId: projectId, startMonth: startMonth),
            categoryNamesById: categoryNamesById,
            canMutateLegacyTransactions: dataStore.isLegacyTransactionEditingEnabled,
            legacyTransactionMutationDisabledMessage: dataStore.legacyTransactionMutationDisabledMessage
        )
    }

    private func configuredDataStore() -> DataStore {
        let dataStore = DataStore(modelContext: modelContext)
        dataStore.loadData()
        return dataStore
    }
}
