import Foundation

extension DataStore {
    /// Legacy profile から canonical profile への移行を安全に実行する。
    /// 現行の modelContainer が canonical entity を含まない場合はスキップし、起動は継続する。
    func runLegacyProfileMigrationIfNeeded() {
        let runner = LegacyProfileMigrationRunner(modelContext: modelContext)
        let report = runner.executeIfNeeded()

        switch report.outcome {
        case .noLegacyProfile, .alreadyMigrated:
            return
        case .dryRunReady, .executed:
            AppLogger.dataStore.info(
                "Legacy profile migration: outcome=\(report.outcome.rawValue), businessId=\(report.businessProfileId?.uuidString ?? "nil"), taxYear=\(report.taxYear ?? 0)"
            )
        case .schemaUnavailable:
            AppLogger.dataStore.warning(
                "Legacy profile migration skipped: canonical schema unavailable (\(report.errorDescription ?? "unknown"))"
            )
        case .failed:
            AppLogger.dataStore.error(
                "Legacy profile migration failed: \(report.errorDescription ?? "unknown")"
            )
        }
    }
}
