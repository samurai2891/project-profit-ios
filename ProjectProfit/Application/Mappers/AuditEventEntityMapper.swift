import Foundation

/// AuditEvent ↔ AuditEventEntity の変換
enum AuditEventEntityMapper {

    static func toDomain(_ entity: AuditEventEntity) -> AuditEvent {
        AuditEvent(
            id: entity.eventId,
            businessId: entity.businessId,
            eventType: AuditEventType(rawValue: entity.eventTypeRaw) ?? .evidenceModified,
            aggregateType: entity.aggregateType,
            aggregateId: entity.aggregateId,
            beforeStateHash: entity.beforeStateHash,
            afterStateHash: entity.afterStateHash,
            actor: entity.actor,
            createdAt: entity.createdAt,
            reason: entity.reason,
            relatedEvidenceId: entity.relatedEvidenceId,
            relatedJournalId: entity.relatedJournalId
        )
    }

    static func toEntity(_ domain: AuditEvent) -> AuditEventEntity {
        AuditEventEntity(
            eventId: domain.id,
            businessId: domain.businessId,
            eventTypeRaw: domain.eventType.rawValue,
            aggregateType: domain.aggregateType,
            aggregateId: domain.aggregateId,
            beforeStateHash: domain.beforeStateHash,
            afterStateHash: domain.afterStateHash,
            actor: domain.actor,
            createdAt: domain.createdAt,
            reason: domain.reason,
            relatedEvidenceId: domain.relatedEvidenceId,
            relatedJournalId: domain.relatedJournalId
        )
    }
}
