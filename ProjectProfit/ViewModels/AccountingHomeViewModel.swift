import SwiftData
import SwiftUI

@MainActor
@Observable
final class AccountingHomeViewModel {
    private let queryUseCase: AccountingHomeQueryUseCase

    var unpostedJournalCount: Int = 0
    var suspenseBalance: Int = 0
    var totalAccounts: Int = 0
    var totalJournalEntries: Int = 0
    var isBootstrapped: Bool = false

    init(modelContext: ModelContext) {
        self.queryUseCase = AccountingHomeQueryUseCase(modelContext: modelContext)
        refresh()
    }

    func refresh() {
        let snapshot = queryUseCase.snapshot()
        unpostedJournalCount = snapshot.unpostedJournalCount
        totalJournalEntries = snapshot.totalJournalEntries
        totalAccounts = snapshot.totalAccounts
        isBootstrapped = snapshot.isBootstrapped
        suspenseBalance = snapshot.suspenseBalance
    }

    var hasWarnings: Bool {
        unpostedJournalCount > 0 || suspenseBalance != 0
    }

    var statusSummary: String {
        if !isBootstrapped {
            return "会計機能が未初期化です"
        }
        if !hasWarnings {
            return "正常"
        }
        var warnings: [String] = []
        if unpostedJournalCount > 0 {
            warnings.append("未投稿仕訳: \(unpostedJournalCount)件")
        }
        if suspenseBalance != 0 {
            warnings.append("仮勘定残高: \(formatCurrency(suspenseBalance))")
        }
        return warnings.joined(separator: " / ")
    }
}
