import Foundation

/// 事業者プロフィール（恒久情報）
/// 年分に依存しない事業者の基本情報
struct BusinessProfile: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let ownerName: String
    let ownerNameKana: String
    let businessName: String
    let defaultPaymentAccountId: String
    let businessAddress: String
    let postalCode: String
    let phoneNumber: String
    let openingDate: Date?
    let taxOfficeCode: String?
    let invoiceRegistrationNumber: String?
    let invoiceIssuerStatus: InvoiceIssuerStatus
    let defaultCurrency: String
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerName: String,
        ownerNameKana: String = "",
        businessName: String = "",
        defaultPaymentAccountId: String = AccountingConstants.defaultPaymentAccountId,
        businessAddress: String = "",
        postalCode: String = "",
        phoneNumber: String = "",
        openingDate: Date? = nil,
        taxOfficeCode: String? = nil,
        invoiceRegistrationNumber: String? = nil,
        invoiceIssuerStatus: InvoiceIssuerStatus = .unknown,
        defaultCurrency: String = "JPY",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
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
        self.invoiceIssuerStatus = invoiceIssuerStatus
        self.defaultCurrency = defaultCurrency
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// イミュータブル更新: 指定フィールドを変更した新しいインスタンスを返す
    func updated(
        ownerName: String? = nil,
        ownerNameKana: String? = nil,
        businessName: String? = nil,
        defaultPaymentAccountId: String? = nil,
        businessAddress: String? = nil,
        postalCode: String? = nil,
        phoneNumber: String? = nil,
        openingDate: Date?? = nil,
        taxOfficeCode: String?? = nil,
        invoiceRegistrationNumber: String?? = nil,
        invoiceIssuerStatus: InvoiceIssuerStatus? = nil
    ) -> BusinessProfile {
        BusinessProfile(
            id: self.id,
            ownerName: ownerName ?? self.ownerName,
            ownerNameKana: ownerNameKana ?? self.ownerNameKana,
            businessName: businessName ?? self.businessName,
            defaultPaymentAccountId: defaultPaymentAccountId ?? self.defaultPaymentAccountId,
            businessAddress: businessAddress ?? self.businessAddress,
            postalCode: postalCode ?? self.postalCode,
            phoneNumber: phoneNumber ?? self.phoneNumber,
            openingDate: openingDate ?? self.openingDate,
            taxOfficeCode: taxOfficeCode ?? self.taxOfficeCode,
            invoiceRegistrationNumber: invoiceRegistrationNumber ?? self.invoiceRegistrationNumber,
            invoiceIssuerStatus: invoiceIssuerStatus ?? self.invoiceIssuerStatus,
            defaultCurrency: self.defaultCurrency,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}
