import Foundation
import SwiftData

/// SwiftData Entity: 監査イベント
@Model
final class AuditEventEntity {
    @Attribute(.unique) var eventId: UUID
    var businessId: UUID
    var eventTypeRaw: String
    var aggregateType: String
    var aggregateId: UUID
    var beforeStateHash: String?
    var afterStateHash: String?
    var actor: String
    var createdAt: Date
    var reason: String?
    var relatedEvidenceId: UUID?
    var relatedJournalId: UUID?

    init(
        eventId: UUID = UUID(),
        businessId: UUID = UUID(),
        eventTypeRaw: String = "",
        aggregateType: String = "",
        aggregateId: UUID = UUID(),
        beforeStateHash: String? = nil,
        afterStateHash: String? = nil,
        actor: String = "",
        createdAt: Date = Date(),
        reason: String? = nil,
        relatedEvidenceId: UUID? = nil,
        relatedJournalId: UUID? = nil
    ) {
        self.eventId = eventId
        self.businessId = businessId
        self.eventTypeRaw = eventTypeRaw
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
