import Foundation

enum StatementLineEntityMapper {
    static func toDomain(_ entity: StatementLineEntity) -> StatementLineRecord {
        StatementLineRecord(
            id: entity.lineId,
            importId: entity.importId,
            businessId: entity.businessId,
            statementKind: StatementKind(rawValue: entity.statementKindRaw) ?? .bank,
            paymentAccountId: entity.paymentAccountId,
            date: entity.date,
            description: entity.entryDescription,
            amount: entity.amount,
            direction: StatementDirection(rawValue: entity.directionRaw) ?? .outflow,
            counterparty: entity.counterparty,
            reference: entity.reference,
            memo: entity.memo,
            matchState: StatementMatchState(rawValue: entity.matchStateRaw) ?? .unmatched,
            matchedCandidateId: entity.matchedCandidateId,
            matchedJournalId: entity.matchedJournalId,
            suggestedCandidateId: entity.suggestedCandidateId,
            suggestedJournalId: entity.suggestedJournalId,
            matchedAt: entity.matchedAt,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    static func toEntity(
        _ domain: StatementLineRecord,
        statementImport: StatementImportEntity? = nil
    ) -> StatementLineEntity {
        StatementLineEntity(
            lineId: domain.id,
            importId: domain.importId,
            businessId: domain.businessId,
            statementKindRaw: domain.statementKind.rawValue,
            paymentAccountId: domain.paymentAccountId,
            date: domain.date,
            entryDescription: domain.description,
            amount: domain.amount,
            directionRaw: domain.direction.rawValue,
            counterparty: domain.counterparty,
            reference: domain.reference,
            memo: domain.memo,
            matchStateRaw: domain.matchState.rawValue,
            matchedCandidateId: domain.matchedCandidateId,
            matchedJournalId: domain.matchedJournalId,
            suggestedCandidateId: domain.suggestedCandidateId,
            suggestedJournalId: domain.suggestedJournalId,
            matchedAt: domain.matchedAt,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            statementImport: statementImport
        )
    }

    static func update(_ entity: StatementLineEntity, from domain: StatementLineRecord) {
        entity.importId = domain.importId
        entity.businessId = domain.businessId
        entity.statementKindRaw = domain.statementKind.rawValue
        entity.paymentAccountId = domain.paymentAccountId
        entity.date = domain.date
        entity.entryDescription = domain.description
        entity.amount = domain.amount
        entity.directionRaw = domain.direction.rawValue
        entity.counterparty = domain.counterparty
        entity.reference = domain.reference
        entity.memo = domain.memo
        entity.matchStateRaw = domain.matchState.rawValue
        entity.matchedCandidateId = domain.matchedCandidateId
        entity.matchedJournalId = domain.matchedJournalId
        entity.suggestedCandidateId = domain.suggestedCandidateId
        entity.suggestedJournalId = domain.suggestedJournalId
        entity.matchedAt = domain.matchedAt
        entity.updatedAt = domain.updatedAt
    }
}
