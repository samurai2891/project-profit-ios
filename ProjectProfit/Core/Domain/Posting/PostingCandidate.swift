import Foundation

struct PostingCandidateLegacySnapshot: Codable, Sendable, Equatable {
    let type: TransactionType
    let categoryId: String
    let recurringId: UUID?
    let paymentAccountId: String?
    let transferToAccountId: String?
    let taxDeductibleRate: Int?
    let taxAmount: Int?
    let taxCodeId: String?
    let taxRate: Int?
    let isTaxIncluded: Bool?
    let taxCategory: TaxCategory?
    let receiptImagePath: String?
    let lineItems: [ReceiptLineItem]
    let counterpartyName: String?
}

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
    let legacySnapshot: PostingCandidateLegacySnapshot?
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
        legacySnapshot: PostingCandidateLegacySnapshot? = nil,
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
        self.legacySnapshot = legacySnapshot
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
            legacySnapshot: self.legacySnapshot,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}
