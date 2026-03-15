import Foundation
import SwiftData

@MainActor
struct TransactionHistoryUseCase {
    private let repository: any TransactionHistoryRepository
    private let exportModelContext: ModelContext?

    init(repository: any TransactionHistoryRepository) {
        self.repository = repository
        self.exportModelContext = nil
    }

    init(modelContext: ModelContext) {
        self.repository = SwiftDataTransactionHistoryRepository(modelContext: modelContext)
        self.exportModelContext = modelContext
    }

    func allTransactions() -> [PPTransaction] {
        (try? repository.allTransactions()) ?? []
    }

    func filteredTransactions(filter: TransactionFilter, sort: TransactionSort? = nil) -> [PPTransaction] {
        (try? repository.filteredTransactions(filter: filter, sort: sort)) ?? []
    }

    func categoryName(for categoryId: String) -> String {
        (try? repository.category(id: categoryId))?.name ?? "未分類"
    }

    func categoryIcon(for categoryId: String) -> String {
        (try? repository.category(id: categoryId))?.icon ?? "ellipsis.circle"
    }

    func projectNames(for allocations: [Allocation]) -> [String] {
        allocations.compactMap { allocation in
            guard let project = try? repository.project(id: allocation.projectId) else {
                return nil
            }
            return project.name
        }
    }

    func projectAllocations(for transaction: PPTransaction) -> [(projectId: UUID, name: String, ratio: Int, amount: Int)] {
        transaction.allocations.compactMap { allocation in
            guard let project = try? repository.project(id: allocation.projectId) else {
                return nil
            }
            return (
                projectId: allocation.projectId,
                name: project.name,
                ratio: allocation.ratio,
                amount: allocation.amount
            )
        }
    }

    func recurringDisplayName(for recurringId: UUID) -> String? {
        guard let recurring = try? repository.recurring(id: recurringId) else {
            return nil
        }
        return "\(recurring.name) (\(recurring.frequency.label))"
    }

    func documentCount(for transactionId: UUID) -> Int {
        (try? repository.documentCount(transactionId: transactionId)) ?? 0
    }

    var canMutateLegacyTransactions: Bool {
        !FeatureFlags.useCanonicalPosting
    }

    var legacyMutationDisabledMessage: String {
        AppError.legacyTransactionMutationDisabled.errorDescription ?? "この操作は現在利用できません"
    }

    func exportCSV(transactions: [PPTransaction]) throws -> URL {
        guard let exportModelContext else {
            throw ExportCoordinator.ExportError.dataUnavailable
        }
        let referenceDate = transactions.max(by: { $0.date < $1.date })?.date ?? Date()
        let fiscalYear = fiscalYear(for: referenceDate, startMonth: FiscalYearSettings.startMonth)
        return try ExportCoordinator.export(
            target: .transactions,
            format: .csv,
            fiscalYear: fiscalYear,
            modelContext: exportModelContext,
            transactionOptions: .init(transactions: transactions)
        )
    }
}
