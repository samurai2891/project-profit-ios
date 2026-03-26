import Foundation

struct SettingsOverviewSnapshot: Equatable {
    let projectCount: Int
    let transactionCount: Int
    let recurringTransactionCount: Int
    let availableBackupYears: [Int]
}

@MainActor
protocol SettingsOverviewRepository {
    func snapshot(startMonth: Int) throws -> SettingsOverviewSnapshot
}
