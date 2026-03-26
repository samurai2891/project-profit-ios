import Foundation
import SwiftData

@MainActor
struct SettingsOverviewUseCase {
    private let repository: any SettingsOverviewRepository

    init(repository: any SettingsOverviewRepository) {
        self.repository = repository
    }

    init(
        modelContext: ModelContext,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.init(
            repository: SwiftDataSettingsOverviewRepository(
                modelContext: modelContext,
                currentDateProvider: currentDateProvider
            )
        )
    }

    func snapshot(startMonth: Int) -> SettingsOverviewSnapshot {
        (try? repository.snapshot(startMonth: startMonth))
            ?? SettingsOverviewSnapshot(
                projectCount: 0,
                transactionCount: 0,
                recurringTransactionCount: 0,
                availableBackupYears: [currentFiscalYear(startMonth: startMonth)]
            )
    }
}
