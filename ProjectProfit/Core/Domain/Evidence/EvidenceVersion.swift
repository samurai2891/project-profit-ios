import Foundation

/// 証憑の変更履歴バージョン
struct EvidenceVersion: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let evidenceId: UUID
    let changedAt: Date
    let changedBy: String
    let previousStructuredFields: EvidenceStructuredFields?
    let nextStructuredFields: EvidenceStructuredFields
    let reason: String
    let modelSource: ModelSource

    init(
        id: UUID = UUID(),
        evidenceId: UUID,
        changedAt: Date = Date(),
        changedBy: String,
        previousStructuredFields: EvidenceStructuredFields? = nil,
        nextStructuredFields: EvidenceStructuredFields,
        reason: String,
        modelSource: ModelSource
    ) {
        self.id = id
        self.evidenceId = evidenceId
        self.changedAt = changedAt
        self.changedBy = changedBy
        self.previousStructuredFields = previousStructuredFields
        self.nextStructuredFields = nextStructuredFields
        self.reason = reason
        self.modelSource = modelSource
    }
}
