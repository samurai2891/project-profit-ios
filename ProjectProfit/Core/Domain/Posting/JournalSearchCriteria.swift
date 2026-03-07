import Foundation

struct JournalSearchCriteria: Sendable {
    let businessId: UUID?
    let taxYear: Int?
    let dateRange: ClosedRange<Date>?
    let amountRange: ClosedRange<Decimal>?
    let counterpartyText: String?
    let registrationNumber: String?
    let projectId: UUID?
    let fileHash: String?
    let textQuery: String?
    let includeCancelled: Bool

    init(
        businessId: UUID? = nil,
        taxYear: Int? = nil,
        dateRange: ClosedRange<Date>? = nil,
        amountRange: ClosedRange<Decimal>? = nil,
        counterpartyText: String? = nil,
        registrationNumber: String? = nil,
        projectId: UUID? = nil,
        fileHash: String? = nil,
        textQuery: String? = nil,
        includeCancelled: Bool = true
    ) {
        self.businessId = businessId
        self.taxYear = taxYear
        self.dateRange = dateRange
        self.amountRange = amountRange
        self.counterpartyText = counterpartyText
        self.registrationNumber = registrationNumber
        self.projectId = projectId
        self.fileHash = fileHash
        self.textQuery = textQuery
        self.includeCancelled = includeCancelled
    }
}
