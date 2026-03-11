import Foundation
import SwiftData

@MainActor
final class SwiftDataTransactionHistoryRepository: TransactionHistoryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allTransactions() throws -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return try modelContext.fetch(descriptor)
    }

    func filteredTransactions(filter: TransactionFilter, sort: TransactionSort?) throws -> [PPTransaction] {
        var result = try allTransactions().filter { transaction in
            if let start = filter.startDate, transaction.date < start { return false }
            if let end = filter.endDate, transaction.date > end { return false }
            if let projectId = filter.projectId,
               !transaction.allocations.contains(where: { $0.projectId == projectId }) {
                return false
            }
            if let categoryId = filter.categoryId, transaction.categoryId != categoryId { return false }
            if let type = filter.type, transaction.type != type { return false }
            if let amountMin = filter.amountMin, transaction.amount < amountMin { return false }
            if let amountMax = filter.amountMax, transaction.amount > amountMax { return false }
            if let counterparty = filter.counterparty, !counterparty.isEmpty {
                guard let value = transaction.counterparty,
                      value.lowercased().contains(counterparty.lowercased()) else {
                    return false
                }
            }
            if !filter.searchText.isEmpty {
                let query = filter.searchText.lowercased()
                let memoMatch = transaction.memo.lowercased().contains(query)
                let counterpartyMatch = transaction.counterparty?.lowercased().contains(query) ?? false
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
                comparison = lhs.amount < rhs.amount
            }
            return sortSpec.order == .desc ? !comparison : comparison
        }
        return result
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
}
