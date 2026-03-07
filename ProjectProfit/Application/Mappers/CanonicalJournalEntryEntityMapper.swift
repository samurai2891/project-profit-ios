import Foundation

/// CanonicalJournalEntry ↔ JournalEntryEntity の変換
enum CanonicalJournalEntryEntityMapper {
    static func toDomain(_ entity: JournalEntryEntity) -> CanonicalJournalEntry {
        let lines = entity.lines
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { JournalLineEntityMapper.toDomain($0, journalId: entity.journalId) }

        return CanonicalJournalEntry(
            id: entity.journalId,
            businessId: entity.businessId,
            taxYear: entity.taxYear,
            journalDate: entity.journalDate,
            voucherNo: entity.voucherNo,
            sourceEvidenceId: entity.sourceEvidenceId,
            sourceCandidateId: entity.sourceCandidateId,
            entryType: CanonicalJournalEntryType(rawValue: entity.entryTypeRaw) ?? .normal,
            description: entity.entryDescription,
            lines: lines,
            approvedAt: entity.approvedAt,
            lockedAt: entity.lockedAt,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    static func toEntity(_ domain: CanonicalJournalEntry) -> JournalEntryEntity {
        let entity = JournalEntryEntity(
            journalId: domain.id,
            businessId: domain.businessId,
            taxYear: domain.taxYear,
            journalDate: domain.journalDate,
            voucherNo: domain.voucherNo,
            sourceEvidenceId: domain.sourceEvidenceId,
            sourceCandidateId: domain.sourceCandidateId,
            entryTypeRaw: domain.entryType.rawValue,
            entryDescription: domain.description,
            approvedAt: domain.approvedAt,
            lockedAt: domain.lockedAt,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            lines: []
        )
        entity.lines = makeLineEntities(from: domain.lines, journalEntry: entity)
        return entity
    }

    static func update(_ entity: JournalEntryEntity, from domain: CanonicalJournalEntry) {
        entity.businessId = domain.businessId
        entity.taxYear = domain.taxYear
        entity.journalDate = domain.journalDate
        entity.voucherNo = domain.voucherNo
        entity.sourceEvidenceId = domain.sourceEvidenceId
        entity.sourceCandidateId = domain.sourceCandidateId
        entity.entryTypeRaw = domain.entryType.rawValue
        entity.entryDescription = domain.description
        entity.approvedAt = domain.approvedAt
        entity.lockedAt = domain.lockedAt
        entity.updatedAt = domain.updatedAt
    }

    static func makeLineEntities(from lines: [JournalLine], journalEntry: JournalEntryEntity) -> [JournalLineEntity] {
        lines
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
                let entity = JournalLineEntityMapper.toEntity($0)
                entity.journalEntry = journalEntry
                return entity
            }
    }
}
