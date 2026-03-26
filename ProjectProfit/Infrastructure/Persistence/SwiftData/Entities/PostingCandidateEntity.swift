import Foundation
import SwiftData

/// SwiftData Entity: 仕訳候補
@Model
final class PostingCandidateEntity {
    @Attribute(.unique) var candidateId: UUID
    var evidenceId: UUID?
    var businessId: UUID
    var taxYear: Int
    var candidateDate: Date
    var counterpartyId: UUID?
    var proposedLinesJSON: String
    var taxAnalysisJSON: String?
    var legacySnapshotJSON: String?
    var confidenceScore: Double
    var statusRaw: String
    var sourceRaw: String
    var memo: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        candidateId: UUID = UUID(),
        evidenceId: UUID? = nil,
        businessId: UUID = UUID(),
        taxYear: Int = 2025,
        candidateDate: Date = Date(),
        counterpartyId: UUID? = nil,
        proposedLinesJSON: String = "[]",
        taxAnalysisJSON: String? = nil,
        legacySnapshotJSON: String? = nil,
        confidenceScore: Double = 0.0,
        statusRaw: String = "draft",
        sourceRaw: String = "manual",
        memo: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.candidateId = candidateId
        self.evidenceId = evidenceId
        self.businessId = businessId
        self.taxYear = taxYear
        self.candidateDate = candidateDate
        self.counterpartyId = counterpartyId
        self.proposedLinesJSON = proposedLinesJSON
        self.taxAnalysisJSON = taxAnalysisJSON
        self.legacySnapshotJSON = legacySnapshotJSON
        self.confidenceScore = confidenceScore
        self.statusRaw = statusRaw
        self.sourceRaw = sourceRaw
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
