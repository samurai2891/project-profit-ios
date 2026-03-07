import Foundation

/// JournalLine ↔ JournalLineEntity の変換
enum JournalLineEntityMapper {
    static func toDomain(_ entity: JournalLineEntity, journalId: UUID) -> JournalLine {
        JournalLine(
            id: entity.lineId,
            journalId: journalId,
            accountId: entity.accountId,
            debitAmount: entity.debitAmount,
            creditAmount: entity.creditAmount,
            taxCodeId: entity.taxCodeId,
            legalReportLineId: entity.legalReportLineId,
            counterpartyId: entity.counterpartyId,
            projectAllocationId: entity.projectAllocationId,
            genreTagIds: CanonicalJSONCoder.decode([UUID].self, from: entity.genreTagIdsJSON, fallback: []),
            evidenceReferenceId: entity.evidenceReferenceId,
            sortOrder: entity.sortOrder,
            withholdingTaxCodeId: entity.withholdingTaxCodeId,
            withholdingTaxAmount: entity.withholdingTaxAmount
        )
    }

    static func toEntity(_ domain: JournalLine) -> JournalLineEntity {
        JournalLineEntity(
            lineId: domain.id,
            accountId: domain.accountId,
            debitAmount: domain.debitAmount,
            creditAmount: domain.creditAmount,
            taxCodeId: domain.taxCodeId,
            legalReportLineId: domain.legalReportLineId,
            counterpartyId: domain.counterpartyId,
            projectAllocationId: domain.projectAllocationId,
            genreTagIdsJSON: CanonicalJSONCoder.encode(domain.genreTagIds, fallback: "[]"),
            evidenceReferenceId: domain.evidenceReferenceId,
            sortOrder: domain.sortOrder,
            withholdingTaxCodeId: domain.withholdingTaxCodeId,
            withholdingTaxAmount: domain.withholdingTaxAmount
        )
    }
}
