import Foundation
import SwiftData

enum TaxYearStateUseCaseError: LocalizedError, Equatable {
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            message
        }
    }
}

@MainActor
struct TaxYearStateUseCase {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    static func validateTransition(
        from current: TaxYearProfile,
        to proposed: TaxYearProfile
    ) throws {
        if current.filingStyle != proposed.filingStyle &&
            !TaxStatusMachine.isValidFilingStyleTransition(
                from: current.filingStyle,
                to: proposed.filingStyle
            )
        {
            throw TaxYearStateUseCaseError.validationFailed(
                "申告方式を\(current.filingStyle.displayName)から\(proposed.filingStyle.displayName)へ変更できません"
            )
        }

        if current.vatStatus != proposed.vatStatus &&
            !TaxStatusMachine.isValidVatTransition(
                from: current.vatStatus,
                to: proposed.vatStatus,
                invoiceStatus: proposed.invoiceIssuerStatusAtYear
            )
        {
            throw TaxYearStateUseCaseError.validationFailed(
                "インボイス登録状態では消費税区分を\(current.vatStatus.displayName)から\(proposed.vatStatus.displayName)へ変更できません"
            )
        }

        if current.yearLockState != proposed.yearLockState &&
            !TaxStatusMachine.isValidLockTransition(
                from: current.yearLockState,
                to: proposed.yearLockState
            )
        {
            throw TaxYearStateUseCaseError.validationFailed(
                "年度状態を\(current.yearLockState.displayName)から\(proposed.yearLockState.displayName)へ変更できません"
            )
        }

        if let error = filingPreflightIssues(for: proposed).first(where: { $0.severity == .error }) {
            throw TaxYearStateUseCaseError.validationFailed(error.message)
        }
    }

    static func filingPreflightIssues(for profile: TaxYearProfile) -> [TaxValidationIssue] {
        TaxStatusMachine.validate(profile)
    }

    func filingPreflightIssues(
        businessId: UUID,
        taxYear: Int,
        fallbackProfile: TaxYearProfile? = nil
    ) throws -> [TaxValidationIssue] {
        let profile = try resolvedProfile(
            businessId: businessId,
            taxYear: taxYear,
            fallbackProfile: fallbackProfile
        )
        return Self.filingPreflightIssues(for: profile)
    }

    func transitionYearLock(
        businessId: UUID,
        taxYear: Int,
        targetState: YearLockState,
        fallbackProfile: TaxYearProfile? = nil
    ) throws -> TaxYearProfile {
        let current = try resolvedProfile(
            businessId: businessId,
            taxYear: taxYear,
            fallbackProfile: fallbackProfile
        )
        let proposed = current.updated(yearLockState: targetState)

        try Self.validateTransition(from: current, to: proposed)
        try save(proposed)
        return proposed
    }

    private func resolvedProfile(
        businessId: UUID,
        taxYear: Int,
        fallbackProfile: TaxYearProfile? = nil
    ) throws -> TaxYearProfile {
        if let fallbackProfile,
           fallbackProfile.businessId == businessId,
           fallbackProfile.taxYear == taxYear
        {
            return fallbackProfile
        }

        let descriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == taxYear
            }
        )
        if let entity = try modelContext.fetch(descriptor).first {
            return TaxYearProfileEntityMapper.toDomain(entity)
        }

        return TaxYearProfile(
            businessId: businessId,
            taxYear: taxYear,
            taxPackVersion: "\(taxYear)-v1"
        )
    }

    private func save(_ profile: TaxYearProfile) throws {
        let descriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate { $0.profileId == profile.id }
        )
        if let entity = try modelContext.fetch(descriptor).first {
            TaxYearProfileEntityMapper.update(entity, from: profile)
        } else {
            modelContext.insert(TaxYearProfileEntityMapper.toEntity(profile))
        }
        try modelContext.save()
    }
}
