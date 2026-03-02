import Foundation

/// 仕訳候補の明細行
struct PostingCandidateLine: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let debitAccountId: UUID?
    let creditAccountId: UUID?
    let amount: Decimal
    let taxCodeId: String?
    let legalReportLineId: String?
    let projectAllocationId: UUID?
    let memo: String?
    let evidenceLineReferenceId: UUID?

    init(
        id: UUID = UUID(),
        debitAccountId: UUID? = nil,
        creditAccountId: UUID? = nil,
        amount: Decimal,
        taxCodeId: String? = nil,
        legalReportLineId: String? = nil,
        projectAllocationId: UUID? = nil,
        memo: String? = nil,
        evidenceLineReferenceId: UUID? = nil
    ) {
        self.id = id
        self.debitAccountId = debitAccountId
        self.creditAccountId = creditAccountId
        self.amount = amount
        self.taxCodeId = taxCodeId
        self.legalReportLineId = legalReportLineId
        self.projectAllocationId = projectAllocationId
        self.memo = memo
        self.evidenceLineReferenceId = evidenceLineReferenceId
    }
}

/// 税分析結果（候補生成時の自動判定結果）
struct TaxAnalysis: Codable, Sendable, Equatable {
    let creditMethod: InputTaxCreditMethod
    let taxRateBreakdown: TaxRateBreakdown
    let taxableAmount: Decimal
    let taxAmount: Decimal
    let deductibleTaxAmount: Decimal
}
