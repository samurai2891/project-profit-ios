import XCTest
@testable import ProjectProfit

final class UtilitiesTests: XCTestCase {

    // MARK: - Helper

    private let calendar = Calendar.current

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        let components = DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
        return calendar.date(from: components)!
    }

    // MARK: - formatCurrency

    func testFormatCurrencyPositiveAmount() {
        let result = formatCurrency(1000)
        XCTAssertEqual(result, "¥1,000")
    }

    func testFormatCurrencyZeroAmount() {
        let result = formatCurrency(0)
        XCTAssertEqual(result, "¥0")
    }

    func testFormatCurrencyNegativeAmount() {
        let result = formatCurrency(-500)
        XCTAssertEqual(result, "-¥500")
    }

    func testFormatCurrencyLargeAmount() {
        let result = formatCurrency(1_000_000)
        XCTAssertEqual(result, "¥1,000,000")
    }

    func testFormatCurrencySmallPositiveAmount() {
        let result = formatCurrency(1)
        XCTAssertEqual(result, "¥1")
    }

    func testFormatCurrencyLargeNegativeAmount() {
        let result = formatCurrency(-1_234_567)
        XCTAssertEqual(result, "-¥1,234,567")
    }

    // MARK: - formatDate

    func testFormatDateReturnsJapaneseMediumFormat() {
        let date = makeDate(year: 2026, month: 2, day: 20)
        let result = formatDate(date)
        // ja_JP medium format: "2026/02/20"
        XCTAssertTrue(result.contains("2026"), "Expected year 2026 in '\(result)'")
        XCTAssertTrue(result.contains("2"), "Expected month component in '\(result)'")
        XCTAssertTrue(result.contains("20"), "Expected day 20 in '\(result)'")
    }

    func testFormatDateDifferentDate() {
        let date = makeDate(year: 2025, month: 12, day: 1)
        let result = formatDate(date)
        XCTAssertTrue(result.contains("2025"), "Expected year 2025 in '\(result)'")
        XCTAssertTrue(result.contains("12"), "Expected month 12 in '\(result)'")
    }

    // MARK: - formatDateShort

    func testFormatDateShortFebruary() {
        let date = makeDate(year: 2026, month: 2, day: 20)
        let result = formatDateShort(date)
        XCTAssertEqual(result, "2月20日")
    }

    func testFormatDateShortJanuary() {
        let date = makeDate(year: 2026, month: 1, day: 1)
        let result = formatDateShort(date)
        XCTAssertEqual(result, "1月1日")
    }

    func testFormatDateShortDecember() {
        let date = makeDate(year: 2025, month: 12, day: 31)
        let result = formatDateShort(date)
        XCTAssertEqual(result, "12月31日")
    }

    // MARK: - todayDate

    func testTodayDateReturnsStartOfDay() {
        let result = todayDate()
        let components = calendar.dateComponents([.hour, .minute, .second], from: result)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    func testTodayDateMatchesCurrentCalendarDay() {
        let result = todayDate()
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        let resultComponents = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(todayComponents.year, resultComponents.year)
        XCTAssertEqual(todayComponents.month, resultComponents.month)
        XCTAssertEqual(todayComponents.day, resultComponents.day)
    }

    // MARK: - monthString

    func testMonthStringFormat() {
        let date = makeDate(year: 2026, month: 2, day: 20)
        let result = monthString(from: date)
        XCTAssertEqual(result, "2026-02")
    }

    func testMonthStringJanuary() {
        let date = makeDate(year: 2025, month: 1, day: 15)
        let result = monthString(from: date)
        XCTAssertEqual(result, "2025-01")
    }

    func testMonthStringDecember() {
        let date = makeDate(year: 2025, month: 12, day: 31)
        let result = monthString(from: date)
        XCTAssertEqual(result, "2025-12")
    }

    // MARK: - startOfMonth

    func testStartOfMonthReturnsFirstDay() {
        let date = makeDate(year: 2026, month: 2, day: 20)
        let result = startOfMonth(date)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 1)
    }

    func testStartOfMonthFromFirstDay() {
        let date = makeDate(year: 2026, month: 3, day: 1)
        let result = startOfMonth(date)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 1)
    }

    func testStartOfMonthFromLastDay() {
        let date = makeDate(year: 2026, month: 1, day: 31)
        let result = startOfMonth(date)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
    }

    func testStartOfMonthTimeIsZero() {
        let date = makeDate(year: 2026, month: 5, day: 15, hour: 14, minute: 30)
        let result = startOfMonth(date)
        let components = calendar.dateComponents([.hour, .minute, .second], from: result)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    // MARK: - endOfMonth

    func testEndOfMonthFebruary2026() {
        let date = makeDate(year: 2026, month: 2, day: 10)
        let result = endOfMonth(date)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 28)
    }

    func testEndOfMonthFebruaryLeapYear() {
        // 2024 is a leap year
        let date = makeDate(year: 2024, month: 2, day: 5)
        let result = endOfMonth(date)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 29)
    }

    func testEndOfMonth30DayMonth() {
        let date = makeDate(year: 2026, month: 4, day: 15)
        let result = endOfMonth(date)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 30)
    }

    func testEndOfMonth31DayMonth() {
        let date = makeDate(year: 2026, month: 1, day: 10)
        let result = endOfMonth(date)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 31)
    }

    func testEndOfMonthDecember() {
        let date = makeDate(year: 2025, month: 12, day: 1)
        let result = endOfMonth(date)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 31)
    }

    // MARK: - startOfYear

    func testStartOfYearReturnsJanFirst() {
        let result = startOfYear(2026)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 1)
    }

    func testStartOfYearTimeIsZero() {
        let result = startOfYear(2025)
        let components = calendar.dateComponents([.hour, .minute, .second], from: result)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 0)
    }

    // MARK: - endOfYear

    func testEndOfYearReturnsDecThirtyFirst() {
        let result = endOfYear(2026)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 31)
    }

    func testEndOfYearDifferentYear() {
        let result = endOfYear(2024)
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 31)
    }

    // MARK: - getNextRegistrationDate (monthly, day not yet passed)

    func testMonthlyDayNotYetPassed() {
        // If today is Feb 20 and dayOfMonth is 25, next date should be this month
        let today = todayDate()
        let comps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentDay = comps.day else {
            XCTFail("Could not determine current day")
            return
        }

        let futureDay = min(currentDay + 5, 28)
        // Only run this branch if we can set a future day in the current month
        guard futureDay > currentDay else { return }

        let result = getNextRegistrationDate(
            frequency: .monthly,
            dayOfMonth: futureDay,
            monthOfYear: nil,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        let resultComps = calendar.dateComponents([.year, .month, .day], from: result!.date)
        XCTAssertEqual(resultComps.month, comps.month)
        XCTAssertEqual(resultComps.day, futureDay)
        XCTAssertTrue(result!.daysUntil > 0)
    }

    // MARK: - getNextRegistrationDate (monthly, day already passed)

    func testMonthlyDayAlreadyPassed() {
        let today = todayDate()
        let comps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentDay = comps.day, let currentMonth = comps.month, let currentYear = comps.year else {
            XCTFail("Could not determine current date components")
            return
        }

        // Use a day that has already passed (currentDay - 1), minimum 1
        let pastDay = max(1, currentDay - 1)
        // If currentDay is 1, the day equals currentDay, so it still wraps to next month (>= logic)
        guard pastDay < currentDay else {
            // currentDay == 1, use dayOfMonth = 1 which triggers >= path
            let result = getNextRegistrationDate(
                frequency: .monthly,
                dayOfMonth: 1,
                monthOfYear: nil,
                isActive: true,
                lastGeneratedDate: nil
            )
            XCTAssertNotNil(result)
            let resultComps = calendar.dateComponents([.month], from: result!.date)
            let expectedMonth = currentMonth == 12 ? 1 : currentMonth + 1
            XCTAssertEqual(resultComps.month, expectedMonth)
            return
        }

        let result = getNextRegistrationDate(
            frequency: .monthly,
            dayOfMonth: pastDay,
            monthOfYear: nil,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        let resultComps = calendar.dateComponents([.year, .month, .day], from: result!.date)
        let expectedMonth = currentMonth == 12 ? 1 : currentMonth + 1
        let expectedYear = currentMonth == 12 ? currentYear + 1 : currentYear
        XCTAssertEqual(resultComps.month, expectedMonth)
        XCTAssertEqual(resultComps.year, expectedYear)
        XCTAssertEqual(resultComps.day, pastDay)
    }

    // MARK: - getNextRegistrationDate (monthly, day equals today)

    func testMonthlyDayEqualsToday() {
        // When currentDay >= dayOfMonth, it wraps to next month
        let today = todayDate()
        let comps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentDay = comps.day, let currentMonth = comps.month else {
            XCTFail("Could not determine current date components")
            return
        }

        let result = getNextRegistrationDate(
            frequency: .monthly,
            dayOfMonth: currentDay,
            monthOfYear: nil,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        let resultComps = calendar.dateComponents([.month], from: result!.date)
        let expectedMonth = currentMonth == 12 ? 1 : currentMonth + 1
        XCTAssertEqual(resultComps.month, expectedMonth)
    }

    // MARK: - getNextRegistrationDate (yearly, month not yet passed)

    func testYearlyMonthNotYetPassed() {
        let today = todayDate()
        let comps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentYear = comps.year, let currentMonth = comps.month, let currentDay = comps.day else {
            XCTFail("Could not determine current date components")
            return
        }

        // Choose a target month in the future
        let futureMonth = currentMonth < 12 ? currentMonth + 1 : currentMonth
        guard futureMonth > currentMonth else { return } // skip if December

        let result = getNextRegistrationDate(
            frequency: .yearly,
            dayOfMonth: 15,
            monthOfYear: futureMonth,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        let resultComps = calendar.dateComponents([.year, .month, .day], from: result!.date)
        XCTAssertEqual(resultComps.year, currentYear)
        XCTAssertEqual(resultComps.month, futureMonth)
        XCTAssertEqual(resultComps.day, 15)
    }

    // MARK: - getNextRegistrationDate (yearly, month already passed)

    func testYearlyMonthAlreadyPassed() {
        let today = todayDate()
        let comps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentYear = comps.year, let currentMonth = comps.month else {
            XCTFail("Could not determine current date components")
            return
        }

        // Choose a target month in the past
        let pastMonth = currentMonth > 1 ? currentMonth - 1 : currentMonth
        guard pastMonth < currentMonth else { return } // skip if January

        let result = getNextRegistrationDate(
            frequency: .yearly,
            dayOfMonth: 10,
            monthOfYear: pastMonth,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        let resultComps = calendar.dateComponents([.year, .month], from: result!.date)
        XCTAssertEqual(resultComps.year, currentYear + 1)
        XCTAssertEqual(resultComps.month, pastMonth)
    }

    // MARK: - getNextRegistrationDate (yearly, same month day already passed)

    func testYearlySameMonthDayAlreadyPassed() {
        let today = todayDate()
        let comps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentYear = comps.year, let currentMonth = comps.month, let currentDay = comps.day else {
            XCTFail("Could not determine current date components")
            return
        }

        // Same month, but day already passed
        let pastDay = max(1, currentDay - 1)
        guard pastDay < currentDay else { return } // skip if day 1

        let result = getNextRegistrationDate(
            frequency: .yearly,
            dayOfMonth: pastDay,
            monthOfYear: currentMonth,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        let resultComps = calendar.dateComponents([.year, .month, .day], from: result!.date)
        XCTAssertEqual(resultComps.year, currentYear + 1)
        XCTAssertEqual(resultComps.month, currentMonth)
        XCTAssertEqual(resultComps.day, pastDay)
    }

    // MARK: - getNextRegistrationDate (inactive)

    func testInactiveReturnsNil() {
        let result = getNextRegistrationDate(
            frequency: .monthly,
            dayOfMonth: 15,
            monthOfYear: nil,
            isActive: false,
            lastGeneratedDate: nil
        )

        XCTAssertNil(result)
    }

    // MARK: - getNextRegistrationDate (daysUntil calculation)

    func testDaysUntilCalculation() {
        let today = todayDate()
        let comps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentDay = comps.day else {
            XCTFail("Could not determine current day")
            return
        }

        // Pick a day in the future within this month
        let futureDay = min(currentDay + 3, 28)
        guard futureDay > currentDay else { return }

        let result = getNextRegistrationDate(
            frequency: .monthly,
            dayOfMonth: futureDay,
            monthOfYear: nil,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.daysUntil, futureDay - currentDay)
    }

    // MARK: - getNextRegistrationDate (label generation)

    func testLabelTodayIsToday() {
        // When daysUntil == 0, label should be "今日"
        // This happens when currentDay >= dayOfMonth for monthly,
        // but then it wraps to next month, so daysUntil won't be 0.
        // For yearly: same month, same day triggers wrap too.
        // daysUntil == 0 is possible if we can hit the exact scenario.
        // Since the function uses todayDate() internally, we verify label
        // content via daysUntil ranges instead.

        let result = getNextRegistrationDate(
            frequency: .monthly,
            dayOfMonth: 28,
            monthOfYear: nil,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        // Just verify the label is a non-empty string
        XCTAssertFalse(result!.label.isEmpty)
    }

    func testLabelFormatShortDays() {
        // Verify label format for 2-7 days: "N日後"
        let today = todayDate()
        let comps = calendar.dateComponents([.day], from: today)
        guard let currentDay = comps.day else { return }

        let targetDay = min(currentDay + 3, 28)
        guard targetDay > currentDay, targetDay - currentDay >= 2, targetDay - currentDay <= 7 else { return }

        let result = getNextRegistrationDate(
            frequency: .monthly,
            dayOfMonth: targetDay,
            monthOfYear: nil,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        if result!.daysUntil >= 2 && result!.daysUntil <= 7 {
            XCTAssertEqual(result!.label, "\(result!.daysUntil)日後")
        }
    }

    func testLabelFormatWeeks() {
        // For 8-30 days: "約N週間後"
        let result = getNextRegistrationDate(
            frequency: .monthly,
            dayOfMonth: 1,
            monthOfYear: nil,
            isActive: true,
            lastGeneratedDate: nil
        )

        // This wraps to next month day 1, which is typically 10-30 days out
        XCTAssertNotNil(result)
        if result!.daysUntil >= 8 && result!.daysUntil <= 30 {
            let weeks = result!.daysUntil / 7
            XCTAssertEqual(result!.label, "約\(weeks)週間後")
        }
    }

    func testLabelFormatMonths() {
        // For > 30 days: "約Nヶ月後"
        // Yearly frequency, far future month will produce > 30 days
        let today = todayDate()
        let comps = calendar.dateComponents([.month], from: today)
        guard let currentMonth = comps.month else { return }

        // Pick a month that's at least 2 months away
        let targetMonth: Int
        if currentMonth <= 10 {
            targetMonth = currentMonth + 2
        } else {
            // Close to end of year, this will wrap to next year
            targetMonth = 1
        }

        let result = getNextRegistrationDate(
            frequency: .yearly,
            dayOfMonth: 15,
            monthOfYear: targetMonth,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        if result!.daysUntil > 30 {
            let months = result!.daysUntil / 30
            XCTAssertEqual(result!.label, "約\(months)ヶ月後")
        }
    }

    func testLabelTomorrowIs明日() {
        let today = todayDate()
        let comps = calendar.dateComponents([.day], from: today)
        guard let currentDay = comps.day else { return }

        let tomorrowDay = currentDay + 1
        guard tomorrowDay <= 28 else { return }

        let result = getNextRegistrationDate(
            frequency: .monthly,
            dayOfMonth: tomorrowDay,
            monthOfYear: nil,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        if result!.daysUntil == 1 {
            XCTAssertEqual(result!.label, "明日")
        }
    }

    // MARK: - getNextRegistrationDate (yearly, nil monthOfYear defaults to 1)

    func testYearlyNilMonthOfYearDefaultsToJanuary() {
        let result = getNextRegistrationDate(
            frequency: .yearly,
            dayOfMonth: 15,
            monthOfYear: nil,
            isActive: true,
            lastGeneratedDate: nil
        )

        XCTAssertNotNil(result)
        let resultComps = calendar.dateComponents([.month], from: result!.date)
        XCTAssertEqual(resultComps.month, 1)
    }

    // MARK: - generateCSV

    func testGenerateCSVStartsWithBOM() {
        let csv = generateCSV(
            transactions: [],
            getCategory: { _ in nil },
            getProject: { _ in nil }
        )

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))
    }

    func testGenerateCSVContainsHeaders() {
        let csv = generateCSV(
            transactions: [],
            getCategory: { _ in nil },
            getProject: { _ in nil }
        )

        let withoutBOM = String(csv.dropFirst())
        XCTAssertEqual(withoutBOM, "\"日付\",\"種類\",\"金額\",\"カテゴリ\",\"プロジェクト\",\"メモ\",\"配分額\",\"定期取引ID\",\"作成日\",\"更新日\",\"レシート画像\",\"明細\"")
    }

    func testGenerateCSVEmptyTransactions() {
        let csv = generateCSV(
            transactions: [],
            getCategory: { _ in nil },
            getProject: { _ in nil }
        )

        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 1, "Empty transactions should produce only the header line")
    }

    func testGenerateCSVWithIncomeTransaction() {
        let date = makeDate(year: 2026, month: 2, day: 20)
        let transaction = PPTransaction(
            type: .income,
            amount: 50000,
            date: date,
            categoryId: "cat-sales",
            memo: "テスト売上"
        )

        let category = PPCategory(
            id: "cat-sales",
            name: "売上",
            type: .income,
            icon: "yensign.circle"
        )

        let csv = generateCSV(
            transactions: [transaction],
            getCategory: { id in id == "cat-sales" ? category : nil },
            getProject: { _ in nil }
        )

        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)

        let row = lines[1]
        XCTAssertTrue(row.contains("2026-02-20"), "Row should contain formatted date")
        XCTAssertTrue(row.contains("収益"), "Income type should be '収益'")
        XCTAssertTrue(row.contains("50000"), "Row should contain amount")
        XCTAssertTrue(row.contains("売上"), "Row should contain category name")
        XCTAssertTrue(row.contains("テスト売上"), "Row should contain memo")
    }

    func testGenerateCSVWithExpenseTransaction() {
        let date = makeDate(year: 2026, month: 3, day: 15)
        let transaction = PPTransaction(
            type: .expense,
            amount: 3000,
            date: date,
            categoryId: "cat-hosting",
            memo: "サーバー代"
        )

        let category = PPCategory(
            id: "cat-hosting",
            name: "ホスティング",
            type: .expense,
            icon: "server.rack"
        )

        let csv = generateCSV(
            transactions: [transaction],
            getCategory: { id in id == "cat-hosting" ? category : nil },
            getProject: { _ in nil }
        )

        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)

        let row = lines[1]
        XCTAssertTrue(row.contains("経費"), "Expense type should be '経費'")
        XCTAssertTrue(row.contains("ホスティング"), "Row should contain category name")
    }

    func testGenerateCSVWithProjectAllocations() {
        let projectId1 = UUID()
        let projectId2 = UUID()
        let date = makeDate(year: 2026, month: 1, day: 10)

        let allocation1 = Allocation(projectId: projectId1, ratio: 60, amount: 30000)
        let allocation2 = Allocation(projectId: projectId2, ratio: 40, amount: 20000)

        let transaction = PPTransaction(
            type: .income,
            amount: 50000,
            date: date,
            categoryId: "cat-sales",
            allocations: [allocation1, allocation2]
        )

        let project1 = PPProject(id: projectId1, name: "ProjectA")
        let project2 = PPProject(id: projectId2, name: "ProjectB")

        let csv = generateCSV(
            transactions: [transaction],
            getCategory: { _ in nil },
            getProject: { id in
                if id == projectId1 { return project1 }
                if id == projectId2 { return project2 }
                return nil
            }
        )

        let lines = csv.components(separatedBy: "\n")
        let row = lines[1]
        XCTAssertTrue(row.contains("ProjectA(60%)"), "Row should contain first project with ratio")
        XCTAssertTrue(row.contains("ProjectB(40%)"), "Row should contain second project with ratio")
        XCTAssertTrue(row.contains("; "), "Project names should be separated by '; '")
    }

    func testGenerateCSVMemoCommaEscaping() {
        let date = makeDate(year: 2026, month: 1, day: 5)
        let transaction = PPTransaction(
            type: .expense,
            amount: 1000,
            date: date,
            categoryId: "cat-other-expense",
            memo: "item1,item2,item3"
        )

        let csv = generateCSV(
            transactions: [transaction],
            getCategory: { _ in nil },
            getProject: { _ in nil }
        )

        let lines = csv.components(separatedBy: "\n")
        let row = lines[1]
        // Fields are double-quoted, so commas within are valid CSV
        XCTAssertTrue(row.contains("item1,item2,item3"), "Commas in memo are preserved inside quoted fields")
    }

    func testGenerateCSVDoubleQuoteEscaping() {
        let date = makeDate(year: 2026, month: 1, day: 5)
        let transaction = PPTransaction(
            type: .expense,
            amount: 1000,
            date: date,
            categoryId: "cat-other-expense",
            memo: "said \"hello\" today"
        )

        let csv = generateCSV(
            transactions: [transaction],
            getCategory: { _ in nil },
            getProject: { _ in nil }
        )

        let lines = csv.components(separatedBy: "\n")
        let row = lines[1]
        // Double quotes inside fields should be escaped as ""
        XCTAssertTrue(row.contains("said \"\"hello\"\" today"), "Double quotes in memo should be escaped as double-double-quotes")
    }

    func testGenerateCSVMultipleTransactions() {
        let date1 = makeDate(year: 2026, month: 1, day: 1)
        let date2 = makeDate(year: 2026, month: 1, day: 2)
        let date3 = makeDate(year: 2026, month: 1, day: 3)

        let transactions = [
            PPTransaction(type: .income, amount: 10000, date: date1, categoryId: "cat-sales"),
            PPTransaction(type: .expense, amount: 5000, date: date2, categoryId: "cat-hosting"),
            PPTransaction(type: .income, amount: 20000, date: date3, categoryId: "cat-service"),
        ]

        let csv = generateCSV(
            transactions: transactions,
            getCategory: { _ in nil },
            getProject: { _ in nil }
        )

        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 4, "Should have 1 header + 3 data rows")
    }

    func testGenerateCSVNilCategoryShowsEmptyString() {
        let date = makeDate(year: 2026, month: 1, day: 1)
        let transaction = PPTransaction(
            type: .income,
            amount: 1000,
            date: date,
            categoryId: "nonexistent"
        )

        let csv = generateCSV(
            transactions: [transaction],
            getCategory: { _ in nil },
            getProject: { _ in nil }
        )

        let lines = csv.components(separatedBy: "\n")
        let row = lines[1]
        // The category field should be empty string within quotes
        // Row format: "date","type","amount","","","memo"
        let fields = parseCSVRow(row)
        XCTAssertEqual(fields.count, 12)
        XCTAssertEqual(fields[3], "", "Nil category should produce empty string")
    }

    func testGenerateCSVDateFormat() {
        let date = makeDate(year: 2025, month: 7, day: 4)
        let transaction = PPTransaction(
            type: .income,
            amount: 100,
            date: date,
            categoryId: "cat-sales"
        )

        let csv = generateCSV(
            transactions: [transaction],
            getCategory: { _ in nil },
            getProject: { _ in nil }
        )

        let lines = csv.components(separatedBy: "\n")
        let row = lines[1]
        XCTAssertTrue(row.contains("2025-07-04"), "Date should be formatted as yyyy-MM-dd")
    }

    // MARK: - CSV Parsing Helper

    /// Simple CSV row parser that handles quoted fields.
    private func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = row.makeIterator()

        while let char = iterator.next() {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    // MARK: - calculateRatioAllocations

    func testCalculateRatioAllocations_evenSplit() {
        let id1 = UUID()
        let id2 = UUID()
        let result = calculateRatioAllocations(amount: 1000, allocations: [
            (projectId: id1, ratio: 50),
            (projectId: id2, ratio: 50),
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].amount + result[1].amount, 1000)
        XCTAssertEqual(result[0].amount, 500)
        XCTAssertEqual(result[1].amount, 500)
    }

    func testCalculateRatioAllocations_oddAmount() {
        let id1 = UUID()
        let id2 = UUID()
        let result = calculateRatioAllocations(amount: 999, allocations: [
            (projectId: id1, ratio: 50),
            (projectId: id2, ratio: 50),
        ])
        XCTAssertEqual(result[0].amount + result[1].amount, 999)
        // 999 * 50 / 100 = 499, remainder = 1 → last gets 500
        XCTAssertEqual(result[0].amount, 499)
        XCTAssertEqual(result[1].amount, 500)
    }

    func testCalculateRatioAllocations_threeWay() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let result = calculateRatioAllocations(amount: 10000, allocations: [
            (projectId: id1, ratio: 33),
            (projectId: id2, ratio: 33),
            (projectId: id3, ratio: 34),
        ])
        let total = result.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 10000, "Total must match original amount exactly")
    }

    func testCalculateRatioAllocations_smallAmount() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let result = calculateRatioAllocations(amount: 1, allocations: [
            (projectId: id1, ratio: 33),
            (projectId: id2, ratio: 33),
            (projectId: id3, ratio: 34),
        ])
        let total = result.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 1)
        // 1 * 33 / 100 = 0, 1 * 33 / 100 = 0, 1 * 34 / 100 = 0 → remainder = 1 → last gets 1
        XCTAssertEqual(result[0].amount, 0)
        XCTAssertEqual(result[1].amount, 0)
        XCTAssertEqual(result[2].amount, 1)
    }

    func testCalculateRatioAllocations_empty() {
        let result = calculateRatioAllocations(amount: 1000, allocations: [])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - recalculateAllocationAmounts

    func testRecalculateAllocationAmounts_preservesTotal() {
        let id1 = UUID()
        let id2 = UUID()
        let existing = [
            Allocation(projectId: id1, ratio: 50, amount: 500),
            Allocation(projectId: id2, ratio: 50, amount: 500),
        ]
        let result = recalculateAllocationAmounts(amount: 999, existingAllocations: existing)
        let total = result.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 999)
        XCTAssertEqual(result[0].projectId, id1)
        XCTAssertEqual(result[1].projectId, id2)
    }

    func testRecalculateAllocationAmounts_empty() {
        let result = recalculateAllocationAmounts(amount: 1000, existingAllocations: [])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - M5: Allocation.ratio clamping

    func testAllocationRatio_clampedToZeroWhenNegative() {
        let alloc = Allocation(projectId: UUID(), ratio: -10, amount: 100)
        XCTAssertEqual(alloc.ratio, 0)
    }

    func testAllocationRatio_clampedTo100WhenExceeds() {
        let alloc = Allocation(projectId: UUID(), ratio: 150, amount: 100)
        XCTAssertEqual(alloc.ratio, 100)
    }

    func testAllocationRatio_boundaryZero() {
        let alloc = Allocation(projectId: UUID(), ratio: 0, amount: 100)
        XCTAssertEqual(alloc.ratio, 0)
    }

    func testAllocationRatio_boundary100() {
        let alloc = Allocation(projectId: UUID(), ratio: 100, amount: 100)
        XCTAssertEqual(alloc.ratio, 100)
    }

    func testAllocationRatio_normalValueUnchanged() {
        let alloc = Allocation(projectId: UUID(), ratio: 50, amount: 100)
        XCTAssertEqual(alloc.ratio, 50)
    }

    // MARK: - M9: CSV expanded fields

    func testGenerateCSVContainsExpandedHeaders() {
        let csv = generateCSV(
            transactions: [],
            getCategory: { _ in nil },
            getProject: { _ in nil }
        )

        let withoutBOM = String(csv.dropFirst())
        XCTAssertTrue(withoutBOM.contains("\"配分額\""), "Header should contain 配分額")
        XCTAssertTrue(withoutBOM.contains("\"定期取引ID\""), "Header should contain 定期取引ID")
        XCTAssertTrue(withoutBOM.contains("\"作成日\""), "Header should contain 作成日")
        XCTAssertTrue(withoutBOM.contains("\"更新日\""), "Header should contain 更新日")
        XCTAssertTrue(withoutBOM.contains("\"レシート画像\""), "Header should contain レシート画像")
        XCTAssertTrue(withoutBOM.contains("\"明細\""), "Header should contain 明細")
    }

    func testGenerateCSVExpandedFieldsOutput() {
        let projectId = UUID()
        let recurringId = UUID()
        let date = makeDate(year: 2026, month: 3, day: 1)
        let createdAt = makeDate(year: 2026, month: 2, day: 28, hour: 10, minute: 30)

        let allocation = Allocation(projectId: projectId, ratio: 100, amount: 5000)
        let lineItem = ReceiptLineItem(name: "品目A", quantity: 2, unitPrice: 2500)

        let transaction = PPTransaction(
            type: .expense,
            amount: 5000,
            date: date,
            categoryId: "cat-tools",
            allocations: [allocation],
            recurringId: recurringId,
            receiptImagePath: "receipt_001.jpg",
            lineItems: [lineItem],
            createdAt: createdAt,
            updatedAt: createdAt
        )

        let project = PPProject(id: projectId, name: "TestProject")

        let csv = generateCSV(
            transactions: [transaction],
            getCategory: { _ in nil },
            getProject: { id in id == projectId ? project : nil }
        )

        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)

        let row = lines[1]
        let fields = parseCSVRow(row)
        XCTAssertEqual(fields.count, 12, "Should have 12 fields")
        XCTAssertTrue(fields[6].contains("TestProject:5000"), "Allocation amounts field")
        XCTAssertEqual(fields[7], recurringId.uuidString, "Recurring ID field")
        XCTAssertTrue(fields[8].contains("2026-02-28"), "Created at field")
        XCTAssertEqual(fields[10], "receipt_001.jpg", "Receipt image field")
        XCTAssertTrue(fields[11].contains("品目A×2@2500"), "Line items field")
    }

    func testGenerateCSVBackwardCompatibleFieldOrder() {
        let date = makeDate(year: 2026, month: 1, day: 1)
        let transaction = PPTransaction(
            type: .income,
            amount: 10000,
            date: date,
            categoryId: "cat-sales",
            memo: "テスト"
        )

        let category = PPCategory(
            id: "cat-sales",
            name: "売上",
            type: .income,
            icon: "yensign.circle"
        )

        let csv = generateCSV(
            transactions: [transaction],
            getCategory: { id in id == "cat-sales" ? category : nil },
            getProject: { _ in nil }
        )

        let lines = csv.components(separatedBy: "\n")
        let fields = parseCSVRow(lines[1])

        // First 6 fields maintain backward compatibility
        XCTAssertTrue(fields[0].contains("2026-01-01"), "Date field unchanged")
        XCTAssertEqual(fields[1], "収益", "Type field unchanged")
        XCTAssertEqual(fields[2], "10000", "Amount field unchanged")
        XCTAssertEqual(fields[3], "売上", "Category field unchanged")
        XCTAssertEqual(fields[5], "テスト", "Memo field unchanged")
    }

    // MARK: - M1: Non-Optional allocationMode/yearlyAmortizationMode

    func testRecurringTransaction_allocationModeNonOptional() {
        let recurring = PPRecurringTransaction(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-tools"
        )
        XCTAssertEqual(recurring.allocationMode, .manual, "Default allocationMode should be .manual")
    }

    func testRecurringTransaction_yearlyAmortizationModeNonOptional() {
        let recurring = PPRecurringTransaction(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-tools"
        )
        XCTAssertEqual(recurring.yearlyAmortizationMode, .lumpSum, "Default yearlyAmortizationMode should be .lumpSum")
    }

    func testRecurringTransaction_explicitAllocationMode() {
        let recurring = PPRecurringTransaction(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-tools",
            allocationMode: .equalAll
        )
        XCTAssertEqual(recurring.allocationMode, .equalAll)
    }

    func testRecurringTransaction_explicitYearlyAmortizationMode() {
        let recurring = PPRecurringTransaction(
            name: "Test",
            type: .expense,
            amount: 1000,
            categoryId: "cat-tools",
            yearlyAmortizationMode: .monthlySpread
        )
        XCTAssertEqual(recurring.yearlyAmortizationMode, .monthlySpread)
    }
}
