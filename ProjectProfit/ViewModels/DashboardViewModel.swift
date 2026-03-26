import SwiftData
import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    private let reportingUseCase: ReportingQueryUseCase
    private var refreshVersion = 0

    var viewMode: ViewMode = .monthly {
        didSet { refresh() }
    }
    var selectedFiscalYear: Int {
        didSet { refresh() }
    }
    var selectedMonth: Int {
        didSet { refresh() }
    }
    private(set) var startMonth: Int

    init(reportingUseCase: ReportingQueryUseCase) {
        self.reportingUseCase = reportingUseCase
        let sm = FiscalYearSettings.startMonth
        self.startMonth = sm
        self.selectedFiscalYear = currentFiscalYear(startMonth: sm)
        self.selectedMonth = Calendar.current.component(.month, from: Date())
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
        let currentMonth = Calendar.current.component(.month, from: Date())
        selectedMonth = currentMonth
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

    // MARK: - Month Navigation

    /// The calendar months available for the selected fiscal year.
    var fiscalYearMonths: [(year: Int, month: Int)] {
        fiscalYearCalendarMonths(fiscalYear: selectedFiscalYear, startMonth: startMonth)
    }

    /// The index of the selected month within the fiscal year's month list.
    private var selectedMonthIndex: Int {
        fiscalYearMonths.firstIndex(where: { $0.month == selectedMonth }) ?? 0
    }

    /// The calendar year corresponding to the currently selected month in the fiscal year.
    private var selectedCalendarYear: Int {
        fiscalYearMonths[selectedMonthIndex].year
    }

    func navigatePreviousMonth() {
        let months = fiscalYearMonths
        let idx = selectedMonthIndex
        if idx > 0 {
            selectedMonth = months[idx - 1].month
        } else {
            // Wrap to previous fiscal year
            selectedFiscalYear -= 1
            let prevMonths = fiscalYearCalendarMonths(fiscalYear: selectedFiscalYear, startMonth: startMonth)
            selectedMonth = prevMonths.last?.month ?? selectedMonth
        }
    }

    func navigateNextMonth() {
        let months = fiscalYearMonths
        let idx = selectedMonthIndex
        if idx < months.count - 1 {
            selectedMonth = months[idx + 1].month
        } else if canNavigateNext {
            selectedFiscalYear += 1
            let nextMonths = fiscalYearCalendarMonths(fiscalYear: selectedFiscalYear, startMonth: startMonth)
            selectedMonth = nextMonths.first?.month ?? selectedMonth
        }
    }

    // MARK: - Date Range

    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        if viewMode == .monthly {
            let calYear = selectedCalendarYear
            let start = calendar.date(from: DateComponents(year: calYear, month: selectedMonth, day: 1)) ?? Date()
            let end = endOfMonth(start)
            return (start, end)
        } else {
            return (
                startOfFiscalYear(selectedFiscalYear, startMonth: startMonth),
                endOfFiscalYear(selectedFiscalYear, startMonth: startMonth)
            )
        }
    }

    // MARK: - Summary Data

    var summary: OverallSummary {
        _ = refreshVersion
        return reportingUseCase.overallSummary(startDate: dateRange.start, endDate: dateRange.end)
    }

    var activeProjects: [ProjectSummary] {
        _ = refreshVersion
        let range = dateRange
        return reportingUseCase.projectSummaries(startDate: range.start, endDate: range.end)
            .filter { $0.status == .active }
            .sorted { $0.profit > $1.profit }
    }

    var expenseCategories: [CategorySummary] {
        _ = refreshVersion
        return Array(
            reportingUseCase.categorySummaries(
                type: .expense,
                startDate: dateRange.start,
                endDate: dateRange.end
            ).prefix(5)
        )
    }

    var monthlySummaries: [MonthlySummary] {
        _ = refreshVersion
        return reportingUseCase.monthlySummaries(fiscalYear: selectedFiscalYear, startMonth: startMonth)
    }

    // MARK: - Display

    var periodLabel: String {
        if viewMode == .monthly {
            let calYear = selectedCalendarYear
            return "\(calYear)年\(selectedMonth)月の収支状況"
        } else {
            return "\(fiscalYearLabelText)の収支状況"
        }
    }

    // MARK: - Actions

    func refresh() {
        refreshVersion &+= 1
    }
}
