import Foundation

/// 監査イベントリポジトリプロトコル
protocol AuditRepository: Sendable {
    func findById(_ id: UUID) async throws -> AuditEvent?
    func findByAggregate(aggregateType: String, aggregateId: UUID) async throws -> [AuditEvent]
    func findByBusiness(businessId: UUID, limit: Int) async throws -> [AuditEvent]
    func findByDateRange(businessId: UUID, from: Date, to: Date) async throws -> [AuditEvent]
    func save(_ event: AuditEvent) async throws
}
