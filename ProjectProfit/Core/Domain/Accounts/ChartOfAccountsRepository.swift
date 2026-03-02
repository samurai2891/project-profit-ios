import Foundation

/// 勘定科目表リポジトリプロトコル
protocol ChartOfAccountsRepository: Sendable {
    func findById(_ id: UUID) async throws -> CanonicalAccount?
    func findByCode(businessId: UUID, code: String) async throws -> CanonicalAccount?
    func findAllByBusiness(businessId: UUID) async throws -> [CanonicalAccount]
    func findByType(businessId: UUID, accountType: CanonicalAccountType) async throws -> [CanonicalAccount]
    func save(_ account: CanonicalAccount) async throws
    func delete(_ id: UUID) async throws
}
