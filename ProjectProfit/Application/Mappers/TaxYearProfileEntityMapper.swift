import Foundation

/// TaxYearProfile ↔ TaxYearProfileEntity の変換
enum TaxYearProfileEntityMapper {

    static func toDomain(_ entity: TaxYearProfileEntity) -> TaxYearProfile {
        TaxYearProfile(
            id: entity.profileId,
            businessId: entity.businessId,
            taxYear: entity.taxYear,
            filingStyle: FilingStyle(rawValue: entity.filingStyleRaw) ?? .blueGeneral,
            blueDeductionLevel: BlueDeductionLevel(rawValue: entity.blueDeductionLevelRaw) ?? .sixtyFive,
            bookkeepingBasis: BookkeepingBasis(rawValue: entity.bookkeepingBasisRaw) ?? .doubleEntry,
            vatStatus: VatStatus(rawValue: entity.vatStatusRaw) ?? .exempt,
            vatMethod: VatMethod(rawValue: entity.vatMethodRaw) ?? .general,
            simplifiedBusinessCategory: entity.simplifiedBusinessCategory,
            invoiceIssuerStatusAtYear: InvoiceIssuerStatus(rawValue: entity.invoiceIssuerStatusAtYearRaw) ?? .unknown,
            electronicBookLevel: ElectronicBookLevel(rawValue: entity.electronicBookLevelRaw) ?? .none,
            etaxSubmissionPlanned: entity.etaxSubmissionPlanned,
            yearLockState: YearLockState(rawValue: entity.yearLockStateRaw) ?? .open,
            taxPackVersion: entity.taxPackVersion,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    static func toEntity(_ domain: TaxYearProfile) -> TaxYearProfileEntity {
        TaxYearProfileEntity(
            profileId: domain.id,
            businessId: domain.businessId,
            taxYear: domain.taxYear,
            filingStyleRaw: domain.filingStyle.rawValue,
            blueDeductionLevelRaw: domain.blueDeductionLevel.rawValue,
            bookkeepingBasisRaw: domain.bookkeepingBasis.rawValue,
            vatStatusRaw: domain.vatStatus.rawValue,
            vatMethodRaw: domain.vatMethod.rawValue,
            simplifiedBusinessCategory: domain.simplifiedBusinessCategory,
            invoiceIssuerStatusAtYearRaw: domain.invoiceIssuerStatusAtYear.rawValue,
            electronicBookLevelRaw: domain.electronicBookLevel.rawValue,
            etaxSubmissionPlanned: domain.etaxSubmissionPlanned,
            yearLockStateRaw: domain.yearLockState.rawValue,
            taxPackVersion: domain.taxPackVersion,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    static func update(_ entity: TaxYearProfileEntity, from domain: TaxYearProfile) {
        entity.businessId = domain.businessId
        entity.taxYear = domain.taxYear
        entity.filingStyleRaw = domain.filingStyle.rawValue
        entity.blueDeductionLevelRaw = domain.blueDeductionLevel.rawValue
        entity.bookkeepingBasisRaw = domain.bookkeepingBasis.rawValue
        entity.vatStatusRaw = domain.vatStatus.rawValue
        entity.vatMethodRaw = domain.vatMethod.rawValue
        entity.simplifiedBusinessCategory = domain.simplifiedBusinessCategory
        entity.invoiceIssuerStatusAtYearRaw = domain.invoiceIssuerStatusAtYear.rawValue
        entity.electronicBookLevelRaw = domain.electronicBookLevel.rawValue
        entity.etaxSubmissionPlanned = domain.etaxSubmissionPlanned
        entity.yearLockStateRaw = domain.yearLockState.rawValue
        entity.taxPackVersion = domain.taxPackVersion
        entity.updatedAt = domain.updatedAt
    }
}
