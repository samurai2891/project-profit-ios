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
            yearlyProfitLoss: yearlyProjectSummaries(projectId: projectId, startMonth: startMonth),
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
        startMonth: Int
    ) -> [FiscalYearProjectSummary] {
        guard fetchProject(id: projectId) != nil else {
            return []
        }

        let records = canonicalProjectSummaryRecords(projectId: projectId)
        let fiscalYears = Set(records.map { fiscalYear(for: $0.date, startMonth: startMonth) })

        return fiscalYears.sorted().map { year in
            let start = startOfFiscalYear(year, startMonth: startMonth)
            let end = endOfFiscalYear(year, startMonth: startMonth)
            let scopedRecords = records.filter { $0.date >= start && $0.date <= end }
            let income = scopedRecords
                .filter { $0.type == .income }
                .reduce(0) { $0 + $1.amount }
            let expense = scopedRecords
                .filter { $0.type == .expense }
                .reduce(0) { $0 + $1.amount }

            return FiscalYearProjectSummary(
                fiscalYear: year,
                label: fiscalYearLabel(year, startMonth: startMonth),
                income: income,
                expense: expense,
                profit: income - expense
            )
        }
    }

    private struct CanonicalProjectSummaryRecord {
        let date: Date
        let type: TransactionType
        let amount: Int
    }

    private func canonicalProjectSummaryRecords(projectId: UUID) -> [CanonicalProjectSummaryRecord] {
        let accountsById = Dictionary(
            uniqueKeysWithValues: fetchCanonicalAccounts().map { ($0.id, $0) }
        )

        return fetchJournalEntries()
            .filter { $0.approvedAt != nil && $0.entryType == .normal }
            .flatMap { journal in
                journal.lines.compactMap { line -> CanonicalProjectSummaryRecord? in
                    guard line.projectAllocationId == projectId,
                          let account = accountsById[line.accountId]
                    else {
                        return nil
                    }

                    let type: TransactionType?
                    let amount: Int
                    switch account.accountType {
                    case .revenue where line.creditAmount > 0:
                        type = .income
                        amount = NSDecimalNumber(decimal: line.creditAmount).intValue
                    case .expense where line.debitAmount > 0:
                        type = .expense
                        amount = NSDecimalNumber(decimal: line.debitAmount).intValue
                    default:
                        type = nil
                        amount = 0
                    }

                    guard let type, amount != 0 else {
                        return nil
                    }

                    return CanonicalProjectSummaryRecord(
                        date: journal.journalDate,
                        type: type,
                        amount: amount
                    )
                }
            }
    }

    private func fetchCanonicalAccounts() -> [CanonicalAccount] {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(sortBy: [SortDescriptor(\.displayOrder)])
        return (try? modelContext.fetch(descriptor))?.map(CanonicalAccountEntityMapper.toDomain) ?? []
    }

    private func fetchJournalEntries() -> [CanonicalJournalEntry] {
        let descriptor = FetchDescriptor<JournalEntryEntity>(sortBy: [SortDescriptor(\.journalDate)])
        return (try? modelContext.fetch(descriptor))?.map(CanonicalJournalEntryEntityMapper.toDomain) ?? []
    }
}
