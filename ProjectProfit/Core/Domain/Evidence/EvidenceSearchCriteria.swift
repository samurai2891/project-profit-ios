import Foundation

/// 証憑検索条件
struct EvidenceSearchCriteria: Sendable {
    let businessId: UUID?
    let taxYear: Int?
    let dateRange: ClosedRange<Date>?
    let amountRange: ClosedRange<Decimal>?
    let legalDocumentTypes: [CanonicalLegalDocumentType]?
    let counterpartyId: UUID?
    let counterpartyText: String?
    let registrationNumber: String?
    let projectId: UUID?
    let fileHash: String?
    let complianceStatus: ComplianceStatus?
    let textQuery: String?
    let includeDeleted: Bool

    init(
        businessId: UUID? = nil,
        taxYear: Int? = nil,
        dateRange: ClosedRange<Date>? = nil,
        amountRange: ClosedRange<Decimal>? = nil,
        legalDocumentTypes: [CanonicalLegalDocumentType]? = nil,
        counterpartyId: UUID? = nil,
        counterpartyText: String? = nil,
        registrationNumber: String? = nil,
        projectId: UUID? = nil,
        fileHash: String? = nil,
        complianceStatus: ComplianceStatus? = nil,
        textQuery: String? = nil,
        includeDeleted: Bool = false
    ) {
        self.businessId = businessId
        self.taxYear = taxYear
        self.dateRange = dateRange
        self.amountRange = amountRange
        self.legalDocumentTypes = legalDocumentTypes
        self.counterpartyId = counterpartyId
        self.counterpartyText = counterpartyText
        self.registrationNumber = registrationNumber
        self.projectId = projectId
        self.fileHash = fileHash
        self.complianceStatus = complianceStatus
        self.textQuery = textQuery
        self.includeDeleted = includeDeleted
    }
}
