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
        guard report.needsMigration else {
            return report
        }
        return execute()
    }

    private enum Mode {
        case dryRun
        case execute
    }

    private func run(mode: Mode) -> LegacyProfileMigrationReport {
        do {
            let legacyDescriptor = FetchDescriptor<PPAccountingProfile>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
            guard let legacy = try modelContext.fetch(legacyDescriptor).first else {
                return .noLegacyProfile()
            }

            let businessDescriptor = FetchDescriptor<BusinessProfileEntity>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
            let existingBusiness = try modelContext.fetch(businessDescriptor).first
            let businessId = existingBusiness?.businessId ?? UUID()

            let taxDescriptor = FetchDescriptor<TaxYearProfileEntity>()
            let existingTaxYear = try modelContext.fetch(taxDescriptor).first {
                $0.businessId == businessId && $0.taxYear == legacy.fiscalYear
            }

            let businessDraft = makeBusinessProfileEntity(legacy: legacy, businessId: businessId)
            let taxYearDraft = makeTaxYearProfileEntity(legacy: legacy, businessId: businessId)

            let shouldCreateBusiness = existingBusiness == nil
            let shouldCreateTax = existingTaxYear == nil
            let needsMigration = shouldCreateBusiness || shouldCreateTax

            if !needsMigration {
                return LegacyProfileMigrationReport(
                    outcome: .alreadyMigrated,
                    legacyProfileId: legacy.id,
                    businessProfileId: businessId,
                    taxYear: legacy.fiscalYear,
                    createdBusinessProfile: false,
                    updatedBusinessProfile: false,
                    createdTaxYearProfile: false,
                    updatedTaxYearProfile: false,
                    warnings: [],
                    errorDescription: nil
                )
            }

            if mode == .execute {
                if existingBusiness == nil {
                    modelContext.insert(businessDraft)
                }

                if existingTaxYear == nil {
                    modelContext.insert(taxYearDraft)
                }

                try modelContext.save()
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
                warnings: [],
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

}
