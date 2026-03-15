import Foundation
import SwiftData

@MainActor
final class SwiftDataProjectQueryRepository: ProjectQueryRepository {
    private let modelContext: ModelContext
    private let reportingRepository: SwiftDataReportingRepository

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.reportingRepository = SwiftDataReportingRepository(modelContext: modelContext)
    }

    func listSnapshot() -> ProjectListSnapshot {
        let projects = fetchProjects()
        let summariesById = Dictionary(
            uniqueKeysWithValues: (try? reportingRepository.projectSummaries(startDate: nil, endDate: nil))?
                .map { ($0.id, $0) } ?? []
        )

        return ProjectListSnapshot(
            activeProjects: projects.filter { $0.isArchived != true },
            archivedProjects: projects.filter { $0.isArchived == true },
            summariesById: summariesById
        )
    }

    func detailSnapshot(projectId: UUID, startMonth: Int) -> ProjectDetailSnapshot {
        let project = fetchProject(id: projectId)
        let transactions = fetchTransactions()
        let categories = fetchCategories()
        let summary = (try? reportingRepository.projectSummaries(startDate: nil, endDate: nil))?
            .first { $0.id == projectId }
        let recentTransactions = transactions
            .filter { transaction in
                transaction.allocations.contains(where: { $0.projectId == projectId })
            }
            .sorted { $0.date > $1.date }

        return ProjectDetailSnapshot(
            project: project,
            summary: summary,
            recentTransactions: recentTransactions,
            yearlyProfitLoss: yearlyProjectSummaries(projectId: projectId, startMonth: startMonth, transactions: transactions),
            categoryNamesById: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) }),
            canMutateLegacyTransactions: !FeatureFlags.useCanonicalPosting,
            legacyTransactionMutationDisabledMessage: AppError.legacyTransactionMutationDisabled.errorDescription ?? ""
        )
    }

    private func fetchProjects() -> [PPProject] {
        let descriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchProject(id: UUID) -> PPProject? {
        let descriptor = FetchDescriptor<PPProject>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchTransactions() -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.deletedAt == nil }
    }

    private func fetchCategories() -> [PPCategory] {
        let descriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\.name)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func yearlyProjectSummaries(
        projectId: UUID,
        startMonth: Int,
        transactions: [PPTransaction]
    ) -> [FiscalYearProjectSummary] {
        guard fetchProject(id: projectId) != nil else {
            return []
        }

        let fiscalYears = Set(
            transactions.compactMap { transaction -> Int? in
                guard transaction.allocations.contains(where: { $0.projectId == projectId }) else {
                    return nil
                }
                return fiscalYear(for: transaction.date, startMonth: startMonth)
            }
        )

        return fiscalYears.sorted().map { year in
            let start = startOfFiscalYear(year, startMonth: startMonth)
            let end = endOfFiscalYear(year, startMonth: startMonth)
            var income = 0
            var expense = 0

            for transaction in transactions where transaction.date >= start && transaction.date <= end {
                guard let allocation = transaction.allocations.first(where: { $0.projectId == projectId }) else {
                    continue
                }
                switch transaction.type {
                case .income:
                    income += allocation.amount
                case .expense:
                    expense += allocation.amount
                case .transfer:
                    break
                }
            }

            return FiscalYearProjectSummary(
                fiscalYear: year,
                label: fiscalYearLabel(year, startMonth: startMonth),
                income: income,
                expense: expense,
                profit: income - expense
            )
        }
    }
}
