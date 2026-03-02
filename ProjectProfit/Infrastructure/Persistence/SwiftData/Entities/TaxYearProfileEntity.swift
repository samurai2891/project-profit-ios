import Foundation
import SwiftData

/// SwiftData Entity: 年分別税務プロフィール
@Model
final class TaxYearProfileEntity {
    @Attribute(.unique) var profileId: UUID
    var businessId: UUID
    var taxYear: Int
    var filingStyleRaw: String
    var blueDeductionLevelRaw: Int
    var bookkeepingBasisRaw: String
    var vatStatusRaw: String
    var vatMethodRaw: String
    var simplifiedBusinessCategory: Int?
    var invoiceIssuerStatusAtYearRaw: String
    var electronicBookLevelRaw: String
    var etaxSubmissionPlanned: Bool
    var yearLockStateRaw: String
    var taxPackVersion: String
    var createdAt: Date
    var updatedAt: Date

    init(
        profileId: UUID = UUID(),
        businessId: UUID = UUID(),
        taxYear: Int = 2025,
        filingStyleRaw: String = "blueGeneral",
        blueDeductionLevelRaw: Int = 650000,
        bookkeepingBasisRaw: String = "doubleEntry",
        vatStatusRaw: String = "exempt",
        vatMethodRaw: String = "general",
        simplifiedBusinessCategory: Int? = nil,
        invoiceIssuerStatusAtYearRaw: String = "unknown",
        electronicBookLevelRaw: String = "none",
        etaxSubmissionPlanned: Bool = false,
        yearLockStateRaw: String = "open",
        taxPackVersion: String = "2025-v1",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.profileId = profileId
        self.businessId = businessId
        self.taxYear = taxYear
        self.filingStyleRaw = filingStyleRaw
        self.blueDeductionLevelRaw = blueDeductionLevelRaw
        self.bookkeepingBasisRaw = bookkeepingBasisRaw
        self.vatStatusRaw = vatStatusRaw
        self.vatMethodRaw = vatMethodRaw
        self.simplifiedBusinessCategory = simplifiedBusinessCategory
        self.invoiceIssuerStatusAtYearRaw = invoiceIssuerStatusAtYearRaw
        self.electronicBookLevelRaw = electronicBookLevelRaw
        self.etaxSubmissionPlanned = etaxSubmissionPlanned
        self.yearLockStateRaw = yearLockStateRaw
        self.taxPackVersion = taxPackVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
