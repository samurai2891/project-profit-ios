import Foundation

struct TransactionFormSnapshot {
    let businessId: UUID?
    let accounts: [PPAccount]
    let activeCategories: [PPCategory]
    let projects: [PPProject]
    let counterparties: [Counterparty]
    let defaultPaymentAccountId: String?
    let isLegacyTransactionEditingEnabled: Bool
    let legacyTransactionMutationDisabledMessage: String
}

@MainActor
protocol TransactionFormRepository {
    func snapshot() throws -> TransactionFormSnapshot
    func legacyAccountId(for canonicalAccountId: UUID) throws -> String?
}
