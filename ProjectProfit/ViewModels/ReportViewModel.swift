import SwiftData
import SwiftUI

@MainActor
@Observable
final class ReportViewModel {
    private let reportingUseCase: ReportingQueryUseCase
    private var refreshVersion = 0
    var selectedFiscalYear: Int {
        didSet { refresh() }
    }
    private(set) var startMonth: Int

    init(reportingUseCase: ReportingQueryUseCase) {
        self.reportingUseCase = reportingUseCase
        let sm = FiscalYearSettings.startMonth
        self.startMonth = sm
        self.selectedFiscalYear = currentFiscalYear(startMonth: sm)
    }

    convenience init(modelContext: ModelContext) {
        self.init(reportingUseCase: ReportingQueryUseCase(modelContext: modelContext))
    }

    /// Reload when fiscal year setting changes.
    func reloadStartMonth() {
        let sm = FiscalYearSettings.startMonth
        guard sm != startMonth else { return }
        startMonth = sm
        selectedFiscalYear = currentFiscalYear(startMonth: sm)
        refresh()
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
        _ = refreshVersion
        return reportingUseCase.overallSummary(startDate: dateRange.start, endDate: dateRange.end)
    }

    // MARK: - Monthly Trend

    var monthlySummaries: [MonthlySummary] {
        _ = refreshVersion
        return reportingUseCase.monthlySummaries(fiscalYear: selectedFiscalYear, startMonth: startMonth)
    }

    // MARK: - Expense Categories

    var expenseCategories: [CategorySummary] {
        _ = refreshVersion
        return reportingUseCase.categorySummaries(type: .expense, startDate: dateRange.start, endDate: dateRange.end)
    }

    // MARK: - Income Categories

    var incomeCategories: [CategorySummary] {
        _ = refreshVersion
        return reportingUseCase.categorySummaries(type: .income, startDate: dateRange.start, endDate: dateRange.end)
    }

    // MARK: - Project Ranking

    var projectRanking: [ProjectSummary] {
        _ = refreshVersion
        return reportingUseCase.projectSummaries(startDate: dateRange.start, endDate: dateRange.end)
            .sorted { $0.profit > $1.profit }
    }

    // MARK: - Year-over-Year Comparison

    var previousYearSummary: OverallSummary {
        _ = refreshVersion
        let prevFY = selectedFiscalYear - 1
        let prevStart = startOfFiscalYear(prevFY, startMonth: startMonth)
        let prevEnd = endOfFiscalYear(prevFY, startMonth: startMonth)
        return reportingUseCase.overallSummary(startDate: prevStart, endDate: prevEnd)
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
        refreshVersion &+= 1
    }
}
