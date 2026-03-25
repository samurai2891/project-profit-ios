import Foundation

@MainActor
protocol TransactionHistoryRepository {
    func allTransactions() throws -> [PPTransaction]
    func allDisplayTransactions() throws -> [CanonicalTransactionDisplayItem]
    func filteredDisplayTransactions(
        filter: TransactionFilter,
        sort: TransactionSort?
    ) throws -> [CanonicalTransactionDisplayItem]
    func allCategories() throws -> [PPCategory]
    func allProjects() throws -> [PPProject]
    func category(id: String) throws -> PPCategory?
    func project(id: UUID) throws -> PPProject?
    func recurring(id: UUID) throws -> PPRecurringTransaction?
    func documentCount(transactionId: UUID) throws -> Int
}
