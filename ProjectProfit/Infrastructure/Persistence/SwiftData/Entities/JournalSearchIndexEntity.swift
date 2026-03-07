import Foundation
import SwiftData

@Model
final class JournalSearchIndexEntity {
    @Attribute(.unique) var journalId: UUID
    var businessId: UUID
    var taxYear: Int
    var journalDate: Date
    var totalAmount: Decimal
    var counterpartyNamesJSON: String
    var registrationNumbersJSON: String
    var projectIdsJSON: String
    var fileHashesJSON: String
    var searchText: String
    var isCancelledOriginal: Bool
    var isReversal: Bool
    var updatedAt: Date

    init(
        journalId: UUID = UUID(),
        businessId: UUID = UUID(),
        taxYear: Int = 2025,
        journalDate: Date = Date(),
        totalAmount: Decimal = 0,
        counterpartyNamesJSON: String = "[]",
        registrationNumbersJSON: String = "[]",
        projectIdsJSON: String = "[]",
        fileHashesJSON: String = "[]",
        searchText: String = "",
        isCancelledOriginal: Bool = false,
        isReversal: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.journalId = journalId
        self.businessId = businessId
        self.taxYear = taxYear
        self.journalDate = journalDate
        self.totalAmount = totalAmount
        self.counterpartyNamesJSON = counterpartyNamesJSON
        self.registrationNumbersJSON = registrationNumbersJSON
        self.projectIdsJSON = projectIdsJSON
        self.fileHashesJSON = fileHashesJSON
        self.searchText = searchText
        self.isCancelledOriginal = isCancelledOriginal
        self.isReversal = isReversal
        self.updatedAt = updatedAt
    }
}
