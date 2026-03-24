import Foundation

enum JournalLineValidationError: LocalizedError, Equatable {
    case negativeDebitAmount(Decimal)
    case negativeCreditAmount(Decimal)
    case bothSidesPositive(debit: Decimal, credit: Decimal)
    case noPositiveSide

    var errorDescription: String? {
        switch self {
        case .negativeDebitAmount:
            return "借方金額にマイナスは指定できません"
        case .negativeCreditAmount:
            return "貸方金額にマイナスは指定できません"
        case .bothSidesPositive:
            return "借方・貸方を同時に正の金額にはできません"
        case .noPositiveSide:
            return "借方・貸方のいずれか一方に正の金額が必要です"
        }
    }
}

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
        do {
            try self.init(
                validating: id,
                journalId: journalId,
                accountId: accountId,
                debitAmount: debitAmount,
                creditAmount: creditAmount,
                taxCodeId: taxCodeId,
                legalReportLineId: legalReportLineId,
                counterpartyId: counterpartyId,
                projectAllocationId: projectAllocationId,
                genreTagIds: genreTagIds,
                evidenceReferenceId: evidenceReferenceId,
                sortOrder: sortOrder,
                withholdingTaxCodeId: withholdingTaxCodeId,
                withholdingTaxAmount: withholdingTaxAmount,
                withholdingTaxBaseAmount: withholdingTaxBaseAmount
            )
        } catch {
            preconditionFailure("Invalid JournalLine: \(error.localizedDescription)")
        }
    }

    init(
        validating id: UUID,
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
    ) throws {
        try Self.validateAmounts(debitAmount: debitAmount, creditAmount: creditAmount)
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

    static func validateAmounts(debitAmount: Decimal, creditAmount: Decimal) throws {
        guard debitAmount >= 0 else {
            throw JournalLineValidationError.negativeDebitAmount(debitAmount)
        }
        guard creditAmount >= 0 else {
            throw JournalLineValidationError.negativeCreditAmount(creditAmount)
        }

        let hasDebit = debitAmount > 0
        let hasCredit = creditAmount > 0
        guard hasDebit != hasCredit else {
            if hasDebit {
                throw JournalLineValidationError.bothSidesPositive(debit: debitAmount, credit: creditAmount)
            }
            throw JournalLineValidationError.noPositiveSide
        }
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
