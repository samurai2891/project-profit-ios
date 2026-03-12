import Foundation

enum StatementImportEntityMapper {
    static func toDomain(_ entity: StatementImportEntity) -> StatementImportRecord {
        StatementImportRecord(
            id: entity.importId,
            businessId: entity.businessId,
            evidenceId: entity.evidenceId,
            statementKind: StatementKind(rawValue: entity.statementKindRaw) ?? .bank,
            paymentAccountId: entity.paymentAccountId,
            fileSource: StatementFileSource(rawValue: entity.fileSourceRaw) ?? .csv,
            importedAt: entity.importedAt,
            originalFileName: entity.originalFileName,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    static func toEntity(_ domain: StatementImportRecord) -> StatementImportEntity {
        StatementImportEntity(
            importId: domain.id,
            businessId: domain.businessId,
            evidenceId: domain.evidenceId,
            statementKindRaw: domain.statementKind.rawValue,
            paymentAccountId: domain.paymentAccountId,
            fileSourceRaw: domain.fileSource.rawValue,
            importedAt: domain.importedAt,
            originalFileName: domain.originalFileName,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    static func update(_ entity: StatementImportEntity, from domain: StatementImportRecord) {
        entity.businessId = domain.businessId
        entity.evidenceId = domain.evidenceId
        entity.statementKindRaw = domain.statementKind.rawValue
        entity.paymentAccountId = domain.paymentAccountId
        entity.fileSourceRaw = domain.fileSource.rawValue
        entity.importedAt = domain.importedAt
        entity.originalFileName = domain.originalFileName
        entity.updatedAt = domain.updatedAt
    }
}
