import XCTest
@testable import ProjectProfit

final class FiscalYearUtilitiesTests: XCTestCase {
    private let calendar = Calendar.current

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - fiscalYear(for:startMonth:)

    func testFiscalYear_april_start_dateInApril() {
        // April 2025 should be FY2025 when startMonth=4
        let date = makeDate(year: 2025, month: 4, day: 1)
        XCTAssertEqual(fiscalYear(for: date, startMonth: 4), 2025)
    }

    func testFiscalYear_april_start_dateInDecember() {
        // December 2025 should be FY2025 when startMonth=4
        let date = makeDate(year: 2025, month: 12, day: 31)
        XCTAssertEqual(fiscalYear(for: date, startMonth: 4), 2025)
    }

    func testFiscalYear_april_start_dateInJanuary() {
        // January 2026 should be FY2025 when startMonth=4
        let date = makeDate(year: 2026, month: 1, day: 15)
        XCTAssertEqual(fiscalYear(for: date, startMonth: 4), 2025)
    }

    func testFiscalYear_april_start_dateInMarch() {
        // March 2026 should be FY2025 when startMonth=4
        let date = makeDate(year: 2026, month: 3, day: 31)
        XCTAssertEqual(fiscalYear(for: date, startMonth: 4), 2025)
    }

    func testFiscalYear_april_start_dateInAprilNextYear() {
        // April 2026 should be FY2026 when startMonth=4
        let date = makeDate(year: 2026, month: 4, day: 1)
        XCTAssertEqual(fiscalYear(for: date, startMonth: 4), 2026)
    }

    func testFiscalYear_january_start() {
        // startMonth=1 is a calendar year
        let jan = makeDate(year: 2025, month: 1, day: 1)
        let dec = makeDate(year: 2025, month: 12, day: 31)
        XCTAssertEqual(fiscalYear(for: jan, startMonth: 1), 2025)
        XCTAssertEqual(fiscalYear(for: dec, startMonth: 1), 2025)
    }

    func testFiscalYear_october_start() {
        // startMonth=10: Oct 2025..Sep 2026 -> FY2025
        let oct = makeDate(year: 2025, month: 10, day: 1)
        XCTAssertEqual(fiscalYear(for: oct, startMonth: 10), 2025)

        let sep = makeDate(year: 2026, month: 9, day: 30)
        XCTAssertEqual(fiscalYear(for: sep, startMonth: 10), 2025)

        let octNext = makeDate(year: 2026, month: 10, day: 1)
        XCTAssertEqual(fiscalYear(for: octNext, startMonth: 10), 2026)
    }

    func testFiscalYear_boundary_first_day_of_fiscal_year() {
        let date = makeDate(year: 2025, month: 4, day: 1)
        XCTAssertEqual(fiscalYear(for: date, startMonth: 4), 2025)
    }

    func testFiscalYear_boundary_last_day_before_fiscal_year() {
        let date = makeDate(year: 2025, month: 3, day: 31)
        XCTAssertEqual(fiscalYear(for: date, startMonth: 4), 2024)
    }

    // MARK: - startOfFiscalYear / endOfFiscalYear

    func testStartOfFiscalYear_aprilStart() {
        let start = startOfFiscalYear(2025, startMonth: 4)
        let comps = calendar.dateComponents([.year, .month, .day], from: start)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 1)
    }

    func testEndOfFiscalYear_aprilStart() {
        let end = endOfFiscalYear(2025, startMonth: 4)
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 31)
        XCTAssertEqual(comps.hour, 23)
        XCTAssertEqual(comps.minute, 59)
        XCTAssertEqual(comps.second, 59)
    }

    func testStartOfFiscalYear_januaryStart() {
        let start = startOfFiscalYear(2025, startMonth: 1)
        let comps = calendar.dateComponents([.year, .month, .day], from: start)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 1)
    }

    func testEndOfFiscalYear_januaryStart() {
        let end = endOfFiscalYear(2025, startMonth: 1)
        let comps = calendar.dateComponents([.year, .month, .day], from: end)
        XCTAssertEqual(comps.year, 2025)
        XCTAssertEqual(comps.month, 12)
        XCTAssertEqual(comps.day, 31)
    }

    func testEndOfFiscalYear_octoberStart() {
        let end = endOfFiscalYear(2025, startMonth: 10)
        let comps = calendar.dateComponents([.year, .month, .day], from: end)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 9)
        XCTAssertEqual(comps.day, 30)
    }

    // MARK: - fiscalYearCalendarMonths

    func testCalendarMonths_aprilStart() {
        let months = fiscalYearCalendarMonths(fiscalYear: 2025, startMonth: 4)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months[0].year, 2025)
        XCTAssertEqual(months[0].month, 4)
        XCTAssertEqual(months[8].year, 2025)
        XCTAssertEqual(months[8].month, 12)
        XCTAssertEqual(months[9].year, 2026)
        XCTAssertEqual(months[9].month, 1)
        XCTAssertEqual(months[11].year, 2026)
        XCTAssertEqual(months[11].month, 3)
    }

    func testCalendarMonths_januaryStart() {
        let months = fiscalYearCalendarMonths(fiscalYear: 2025, startMonth: 1)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months[0].year, 2025)
        XCTAssertEqual(months[0].month, 1)
        XCTAssertEqual(months[11].year, 2025)
        XCTAssertEqual(months[11].month, 12)
    }

    func testCalendarMonths_octoberStart() {
        let months = fiscalYearCalendarMonths(fiscalYear: 2025, startMonth: 10)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months[0].year, 2025)
        XCTAssertEqual(months[0].month, 10)
        XCTAssertEqual(months[2].year, 2025)
        XCTAssertEqual(months[2].month, 12)
        XCTAssertEqual(months[3].year, 2026)
        XCTAssertEqual(months[3].month, 1)
        XCTAssertEqual(months[11].year, 2026)
        XCTAssertEqual(months[11].month, 9)
    }

    // MARK: - Labels

    func testFiscalYearLabel_aprilStart() {
        XCTAssertEqual(fiscalYearLabel(2025, startMonth: 4), "2025年度")
    }

    func testFiscalYearLabel_januaryStart() {
        XCTAssertEqual(fiscalYearLabel(2025, startMonth: 1), "2025年")
    }

    func testFiscalYearPeriodLabel_aprilStart() {
        XCTAssertEqual(fiscalYearPeriodLabel(2025, startMonth: 4), "2025年4月〜2026年3月")
    }

    func testFiscalYearPeriodLabel_januaryStart() {
        XCTAssertEqual(fiscalYearPeriodLabel(2025, startMonth: 1), "2025年1月〜2025年12月")
    }

    func testFiscalYearPeriodLabel_octoberStart() {
        XCTAssertEqual(fiscalYearPeriodLabel(2025, startMonth: 10), "2025年10月〜2026年9月")
    }

    // MARK: - currentFiscalYear

    func testCurrentFiscalYear_returnsReasonableValue() {
        let fy = currentFiscalYear(startMonth: 4)
        let calendarYear = calendar.component(.year, from: Date())
        // Current FY should be within 1 year of calendar year
        XCTAssertTrue(abs(fy - calendarYear) <= 1)
    }

    // MARK: - FiscalYearSettings

    func testFiscalYearSettings_defaultStartMonth() {
        XCTAssertEqual(FiscalYearSettings.defaultStartMonth, 1)
    }

    func testFiscalYearSettings_readsFromUserDefaults() {
        UserDefaults.standard.set(10, forKey: FiscalYearSettings.userDefaultsKey)
        XCTAssertEqual(FiscalYearSettings.startMonth, 10)
        // Clean up
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
    }

    func testFiscalYearSettings_invalidValueFallsBackToDefault() {
        UserDefaults.standard.set(13, forKey: FiscalYearSettings.userDefaultsKey)
        XCTAssertEqual(FiscalYearSettings.startMonth, FiscalYearSettings.defaultStartMonth)
        // Clean up
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
    }

    func testFiscalYearSettings_zeroFallsBackToDefault() {
        UserDefaults.standard.set(0, forKey: FiscalYearSettings.userDefaultsKey)
        XCTAssertEqual(FiscalYearSettings.startMonth, FiscalYearSettings.defaultStartMonth)
        // Clean up
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
    }
}
