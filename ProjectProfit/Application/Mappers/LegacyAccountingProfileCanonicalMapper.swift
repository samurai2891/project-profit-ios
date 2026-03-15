import Foundation

/// 旧プロフィールから canonical profile への変換（読み取り専用、新規作成には使用しない）
enum LegacyAccountingProfileCanonicalMapper {

    @available(*, deprecated, message: "Legacy → canonical マイグレーション専用。新規コードでは使用しない。")
    static func businessProfile(
        from legacy: PPAccountingProfile,
        sensitivePayload: ProfileSensitivePayload?,
        existingId: UUID? = nil
    ) -> BusinessProfile {
        BusinessProfile(
            id: existingId ?? UUID(),
            ownerName: legacy.ownerName,
            ownerNameKana: normalized(sensitivePayload?.ownerNameKana ?? legacy.ownerNameKana),
            businessName: legacy.businessName,
            defaultPaymentAccountId: legacy.defaultPaymentAccountId,
            businessAddress: normalized(sensitivePayload?.address ?? legacy.address),
            postalCode: normalized(sensitivePayload?.postalCode ?? legacy.postalCode),
            phoneNumber: normalized(sensitivePayload?.phoneNumber ?? legacy.phoneNumber),
            openingDate: legacy.openingDate,
            taxOfficeCode: normalized(legacy.taxOfficeCode),
            invoiceRegistrationNumber: nil,
            invoiceIssuerStatus: .unknown,
            defaultCurrency: "JPY",
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt
        )
    }

    @available(*, deprecated, message: "Legacy → canonical マイグレーション専用。新規コードでは使用しない。")
    static func taxYearProfile(
        from legacy: PPAccountingProfile,
        businessId: UUID,
        taxPackVersion: String,
        existingId: UUID? = nil
    ) -> TaxYearProfile {
        let bookkeepingBasis: BookkeepingBasis = switch legacy.bookkeepingMode {
        case .singleEntry:
            .singleEntry
        case .doubleEntry, .auto, .locked:
            .doubleEntry
        }

        return TaxYearProfile(
            id: existingId ?? UUID(),
            businessId: businessId,
            taxYear: legacy.fiscalYear,
            filingStyle: legacy.isBlueReturn ? .blueGeneral : .white,
            blueDeductionLevel: legacy.isBlueReturn ? .sixtyFive : .none,
            bookkeepingBasis: bookkeepingBasis,
            vatStatus: .exempt,
            vatMethod: .general,
            simplifiedBusinessCategory: nil,
            invoiceIssuerStatusAtYear: .unknown,
            electronicBookLevel: .none,
            etaxSubmissionPlanned: false,
            yearLockState: legacy.isYearLocked(legacy.fiscalYear) ? .finalLock : .open,
            taxPackVersion: taxPackVersion,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt
        )
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
