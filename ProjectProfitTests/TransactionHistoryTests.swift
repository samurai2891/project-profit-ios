import XCTest
@testable import ProjectProfit

final class TransactionHistoryTests: XCTestCase {

    // MARK: - Helper

    private let calendar = Calendar.current

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeTransaction(
        type: TransactionType = .income,
        amount: Int = 1000,
        date: Date,
        categoryId: String = "cat-sales",
        recurringId: UUID? = nil
    ) -> PPTransaction {
        PPTransaction(
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            recurringId: recurringId
        )
    }

    // MARK: - formatYearMonth

    func testFormatYearMonth() {
        let date = makeDate(year: 2026, month: 2, day: 15)
        let result = formatYearMonth(date)
        XCTAssertEqual(result, "2026年2月")
    }

    func testFormatYearMonthJanuary() {
        let date = makeDate(year: 2025, month: 1, day: 1)
        let result = formatYearMonth(date)
        XCTAssertEqual(result, "2025年1月")
    }

    func testFormatYearMonthDecember() {
        let date = makeDate(year: 2025, month: 12, day: 31)
        let result = formatYearMonth(date)
        XCTAssertEqual(result, "2025年12月")
    }

    // MARK: - TransactionGroup

    func testTransactionGroupId() {
        let group = TransactionGroup(
            yearMonth: "2026-02",
            displayLabel: "2026年2月",
            transactions: [],
            income: 5000,
            expense: 3000,
            transfer: 0
        )
        XCTAssertEqual(group.id, "2026-02")
    }

    // MARK: - Grouping Logic (standalone)

    func testGroupedByYearMonth() {
        let jan = makeDate(year: 2026, month: 1, day: 10)
        let feb1 = makeDate(year: 2026, month: 2, day: 5)
        let feb2 = makeDate(year: 2026, month: 2, day: 20)
        let transactions = [
            makeTransaction(date: jan),
            makeTransaction(date: feb1),
            makeTransaction(date: feb2),
        ]

        let groups = groupTransactionsByMonth(transactions)
        XCTAssertEqual(groups.count, 2)
    }

    func testGroupedSortedDescending() {
        let jan = makeDate(year: 2026, month: 1, day: 10)
        let feb = makeDate(year: 2026, month: 2, day: 5)
        let mar = makeDate(year: 2026, month: 3, day: 15)
        let transactions = [
            makeTransaction(date: jan),
            makeTransaction(date: mar),
            makeTransaction(date: feb),
        ]

        let groups = groupTransactionsByMonth(transactions)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups[0].yearMonth, "2026-03")
        XCTAssertEqual(groups[1].yearMonth, "2026-02")
        XCTAssertEqual(groups[2].yearMonth, "2026-01")
    }

    func testSelectedTypeFiltersIncome() {
        let date = makeDate(year: 2026, month: 2, day: 10)
        let transactions = [
            makeTransaction(type: .income, amount: 5000, date: date),
            makeTransaction(type: .expense, amount: 3000, date: date),
            makeTransaction(type: .income, amount: 2000, date: date),
        ]

        let filtered = transactions.filter { $0.type == .income }
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.type == .income })
    }

    func testSelectedTypeFiltersExpense() {
        let date = makeDate(year: 2026, month: 2, day: 10)
        let transactions = [
            makeTransaction(type: .income, amount: 5000, date: date),
            makeTransaction(type: .expense, amount: 3000, date: date),
            makeTransaction(type: .expense, amount: 1000, date: date),
        ]

        let filtered = transactions.filter { $0.type == .expense }
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.type == .expense })
    }

    func testSelectedTypeNilShowsAll() {
        let date = makeDate(year: 2026, month: 2, day: 10)
        let transactions = [
            makeTransaction(type: .income, amount: 5000, date: date),
            makeTransaction(type: .expense, amount: 3000, date: date),
        ]

        let type: TransactionType? = nil
        let filtered = type.map { t in transactions.filter { $0.type == t } } ?? transactions
        XCTAssertEqual(filtered.count, 2)
    }

    func testGroupIncomeExpenseTotals() {
        let date1 = makeDate(year: 2026, month: 2, day: 5)
        let date2 = makeDate(year: 2026, month: 2, day: 10)
        let date3 = makeDate(year: 2026, month: 2, day: 15)
        let transactions = [
            makeTransaction(type: .income, amount: 10000, date: date1),
            makeTransaction(type: .expense, amount: 3000, date: date2),
            makeTransaction(type: .income, amount: 5000, date: date3),
        ]

        let groups = groupTransactionsByMonth(transactions)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].income, 15000)
        XCTAssertEqual(groups[0].expense, 3000)
    }

    func testRecurringTransactionLink() {
        let recurringId = UUID()
        let date = makeDate(year: 2026, month: 2, day: 10)
        let transaction = makeTransaction(date: date, recurringId: recurringId)

        XCTAssertEqual(transaction.recurringId, recurringId)
        XCTAssertNotNil(transaction.recurringId)
    }

    // MARK: - Private grouping helper (mirrors ViewModel logic)

    private func groupTransactionsByMonth(_ transactions: [PPTransaction]) -> [TransactionGroup] {
        let grouped = Dictionary(grouping: transactions) { transaction -> String in
            let comps = calendar.dateComponents([.year, .month], from: transaction.date)
            let year = comps.year ?? 0
            let month = comps.month ?? 0
            return String(format: "%04d-%02d", year, month)
        }

        return grouped.map { yearMonth, txns in
            let income = txns
                .filter { $0.type == .income }
                .reduce(0) { $0 + $1.amount }
            let expense = txns
                .filter { $0.type == .expense }
                .reduce(0) { $0 + $1.amount }
            let displayLabel = formatYearMonth(txns.first?.date ?? Date())

            let transfer = txns
                .filter { $0.type == .transfer }
                .reduce(0) { $0 + $1.amount }

            return TransactionGroup(
                yearMonth: yearMonth,
                displayLabel: displayLabel,
                transactions: txns,
                income: income,
                expense: expense,
                transfer: transfer
            )
        }
        .sorted { $0.yearMonth > $1.yearMonth }
    }
}
