import Foundation

/// 証憑ドキュメント（正本系統の起点）
/// Evidence → PostingCandidate → PostedJournal の1系統のみ
struct EvidenceDocument: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let taxYear: Int
    let sourceType: EvidenceSourceType
    let legalDocumentType: CanonicalLegalDocumentType
    let storageCategory: StorageCategory
    let receivedAt: Date
    let issueDate: Date?
    let paymentDate: Date?
    let originalFilename: String
    let mimeType: String
    let fileHash: String
    let originalFilePath: String
    let ocrText: String?
    let extractionVersion: String?
    let searchTokens: [String]
    let structuredFields: EvidenceStructuredFields?
    let linkedCounterpartyId: UUID?
    let linkedProjectIds: [UUID]
    let complianceStatus: ComplianceStatus
    let retentionPolicyId: UUID?
    let deletedAt: Date?
    let lockedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        businessId: UUID,
        taxYear: Int,
        sourceType: EvidenceSourceType,
        legalDocumentType: CanonicalLegalDocumentType,
        storageCategory: StorageCategory,
        receivedAt: Date = Date(),
        issueDate: Date? = nil,
        paymentDate: Date? = nil,
        originalFilename: String,
        mimeType: String,
        fileHash: String,
        originalFilePath: String,
        ocrText: String? = nil,
        extractionVersion: String? = nil,
        searchTokens: [String] = [],
        structuredFields: EvidenceStructuredFields? = nil,
        linkedCounterpartyId: UUID? = nil,
        linkedProjectIds: [UUID] = [],
        complianceStatus: ComplianceStatus = .pendingReview,
        retentionPolicyId: UUID? = nil,
        deletedAt: Date? = nil,
        lockedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.taxYear = taxYear
        self.sourceType = sourceType
        self.legalDocumentType = legalDocumentType
        self.storageCategory = storageCategory
        self.receivedAt = receivedAt
        self.issueDate = issueDate
        self.paymentDate = paymentDate
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.fileHash = fileHash
        self.originalFilePath = originalFilePath
        self.ocrText = ocrText
        self.extractionVersion = extractionVersion
        self.searchTokens = searchTokens
        self.structuredFields = structuredFields
        self.linkedCounterpartyId = linkedCounterpartyId
        self.linkedProjectIds = linkedProjectIds
        self.complianceStatus = complianceStatus
        self.retentionPolicyId = retentionPolicyId
        self.deletedAt = deletedAt
        self.lockedAt = lockedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// イミュータブル更新
    func updated(
        ocrText: String?? = nil,
        extractionVersion: String?? = nil,
        searchTokens: [String]? = nil,
        structuredFields: EvidenceStructuredFields?? = nil,
        linkedCounterpartyId: UUID?? = nil,
        linkedProjectIds: [UUID]? = nil,
        complianceStatus: ComplianceStatus? = nil,
        lockedAt: Date?? = nil
    ) -> EvidenceDocument {
        EvidenceDocument(
            id: self.id,
            businessId: self.businessId,
            taxYear: self.taxYear,
            sourceType: self.sourceType,
            legalDocumentType: self.legalDocumentType,
            storageCategory: self.storageCategory,
            receivedAt: self.receivedAt,
            issueDate: self.issueDate,
            paymentDate: self.paymentDate,
            originalFilename: self.originalFilename,
            mimeType: self.mimeType,
            fileHash: self.fileHash,
            originalFilePath: self.originalFilePath,
            ocrText: ocrText ?? self.ocrText,
            extractionVersion: extractionVersion ?? self.extractionVersion,
            searchTokens: searchTokens ?? self.searchTokens,
            structuredFields: structuredFields ?? self.structuredFields,
            linkedCounterpartyId: linkedCounterpartyId ?? self.linkedCounterpartyId,
            linkedProjectIds: linkedProjectIds ?? self.linkedProjectIds,
            complianceStatus: complianceStatus ?? self.complianceStatus,
            retentionPolicyId: self.retentionPolicyId,
            deletedAt: self.deletedAt,
            lockedAt: lockedAt ?? self.lockedAt,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}
