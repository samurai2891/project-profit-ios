import Foundation
import SwiftData

typealias LegacyDataMigrationResult = LegacyDataMigrationExecutor.MigrationResult

@MainActor
struct SettingsMaintenanceWorkflowUseCase {
    private let modelContext: ModelContext
    private let reloadStoreState: @MainActor () -> Void

    init(
        modelContext: ModelContext,
        reloadStoreState: @escaping @MainActor () -> Void = {}
    ) {
        self.modelContext = modelContext
        self.reloadStoreState = reloadStoreState
    }

    func exportBackup(scope: BackupScope) throws -> BackupExportResult {
        try BackupService(modelContext: modelContext).export(scope: scope)
    }

    func dryRunRestore(snapshotURL: URL) throws -> RestoreDryRunReport {
        try RestoreService(modelContext: modelContext).dryRun(snapshotURL: snapshotURL)
    }

    func applyRestore(snapshotURL: URL) throws -> RestoreApplyResult {
        let result = try RestoreService(modelContext: modelContext).apply(snapshotURL: snapshotURL)
        reloadStoreState()
        return result
    }

    func dryRunMigration() throws -> MigrationDryRunReport {
        try MigrationReportRunner(modelContext: modelContext).dryRun()
    }

    func executeMigration() throws -> LegacyDataMigrationResult {
        guard let businessId = try currentBusinessId() else {
            throw SettingsMaintenanceWorkflowError.businessProfileMissing
        }

        let result = try LegacyDataMigrationExecutor(modelContext: modelContext)
            .execute(businessId: businessId)
        reloadStoreState()
        return result
    }

    private func currentBusinessId() throws -> UUID? {
        let descriptor = FetchDescriptor<BusinessProfileEntity>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).first?.businessId
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
