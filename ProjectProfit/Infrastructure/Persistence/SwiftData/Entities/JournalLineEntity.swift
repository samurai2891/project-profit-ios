import Foundation
import SwiftData

/// SwiftData Entity: 仕訳明細行
@Model
final class JournalLineEntity {
    @Attribute(.unique) var lineId: UUID
    var accountId: UUID
    var debitAmount: Decimal
    var creditAmount: Decimal
    var taxCodeId: String?
    var legalReportLineId: String?
    var counterpartyId: UUID?
    var projectAllocationId: UUID?
    var genreTagIdsJSON: String
    var evidenceReferenceId: UUID?
    var sortOrder: Int
    var withholdingTaxCodeId: String?
    var withholdingTaxAmount: Decimal?

    var journalEntry: JournalEntryEntity?

    init(
        lineId: UUID = UUID(),
        accountId: UUID = UUID(),
        debitAmount: Decimal = 0,
        creditAmount: Decimal = 0,
        taxCodeId: String? = nil,
        legalReportLineId: String? = nil,
        counterpartyId: UUID? = nil,
        projectAllocationId: UUID? = nil,
        genreTagIdsJSON: String = "[]",
        evidenceReferenceId: UUID? = nil,
        sortOrder: Int = 0,
        withholdingTaxCodeId: String? = nil,
        withholdingTaxAmount: Decimal? = nil
    ) {
        self.lineId = lineId
        self.accountId = accountId
        self.debitAmount = debitAmount
        self.creditAmount = creditAmount
        self.taxCodeId = taxCodeId
        self.legalReportLineId = legalReportLineId
        self.counterpartyId = counterpartyId
        self.projectAllocationId = projectAllocationId
        self.genreTagIdsJSON = genreTagIdsJSON
        self.evidenceReferenceId = evidenceReferenceId
        self.sortOrder = sortOrder
        self.withholdingTaxCodeId = withholdingTaxCodeId
        self.withholdingTaxAmount = withholdingTaxAmount
    }
}
