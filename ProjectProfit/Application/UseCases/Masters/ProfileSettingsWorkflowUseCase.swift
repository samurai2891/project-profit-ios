import Foundation
import SwiftData

@MainActor
struct ProfileSettingsWorkflowUseCase {
    struct Ports {
        let readSensitivePayload: @MainActor () -> ProfileSensitivePayload?
        let readCurrentTaxYear: @MainActor () -> Int?
        let applyState: @MainActor (ProfileSettingsState) -> Void
        let persistSensitivePayload: @MainActor (ProfileSensitivePayload, UUID) -> Bool
        let setLastError: @MainActor (AppError?) -> Void
    }

    private let modelContext: ModelContext
    private let ports: Ports
    private let profileSettingsUseCase: ProfileSettingsUseCase
    private let currentDateProvider: () -> Date

    init(
        modelContext: ModelContext,
        ports: Ports,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.ports = ports
        self.profileSettingsUseCase = ProfileSettingsUseCase(modelContext: modelContext)
        self.currentDateProvider = currentDateProvider
    }

    @discardableResult
    func loadProfile(defaultTaxYear: Int? = nil) async -> Bool {
        WorkflowPersistenceSupport.runLegacyProfileMigrationIfNeeded(modelContext: modelContext)

        let payload = ports.readSensitivePayload()
        let resolvedTaxYear = defaultTaxYear
            ?? ports.readCurrentTaxYear()
            ?? currentCalendarYear()

        do {
            let state = try await profileSettingsUseCase.load(
                defaultTaxYear: resolvedTaxYear,
                sensitivePayload: payload
            )
            ports.applyState(state)
            ports.setLastError(nil)
            return true
        } catch {
            AppLogger.dataStore.error("Failed to reload profile settings: \(error.localizedDescription)")
            ports.setLastError(.dataLoadFailed(underlying: error))
            return false
        }
    }

    @discardableResult
    func saveProfile(
        command: SaveProfileSettingsCommand,
        sensitivePayload: ProfileSensitivePayload
    ) async -> Result<Void, Error> {
        WorkflowPersistenceSupport.runLegacyProfileMigrationIfNeeded(modelContext: modelContext)

        do {
            let state = try await profileSettingsUseCase.load(
                defaultTaxYear: command.taxYear,
                sensitivePayload: ports.readSensitivePayload() ?? sensitivePayload
            )
            let savedState = try await profileSettingsUseCase.save(
                command: command,
                currentState: state
            )

            guard ports.persistSensitivePayload(sensitivePayload, savedState.businessProfile.id) else {
                let secureStoreError = makeSecureStoreSaveError()
                do {
                    let rollbackState = try await profileSettingsUseCase.save(
                        command: rollbackCommand(from: state),
                        currentState: savedState
                    )
                    ports.applyState(rollbackState)
                } catch {
                    let rollbackError = makeSecureStoreRollbackError(rollbackError: error)
                    ports.setLastError(.saveFailed(underlying: rollbackError))
                    AppLogger.dataStore.error("Failed to rollback profile settings after secure payload save failure: \(error.localizedDescription)")
                    return .failure(rollbackError)
                }

                ports.setLastError(.saveFailed(underlying: secureStoreError))
                return .failure(secureStoreError)
            }

            ports.applyState(savedState)
            ports.setLastError(nil)
            return .success(())
        } catch {
            AppLogger.dataStore.error("Failed to save profile settings: \(error.localizedDescription)")
            ports.setLastError(.saveFailed(underlying: error))
            return .failure(error)
        }
    }

    private func currentCalendarYear() -> Int {
        Calendar.current.component(.year, from: currentDateProvider())
    }

    private func rollbackCommand(from state: ProfileSettingsState) -> SaveProfileSettingsCommand {
        SaveProfileSettingsCommand(
            ownerName: state.businessProfile.ownerName,
            ownerNameKana: state.businessProfile.ownerNameKana,
            businessName: state.businessProfile.businessName,
            businessAddress: state.businessProfile.businessAddress,
            postalCode: state.businessProfile.postalCode,
            phoneNumber: state.businessProfile.phoneNumber,
            openingDate: state.businessProfile.openingDate,
            taxOfficeCode: state.businessProfile.taxOfficeCode,
            filingStyle: state.taxYearProfile.filingStyle,
            blueDeductionLevel: state.taxYearProfile.blueDeductionLevel,
            bookkeepingBasis: state.taxYearProfile.bookkeepingBasis,
            vatStatus: state.taxYearProfile.vatStatus,
            vatMethod: state.taxYearProfile.vatMethod,
            simplifiedBusinessCategory: state.taxYearProfile.simplifiedBusinessCategory,
            invoiceIssuerStatusAtYear: state.taxYearProfile.invoiceIssuerStatusAtYear,
            electronicBookLevel: state.taxYearProfile.electronicBookLevel,
            yearLockState: state.taxYearProfile.yearLockState,
            taxYear: state.taxYearProfile.taxYear
        )
    }

    private func makeSecureStoreSaveError() -> NSError {
        NSError(
            domain: "ProfileSecureStore",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "secure profile payload save failed"]
        )
    }

    private func makeSecureStoreRollbackError(rollbackError: Error) -> NSError {
        NSError(
            domain: "ProfileSecureStore",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "secure profile payload save failed and canonical rollback failed",
                NSUnderlyingErrorKey: rollbackError,
            ]
        )
    }
}
