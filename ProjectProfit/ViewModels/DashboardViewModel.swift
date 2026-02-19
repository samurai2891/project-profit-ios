import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    let dataStore: DataStore
    var viewMode: ViewMode = .monthly

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    // MARK: - Date Computation

    var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    var currentMonth: Int {
        Calendar.current.component(.month, from: Date())
    }

    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        if viewMode == .monthly {
            let start = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: 1)) ?? Date()
            let end = endOfMonth(start)
            return (start, end)
        } else {
            return (startOfYear(currentYear), endOfYear(currentYear))
        }
    }

    // MARK: - Summary Data

    var summary: OverallSummary {
        dataStore.getOverallSummary(startDate: dateRange.start, endDate: dateRange.end)
    }

    var topProjects: [ProjectSummary] {
        dataStore.getAllProjectSummaries()
            .sorted { $0.profit > $1.profit }
            .prefix(3)
            .map { $0 }
    }

    var expenseCategories: [CategorySummary] {
        Array(
            dataStore.getCategorySummaries(
                type: .expense,
                startDate: dateRange.start,
                endDate: dateRange.end
            ).prefix(5)
        )
    }

    var monthlySummaries: [MonthlySummary] {
        dataStore.getMonthlySummaries(year: currentYear)
    }

    // MARK: - Display

    var periodLabel: String {
        viewMode == .monthly
            ? "\(currentYear)年\(currentMonth)月の収支状況"
            : "\(currentYear)年の収支状況"
    }

    // MARK: - Actions

    func refresh() {
        dataStore.loadData()
    }
}
