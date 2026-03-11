import SwiftUI
import SwiftData

// MARK: - ProjectDetailViewModel

@MainActor
@Observable
final class ProjectDetailViewModel {
    let projectId: UUID
    private let projectQueryUseCase: ProjectQueryUseCase
    private(set) var detailSnapshot: ProjectDetailSnapshot = .empty

    init(modelContext: ModelContext, projectId: UUID) {
        self.projectId = projectId
        self.projectQueryUseCase = ProjectQueryUseCase(modelContext: modelContext)
        self.detailSnapshot = projectQueryUseCase.detailSnapshot(projectId: projectId)
    }

    // MARK: - Computed Properties

    var currentProject: PPProject? {
        detailSnapshot.project
    }

    var summary: ProjectSummary? {
        detailSnapshot.summary
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
        detailSnapshot.recentTransactions
    }

    var yearlyProfitLoss: [FiscalYearProjectSummary] {
        detailSnapshot.yearlyProfitLoss
    }

    var canMutateLegacyTransactions: Bool {
        detailSnapshot.canMutateLegacyTransactions
    }

    var legacyTransactionMutationDisabledMessage: String {
        detailSnapshot.legacyTransactionMutationDisabledMessage
    }

    func getCategoryName(for categoryId: String) -> String {
        detailSnapshot.categoryNamesById[categoryId] ?? "未分類"
    }

    func reload() {
        detailSnapshot = projectQueryUseCase.detailSnapshot(projectId: projectId)
    }
}
