import Foundation

/// EvidenceDocument ↔ EvidenceRecordEntity の変換
enum EvidenceRecordEntityMapper {
    static func toDomain(_ entity: EvidenceRecordEntity) -> EvidenceDocument {
        EvidenceDocument(
            id: entity.evidenceId,
            businessId: entity.businessId,
            taxYear: entity.taxYear,
            sourceType: EvidenceSourceType(rawValue: entity.sourceTypeRaw) ?? .manualNoFile,
            legalDocumentType: CanonicalLegalDocumentType(rawValue: entity.legalDocumentTypeRaw) ?? .other,
            storageCategory: StorageCategory(rawValue: entity.storageCategoryRaw) ?? .paperScan,
            receivedAt: entity.receivedAt,
            issueDate: entity.issueDate,
            paymentDate: entity.paymentDate,
            originalFilename: entity.originalFilename,
            mimeType: entity.mimeType,
            fileHash: entity.fileHash,
            originalFilePath: entity.originalFilePath,
            ocrText: entity.ocrText,
            extractionVersion: entity.extractionVersion,
            searchTokens: CanonicalJSONCoder.decode([String].self, from: entity.searchTokensJSON, fallback: []),
            structuredFields: CanonicalJSONCoder.decodeIfPresent(EvidenceStructuredFields.self, from: entity.structuredFieldsJSON),
            linkedCounterpartyId: entity.linkedCounterpartyId,
            linkedProjectIds: CanonicalJSONCoder.decode([UUID].self, from: entity.linkedProjectIdsJSON, fallback: []),
            complianceStatus: ComplianceStatus(rawValue: entity.complianceStatusRaw) ?? .pendingReview,
            retentionPolicyId: entity.retentionPolicyId,
            deletedAt: entity.deletedAt,
            lockedAt: entity.lockedAt,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    static func toEntity(_ domain: EvidenceDocument) -> EvidenceRecordEntity {
        EvidenceRecordEntity(
            evidenceId: domain.id,
            businessId: domain.businessId,
            taxYear: domain.taxYear,
            sourceTypeRaw: domain.sourceType.rawValue,
            legalDocumentTypeRaw: domain.legalDocumentType.rawValue,
            storageCategoryRaw: domain.storageCategory.rawValue,
            receivedAt: domain.receivedAt,
            issueDate: domain.issueDate,
            paymentDate: domain.paymentDate,
            originalFilename: domain.originalFilename,
            mimeType: domain.mimeType,
            fileHash: domain.fileHash,
            originalFilePath: domain.originalFilePath,
            ocrText: domain.ocrText,
            extractionVersion: domain.extractionVersion,
            searchTokensJSON: CanonicalJSONCoder.encode(domain.searchTokens, fallback: "[]"),
            structuredFieldsJSON: CanonicalJSONCoder.encodeIfPresent(domain.structuredFields),
            linkedCounterpartyId: domain.linkedCounterpartyId,
            linkedProjectIdsJSON: CanonicalJSONCoder.encode(domain.linkedProjectIds, fallback: "[]"),
            complianceStatusRaw: domain.complianceStatus.rawValue,
            retentionPolicyId: domain.retentionPolicyId,
            deletedAt: domain.deletedAt,
            lockedAt: domain.lockedAt,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    static func update(_ entity: EvidenceRecordEntity, from domain: EvidenceDocument) {
        entity.businessId = domain.businessId
        entity.taxYear = domain.taxYear
        entity.sourceTypeRaw = domain.sourceType.rawValue
        entity.legalDocumentTypeRaw = domain.legalDocumentType.rawValue
        entity.storageCategoryRaw = domain.storageCategory.rawValue
        entity.receivedAt = domain.receivedAt
        entity.issueDate = domain.issueDate
        entity.paymentDate = domain.paymentDate
        entity.originalFilename = domain.originalFilename
        entity.mimeType = domain.mimeType
        entity.fileHash = domain.fileHash
        entity.originalFilePath = domain.originalFilePath
        entity.ocrText = domain.ocrText
        entity.extractionVersion = domain.extractionVersion
        entity.searchTokensJSON = CanonicalJSONCoder.encode(domain.searchTokens, fallback: "[]")
        entity.structuredFieldsJSON = CanonicalJSONCoder.encodeIfPresent(domain.structuredFields)
        entity.linkedCounterpartyId = domain.linkedCounterpartyId
        entity.linkedProjectIdsJSON = CanonicalJSONCoder.encode(domain.linkedProjectIds, fallback: "[]")
        entity.complianceStatusRaw = domain.complianceStatus.rawValue
        entity.retentionPolicyId = domain.retentionPolicyId
        entity.deletedAt = domain.deletedAt
        entity.lockedAt = domain.lockedAt
        entity.updatedAt = domain.updatedAt
    }
}
