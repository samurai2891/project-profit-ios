import Foundation

// MARK: - Fiscal Year Calculation

/// Returns the fiscal year number for a given date.
/// For startMonth=4: dates in Apr 2025..Mar 2026 -> fiscal year 2025
/// For startMonth=1: dates in Jan 2025..Dec 2025 -> fiscal year 2025
func fiscalYear(for date: Date, startMonth: Int) -> Int {
    let calendar = Calendar.current
    let month = calendar.component(.month, from: date)
    let year = calendar.component(.year, from: date)
    if startMonth == 1 {
        return year
    }
    return month >= startMonth ? year : year - 1
}

/// Returns the start date of a fiscal year (first day of startMonth).
/// e.g. fiscalYear=2025, startMonth=4 -> 2025-04-01
func startOfFiscalYear(_ fy: Int, startMonth: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: fy, month: startMonth, day: 1)) ?? Date()
}

/// Returns the end date of a fiscal year (last day of the month before startMonth of next year).
/// e.g. fiscalYear=2025, startMonth=4 -> 2026-03-31 23:59:59
func endOfFiscalYear(_ fy: Int, startMonth: Int) -> Date {
    let calendar = Calendar.current
    if startMonth == 1 {
        // Calendar year: Jan 1 to Dec 31
        var comps = DateComponents(year: fy, month: 12, day: 31)
        comps.hour = 23
        comps.minute = 59
        comps.second = 59
        return calendar.date(from: comps) ?? Date()
    }
    // Next fiscal year start minus 1 second
    let nextFYStart = calendar.date(from: DateComponents(year: fy + 1, month: startMonth, day: 1)) ?? Date()
    return calendar.date(byAdding: .second, value: -1, to: nextFYStart) ?? Date()
}

/// Returns "2025年度" or "2025年" (when startMonth==1).
func fiscalYearLabel(_ fy: Int, startMonth: Int) -> String {
    startMonth == 1 ? "\(fy)年" : "\(fy)年度"
}

/// Returns "2025年4月〜2026年3月" style period label.
func fiscalYearPeriodLabel(_ fy: Int, startMonth: Int) -> String {
    if startMonth == 1 {
        return "\(fy)年1月〜\(fy)年12月"
    }
    let endMonth = startMonth - 1
    let endYear = fy + 1
    return "\(fy)年\(startMonth)月〜\(endYear)年\(endMonth)月"
}

/// Returns the current fiscal year based on today's date.
func currentFiscalYear(startMonth: Int) -> Int {
    fiscalYear(for: Date(), startMonth: startMonth)
}

/// Returns 12 (year, month) pairs for a fiscal year in chronological order.
/// e.g. fiscalYear=2025, startMonth=4 -> [(2025,4), (2025,5), ..., (2025,12), (2026,1), (2026,2), (2026,3)]
func fiscalYearCalendarMonths(fiscalYear fy: Int, startMonth: Int) -> [(year: Int, month: Int)] {
    (0..<12).map { offset in
        let month = ((startMonth - 1 + offset) % 12) + 1
        let year = fy + (startMonth - 1 + offset) / 12
        return (year: year, month: month)
    }
}
