import Foundation
import SwiftData

/// SwiftData Entity: 証憑レコード
@Model
final class EvidenceRecordEntity {
    @Attribute(.unique) var evidenceId: UUID
    var businessId: UUID
    var taxYear: Int
    var sourceTypeRaw: String
    var legalDocumentTypeRaw: String
    var storageCategoryRaw: String
    var receivedAt: Date
    var issueDate: Date?
    var paymentDate: Date?
    var originalFilename: String
    var mimeType: String
    var fileHash: String
    var originalFilePath: String
    var ocrText: String?
    var extractionVersion: String?
    var searchTokensJSON: String
    var structuredFieldsJSON: String?
    var linkedCounterpartyId: UUID?
    var linkedProjectIdsJSON: String
    var complianceStatusRaw: String
    var retentionPolicyId: UUID?
    var deletedAt: Date?
    var lockedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        evidenceId: UUID = UUID(),
        businessId: UUID = UUID(),
        taxYear: Int = 2025,
        sourceTypeRaw: String = "manualNoFile",
        legalDocumentTypeRaw: String = "other",
        storageCategoryRaw: String = "paperScan",
        receivedAt: Date = Date(),
        issueDate: Date? = nil,
        paymentDate: Date? = nil,
        originalFilename: String = "",
        mimeType: String = "",
        fileHash: String = "",
        originalFilePath: String = "",
        ocrText: String? = nil,
        extractionVersion: String? = nil,
        searchTokensJSON: String = "[]",
        structuredFieldsJSON: String? = nil,
        linkedCounterpartyId: UUID? = nil,
        linkedProjectIdsJSON: String = "[]",
        complianceStatusRaw: String = "pendingReview",
        retentionPolicyId: UUID? = nil,
        deletedAt: Date? = nil,
        lockedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.evidenceId = evidenceId
        self.businessId = businessId
        self.taxYear = taxYear
        self.sourceTypeRaw = sourceTypeRaw
        self.legalDocumentTypeRaw = legalDocumentTypeRaw
        self.storageCategoryRaw = storageCategoryRaw
        self.receivedAt = receivedAt
        self.issueDate = issueDate
        self.paymentDate = paymentDate
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.fileHash = fileHash
        self.originalFilePath = originalFilePath
        self.ocrText = ocrText
        self.extractionVersion = extractionVersion
        self.searchTokensJSON = searchTokensJSON
        self.structuredFieldsJSON = structuredFieldsJSON
        self.linkedCounterpartyId = linkedCounterpartyId
        self.linkedProjectIdsJSON = linkedProjectIdsJSON
        self.complianceStatusRaw = complianceStatusRaw
        self.retentionPolicyId = retentionPolicyId
        self.deletedAt = deletedAt
        self.lockedAt = lockedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
