import Foundation
import SwiftData

@Model
final class EvidenceSearchIndexEntity {
    @Attribute(.unique) var evidenceId: UUID
    var businessId: UUID
    var taxYear: Int
    var issueDate: Date?
    var receivedAt: Date
    var totalAmount: Decimal?
    var counterpartyNameNormalized: String
    var registrationNumberNormalized: String?
    var projectIdsJSON: String
    var fileHashNormalized: String
    var legalDocumentTypeRaw: String
    var complianceStatusRaw: String
    var deletedAt: Date?
    var searchText: String
    var updatedAt: Date

    init(
        evidenceId: UUID = UUID(),
        businessId: UUID = UUID(),
        taxYear: Int = 2025,
        issueDate: Date? = nil,
        receivedAt: Date = Date(),
        totalAmount: Decimal? = nil,
        counterpartyNameNormalized: String = "",
        registrationNumberNormalized: String? = nil,
        projectIdsJSON: String = "[]",
        fileHashNormalized: String = "",
        legalDocumentTypeRaw: String = "other",
        complianceStatusRaw: String = "unknown",
        deletedAt: Date? = nil,
        searchText: String = "",
        updatedAt: Date = Date()
    ) {
        self.evidenceId = evidenceId
        self.businessId = businessId
        self.taxYear = taxYear
        self.issueDate = issueDate
        self.receivedAt = receivedAt
        self.totalAmount = totalAmount
        self.counterpartyNameNormalized = counterpartyNameNormalized
        self.registrationNumberNormalized = registrationNumberNormalized
        self.projectIdsJSON = projectIdsJSON
        self.fileHashNormalized = fileHashNormalized
        self.legalDocumentTypeRaw = legalDocumentTypeRaw
        self.complianceStatusRaw = complianceStatusRaw
        self.deletedAt = deletedAt
        self.searchText = searchText
        self.updatedAt = updatedAt
    }
}
