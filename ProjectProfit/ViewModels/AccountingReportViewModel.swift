import SwiftUI

enum AccountingReportType: String, CaseIterable {
    case trialBalance = "試算表"
    case profitLoss = "損益計算書"
    case balanceSheet = "貸借対照表"
}

@MainActor
@Observable
final class AccountingReportViewModel {
    private let dataStore: DataStore
    var selectedReportType: AccountingReportType = .trialBalance
    var fiscalYear: Int

    var trialBalance: TrialBalanceReport?
    var profitLoss: ProfitLossReport?
    var balanceSheet: BalanceSheetReport?

    init(dataStore: DataStore) {
        self.dataStore = dataStore
        self.fiscalYear = currentFiscalYear(startMonth: FiscalYearSettings.startMonth)
        refresh()
    }

    func refresh() {
        let startMonth = FiscalYearSettings.startMonth
        trialBalance = AccountingReportService.generateTrialBalance(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines,
            startMonth: startMonth
        )
        profitLoss = AccountingReportService.generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines,
            startMonth: startMonth
        )
        balanceSheet = AccountingReportService.generateBalanceSheet(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines,
            startMonth: startMonth
        )
    }

    func navigatePreviousYear() {
        fiscalYear -= 1
        refresh()
    }

    func navigateNextYear() {
        let currentYear = currentFiscalYear(startMonth: FiscalYearSettings.startMonth)
        if fiscalYear < currentYear {
            fiscalYear += 1
            refresh()
        }
    }
}
