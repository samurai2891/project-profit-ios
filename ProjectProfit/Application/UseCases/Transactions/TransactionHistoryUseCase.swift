import Foundation
import SwiftData

@MainActor
struct TransactionHistoryUseCase {
    private let repository: any TransactionHistoryRepository

    init(repository: any TransactionHistoryRepository) {
        self.repository = repository
    }

    init(modelContext: ModelContext) {
        self.init(repository: SwiftDataTransactionHistoryRepository(modelContext: modelContext))
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
        let categoriesById = Dictionary(uniqueKeysWithValues: allCategories().map { ($0.id, $0) })
        let projectsById = Dictionary(uniqueKeysWithValues: allProjects().map { ($0.id, $0) })
        let csv = generateCSV(
            transactions: transactions,
            getCategory: { categoriesById[$0] },
            getProject: { projectsById[$0] }
        )
        guard let data = csv.data(using: .utf8) else {
            throw ExportCoordinator.ExportError.fileWriteFailed
        }

        let referenceDate = transactions.max(by: { $0.date < $1.date })?.date ?? Date()
        let fiscalYear = fiscalYear(for: referenceDate, startMonth: FiscalYearSettings.startMonth)
        let fileName = ExportCoordinator.makeFileName(target: .transactions, fiscalYear: fiscalYear, format: .csv)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func allCategories() -> [PPCategory] {
        (try? repository.allCategories()) ?? []
    }

    private func allProjects() -> [PPProject] {
        (try? repository.allProjects()) ?? []
    }
}
