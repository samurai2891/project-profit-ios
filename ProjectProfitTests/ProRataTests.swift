import XCTest
@testable import ProjectProfit

final class ProRataTests: XCTestCase {
    private let calendar = Calendar.current

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - calculateProRataAmount

    func testProRataFullMonth() {
        // 30 active days in a 30-day month = full amount
        XCTAssertEqual(calculateProRataAmount(totalAmount: 30000, activeDays: 30, totalDays: 30), 30000)
    }

    func testProRataHalfMonth() {
        // 15 active days in a 30-day month = half
        XCTAssertEqual(calculateProRataAmount(totalAmount: 30000, activeDays: 15, totalDays: 30), 15000)
    }

    func testProRataZeroDays() {
        XCTAssertEqual(calculateProRataAmount(totalAmount: 30000, activeDays: 0, totalDays: 30), 0)
    }

    func testProRataZeroTotalDays() {
        XCTAssertEqual(calculateProRataAmount(totalAmount: 30000, activeDays: 15, totalDays: 0), 0)
    }

    func testProRataExceedsTotal() {
        // activeDays > totalDays should return full amount
        XCTAssertEqual(calculateProRataAmount(totalAmount: 30000, activeDays: 35, totalDays: 30), 30000)
    }

    // MARK: - daysInMonth

    func testDaysInMonthFebruary() {
        XCTAssertEqual(daysInMonth(year: 2026, month: 2), 28)
    }

    func testDaysInMonthFebruaryLeapYear() {
        XCTAssertEqual(daysInMonth(year: 2024, month: 2), 29)
    }

    func testDaysInMonthJanuary() {
        XCTAssertEqual(daysInMonth(year: 2026, month: 1), 31)
    }

    func testDaysInMonthApril() {
        XCTAssertEqual(daysInMonth(year: 2026, month: 4), 30)
    }

    // MARK: - redistributeAllocationsForCompletion

    func testRedistribute_completedMidMonth_twoProjects() {
        // Project A completes on Feb 15 in a 28-day month
        // Project A: 50%, Project B: 50%
        // Amount: 28000
        // Project A gets 15/28 * 14000 = 7500, Project B gets 14000 + (14000-7500) = 20500
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 14000),
            Allocation(projectId: projectB, ratio: 50, amount: 14000),
        ]
        let result = redistributeAllocationsForCompletion(
            totalAmount: 28000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2026, month: 2, day: 15),
            transactionDate: makeDate(year: 2026, month: 2, day: 1),
            originalAllocations: allocations,
            activeProjectIds: Set([projectB])
        )
        XCTAssertEqual(result.count, 2)
        // Project A: 14000 * 15 / 28 = 7500
        let allocA = result.first(where: { $0.projectId == projectA })!
        XCTAssertEqual(allocA.amount, 7500)
        // Project B: 14000 + (14000 - 7500) = 20500
        let allocB = result.first(where: { $0.projectId == projectB })!
        XCTAssertEqual(allocB.amount, 20500)
    }

    func testRedistribute_completedBeforeMonth_zeroDays() {
        // Project A completed in January, transaction in February
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 15000),
            Allocation(projectId: projectB, ratio: 50, amount: 15000),
        ]
        let result = redistributeAllocationsForCompletion(
            totalAmount: 30000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2026, month: 1, day: 20),
            transactionDate: makeDate(year: 2026, month: 2, day: 1),
            originalAllocations: allocations,
            activeProjectIds: Set([projectB])
        )
        let allocA = result.first(where: { $0.projectId == projectA })!
        XCTAssertEqual(allocA.amount, 0) // Zero active days
        let allocB = result.first(where: { $0.projectId == projectB })!
        XCTAssertEqual(allocB.amount, 30000) // Gets all redistributed
    }

    func testRedistribute_completedAfterMonth_unchanged() {
        // Project A completed in March, transaction in February -> no change
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 15000),
            Allocation(projectId: projectB, ratio: 50, amount: 15000),
        ]
        let result = redistributeAllocationsForCompletion(
            totalAmount: 30000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2026, month: 3, day: 10),
            transactionDate: makeDate(year: 2026, month: 2, day: 1),
            originalAllocations: allocations,
            activeProjectIds: Set([projectB])
        )
        XCTAssertEqual(result[0].amount, 15000) // Unchanged
        XCTAssertEqual(result[1].amount, 15000) // Unchanged
    }

    func testRedistribute_threeProjects_oneCompleted() {
        // A:40%, B:30%, C:30% - B completes on day 10 of 30-day month
        let projectA = UUID()
        let projectB = UUID()
        let projectC = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 40, amount: 12000),
            Allocation(projectId: projectB, ratio: 30, amount: 9000),
            Allocation(projectId: projectC, ratio: 30, amount: 9000),
        ]
        let result = redistributeAllocationsForCompletion(
            totalAmount: 30000,
            completedProjectId: projectB,
            completedAt: makeDate(year: 2026, month: 4, day: 10),
            transactionDate: makeDate(year: 2026, month: 4, day: 1),
            originalAllocations: allocations,
            activeProjectIds: Set([projectA, projectC])
        )
        let allocB = result.first(where: { $0.projectId == projectB })!
        // B: 9000 * 10 / 30 = 3000
        XCTAssertEqual(allocB.amount, 3000)
        // Redistributable: 9000 - 3000 = 6000
        // A gets 6000 * 40 / 70 = 3428, C gets 6000 * 30 / 70 = 2571, remainder 1 to C
        let allocA = result.first(where: { $0.projectId == projectA })!
        let allocC = result.first(where: { $0.projectId == projectC })!
        XCTAssertEqual(allocA.amount + allocB.amount + allocC.amount, 12000 + 9000 + 9000 - (9000 - 3000) + (9000 - 3000))
        // Just verify total adds up correctly
        let total = result.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 30000)
    }

    func testRedistribute_noOtherActiveProjects() {
        // Only completed project - just pro-rate, no redistribution
        let projectA = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 100, amount: 30000),
        ]
        let result = redistributeAllocationsForCompletion(
            totalAmount: 30000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2026, month: 4, day: 15),
            transactionDate: makeDate(year: 2026, month: 4, day: 1),
            originalAllocations: allocations,
            activeProjectIds: Set()
        )
        XCTAssertEqual(result.count, 1)
        // 30000 * 15 / 30 = 15000
        XCTAssertEqual(result[0].amount, 15000)
    }

    func testRedistribute_completedProjectNotInAllocations() {
        // completedProjectId not in allocations -> return unchanged
        let projectA = UUID()
        let projectB = UUID()
        let unknownId = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 15000),
            Allocation(projectId: projectB, ratio: 50, amount: 15000),
        ]
        let result = redistributeAllocationsForCompletion(
            totalAmount: 30000,
            completedProjectId: unknownId,
            completedAt: makeDate(year: 2026, month: 2, day: 15),
            transactionDate: makeDate(year: 2026, month: 2, day: 1),
            originalAllocations: allocations,
            activeProjectIds: Set([projectA, projectB])
        )
        XCTAssertEqual(result[0].amount, 15000)
        XCTAssertEqual(result[1].amount, 15000)
    }

    // MARK: - daysInYear

    func testDaysInYear_nonLeapYear() {
        XCTAssertEqual(daysInYear(2025), 365)
    }

    func testDaysInYear_leapYear() {
        XCTAssertEqual(daysInYear(2024), 366)
    }

    // MARK: - redistributeAllocationsForYearlyCompletion

    func testYearlyRedistribute_completedMidYear() {
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 60000),
            Allocation(projectId: projectB, ratio: 50, amount: 60000),
        ]
        // Jan 1 to Mar 31 = 90 days in non-leap year
        let result = redistributeAllocationsForYearlyCompletion(
            totalAmount: 120000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2025, month: 3, day: 31),
            transactionYear: 2025,
            originalAllocations: allocations,
            activeProjectIds: Set([projectB])
        )
        let allocA = result.first { $0.projectId == projectA }!
        let allocB = result.first { $0.projectId == projectB }!
        // 60000 * 90 / 365 = 14794
        XCTAssertEqual(allocA.amount, 14794)
        XCTAssertEqual(allocA.amount + allocB.amount, 120000)
    }

    func testYearlyRedistribute_completedBeforeYear() {
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 60000),
            Allocation(projectId: projectB, ratio: 50, amount: 60000),
        ]
        let result = redistributeAllocationsForYearlyCompletion(
            totalAmount: 120000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2024, month: 12, day: 31),
            transactionYear: 2025,
            originalAllocations: allocations,
            activeProjectIds: Set([projectB])
        )
        let allocA = result.first { $0.projectId == projectA }!
        XCTAssertEqual(allocA.amount, 0)
    }

    func testYearlyRedistribute_completedAfterYear() {
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 60000),
            Allocation(projectId: projectB, ratio: 50, amount: 60000),
        ]
        let result = redistributeAllocationsForYearlyCompletion(
            totalAmount: 120000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2026, month: 6, day: 15),
            transactionYear: 2025,
            originalAllocations: allocations,
            activeProjectIds: Set([projectB])
        )
        // Unchanged since completed after the year
        XCTAssertEqual(result[0].amount, 60000)
        XCTAssertEqual(result[1].amount, 60000)
    }

    func testYearlyRedistribute_leapYear() {
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 100, amount: 36600),
            Allocation(projectId: projectB, ratio: 0, amount: 0),
        ]
        // Jan 1 in leap year 2024, completed on Jan 1 (1 active day out of 366)
        let result = redistributeAllocationsForYearlyCompletion(
            totalAmount: 36600,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2024, month: 1, day: 1),
            transactionYear: 2024,
            originalAllocations: allocations,
            activeProjectIds: Set()
        )
        let allocA = result.first { $0.projectId == projectA }!
        // 36600 * 1 / 366 = 100
        XCTAssertEqual(allocA.amount, 100)
    }

    // MARK: - calculateActiveDaysInMonth

    func testActiveDaysInMonth_startDateOnly_midMonth() {
        // Project starts Mar 15, month is March (31 days)
        // Active: Mar 15..31 = 17 days
        let startDate = makeDate(year: 2026, month: 3, day: 15)
        let result = calculateActiveDaysInMonth(startDate: startDate, completedAt: nil, year: 2026, month: 3)
        XCTAssertEqual(result, 17)
    }

    func testActiveDaysInMonth_startDateOnly_outsideMonth() {
        // Project starts Jan 10, month is March -> full month (31 days)
        let startDate = makeDate(year: 2026, month: 1, day: 10)
        let result = calculateActiveDaysInMonth(startDate: startDate, completedAt: nil, year: 2026, month: 3)
        XCTAssertEqual(result, 31)
    }

    func testActiveDaysInMonth_startDateOnly_afterMonth() {
        // Project starts Apr 1, month is March -> 0 days
        let startDate = makeDate(year: 2026, month: 4, day: 1)
        let result = calculateActiveDaysInMonth(startDate: startDate, completedAt: nil, year: 2026, month: 3)
        XCTAssertEqual(result, 0)
    }

    func testActiveDaysInMonth_completedAtOnly_backwardCompat() {
        // Project completes Feb 15 in 28-day month
        // Active: Feb 1..15 = 15 days
        let completedAt = makeDate(year: 2026, month: 2, day: 15)
        let result = calculateActiveDaysInMonth(startDate: nil, completedAt: completedAt, year: 2026, month: 2)
        XCTAssertEqual(result, 15)
    }

    func testActiveDaysInMonth_bothSet_sameMonth() {
        // Start Mar 10, complete Mar 20 in a 31-day month
        // Active: Mar 10..20 = 11 days
        let startDate = makeDate(year: 2026, month: 3, day: 10)
        let completedAt = makeDate(year: 2026, month: 3, day: 20)
        let result = calculateActiveDaysInMonth(startDate: startDate, completedAt: completedAt, year: 2026, month: 3)
        XCTAssertEqual(result, 11)
    }

    func testActiveDaysInMonth_bothSet_outsideMonth() {
        // Start Jan 1, complete Dec 31 -> March is full month
        let startDate = makeDate(year: 2026, month: 1, day: 1)
        let completedAt = makeDate(year: 2026, month: 12, day: 31)
        let result = calculateActiveDaysInMonth(startDate: startDate, completedAt: completedAt, year: 2026, month: 3)
        XCTAssertEqual(result, 31)
    }

    func testActiveDaysInMonth_nilNil_fullMonth() {
        // Both nil -> full month
        let result = calculateActiveDaysInMonth(startDate: nil, completedAt: nil, year: 2026, month: 4)
        XCTAssertEqual(result, 30)
    }

    func testActiveDaysInMonth_leapYearFebruary() {
        // Feb 2024 has 29 days, start Feb 10
        let startDate = makeDate(year: 2024, month: 2, day: 10)
        let result = calculateActiveDaysInMonth(startDate: startDate, completedAt: nil, year: 2024, month: 2)
        XCTAssertEqual(result, 20) // Feb 10..29 = 20 days
    }

    // MARK: - calculateActiveDaysInYear

    func testActiveDaysInYear_startDateOnly() {
        // Project starts Jul 1 in 2025 (non-leap, 365 days)
        // Active: Jul 1..Dec 31 = 184 days
        let startDate = makeDate(year: 2025, month: 7, day: 1)
        let result = calculateActiveDaysInYear(startDate: startDate, completedAt: nil, year: 2025)
        XCTAssertEqual(result, 184)
    }

    func testActiveDaysInYear_completedAtOnly() {
        // Project completes Mar 31 in 2025
        // Active: Jan 1..Mar 31 = 90 days
        let completedAt = makeDate(year: 2025, month: 3, day: 31)
        let result = calculateActiveDaysInYear(startDate: nil, completedAt: completedAt, year: 2025)
        XCTAssertEqual(result, 90)
    }

    func testActiveDaysInYear_bothNil() {
        let result = calculateActiveDaysInYear(startDate: nil, completedAt: nil, year: 2025)
        XCTAssertEqual(result, 365)
    }

    // MARK: - redistributeAllocationsForCompletion with startDate

    func testRedistribute_withStartDate_midMonth() {
        // Project A starts Mar 15 (not completed), Project B is active from start of month
        // March has 31 days. Project A: active 17 days (Mar 15..31)
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 15500),
            Allocation(projectId: projectB, ratio: 50, amount: 15500),
        ]
        // Use endOfMonth as completedAt since project is not actually completed
        let result = redistributeAllocationsForCompletion(
            totalAmount: 31000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2026, month: 3, day: 31),
            transactionDate: makeDate(year: 2026, month: 3, day: 1),
            originalAllocations: allocations,
            activeProjectIds: Set([projectB]),
            startDate: makeDate(year: 2026, month: 3, day: 15)
        )
        let allocA = result.first(where: { $0.projectId == projectA })!
        // 15500 * 17 / 31 = 8500
        XCTAssertEqual(allocA.amount, 8500)
        // Total preserved
        let total = result.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 31000)
    }

    func testRedistribute_withStartDateAndCompletedAt_sameMonth() {
        // Project A starts Mar 10, completes Mar 20
        // Active days: 11 (Mar 10..20), March has 31 days
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 15500),
            Allocation(projectId: projectB, ratio: 50, amount: 15500),
        ]
        let result = redistributeAllocationsForCompletion(
            totalAmount: 31000,
            completedProjectId: projectA,
            completedAt: makeDate(year: 2026, month: 3, day: 20),
            transactionDate: makeDate(year: 2026, month: 3, day: 1),
            originalAllocations: allocations,
            activeProjectIds: Set([projectB]),
            startDate: makeDate(year: 2026, month: 3, day: 10)
        )
        let allocA = result.first(where: { $0.projectId == projectA })!
        // 15500 * 11 / 31 = 5500
        XCTAssertEqual(allocA.amount, 5500)
        let total = result.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 31000)
    }

    // MARK: - Edge cases: same-day start and completion

    func testActiveDaysInMonth_startDateEqualsCompletedAt_sameDay() {
        let date = makeDate(year: 2026, month: 3, day: 15)
        let result = calculateActiveDaysInMonth(startDate: date, completedAt: date, year: 2026, month: 3)
        XCTAssertEqual(result, 1, "Single day should count as 1 active day")
    }

    func testActiveDaysInMonth_startDateOnFirstOfMonth_fullMonth() {
        let startDate = makeDate(year: 2026, month: 3, day: 1)
        let result = calculateActiveDaysInMonth(startDate: startDate, completedAt: nil, year: 2026, month: 3)
        XCTAssertEqual(result, 31, "Starting on day 1 should count full month")
    }

    func testActiveDaysInYear_startDateEqualsCompletedAt_sameDay() {
        let date = makeDate(year: 2025, month: 6, day: 15)
        let result = calculateActiveDaysInYear(startDate: date, completedAt: date, year: 2025)
        XCTAssertEqual(result, 1, "Single day should count as 1 active day")
    }

    func testRedistribute_startDateEqualsCompletedAt_sameDay() {
        let projectA = UUID()
        let projectB = UUID()
        let allocations = [
            Allocation(projectId: projectA, ratio: 50, amount: 15500),
            Allocation(projectId: projectB, ratio: 50, amount: 15500),
        ]
        let sameDay = makeDate(year: 2026, month: 3, day: 15)
        let result = redistributeAllocationsForCompletion(
            totalAmount: 31000,
            completedProjectId: projectA,
            completedAt: sameDay,
            transactionDate: makeDate(year: 2026, month: 3, day: 1),
            originalAllocations: allocations,
            activeProjectIds: Set([projectB]),
            startDate: sameDay
        )
        let allocA = result.first(where: { $0.projectId == projectA })!
        // 15500 * 1 / 31 = 500
        XCTAssertEqual(allocA.amount, 500)
        let total = result.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 31000)
    }
}
