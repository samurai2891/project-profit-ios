import Foundation

/// BusinessProfile ↔ BusinessProfileEntity の変換
enum BusinessProfileEntityMapper {

    static func toDomain(_ entity: BusinessProfileEntity) -> BusinessProfile {
        BusinessProfile(
            id: entity.businessId,
            ownerName: entity.ownerName,
            ownerNameKana: entity.ownerNameKana,
            businessName: entity.businessName,
            businessAddress: entity.businessAddress,
            postalCode: entity.postalCode,
            phoneNumber: entity.phoneNumber,
            openingDate: entity.openingDate,
            taxOfficeCode: entity.taxOfficeCode,
            invoiceRegistrationNumber: entity.invoiceRegistrationNumber,
            invoiceIssuerStatus: InvoiceIssuerStatus(rawValue: entity.invoiceIssuerStatusRaw) ?? .unknown,
            defaultCurrency: entity.defaultCurrency,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    static func toEntity(_ domain: BusinessProfile) -> BusinessProfileEntity {
        BusinessProfileEntity(
            businessId: domain.id,
            ownerName: domain.ownerName,
            ownerNameKana: domain.ownerNameKana,
            businessName: domain.businessName,
            businessAddress: domain.businessAddress,
            postalCode: domain.postalCode,
            phoneNumber: domain.phoneNumber,
            openingDate: domain.openingDate,
            taxOfficeCode: domain.taxOfficeCode,
            invoiceRegistrationNumber: domain.invoiceRegistrationNumber,
            invoiceIssuerStatusRaw: domain.invoiceIssuerStatus.rawValue,
            defaultCurrency: domain.defaultCurrency,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    static func update(_ entity: BusinessProfileEntity, from domain: BusinessProfile) {
        entity.ownerName = domain.ownerName
        entity.ownerNameKana = domain.ownerNameKana
        entity.businessName = domain.businessName
        entity.businessAddress = domain.businessAddress
        entity.postalCode = domain.postalCode
        entity.phoneNumber = domain.phoneNumber
        entity.openingDate = domain.openingDate
        entity.taxOfficeCode = domain.taxOfficeCode
        entity.invoiceRegistrationNumber = domain.invoiceRegistrationNumber
        entity.invoiceIssuerStatusRaw = domain.invoiceIssuerStatus.rawValue
        entity.updatedAt = domain.updatedAt
    }
}
