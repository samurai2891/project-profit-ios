import Foundation
import SwiftData

/// SwiftData Entity: 事業者プロフィール
@Model
final class BusinessProfileEntity {
    @Attribute(.unique) var businessId: UUID
    var ownerName: String
    var ownerNameKana: String
    var businessName: String
    var defaultPaymentAccountId: String?
    var businessAddress: String
    var postalCode: String
    var phoneNumber: String
    var openingDate: Date?
    var taxOfficeCode: String?
    var invoiceRegistrationNumber: String?
    var invoiceIssuerStatusRaw: String
    var defaultCurrency: String
    var createdAt: Date
    var updatedAt: Date

    init(
        businessId: UUID = UUID(),
        ownerName: String = "",
        ownerNameKana: String = "",
        businessName: String = "",
        defaultPaymentAccountId: String? = nil,
        businessAddress: String = "",
        postalCode: String = "",
        phoneNumber: String = "",
        openingDate: Date? = nil,
        taxOfficeCode: String? = nil,
        invoiceRegistrationNumber: String? = nil,
        invoiceIssuerStatusRaw: String = "unknown",
        defaultCurrency: String = "JPY",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.businessId = businessId
        self.ownerName = ownerName
        self.ownerNameKana = ownerNameKana
        self.businessName = businessName
        self.defaultPaymentAccountId = defaultPaymentAccountId
        self.businessAddress = businessAddress
        self.postalCode = postalCode
        self.phoneNumber = phoneNumber
        self.openingDate = openingDate
        self.taxOfficeCode = taxOfficeCode
        self.invoiceRegistrationNumber = invoiceRegistrationNumber
        self.invoiceIssuerStatusRaw = invoiceIssuerStatusRaw
        self.defaultCurrency = defaultCurrency
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
