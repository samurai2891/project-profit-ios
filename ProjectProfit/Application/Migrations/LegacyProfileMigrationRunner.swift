import Foundation
import SwiftData

enum LegacyProfileMigrationOutcome: String, Sendable, Equatable {
    case noLegacyProfile
    case alreadyMigrated
    case dryRunReady
    case executed
    case schemaUnavailable
    case failed
}

struct LegacyProfileMigrationReport: Sendable {
    let outcome: LegacyProfileMigrationOutcome
    let legacyProfileId: String?
    let businessProfileId: UUID?
    let taxYear: Int?
    let createdBusinessProfile: Bool
    let updatedBusinessProfile: Bool
    let createdTaxYearProfile: Bool
    let updatedTaxYearProfile: Bool
    let deletedLegacyProfiles: Int
    let warnings: [String]
    let errorDescription: String?

    var needsMigration: Bool {
        outcome == .dryRunReady
    }

    static func noLegacyProfile() -> LegacyProfileMigrationReport {
        LegacyProfileMigrationReport(
            outcome: .noLegacyProfile,
            legacyProfileId: nil,
            businessProfileId: nil,
            taxYear: nil,
            createdBusinessProfile: false,
            updatedBusinessProfile: false,
            createdTaxYearProfile: false,
            updatedTaxYearProfile: false,
            deletedLegacyProfiles: 0,
            warnings: [],
            errorDescription: nil
        )
    }
}

@MainActor
final class LegacyProfileMigrationRunner {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func dryRun() -> LegacyProfileMigrationReport {
        run(mode: .dryRun)
    }

    @discardableResult
    func execute() -> LegacyProfileMigrationReport {
        run(mode: .execute)
    }

    @discardableResult
    func executeIfNeeded() -> LegacyProfileMigrationReport {
        let report = dryRun()
        switch report.outcome {
        case .dryRunReady:
            return execute()
        default:
            return report
        }
    }

    private enum Mode {
        case dryRun
        case execute
    }

    private func run(mode: Mode) -> LegacyProfileMigrationReport {
        do {
            let legacyProfiles = try modelContext.fetch(
                FetchDescriptor<PPAccountingProfile>(sortBy: [SortDescriptor(\.createdAt)])
            )

            let businessDescriptor = FetchDescriptor<BusinessProfileEntity>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
            let existingBusiness = try modelContext.fetch(businessDescriptor).first
            let taxYearEntities = try modelContext.fetch(FetchDescriptor<TaxYearProfileEntity>())

            guard let legacy = legacyProfiles.first else {
                if existingBusiness != nil || !taxYearEntities.isEmpty {
                    return LegacyProfileMigrationReport(
                        outcome: .alreadyMigrated,
                        legacyProfileId: nil,
                        businessProfileId: existingBusiness?.businessId,
                        taxYear: nil,
                        createdBusinessProfile: false,
                        updatedBusinessProfile: false,
                        createdTaxYearProfile: false,
                        updatedTaxYearProfile: false,
                        deletedLegacyProfiles: 0,
                        warnings: [],
                        errorDescription: nil
                    )
                }
                return .noLegacyProfile()
            }

            let businessId = existingBusiness?.businessId ?? UUID()
            let businessDraft = makeBusinessProfileEntity(legacy: legacy, businessId: businessId)
            var warnings: [String] = []

            let shouldCreateBusiness = existingBusiness == nil
            var knownTaxYears = Set(
                taxYearEntities
                    .filter { $0.businessId == businessId }
                    .map(\.taxYear)
            )
            var taxProfilesToCreate: [TaxYearProfileEntity] = []
            for legacyProfile in legacyProfiles {
                guard !knownTaxYears.contains(legacyProfile.fiscalYear) else {
                    continue
                }
                taxProfilesToCreate.append(
                    makeTaxYearProfileEntity(legacy: legacyProfile, businessId: businessId)
                )
                knownTaxYears.insert(legacyProfile.fiscalYear)
            }
            let shouldCreateTax = !taxProfilesToCreate.isEmpty

            if mode == .execute {
                if shouldCreateBusiness {
                    modelContext.insert(businessDraft)
                }

                taxProfilesToCreate.forEach(modelContext.insert)
                try modelContext.save()

                warnings.append(contentsOf: migrateSecurePayloadIfNeeded(
                    legacyProfileIds: legacyProfiles.map(\.id),
                    canonicalBusinessId: businessId
                ))

                legacyProfiles.forEach(modelContext.delete)
                if !legacyProfiles.isEmpty {
                    try modelContext.save()
                }
            }

            return LegacyProfileMigrationReport(
                outcome: mode == .dryRun ? .dryRunReady : .executed,
                legacyProfileId: legacy.id,
                businessProfileId: businessId,
                taxYear: legacy.fiscalYear,
                createdBusinessProfile: shouldCreateBusiness,
                updatedBusinessProfile: false,
                createdTaxYearProfile: shouldCreateTax,
                updatedTaxYearProfile: false,
                deletedLegacyProfiles: mode == .execute ? legacyProfiles.count : 0,
                warnings: warnings,
                errorDescription: nil
            )
        } catch {
            let message = error.localizedDescription
            let schemaUnavailable = message.localizedCaseInsensitiveContains("schema") ||
                message.localizedCaseInsensitiveContains("entity") ||
                message.localizedCaseInsensitiveContains("model")

            return LegacyProfileMigrationReport(
                outcome: schemaUnavailable ? .schemaUnavailable : .failed,
                legacyProfileId: nil,
                businessProfileId: nil,
                taxYear: nil,
                createdBusinessProfile: false,
                updatedBusinessProfile: false,
                createdTaxYearProfile: false,
                updatedTaxYearProfile: false,
                deletedLegacyProfiles: 0,
                warnings: schemaUnavailable ? ["canonical schema unavailable in current container"] : [],
                errorDescription: message
            )
        }
    }

    private func makeBusinessProfileEntity(legacy: PPAccountingProfile, businessId: UUID) -> BusinessProfileEntity {
        BusinessProfileEntity(
            businessId: businessId,
            ownerName: legacy.ownerName,
            ownerNameKana: legacy.ownerNameKana ?? "",
            businessName: legacy.businessName,
            defaultPaymentAccountId: legacy.defaultPaymentAccountId,
            businessAddress: legacy.address ?? "",
            postalCode: legacy.postalCode ?? "",
            phoneNumber: legacy.phoneNumber ?? "",
            openingDate: legacy.openingDate,
            taxOfficeCode: legacy.taxOfficeCode,
            invoiceRegistrationNumber: nil,
            invoiceIssuerStatusRaw: InvoiceIssuerStatus.unknown.rawValue,
            defaultCurrency: "JPY",
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt
        )
    }

    private func makeTaxYearProfileEntity(legacy: PPAccountingProfile, businessId: UUID) -> TaxYearProfileEntity {
        TaxYearProfileEntity(
            profileId: UUID(),
            businessId: businessId,
            taxYear: legacy.fiscalYear,
            filingStyleRaw: legacy.isBlueReturn ? FilingStyle.blueGeneral.rawValue : FilingStyle.white.rawValue,
            blueDeductionLevelRaw: mapBlueDeductionLevel(legacy).rawValue,
            bookkeepingBasisRaw: mapBookkeepingBasis(legacy).rawValue,
            vatStatusRaw: VatStatus.exempt.rawValue,
            vatMethodRaw: VatMethod.general.rawValue,
            simplifiedBusinessCategory: nil,
            invoiceIssuerStatusAtYearRaw: InvoiceIssuerStatus.unknown.rawValue,
            electronicBookLevelRaw: ElectronicBookLevel.none.rawValue,
            etaxSubmissionPlanned: false,
            yearLockStateRaw: legacy.isYearLocked(legacy.fiscalYear) ? YearLockState.finalLock.rawValue : YearLockState.open.rawValue,
            taxPackVersion: "legacy-migrated",
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt
        )
    }

    private func mapBookkeepingBasis(_ legacy: PPAccountingProfile) -> BookkeepingBasis {
        switch legacy.bookkeepingMode {
        case .singleEntry:
            return .singleEntry
        case .doubleEntry:
            return .doubleEntry
        case .auto, .locked:
            return .doubleEntry
        }
    }

    private func mapBlueDeductionLevel(_ legacy: PPAccountingProfile) -> BlueDeductionLevel {
        guard legacy.isBlueReturn else {
            return .none
        }

        switch legacy.bookkeepingMode {
        case .singleEntry:
            return .ten
        case .doubleEntry, .auto, .locked:
            return .sixtyFive
        }
    }

    private func migrateSecurePayloadIfNeeded(
        legacyProfileIds: [String],
        canonicalBusinessId: UUID
    ) -> [String] {
        let canonicalProfileId = canonicalBusinessId.uuidString
        var warnings: [String] = []
        var hasCanonicalPayload = ProfileSecureStore.load(profileId: canonicalProfileId) != nil

        for legacyProfileId in Set(legacyProfileIds) where legacyProfileId != canonicalProfileId {
            guard let payload = ProfileSecureStore.load(profileId: legacyProfileId) else {
                continue
            }
            if !hasCanonicalPayload {
                guard ProfileSecureStore.save(payload, profileId: canonicalProfileId) else {
                    warnings.append("secure payload migration failed")
                    continue
                }
                hasCanonicalPayload = true
            }
            _ = ProfileSecureStore.delete(profileId: legacyProfileId)
        }
        return warnings
    }

}
