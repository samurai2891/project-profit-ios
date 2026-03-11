import Foundation

struct ProjectListSnapshot {
    let activeProjects: [PPProject]
    let archivedProjects: [PPProject]
    let summariesById: [UUID: ProjectSummary]

    static let empty = ProjectListSnapshot(
        activeProjects: [],
        archivedProjects: [],
        summariesById: [:]
    )
}

struct ProjectDetailSnapshot {
    let project: PPProject?
    let summary: ProjectSummary?
    let recentTransactions: [PPTransaction]
    let yearlyProfitLoss: [FiscalYearProjectSummary]
    let categoryNamesById: [String: String]
    let canMutateLegacyTransactions: Bool
    let legacyTransactionMutationDisabledMessage: String

    static let empty = ProjectDetailSnapshot(
        project: nil,
        summary: nil,
        recentTransactions: [],
        yearlyProfitLoss: [],
        categoryNamesById: [:],
        canMutateLegacyTransactions: false,
        legacyTransactionMutationDisabledMessage: AppError.legacyTransactionMutationDisabled.errorDescription ?? ""
    )
}

@MainActor
protocol ProjectQueryRepository {
    func listSnapshot() -> ProjectListSnapshot
    func detailSnapshot(projectId: UUID, startMonth: Int) -> ProjectDetailSnapshot
}
