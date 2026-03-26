import SwiftData
import SwiftUI

enum AccountingReportType: String, CaseIterable {
    case trialBalance = "試算表"
    case profitLoss = "損益計算書"
    case balanceSheet = "貸借対照表"
}

@MainActor
@Observable
final class AccountingReportViewModel {
    private let queryUseCase: AccountingReportQueryUseCase
    var selectedReportType: AccountingReportType = .trialBalance
    var fiscalYear: Int

    var trialBalance: TrialBalanceReport?
    var profitLoss: ProfitLossReport?
    var balanceSheet: BalanceSheetReport?

    init(modelContext: ModelContext) {
        self.queryUseCase = AccountingReportQueryUseCase(modelContext: modelContext)
        self.fiscalYear = currentFiscalYear(startMonth: FiscalYearSettings.startMonth)
        refresh()
    }

    func refresh() {
        let bundle = queryUseCase.reportBundle(fiscalYear: fiscalYear)
        trialBalance = bundle.trialBalance
        profitLoss = bundle.profitLoss
        balanceSheet = bundle.balanceSheet
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
