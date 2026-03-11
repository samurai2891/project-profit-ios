import Foundation
import SwiftData

@MainActor
struct AppShellWorkflowUseCase {
    func reloadStoreState(dataStore: DataStore) {
        dataStore.loadData()
        dataStore.recalculateAllPartialPeriodProjects()
    }

    func refreshRecurringPreview(dataStore: DataStore) -> [RecurringPreviewItem] {
        RecurringWorkflowUseCase(modelContext: dataStore.modelContext).previewRecurringTransactions()
    }

    func currentError(dataStore: DataStore) -> AppError? {
        dataStore.lastError
    }

    func dismissCurrentError(dataStore: DataStore) {
        dataStore.lastError = nil
    }
}
