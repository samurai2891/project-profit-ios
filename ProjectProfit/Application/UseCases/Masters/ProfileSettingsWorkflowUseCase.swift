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
                sensitivePayload: sensitivePayload
            )
            guard ports.persistSensitivePayload(sensitivePayload, state.businessProfile.id) else {
                return .failure(AppError.saveFailed(underlying: NSError(domain: "ProfileSecureStore", code: 1)))
            }

            let savedState = try await profileSettingsUseCase.save(
                command: command,
                currentState: state
            )
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
}
