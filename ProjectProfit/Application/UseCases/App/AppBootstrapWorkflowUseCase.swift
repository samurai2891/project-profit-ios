import Foundation

@MainActor
struct AppBootstrapWorkflowUseCase {
    func initialize(dataStore: DataStore) async throws {
        dataStore.loadData()
        _ = await ProfileSettingsWorkflowUseCase(dataStore: dataStore).loadProfile()
        dataStore.recalculateAllPartialPeriodProjects()
    }
}
