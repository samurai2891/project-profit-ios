import Foundation

/// 取引先リポジトリプロトコル
protocol CounterpartyRepository: Sendable {
    func findById(_ id: UUID) async throws -> Counterparty?
    func findByBusiness(businessId: UUID) async throws -> [Counterparty]
    func findByName(businessId: UUID, query: String) async throws -> [Counterparty]
    func findByDisplayNamePrefix(businessId: UUID, query: String) async throws -> [Counterparty]
    func findByRegistrationNumber(_ number: String) async throws -> Counterparty?
    func save(_ counterparty: Counterparty) async throws
    func delete(_ id: UUID) async throws
}
