import Foundation

/// Counterparty ↔ CounterpartyEntity の変換
enum CounterpartyEntityMapper {
    static func toDomain(_ entity: CounterpartyEntity) -> Counterparty {
        let payeeInfo: PayeeInfo? = entity.payeeIsWithholdingSubject
            ? PayeeInfo(
                isWithholdingSubject: true,
                withholdingCategory: WithholdingTaxCode.resolve(id: entity.payeeWithholdingCategoryRaw)
            )
            : entity.payeeWithholdingCategoryRaw != nil
                ? PayeeInfo(
                    isWithholdingSubject: false,
                    withholdingCategory: WithholdingTaxCode.resolve(id: entity.payeeWithholdingCategoryRaw)
                )
                : nil

        return Counterparty(
            id: entity.counterpartyId,
            businessId: entity.businessId,
            displayName: entity.displayName,
            kana: entity.kana,
            legalName: entity.legalName,
            corporateNumber: entity.corporateNumber,
            invoiceRegistrationNumber: entity.invoiceRegistrationNumber,
            invoiceIssuerStatus: InvoiceIssuerStatus(rawValue: entity.invoiceIssuerStatusRaw) ?? .unknown,
            statusEffectiveFrom: entity.statusEffectiveFrom,
            statusEffectiveTo: entity.statusEffectiveTo,
            address: entity.address,
            phone: entity.phone,
            email: entity.email,
            defaultAccountId: entity.defaultAccountId,
            defaultTaxCodeId: entity.defaultTaxCodeId,
            defaultProjectId: entity.defaultProjectId,
            notes: entity.notes,
            payeeInfo: payeeInfo,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    static func toEntity(_ domain: Counterparty) -> CounterpartyEntity {
        CounterpartyEntity(
            counterpartyId: domain.id,
            businessId: domain.businessId,
            displayName: domain.displayName,
            kana: domain.kana,
            legalName: domain.legalName,
            corporateNumber: domain.corporateNumber,
            invoiceRegistrationNumber: domain.invoiceRegistrationNumber,
            invoiceIssuerStatusRaw: domain.invoiceIssuerStatus.rawValue,
            statusEffectiveFrom: domain.statusEffectiveFrom,
            statusEffectiveTo: domain.statusEffectiveTo,
            address: domain.address,
            phone: domain.phone,
            email: domain.email,
            defaultAccountId: domain.defaultAccountId,
            defaultTaxCodeId: domain.defaultTaxCodeId,
            defaultProjectId: domain.defaultProjectId,
            notes: domain.notes,
            payeeIsWithholdingSubject: domain.payeeInfo?.isWithholdingSubject ?? false,
            payeeWithholdingCategoryRaw: domain.payeeInfo?.withholdingCategory?.rawValue,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    static func update(_ entity: CounterpartyEntity, from domain: Counterparty) {
        entity.businessId = domain.businessId
        entity.displayName = domain.displayName
        entity.kana = domain.kana
        entity.legalName = domain.legalName
        entity.corporateNumber = domain.corporateNumber
        entity.invoiceRegistrationNumber = domain.invoiceRegistrationNumber
        entity.invoiceIssuerStatusRaw = domain.invoiceIssuerStatus.rawValue
        entity.statusEffectiveFrom = domain.statusEffectiveFrom
        entity.statusEffectiveTo = domain.statusEffectiveTo
        entity.address = domain.address
        entity.phone = domain.phone
        entity.email = domain.email
        entity.defaultAccountId = domain.defaultAccountId
        entity.defaultTaxCodeId = domain.defaultTaxCodeId
        entity.defaultProjectId = domain.defaultProjectId
        entity.notes = domain.notes
        entity.payeeIsWithholdingSubject = domain.payeeInfo?.isWithholdingSubject ?? false
        entity.payeeWithholdingCategoryRaw = domain.payeeInfo?.withholdingCategory?.rawValue
        entity.updatedAt = domain.updatedAt
    }
}
