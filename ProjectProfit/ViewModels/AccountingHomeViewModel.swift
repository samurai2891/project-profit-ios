import SwiftUI

@MainActor
@Observable
final class AccountingHomeViewModel {
    private let dataStore: DataStore

    var unpostedJournalCount: Int = 0
    var suspenseBalance: Int = 0
    var totalAccounts: Int = 0
    var totalJournalEntries: Int = 0
    var isBootstrapped: Bool = false

    init(dataStore: DataStore) {
        self.dataStore = dataStore
        refresh()
    }

    func refresh() {
        let entries = dataStore.journalEntries
        let lines = dataStore.journalLines

        unpostedJournalCount = entries.filter { !$0.isPosted }.count
        totalJournalEntries = entries.count
        totalAccounts = dataStore.accounts.filter { $0.isActive }.count
        isBootstrapped = dataStore.accountingProfile != nil

        // 仮勘定の借方合計 - 貸方合計
        let suspenseLines = lines.filter { $0.accountId == AccountingConstants.suspenseAccountId }
        let debitTotal = suspenseLines.reduce(0) { $0 + $1.debit }
        let creditTotal = suspenseLines.reduce(0) { $0 + $1.credit }
        suspenseBalance = debitTotal - creditTotal
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
