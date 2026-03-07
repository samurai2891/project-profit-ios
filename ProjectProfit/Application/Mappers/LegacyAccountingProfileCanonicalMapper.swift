import Foundation

/// 旧プロフィールと canonical profile の相互変換
enum LegacyAccountingProfileCanonicalMapper {

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

    static func syncLegacyProfile(
        _ legacy: PPAccountingProfile,
        from businessProfile: BusinessProfile,
        taxYearProfile: TaxYearProfile
    ) {
        legacy.fiscalYear = taxYearProfile.taxYear
        legacy.bookkeepingMode = bookkeepingMode(for: taxYearProfile.bookkeepingBasis)
        legacy.businessName = businessProfile.businessName
        legacy.ownerName = businessProfile.ownerName
        legacy.taxOfficeCode = normalized(businessProfile.taxOfficeCode)
        legacy.isBlueReturn = taxYearProfile.filingStyle.isBlue
        legacy.defaultPaymentAccountId = businessProfile.defaultPaymentAccountId
        legacy.openingDate = businessProfile.openingDate

        var lockedYears = Set(legacy.lockedYears ?? [])
        if taxYearProfile.yearLockState == .open {
            lockedYears.remove(taxYearProfile.taxYear)
        } else {
            lockedYears.insert(taxYearProfile.taxYear)
        }
        legacy.lockedYears = lockedYears.sorted()
        legacy.updatedAt = Date()
    }

    private static func bookkeepingMode(for basis: BookkeepingBasis) -> BookkeepingMode {
        switch basis {
        case .singleEntry:
            .singleEntry
        case .doubleEntry, .cashBasis:
            .doubleEntry
        }
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
