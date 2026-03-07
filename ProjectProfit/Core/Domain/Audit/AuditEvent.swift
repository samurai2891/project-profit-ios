import Foundation

/// 監査イベント（全操作に記録 — Golden Rules）
struct AuditEvent: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let eventType: AuditEventType
    let aggregateType: String
    let aggregateId: UUID
    let beforeStateHash: String?
    let afterStateHash: String?
    let actor: String
    let createdAt: Date
    let reason: String?
    let relatedEvidenceId: UUID?
    let relatedJournalId: UUID?

    init(
        id: UUID = UUID(),
        businessId: UUID,
        eventType: AuditEventType,
        aggregateType: String,
        aggregateId: UUID,
        beforeStateHash: String? = nil,
        afterStateHash: String? = nil,
        actor: String,
        createdAt: Date = Date(),
        reason: String? = nil,
        relatedEvidenceId: UUID? = nil,
        relatedJournalId: UUID? = nil
    ) {
        self.id = id
        self.businessId = businessId
        self.eventType = eventType
        self.aggregateType = aggregateType
        self.aggregateId = aggregateId
        self.beforeStateHash = beforeStateHash
        self.afterStateHash = afterStateHash
        self.actor = actor
        self.createdAt = createdAt
        self.reason = reason
        self.relatedEvidenceId = relatedEvidenceId
        self.relatedJournalId = relatedJournalId
    }
}
