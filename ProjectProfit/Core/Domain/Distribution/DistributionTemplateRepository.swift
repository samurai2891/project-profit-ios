import Foundation

/// 配賦ルールテンプレートリポジトリプロトコル
protocol DistributionTemplateRepository: Sendable {
    func findById(_ id: UUID) async throws -> DistributionRule?
    func findByBusiness(businessId: UUID) async throws -> [DistributionRule]
    func findActive(businessId: UUID, at date: Date) async throws -> [DistributionRule]
    func save(_ rule: DistributionRule) async throws
    func delete(_ id: UUID) async throws
}
