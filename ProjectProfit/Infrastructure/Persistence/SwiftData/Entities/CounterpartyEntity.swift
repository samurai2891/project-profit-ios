import Foundation
import SwiftData

/// SwiftData Entity: 取引先
@Model
final class CounterpartyEntity {
    @Attribute(.unique) var counterpartyId: UUID
    var businessId: UUID
    var displayName: String
    var kana: String?
    var legalName: String?
    var corporateNumber: String?
    var invoiceRegistrationNumber: String?
    var invoiceIssuerStatusRaw: String
    var statusEffectiveFrom: Date?
    var statusEffectiveTo: Date?
    var address: String?
    var phone: String?
    var email: String?
    var defaultAccountId: UUID?
    var defaultTaxCodeId: String?
    var defaultProjectId: UUID?
    var notes: String?
    var payeeIsWithholdingSubject: Bool
    var payeeWithholdingCategoryRaw: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        counterpartyId: UUID = UUID(),
        businessId: UUID = UUID(),
        displayName: String = "",
        kana: String? = nil,
        legalName: String? = nil,
        corporateNumber: String? = nil,
        invoiceRegistrationNumber: String? = nil,
        invoiceIssuerStatusRaw: String = "unknown",
        statusEffectiveFrom: Date? = nil,
        statusEffectiveTo: Date? = nil,
        address: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        defaultAccountId: UUID? = nil,
        defaultTaxCodeId: String? = nil,
        defaultProjectId: UUID? = nil,
        notes: String? = nil,
        payeeIsWithholdingSubject: Bool = false,
        payeeWithholdingCategoryRaw: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.counterpartyId = counterpartyId
        self.businessId = businessId
        self.displayName = displayName
        self.kana = kana
        self.legalName = legalName
        self.corporateNumber = corporateNumber
        self.invoiceRegistrationNumber = invoiceRegistrationNumber
        self.invoiceIssuerStatusRaw = invoiceIssuerStatusRaw
        self.statusEffectiveFrom = statusEffectiveFrom
        self.statusEffectiveTo = statusEffectiveTo
        self.address = address
        self.phone = phone
        self.email = email
        self.defaultAccountId = defaultAccountId
        self.defaultTaxCodeId = defaultTaxCodeId
        self.defaultProjectId = defaultProjectId
        self.notes = notes
        self.payeeIsWithholdingSubject = payeeIsWithholdingSubject
        self.payeeWithholdingCategoryRaw = payeeWithholdingCategoryRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
