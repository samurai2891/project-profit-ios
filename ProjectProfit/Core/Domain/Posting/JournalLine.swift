import Foundation

/// 仕訳明細行（PostedJournal の構成要素）
struct JournalLine: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let journalId: UUID
    let accountId: UUID
    let debitAmount: Decimal
    let creditAmount: Decimal
    let taxCodeId: String?
    let legalReportLineId: String?
    let counterpartyId: UUID?
    let projectAllocationId: UUID?
    let genreTagIds: [UUID]
    let evidenceReferenceId: UUID?
    let sortOrder: Int
    let withholdingTaxCodeId: String?
    let withholdingTaxAmount: Decimal?
    let withholdingTaxBaseAmount: Decimal?

    init(
        id: UUID = UUID(),
        journalId: UUID,
        accountId: UUID,
        debitAmount: Decimal = 0,
        creditAmount: Decimal = 0,
        taxCodeId: String? = nil,
        legalReportLineId: String? = nil,
        counterpartyId: UUID? = nil,
        projectAllocationId: UUID? = nil,
        genreTagIds: [UUID] = [],
        evidenceReferenceId: UUID? = nil,
        sortOrder: Int = 0,
        withholdingTaxCodeId: String? = nil,
        withholdingTaxAmount: Decimal? = nil,
        withholdingTaxBaseAmount: Decimal? = nil
    ) {
        self.id = id
        self.journalId = journalId
        self.accountId = accountId
        self.debitAmount = debitAmount
        self.creditAmount = creditAmount
        self.taxCodeId = taxCodeId
        self.legalReportLineId = legalReportLineId
        self.counterpartyId = counterpartyId
        self.projectAllocationId = projectAllocationId
        self.genreTagIds = genreTagIds
        self.evidenceReferenceId = evidenceReferenceId
        self.sortOrder = sortOrder
        self.withholdingTaxCodeId = withholdingTaxCodeId
        self.withholdingTaxAmount = withholdingTaxAmount
        self.withholdingTaxBaseAmount = withholdingTaxBaseAmount
    }

    /// この行が借方行か
    var isDebit: Bool { debitAmount > 0 }

    /// この行が貸方行か
    var isCredit: Bool { creditAmount > 0 }

    /// この行の金額（借方または貸方）
    var amount: Decimal {
        debitAmount > 0 ? debitAmount : creditAmount
    }
}
