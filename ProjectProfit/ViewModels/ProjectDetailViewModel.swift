import SwiftUI

// MARK: - ProjectDetailViewModel

@MainActor
@Observable
final class ProjectDetailViewModel {
    let dataStore: DataStore
    let projectId: UUID

    init(dataStore: DataStore, projectId: UUID) {
        self.dataStore = dataStore
        self.projectId = projectId
    }

    // MARK: - Computed Properties

    var currentProject: PPProject? {
        dataStore.projects.first(where: { $0.id == projectId })
    }

    var summary: ProjectSummary? {
        dataStore.getProjectSummary(projectId: projectId)
    }

    var projectIncome: Int {
        summary?.totalIncome ?? 0
    }

    var projectExpense: Int {
        summary?.totalExpense ?? 0
    }

    var projectProfit: Int {
        summary?.profit ?? 0
    }

    var recentTransactions: [PPTransaction] {
        dataStore.transactions
            .filter { t in t.allocations.contains(where: { $0.projectId == projectId }) }
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0 }
    }

    // MARK: - Actions

    func deleteTransaction(id: UUID) {
        dataStore.deleteTransaction(id: id)
    }

    func getCategoryName(for categoryId: String) -> String {
        dataStore.getCategory(id: categoryId)?.name ?? "未分類"
    }
}
