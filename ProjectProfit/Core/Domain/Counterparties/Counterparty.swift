import Foundation

enum RegistrationNumberNormalizer {
    static func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let uppercased = trimmed.uppercased()
        let digits = uppercased.hasPrefix("T") ? String(uppercased.dropFirst()) : uppercased
        guard digits.count == 13, digits.allSatisfy(\.isNumber) else {
            return nil
        }
        return "T\(digits)"
    }
}

/// 取引先マスタ（独立したエンティティ）
/// 現行の PPTransaction.counterparty: String → マスタに昇格
struct Counterparty: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let displayName: String
    let kana: String?
    let legalName: String?
    let corporateNumber: String?
    let invoiceRegistrationNumber: String?
    let invoiceIssuerStatus: InvoiceIssuerStatus
    let statusEffectiveFrom: Date?
    let statusEffectiveTo: Date?
    let address: String?
    let phone: String?
    let email: String?
    let defaultAccountId: UUID?
    let defaultTaxCodeId: String?
    let defaultProjectId: UUID?
    let notes: String?
    let payeeInfo: PayeeInfo?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        businessId: UUID,
        displayName: String,
        kana: String? = nil,
        legalName: String? = nil,
        corporateNumber: String? = nil,
        invoiceRegistrationNumber: String? = nil,
        invoiceIssuerStatus: InvoiceIssuerStatus = .unknown,
        statusEffectiveFrom: Date? = nil,
        statusEffectiveTo: Date? = nil,
        address: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        defaultAccountId: UUID? = nil,
        defaultTaxCodeId: String? = nil,
        defaultProjectId: UUID? = nil,
        notes: String? = nil,
        payeeInfo: PayeeInfo? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.displayName = displayName
        self.kana = kana
        self.legalName = legalName
        self.corporateNumber = corporateNumber
        self.invoiceRegistrationNumber = invoiceRegistrationNumber
        self.invoiceIssuerStatus = invoiceIssuerStatus
        self.statusEffectiveFrom = statusEffectiveFrom
        self.statusEffectiveTo = statusEffectiveTo
        self.address = address
        self.phone = phone
        self.email = email
        self.defaultAccountId = defaultAccountId
        self.defaultTaxCodeId = defaultTaxCodeId
        self.defaultProjectId = defaultProjectId
        self.notes = notes
        self.payeeInfo = payeeInfo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// イミュータブル更新
    func updated(
        displayName: String? = nil,
        kana: String?? = nil,
        invoiceRegistrationNumber: String?? = nil,
        invoiceIssuerStatus: InvoiceIssuerStatus? = nil,
        statusEffectiveFrom: Date?? = nil,
        statusEffectiveTo: Date?? = nil,
        defaultAccountId: UUID?? = nil,
        defaultTaxCodeId: String?? = nil,
        payeeInfo: PayeeInfo?? = nil
    ) -> Counterparty {
        Counterparty(
            id: self.id,
            businessId: self.businessId,
            displayName: displayName ?? self.displayName,
            kana: kana ?? self.kana,
            legalName: self.legalName,
            corporateNumber: self.corporateNumber,
            invoiceRegistrationNumber: invoiceRegistrationNumber ?? self.invoiceRegistrationNumber,
            invoiceIssuerStatus: invoiceIssuerStatus ?? self.invoiceIssuerStatus,
            statusEffectiveFrom: statusEffectiveFrom ?? self.statusEffectiveFrom,
            statusEffectiveTo: statusEffectiveTo ?? self.statusEffectiveTo,
            address: self.address,
            phone: self.phone,
            email: self.email,
            defaultAccountId: defaultAccountId ?? self.defaultAccountId,
            defaultTaxCodeId: defaultTaxCodeId ?? self.defaultTaxCodeId,
            defaultProjectId: self.defaultProjectId,
            notes: self.notes,
            payeeInfo: payeeInfo ?? self.payeeInfo,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }

    var normalizedInvoiceRegistrationNumber: String? {
        RegistrationNumberNormalizer.normalize(invoiceRegistrationNumber)
    }
}
