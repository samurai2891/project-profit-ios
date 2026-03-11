import Foundation

typealias LegacyDataMigrationResult = LegacyDataMigrationExecutor.MigrationResult

@MainActor
struct SettingsMaintenanceWorkflowUseCase {
    private let dataStore: DataStore

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    func exportBackup(scope: BackupScope) throws -> BackupExportResult {
        try BackupService(modelContext: dataStore.modelContext).export(scope: scope)
    }

    func dryRunRestore(snapshotURL: URL) throws -> RestoreDryRunReport {
        try RestoreService(modelContext: dataStore.modelContext).dryRun(snapshotURL: snapshotURL)
    }

    func applyRestore(snapshotURL: URL) throws -> RestoreApplyResult {
        let result = try RestoreService(modelContext: dataStore.modelContext).apply(snapshotURL: snapshotURL)
        reloadStoreState()
        return result
    }

    func dryRunMigration() throws -> MigrationDryRunReport {
        try MigrationReportRunner(modelContext: dataStore.modelContext).dryRun()
    }

    func executeMigration() throws -> LegacyDataMigrationResult {
        guard let businessId = dataStore.businessProfile?.id else {
            throw SettingsMaintenanceWorkflowError.businessProfileMissing
        }

        let result = try LegacyDataMigrationExecutor(modelContext: dataStore.modelContext)
            .execute(businessId: businessId)
        reloadStoreState()
        return result
    }

    private func reloadStoreState() {
        dataStore.loadData()
        dataStore.recalculateAllPartialPeriodProjects()
    }
}

enum SettingsMaintenanceWorkflowError: LocalizedError {
    case businessProfileMissing

    var errorDescription: String? {
        switch self {
        case .businessProfileMissing:
            return "事業者情報が未設定です"
        }
    }
}
