import Foundation

/// 証憑検索条件
struct EvidenceSearchCriteria: Sendable {
    let businessId: UUID?
    let taxYear: Int?
    let dateRange: ClosedRange<Date>?
    let legalDocumentTypes: [CanonicalLegalDocumentType]?
    let counterpartyId: UUID?
    let projectId: UUID?
    let complianceStatus: ComplianceStatus?
    let textQuery: String?
    let includeDeleted: Bool

    init(
        businessId: UUID? = nil,
        taxYear: Int? = nil,
        dateRange: ClosedRange<Date>? = nil,
        legalDocumentTypes: [CanonicalLegalDocumentType]? = nil,
        counterpartyId: UUID? = nil,
        projectId: UUID? = nil,
        complianceStatus: ComplianceStatus? = nil,
        textQuery: String? = nil,
        includeDeleted: Bool = false
    ) {
        self.businessId = businessId
        self.taxYear = taxYear
        self.dateRange = dateRange
        self.legalDocumentTypes = legalDocumentTypes
        self.counterpartyId = counterpartyId
        self.projectId = projectId
        self.complianceStatus = complianceStatus
        self.textQuery = textQuery
        self.includeDeleted = includeDeleted
    }
}
