import SwiftUI

@MainActor
@Observable
final class ReportViewModel {
    let dataStore: DataStore
    var selectedFiscalYear: Int
    private(set) var startMonth: Int

    init(dataStore: DataStore) {
        self.dataStore = dataStore
        let sm = FiscalYearSettings.startMonth
        self.startMonth = sm
        self.selectedFiscalYear = currentFiscalYear(startMonth: sm)
    }

    /// Reload when fiscal year setting changes.
    func reloadStartMonth() {
        let sm = FiscalYearSettings.startMonth
        guard sm != startMonth else { return }
        startMonth = sm
        selectedFiscalYear = currentFiscalYear(startMonth: sm)
    }

    var fiscalYearLabelText: String {
        fiscalYearLabel(selectedFiscalYear, startMonth: startMonth)
    }

    var fiscalYearPeriodText: String {
        fiscalYearPeriodLabel(selectedFiscalYear, startMonth: startMonth)
    }

    var canNavigateNext: Bool {
        selectedFiscalYear < currentFiscalYear(startMonth: startMonth)
    }

    func navigatePreviousYear() {
        selectedFiscalYear -= 1
    }

    func navigateNextYear() {
        if canNavigateNext {
            selectedFiscalYear += 1
        }
    }

    // MARK: - Date Range

    private var dateRange: (start: Date, end: Date) {
        (
            startOfFiscalYear(selectedFiscalYear, startMonth: startMonth),
            endOfFiscalYear(selectedFiscalYear, startMonth: startMonth)
        )
    }

    // MARK: - Overall Summary

    var overallSummary: OverallSummary {
        dataStore.getOverallSummary(startDate: dateRange.start, endDate: dateRange.end)
    }

    // MARK: - Monthly Trend

    var monthlySummaries: [MonthlySummary] {
        dataStore.getMonthlySummaries(fiscalYear: selectedFiscalYear, startMonth: startMonth)
    }

    // MARK: - Expense Categories

    var expenseCategories: [CategorySummary] {
        dataStore.getCategorySummaries(type: .expense, startDate: dateRange.start, endDate: dateRange.end)
    }

    // MARK: - Income Categories

    var incomeCategories: [CategorySummary] {
        dataStore.getCategorySummaries(type: .income, startDate: dateRange.start, endDate: dateRange.end)
    }

    // MARK: - Project Ranking

    var projectRanking: [ProjectSummary] {
        dataStore.getAllProjectSummaries(startDate: dateRange.start, endDate: dateRange.end)
            .sorted { $0.profit > $1.profit }
    }

    // MARK: - Year-over-Year Comparison

    var previousYearSummary: OverallSummary {
        let prevFY = selectedFiscalYear - 1
        let prevStart = startOfFiscalYear(prevFY, startMonth: startMonth)
        let prevEnd = endOfFiscalYear(prevFY, startMonth: startMonth)
        return dataStore.getOverallSummary(startDate: prevStart, endDate: prevEnd)
    }

    var yoyIncomeChange: Int {
        overallSummary.totalIncome - previousYearSummary.totalIncome
    }

    var yoyExpenseChange: Int {
        overallSummary.totalExpense - previousYearSummary.totalExpense
    }

    var yoyProfitChange: Int {
        overallSummary.netProfit - previousYearSummary.netProfit
    }

    // MARK: - Actions

    func refresh() {
        dataStore.loadData()
    }
}
