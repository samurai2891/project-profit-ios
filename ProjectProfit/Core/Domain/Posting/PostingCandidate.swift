import Foundation

/// 仕訳候補（Evidence → Candidate → PostedJournal の中間段階）
/// OCR → 即確定仕訳にしない。必ず Candidate 経由で承認を経る
struct PostingCandidate: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let evidenceId: UUID?
    let businessId: UUID
    let taxYear: Int
    let candidateDate: Date
    let counterpartyId: UUID?
    let proposedLines: [PostingCandidateLine]
    let taxAnalysis: TaxAnalysis?
    let confidenceScore: Double
    let status: CandidateStatus
    let source: CandidateSource
    let memo: String?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        evidenceId: UUID? = nil,
        businessId: UUID,
        taxYear: Int,
        candidateDate: Date,
        counterpartyId: UUID? = nil,
        proposedLines: [PostingCandidateLine] = [],
        taxAnalysis: TaxAnalysis? = nil,
        confidenceScore: Double = 0.0,
        status: CandidateStatus = .draft,
        source: CandidateSource = .manual,
        memo: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.evidenceId = evidenceId
        self.businessId = businessId
        self.taxYear = taxYear
        self.candidateDate = candidateDate
        self.counterpartyId = counterpartyId
        self.proposedLines = proposedLines
        self.taxAnalysis = taxAnalysis
        self.confidenceScore = confidenceScore
        self.status = status
        self.source = source
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// イミュータブル更新
    func updated(
        proposedLines: [PostingCandidateLine]? = nil,
        taxAnalysis: TaxAnalysis?? = nil,
        confidenceScore: Double? = nil,
        status: CandidateStatus? = nil,
        counterpartyId: UUID?? = nil,
        memo: String?? = nil
    ) -> PostingCandidate {
        PostingCandidate(
            id: self.id,
            evidenceId: self.evidenceId,
            businessId: self.businessId,
            taxYear: self.taxYear,
            candidateDate: self.candidateDate,
            counterpartyId: counterpartyId ?? self.counterpartyId,
            proposedLines: proposedLines ?? self.proposedLines,
            taxAnalysis: taxAnalysis ?? self.taxAnalysis,
            confidenceScore: confidenceScore ?? self.confidenceScore,
            status: status ?? self.status,
            source: self.source,
            memo: memo ?? self.memo,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}
