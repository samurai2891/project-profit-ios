import Foundation

@MainActor
protocol TransactionHistoryRepository {
    func allTransactions() throws -> [PPTransaction]
    func filteredTransactions(filter: TransactionFilter, sort: TransactionSort?) throws -> [PPTransaction]
    func allCategories() throws -> [PPCategory]
    func allProjects() throws -> [PPProject]
    func category(id: String) throws -> PPCategory?
    func project(id: UUID) throws -> PPProject?
    func recurring(id: UUID) throws -> PPRecurringTransaction?
    func documentCount(transactionId: UUID) throws -> Int
}
