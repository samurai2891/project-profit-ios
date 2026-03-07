import Foundation
import SwiftData

struct ProfileSettingsState: Sendable {
    let businessProfile: BusinessProfile
    let taxYearProfile: TaxYearProfile
}

struct SaveProfileSettingsCommand: Sendable {
    let ownerName: String
    let ownerNameKana: String
    let businessName: String
    let businessAddress: String
    let postalCode: String
    let phoneNumber: String
    let openingDate: Date?
    let taxOfficeCode: String?
    let filingStyle: FilingStyle
    let blueDeductionLevel: BlueDeductionLevel
    let bookkeepingBasis: BookkeepingBasis
    let vatStatus: VatStatus
    let vatMethod: VatMethod
    let simplifiedBusinessCategory: Int?
    let invoiceIssuerStatusAtYear: InvoiceIssuerStatus
    let electronicBookLevel: ElectronicBookLevel
    let yearLockState: YearLockState
    let taxYear: Int
}

enum ProfileSettingsUseCaseError: LocalizedError, Equatable {
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            message
        }
    }
}

@MainActor
struct ProfileSettingsUseCase {
    private let businessProfileRepository: any BusinessProfileRepository
    private let taxYearProfileRepository: any TaxYearProfileRepository
    private let taxYearPackProvider: any TaxYearPackProviderPort

    init(
        businessProfileRepository: any BusinessProfileRepository,
        taxYearProfileRepository: any TaxYearProfileRepository,
        taxYearPackProvider: any TaxYearPackProviderPort
    ) {
        self.businessProfileRepository = businessProfileRepository
        self.taxYearProfileRepository = taxYearProfileRepository
        self.taxYearPackProvider = taxYearPackProvider
    }

    init(modelContext: ModelContext) {
        self.init(
            businessProfileRepository: SwiftDataBusinessProfileRepository(modelContext: modelContext),
            taxYearProfileRepository: SwiftDataTaxYearProfileRepository(modelContext: modelContext),
            taxYearPackProvider: BundledTaxYearPackProvider(bundle: .main)
        )
    }

    func load(
        defaultTaxYear: Int,
        legacyProfile: PPAccountingProfile? = nil,
        sensitivePayload: ProfileSensitivePayload? = nil
    ) async throws -> ProfileSettingsState {
        if let businessProfile = try await businessProfileRepository.findDefault() {
            let taxYearProfile = try await existingOrDefaultTaxYearProfile(
                businessProfile: businessProfile,
                defaultTaxYear: defaultTaxYear
            )
            return ProfileSettingsState(businessProfile: businessProfile, taxYearProfile: taxYearProfile)
        }

        if let legacyProfile {
            let fallbackVersion = await defaultPackVersion(for: legacyProfile.fiscalYear)
            let businessProfile = LegacyAccountingProfileCanonicalMapper.businessProfile(
                from: legacyProfile,
                sensitivePayload: sensitivePayload
            )
            let taxYearProfile = LegacyAccountingProfileCanonicalMapper.taxYearProfile(
                from: legacyProfile,
                businessId: businessProfile.id,
                taxPackVersion: fallbackVersion
            )
            try await businessProfileRepository.save(businessProfile)
            try await taxYearProfileRepository.save(taxYearProfile)
            return ProfileSettingsState(businessProfile: businessProfile, taxYearProfile: taxYearProfile)
        }

        let fallbackVersion = await defaultPackVersion(for: defaultTaxYear)
        let businessProfile = BusinessProfile(ownerName: "")
        let taxYearProfile = TaxYearProfile(
            businessId: businessProfile.id,
            taxYear: defaultTaxYear,
            taxPackVersion: fallbackVersion
        )
        try await businessProfileRepository.save(businessProfile)
        try await taxYearProfileRepository.save(taxYearProfile)
        return ProfileSettingsState(businessProfile: businessProfile, taxYearProfile: taxYearProfile)
    }

    func save(
        command: SaveProfileSettingsCommand,
        currentState: ProfileSettingsState
    ) async throws -> ProfileSettingsState {
        let normalizedVatMethod = command.vatStatus == .exempt ? .general : command.vatMethod
        let normalizedDeductionLevel = command.filingStyle.isBlue ? command.blueDeductionLevel : .none
        let normalizedSimplifiedBusinessCategory: Int? = {
            guard command.vatStatus == .taxable && command.vatMethod == .simplified else {
                return nil
            }
            return command.simplifiedBusinessCategory ?? currentState.taxYearProfile.simplifiedBusinessCategory
        }()
        let normalizedBookkeepingBasis: BookkeepingBasis = {
            if command.filingStyle == .blueCashBasis {
                return .cashBasis
            }
            return command.bookkeepingBasis
        }()
        let packVersion = await defaultPackVersion(for: command.taxYear)

        let businessProfile = currentState.businessProfile.updated(
            ownerName: command.ownerName,
            ownerNameKana: command.ownerNameKana,
            businessName: command.businessName,
            businessAddress: command.businessAddress,
            postalCode: command.postalCode,
            phoneNumber: command.phoneNumber,
            openingDate: .some(command.openingDate),
            taxOfficeCode: .some(command.taxOfficeCode)
        )

        let taxYearProfile = TaxYearProfile(
            id: currentState.taxYearProfile.id,
            businessId: currentState.taxYearProfile.businessId,
            taxYear: command.taxYear,
            filingStyle: command.filingStyle,
            blueDeductionLevel: normalizedDeductionLevel,
            bookkeepingBasis: normalizedBookkeepingBasis,
            vatStatus: command.vatStatus,
            vatMethod: normalizedVatMethod,
            simplifiedBusinessCategory: normalizedSimplifiedBusinessCategory,
            invoiceIssuerStatusAtYear: command.invoiceIssuerStatusAtYear,
            electronicBookLevel: command.electronicBookLevel,
            etaxSubmissionPlanned: currentState.taxYearProfile.etaxSubmissionPlanned,
            yearLockState: command.yearLockState,
            taxPackVersion: packVersion,
            createdAt: currentState.taxYearProfile.createdAt,
            updatedAt: Date()
        )

        do {
            try TaxYearStateUseCase.validateTransition(
                from: currentState.taxYearProfile,
                to: taxYearProfile
            )
        } catch let error as TaxYearStateUseCaseError {
            throw ProfileSettingsUseCaseError.validationFailed(error.localizedDescription)
        } catch {
            throw error
        }

        try await businessProfileRepository.save(businessProfile)
        try await taxYearProfileRepository.save(taxYearProfile)
        return ProfileSettingsState(businessProfile: businessProfile, taxYearProfile: taxYearProfile)
    }

    private func existingOrDefaultTaxYearProfile(
        businessProfile: BusinessProfile,
        defaultTaxYear: Int
    ) async throws -> TaxYearProfile {
        if let existing = try await taxYearProfileRepository.findByBusinessAndYear(
            businessId: businessProfile.id,
            taxYear: defaultTaxYear
        ) {
            return existing
        }

        let fallbackVersion = await defaultPackVersion(for: defaultTaxYear)
        let created = TaxYearProfile(
            businessId: businessProfile.id,
            taxYear: defaultTaxYear,
            taxPackVersion: fallbackVersion
        )
        try await taxYearProfileRepository.save(created)
        return created
    }

    private func defaultPackVersion(for taxYear: Int) async -> String {
        if let pack = try? await taxYearPackProvider.pack(for: taxYear) {
            return pack.version
        }
        return "\(taxYear)-v1"
    }
}
