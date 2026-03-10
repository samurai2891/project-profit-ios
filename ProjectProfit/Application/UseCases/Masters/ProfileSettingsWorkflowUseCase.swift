import Foundation

@MainActor
struct ProfileSettingsWorkflowUseCase {
    private let dataStore: DataStore
    private let profileSettingsUseCase: ProfileSettingsUseCase
    private let currentDateProvider: () -> Date

    init(
        dataStore: DataStore,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.dataStore = dataStore
        self.profileSettingsUseCase = ProfileSettingsUseCase(modelContext: dataStore.modelContext)
        self.currentDateProvider = currentDateProvider
    }

    @discardableResult
    func loadProfile(defaultTaxYear: Int? = nil) async -> Bool {
        dataStore.runLegacyProfileMigrationIfNeeded()
        dataStore.refreshCanonicalProfileCache()

        let payload = dataStore.profileSensitivePayload
        let resolvedTaxYear = defaultTaxYear
            ?? dataStore.currentTaxYearProfile?.taxYear
            ?? currentCalendarYear()

        do {
            let state = try await profileSettingsUseCase.load(
                defaultTaxYear: resolvedTaxYear,
                sensitivePayload: payload
            )
            dataStore.applyProfileSettingsState(state)
            dataStore.lastError = nil
            return true
        } catch {
            AppLogger.dataStore.error("Failed to reload profile settings: \(error.localizedDescription)")
            dataStore.lastError = .dataLoadFailed(underlying: error)
            return false
        }
    }

    @discardableResult
    func saveProfile(
        command: SaveProfileSettingsCommand,
        sensitivePayload: ProfileSensitivePayload
    ) async -> Result<Void, Error> {
        dataStore.runLegacyProfileMigrationIfNeeded()
        dataStore.refreshCanonicalProfileCache()

        do {
            let state = try await profileSettingsUseCase.load(
                defaultTaxYear: command.taxYear,
                sensitivePayload: sensitivePayload
            )
            guard dataStore.persistSensitivePayload(sensitivePayload, businessProfileId: state.businessProfile.id) else {
                return .failure(AppError.saveFailed(underlying: NSError(domain: "ProfileSecureStore", code: 1)))
            }

            let savedState = try await profileSettingsUseCase.save(
                command: command,
                currentState: state
            )
            dataStore.applyProfileSettingsState(savedState)

            if dataStore.save() {
                dataStore.lastError = nil
                return .success(())
            }
            return .failure(dataStore.lastError ?? AppError.saveFailed(underlying: NSError(domain: "ProfileSettings", code: 2)))
        } catch {
            AppLogger.dataStore.error("Failed to save profile settings: \(error.localizedDescription)")
            dataStore.lastError = .saveFailed(underlying: error)
            return .failure(error)
        }
    }

    private func currentCalendarYear() -> Int {
        Calendar.current.component(.year, from: currentDateProvider())
    }
}
