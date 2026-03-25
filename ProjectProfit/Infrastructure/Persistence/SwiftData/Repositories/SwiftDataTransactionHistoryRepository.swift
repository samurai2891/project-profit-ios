import Foundation
import SwiftData

@MainActor
final class SwiftDataTransactionHistoryRepository: TransactionHistoryRepository {
    private let modelContext: ModelContext
    private let displayBuilder: CanonicalTransactionDisplayBuilder

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.displayBuilder = CanonicalTransactionDisplayBuilder(modelContext: modelContext)
    }

    func allTransactions() throws -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return try modelContext.fetch(descriptor)
    }

    func allDisplayTransactions() throws -> [CanonicalTransactionDisplayItem] {
        displayBuilder.allDisplayItems()
    }

    func filteredDisplayTransactions(
        filter: TransactionFilter,
        sort: TransactionSort?
    ) throws -> [CanonicalTransactionDisplayItem] {
        var result = try allDisplayTransactions().filter { transaction in
            if let start = filter.startDate, transaction.date < start { return false }
            if let end = filter.endDate, transaction.date > end { return false }
            if let projectId = filter.projectId,
               !transaction.projectAllocations.contains(where: { $0.projectId == projectId }) {
                return false
            }
            if let categoryId = filter.categoryId, transaction.categoryId != categoryId { return false }
            if let type = filter.type, transaction.type != type { return false }

            let comparableAmount = comparableAmount(for: transaction, filter: filter)
            if let amountMin = filter.amountMin, comparableAmount < amountMin { return false }
            if let amountMax = filter.amountMax, comparableAmount > amountMax { return false }

            if let counterparty = normalized(filter.counterparty), !counterparty.isEmpty {
                guard let value = normalized(transaction.counterpartyName),
                      value.contains(counterparty) else {
                    return false
                }
            }
            if let query = normalized(filter.searchText), !query.isEmpty {
                let memoMatch = normalized(transaction.memo)?.contains(query) ?? false
                let counterpartyMatch = normalized(transaction.counterpartyName)?.contains(query) ?? false
                if !memoMatch && !counterpartyMatch { return false }
            }
            return true
        }

        let sortSpec = sort ?? TransactionSort(field: .date, order: .desc)
        result.sort { lhs, rhs in
            let comparison: Bool
            switch sortSpec.field {
            case .date:
                comparison = lhs.date < rhs.date
            case .amount:
                let lhsAmount = comparableAmount(for: lhs, filter: filter)
                let rhsAmount = comparableAmount(for: rhs, filter: filter)
                comparison = lhsAmount < rhsAmount
            }
            return sortSpec.order == .desc ? !comparison : comparison
        }
        return result.map { $0.focused(on: filter.projectId) }
    }

    func allCategories() throws -> [PPCategory] {
        let descriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(descriptor)
    }

    func allProjects() throws -> [PPProject] {
        let descriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try modelContext.fetch(descriptor)
    }

    func category(id: String) throws -> PPCategory? {
        let targetId = id
        let descriptor = FetchDescriptor<PPCategory>(predicate: #Predicate { $0.id == targetId })
        return try modelContext.fetch(descriptor).first
    }

    func project(id: UUID) throws -> PPProject? {
        let targetId = id
        let descriptor = FetchDescriptor<PPProject>(predicate: #Predicate { $0.id == targetId })
        return try modelContext.fetch(descriptor).first
    }

    func recurring(id: UUID) throws -> PPRecurringTransaction? {
        let targetId = id
        let descriptor = FetchDescriptor<PPRecurringTransaction>(predicate: #Predicate { $0.id == targetId })
        return try modelContext.fetch(descriptor).first
    }

    func documentCount(transactionId: UUID) throws -> Int {
        let targetId = transactionId
        let descriptor = FetchDescriptor<PPDocumentRecord>(predicate: #Predicate { $0.transactionId == targetId })
        return try modelContext.fetch(descriptor).count
    }

    private func comparableAmount(
        for transaction: CanonicalTransactionDisplayItem,
        filter: TransactionFilter
    ) -> Int {
        guard let projectId = filter.projectId else {
            return transaction.amount
        }
        return transaction.projectAllocations.first(where: { $0.projectId == projectId })?.amount ?? transaction.amount
    }

    private func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
