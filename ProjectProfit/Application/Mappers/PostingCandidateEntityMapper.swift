import Foundation

/// PostingCandidate ↔ PostingCandidateEntity の変換
enum PostingCandidateEntityMapper {
    static func toDomain(_ entity: PostingCandidateEntity) -> PostingCandidate {
        PostingCandidate(
            id: entity.candidateId,
            evidenceId: entity.evidenceId,
            businessId: entity.businessId,
            taxYear: entity.taxYear,
            candidateDate: entity.candidateDate,
            counterpartyId: entity.counterpartyId,
            proposedLines: CanonicalJSONCoder.decode([PostingCandidateLine].self, from: entity.proposedLinesJSON, fallback: []),
            taxAnalysis: CanonicalJSONCoder.decodeIfPresent(TaxAnalysis.self, from: entity.taxAnalysisJSON),
            confidenceScore: entity.confidenceScore,
            status: CandidateStatus(rawValue: entity.statusRaw) ?? .draft,
            source: CandidateSource(rawValue: entity.sourceRaw) ?? .manual,
            memo: entity.memo,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    static func toEntity(_ domain: PostingCandidate) -> PostingCandidateEntity {
        PostingCandidateEntity(
            candidateId: domain.id,
            evidenceId: domain.evidenceId,
            businessId: domain.businessId,
            taxYear: domain.taxYear,
            candidateDate: domain.candidateDate,
            counterpartyId: domain.counterpartyId,
            proposedLinesJSON: CanonicalJSONCoder.encode(domain.proposedLines, fallback: "[]"),
            taxAnalysisJSON: CanonicalJSONCoder.encodeIfPresent(domain.taxAnalysis),
            confidenceScore: domain.confidenceScore,
            statusRaw: domain.status.rawValue,
            sourceRaw: domain.source.rawValue,
            memo: domain.memo,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    static func update(_ entity: PostingCandidateEntity, from domain: PostingCandidate) {
        entity.evidenceId = domain.evidenceId
        entity.businessId = domain.businessId
        entity.taxYear = domain.taxYear
        entity.candidateDate = domain.candidateDate
        entity.counterpartyId = domain.counterpartyId
        entity.proposedLinesJSON = CanonicalJSONCoder.encode(domain.proposedLines, fallback: "[]")
        entity.taxAnalysisJSON = CanonicalJSONCoder.encodeIfPresent(domain.taxAnalysis)
        entity.confidenceScore = domain.confidenceScore
        entity.statusRaw = domain.status.rawValue
        entity.sourceRaw = domain.source.rawValue
        entity.memo = domain.memo
        entity.updatedAt = domain.updatedAt
    }
}
