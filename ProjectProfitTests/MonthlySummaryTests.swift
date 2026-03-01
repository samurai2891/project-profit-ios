import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class MonthlySummaryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Helper

    /// Finds a row by id from the summary result, failing the test if not found.
    private func findRow(_ rows: [MonthlySummaryRow], id: String, file: StaticString = #file, line: UInt = #line) -> MonthlySummaryRow? {
        let row = rows.first { $0.id == id }
        if row == nil {
            XCTFail("Expected row with id '\(id)' not found in summary rows: \(rows.map(\.id))", file: file, line: line)
        }
        return row
    }

    // MARK: - 1. Empty

    func testMonthlySummary_Empty() {
        let rows = dataStore.getMonthlySummary(year: 2025)
        // getMonthlySummary always returns structural rows, but all amounts should be zero
        for row in rows {
            XCTAssertEqual(row.total, 0, "Row '\(row.id)' should have zero total when no journal entries exist")
            XCTAssertTrue(row.amounts.allSatisfy { $0 == 0 }, "Row '\(row.id)' should have all zero monthly amounts")
        }
    }

    // MARK: - 2. Cash Sale

    func testMonthlySummary_CashSale() {
        // Dr cash 100,000 / Cr sales 100,000 in January 2025
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 15),
            memo: "現金売上",
            lines: [
                (accountId: "acct-cash", debit: 100_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 100_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let cashSalesRow = findRow(rows, id: "sales-cash") else { return }
        XCTAssertEqual(cashSalesRow.amounts[0], 100_000, "January cash sales should be 100,000")
        XCTAssertEqual(cashSalesRow.label, "  現金売上")

        // All other months should be zero
        for month in 1..<12 {
            XCTAssertEqual(cashSalesRow.amounts[month], 0, "Month \(month + 1) should be 0")
        }
    }

    // MARK: - 3. Credit Sale

    func testMonthlySummary_CreditSale() {
        // Dr ar 80,000 / Cr sales 80,000 in February 2025
        dataStore.addManualJournalEntry(
            date: date(2025, 2, 20),
            memo: "掛売上",
            lines: [
                (accountId: "acct-ar", debit: 80_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 80_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let creditSalesRow = findRow(rows, id: "sales-credit") else { return }
        XCTAssertEqual(creditSalesRow.amounts[1], 80_000, "February credit sales should be 80,000")
        XCTAssertEqual(creditSalesRow.label, "  掛売上")

        // January should be zero
        XCTAssertEqual(creditSalesRow.amounts[0], 0)
    }

    // MARK: - 4. Sales Total

    func testMonthlySummary_SalesTotal() {
        // Cash sale 100k in January
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 10),
            memo: "現金売上",
            lines: [
                (accountId: "acct-cash", debit: 100_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 100_000, memo: ""),
            ]
        )

        // Credit sale 80k in February
        dataStore.addManualJournalEntry(
            date: date(2025, 2, 15),
            memo: "掛売上",
            lines: [
                (accountId: "acct-ar", debit: 80_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 80_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let salesTotal = findRow(rows, id: "sales-total") else { return }
        XCTAssertEqual(salesTotal.amounts[0], 100_000, "January total sales should be 100,000")
        XCTAssertEqual(salesTotal.amounts[1], 80_000, "February total sales should be 80,000")
        XCTAssertEqual(salesTotal.total, 180_000, "Annual sales total should be 180,000")
        XCTAssertTrue(salesTotal.isSubtotal, "sales-total should be a subtotal row")
        XCTAssertEqual(salesTotal.label, "売上（収入）金額 計")
    }

    // MARK: - 5. Other Income

    func testMonthlySummary_OtherIncome() {
        // Dr cash 5,000 / Cr other-income 5,000 in March
        dataStore.addManualJournalEntry(
            date: date(2025, 3, 5),
            memo: "雑収入",
            lines: [
                (accountId: "acct-cash", debit: 5_000, credit: 0, memo: ""),
                (accountId: "acct-other-income", debit: 0, credit: 5_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let otherIncomeRow = findRow(rows, id: "other-income") else { return }
        XCTAssertEqual(otherIncomeRow.amounts[2], 5_000, "March other income should be 5,000")
        XCTAssertEqual(otherIncomeRow.total, 5_000)
        XCTAssertEqual(otherIncomeRow.label, "雑収入")
    }

    // MARK: - 6. Cash Purchase

    func testMonthlySummary_CashPurchase() {
        // Dr purchases 50,000 / Cr cash 50,000 in April
        dataStore.addManualJournalEntry(
            date: date(2025, 4, 10),
            memo: "現金仕入",
            lines: [
                (accountId: "acct-purchases", debit: 50_000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 50_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let cashPurchaseRow = findRow(rows, id: "purchases-cash") else { return }
        XCTAssertEqual(cashPurchaseRow.amounts[3], 50_000, "April cash purchases should be 50,000")
        XCTAssertEqual(cashPurchaseRow.label, "  現金仕入")
    }

    // MARK: - 7. Credit Purchase

    func testMonthlySummary_CreditPurchase() {
        // Dr purchases 30,000 / Cr ap 30,000 in May
        dataStore.addManualJournalEntry(
            date: date(2025, 5, 20),
            memo: "掛仕入",
            lines: [
                (accountId: "acct-purchases", debit: 30_000, credit: 0, memo: ""),
                (accountId: "acct-ap", debit: 0, credit: 30_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let creditPurchaseRow = findRow(rows, id: "purchases-credit") else { return }
        XCTAssertEqual(creditPurchaseRow.amounts[4], 30_000, "May credit purchases should be 30,000")
        XCTAssertEqual(creditPurchaseRow.label, "  掛仕入")
    }

    // MARK: - 8. Expenses

    func testMonthlySummary_Expenses() {
        // Dr rent 80,000 / Cr cash 80,000 in June
        dataStore.addManualJournalEntry(
            date: date(2025, 6, 1),
            memo: "家賃支払",
            lines: [
                (accountId: "acct-rent", debit: 80_000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 80_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let rentRow = findRow(rows, id: "expense-acct-rent") else { return }
        XCTAssertEqual(rentRow.amounts[5], 80_000, "June rent expense should be 80,000")
        XCTAssertEqual(rentRow.label, "  地代家賃")
    }

    // MARK: - 9. Expense Total

    func testMonthlySummary_ExpenseTotal() {
        // Rent 80k in June
        dataStore.addManualJournalEntry(
            date: date(2025, 6, 1),
            memo: "家賃",
            lines: [
                (accountId: "acct-rent", debit: 80_000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 80_000, memo: ""),
            ]
        )

        // Travel 15k in July
        dataStore.addManualJournalEntry(
            date: date(2025, 7, 10),
            memo: "交通費",
            lines: [
                (accountId: "acct-travel", debit: 15_000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 15_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let expenseTotal = findRow(rows, id: "expense-total") else { return }
        XCTAssertEqual(expenseTotal.amounts[5], 80_000, "June expense total should be 80,000")
        XCTAssertEqual(expenseTotal.amounts[6], 15_000, "July expense total should be 15,000")
        XCTAssertEqual(expenseTotal.total, 95_000, "Annual expense total should be 95,000")
        XCTAssertTrue(expenseTotal.isSubtotal, "expense-total should be a subtotal row")
    }

    // MARK: - 10. Subtotal Flags

    func testMonthlySummary_SubtotalFlags() {
        // Create minimal entries to produce all subtotal rows
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 1),
            memo: "テスト売上",
            lines: [
                (accountId: "acct-cash", debit: 1_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 1_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        // Verify subtotal rows
        let subtotalIds: Set<String> = ["sales-total", "purchases-total", "expense-total"]
        let nonSubtotalIds: Set<String> = ["sales-cash", "sales-credit", "other-income", "purchases-cash", "purchases-credit"]

        for row in rows {
            if subtotalIds.contains(row.id) {
                XCTAssertTrue(row.isSubtotal, "\(row.id) should have isSubtotal=true")
            } else if nonSubtotalIds.contains(row.id) {
                XCTAssertFalse(row.isSubtotal, "\(row.id) should have isSubtotal=false")
            }
        }

        // Ensure all three subtotal rows exist
        for expectedId in subtotalIds {
            XCTAssertTrue(rows.contains { $0.id == expectedId }, "Expected subtotal row '\(expectedId)' should be present")
        }
    }

    // MARK: - 11. Year Filter

    func testMonthlySummary_YearFilter() {
        // 2025 entry
        dataStore.addManualJournalEntry(
            date: date(2025, 3, 15),
            memo: "2025年売上",
            lines: [
                (accountId: "acct-cash", debit: 100_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 100_000, memo: ""),
            ]
        )

        // 2026 entry
        dataStore.addManualJournalEntry(
            date: date(2026, 3, 15),
            memo: "2026年売上",
            lines: [
                (accountId: "acct-cash", debit: 200_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 200_000, memo: ""),
            ]
        )

        // Query 2025 only
        let rows2025 = dataStore.getMonthlySummary(year: 2025)
        guard let salesTotal2025 = findRow(rows2025, id: "sales-total") else { return }
        XCTAssertEqual(salesTotal2025.total, 100_000, "2025 total should only include 2025 entries")
        XCTAssertEqual(salesTotal2025.amounts[2], 100_000, "March 2025 should be 100,000")

        // Query 2026 only
        let rows2026 = dataStore.getMonthlySummary(year: 2026)
        guard let salesTotal2026 = findRow(rows2026, id: "sales-total") else { return }
        XCTAssertEqual(salesTotal2026.total, 200_000, "2026 total should only include 2026 entries")
        XCTAssertEqual(salesTotal2026.amounts[2], 200_000, "March 2026 should be 200,000")
    }

    // MARK: - 12. All Months

    func testMonthlySummary_AllMonths() {
        // Create a cash sale entry in every month of 2025
        for month in 1...12 {
            let amount = month * 10_000
            dataStore.addManualJournalEntry(
                date: date(2025, month, 15),
                memo: "\(month)月売上",
                lines: [
                    (accountId: "acct-cash", debit: amount, credit: 0, memo: ""),
                    (accountId: "acct-sales", debit: 0, credit: amount, memo: ""),
                ]
            )
        }

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let cashSalesRow = findRow(rows, id: "sales-cash") else { return }

        // Verify each month has correct amount
        for month in 0..<12 {
            let expected = (month + 1) * 10_000
            XCTAssertEqual(cashSalesRow.amounts[month], expected, "Month \(month + 1) should be \(expected)")
        }

        // Total: 10k + 20k + ... + 120k = 780k
        let expectedTotal = (1...12).reduce(0) { $0 + $1 * 10_000 }
        XCTAssertEqual(cashSalesRow.total, expectedTotal, "Annual cash sales total should be \(expectedTotal)")
    }

    // MARK: - 13. Row Totals

    func testMonthlySummary_RowTotals() {
        // Jan 100k, Mar 50k, Dec 200k — cash sales
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 5),
            memo: "1月売上",
            lines: [
                (accountId: "acct-cash", debit: 100_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 100_000, memo: ""),
            ]
        )

        dataStore.addManualJournalEntry(
            date: date(2025, 3, 10),
            memo: "3月売上",
            lines: [
                (accountId: "acct-cash", debit: 50_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 50_000, memo: ""),
            ]
        )

        dataStore.addManualJournalEntry(
            date: date(2025, 12, 25),
            memo: "12月売上",
            lines: [
                (accountId: "acct-cash", debit: 200_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 200_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let cashSalesRow = findRow(rows, id: "sales-cash") else { return }
        XCTAssertEqual(cashSalesRow.amounts[0], 100_000, "January")
        XCTAssertEqual(cashSalesRow.amounts[2], 50_000, "March")
        XCTAssertEqual(cashSalesRow.amounts[11], 200_000, "December")
        XCTAssertEqual(cashSalesRow.total, 350_000, "Row total should be 350,000")
    }

    // MARK: - 14. Annual Blue Return (Full Year)

    func testMonthlySummary_AnnualBlueReturn() {
        // Monthly cash sales: 500k each month Jan-Dec
        for month in 1...12 {
            dataStore.addManualJournalEntry(
                date: date(2025, month, 5),
                memo: "\(month)月現金売上",
                lines: [
                    (accountId: "acct-cash", debit: 500_000, credit: 0, memo: ""),
                    (accountId: "acct-sales", debit: 0, credit: 500_000, memo: ""),
                ]
            )
        }

        // Monthly credit sales: 300k each month Jan-Dec
        for month in 1...12 {
            dataStore.addManualJournalEntry(
                date: date(2025, month, 10),
                memo: "\(month)月掛売上",
                lines: [
                    (accountId: "acct-ar", debit: 300_000, credit: 0, memo: ""),
                    (accountId: "acct-sales", debit: 0, credit: 300_000, memo: ""),
                ]
            )
        }

        // Monthly cash purchases: 200k each month Jan-Dec
        for month in 1...12 {
            dataStore.addManualJournalEntry(
                date: date(2025, month, 12),
                memo: "\(month)月現金仕入",
                lines: [
                    (accountId: "acct-purchases", debit: 200_000, credit: 0, memo: ""),
                    (accountId: "acct-cash", debit: 0, credit: 200_000, memo: ""),
                ]
            )
        }

        // Monthly rent: 120k each month Jan-Dec
        for month in 1...12 {
            dataStore.addManualJournalEntry(
                date: date(2025, month, 25),
                memo: "\(month)月家賃",
                lines: [
                    (accountId: "acct-rent", debit: 120_000, credit: 0, memo: ""),
                    (accountId: "acct-cash", debit: 0, credit: 120_000, memo: ""),
                ]
            )
        }

        // Monthly supplies: 30k in Jan, Mar, Jun, Sep, Dec (5 months)
        for month in [1, 3, 6, 9, 12] {
            dataStore.addManualJournalEntry(
                date: date(2025, month, 20),
                memo: "\(month)月消耗品",
                lines: [
                    (accountId: "acct-supplies", debit: 30_000, credit: 0, memo: ""),
                    (accountId: "acct-cash", debit: 0, credit: 30_000, memo: ""),
                ]
            )
        }

        let rows = dataStore.getMonthlySummary(year: 2025)

        // --- Sales ---
        guard let cashSales = findRow(rows, id: "sales-cash") else { return }
        for month in 0..<12 {
            XCTAssertEqual(cashSales.amounts[month], 500_000, "Cash sales month \(month + 1)")
        }
        XCTAssertEqual(cashSales.total, 6_000_000, "Annual cash sales = 500k * 12")

        guard let creditSales = findRow(rows, id: "sales-credit") else { return }
        for month in 0..<12 {
            XCTAssertEqual(creditSales.amounts[month], 300_000, "Credit sales month \(month + 1)")
        }
        XCTAssertEqual(creditSales.total, 3_600_000, "Annual credit sales = 300k * 12")

        guard let salesTotal = findRow(rows, id: "sales-total") else { return }
        for month in 0..<12 {
            XCTAssertEqual(salesTotal.amounts[month], 800_000, "Sales total month \(month + 1) = 500k + 300k")
        }
        XCTAssertEqual(salesTotal.total, 9_600_000, "Annual sales total = 800k * 12")
        XCTAssertTrue(salesTotal.isSubtotal)

        // --- Purchases ---
        guard let cashPurchases = findRow(rows, id: "purchases-cash") else { return }
        for month in 0..<12 {
            XCTAssertEqual(cashPurchases.amounts[month], 200_000, "Cash purchases month \(month + 1)")
        }
        XCTAssertEqual(cashPurchases.total, 2_400_000, "Annual cash purchases = 200k * 12")

        guard let purchasesTotal = findRow(rows, id: "purchases-total") else { return }
        XCTAssertEqual(purchasesTotal.total, 2_400_000, "Purchases total (all cash)")
        XCTAssertTrue(purchasesTotal.isSubtotal)

        // --- Expenses ---
        guard let rentRow = findRow(rows, id: "expense-acct-rent") else { return }
        for month in 0..<12 {
            XCTAssertEqual(rentRow.amounts[month], 120_000, "Rent month \(month + 1)")
        }
        XCTAssertEqual(rentRow.total, 1_440_000, "Annual rent = 120k * 12")

        guard let suppliesRow = findRow(rows, id: "expense-acct-supplies") else { return }
        let suppliesMonths: Set<Int> = [0, 2, 5, 8, 11] // Jan, Mar, Jun, Sep, Dec (0-indexed)
        for month in 0..<12 {
            if suppliesMonths.contains(month) {
                XCTAssertEqual(suppliesRow.amounts[month], 30_000, "Supplies month \(month + 1)")
            } else {
                XCTAssertEqual(suppliesRow.amounts[month], 0, "Supplies month \(month + 1) should be 0")
            }
        }
        XCTAssertEqual(suppliesRow.total, 150_000, "Annual supplies = 30k * 5")

        guard let expenseTotal = findRow(rows, id: "expense-total") else { return }
        XCTAssertEqual(expenseTotal.total, 1_590_000, "Annual expenses = rent 1,440k + supplies 150k")
        XCTAssertTrue(expenseTotal.isSubtotal)

        // --- Row Order Validation (NTA structure) ---
        let ids = rows.map(\.id)
        let salesCashIdx = ids.firstIndex(of: "sales-cash")!
        let salesCreditIdx = ids.firstIndex(of: "sales-credit")!
        let salesTotalIdx = ids.firstIndex(of: "sales-total")!
        let otherIncomeIdx = ids.firstIndex(of: "other-income")!
        let purchasesCashIdx = ids.firstIndex(of: "purchases-cash")!
        let purchasesTotalIdx = ids.firstIndex(of: "purchases-total")!
        let expenseTotalIdx = ids.firstIndex(of: "expense-total")!

        XCTAssertLessThan(salesCashIdx, salesCreditIdx, "cash sales before credit sales")
        XCTAssertLessThan(salesCreditIdx, salesTotalIdx, "credit sales before sales total")
        XCTAssertLessThan(salesTotalIdx, otherIncomeIdx, "sales total before other income")
        XCTAssertLessThan(otherIncomeIdx, purchasesCashIdx, "other income before purchases")
        XCTAssertLessThan(purchasesCashIdx, purchasesTotalIdx, "purchases cash before purchases total")
        XCTAssertLessThan(purchasesTotalIdx, expenseTotalIdx, "purchases total before expense total")
    }

    // MARK: - 15. Other Sales Category

    func testMonthlySummary_OtherSales() {
        // Dr bank (not cash, not ar) / Cr sales — should classify as "other sales"
        dataStore.addManualJournalEntry(
            date: date(2025, 8, 10),
            memo: "銀行振込売上",
            lines: [
                (accountId: "acct-bank", debit: 60_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 60_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        // sales-other should appear since counter-account is neither cash nor ar
        guard let otherSalesRow = findRow(rows, id: "sales-other") else { return }
        XCTAssertEqual(otherSalesRow.amounts[7], 60_000, "August other sales should be 60,000")
        XCTAssertEqual(otherSalesRow.label, "  その他売上")

        // sales-cash and sales-credit should be zero
        guard let cashSalesRow = findRow(rows, id: "sales-cash") else { return }
        XCTAssertEqual(cashSalesRow.total, 0)

        guard let creditSalesRow = findRow(rows, id: "sales-credit") else { return }
        XCTAssertEqual(creditSalesRow.total, 0)

        // sales-total should still reflect the other sales
        guard let salesTotal = findRow(rows, id: "sales-total") else { return }
        XCTAssertEqual(salesTotal.amounts[7], 60_000)
        XCTAssertEqual(salesTotal.total, 60_000)
    }

    // MARK: - 16. Multiple Entries Same Month Accumulate

    func testMonthlySummary_MultipleEntriesSameMonth() {
        // Two cash sales in January
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 5),
            memo: "売上1",
            lines: [
                (accountId: "acct-cash", debit: 40_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 40_000, memo: ""),
            ]
        )
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 20),
            memo: "売上2",
            lines: [
                (accountId: "acct-cash", debit: 60_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 60_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let cashSalesRow = findRow(rows, id: "sales-cash") else { return }
        XCTAssertEqual(cashSalesRow.amounts[0], 100_000, "January cash sales should accumulate to 100,000")
        XCTAssertEqual(cashSalesRow.total, 100_000)
    }

    // MARK: - 17. Unposted Entries Excluded

    func testMonthlySummary_UnpostedEntriesExcluded() {
        // Create an unbalanced (unposted) entry
        let entry = dataStore.addManualJournalEntry(
            date: date(2025, 4, 1),
            memo: "不均衡仕訳",
            lines: [
                (accountId: "acct-cash", debit: 50_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 30_000, memo: ""),
            ]
        )
        XCTAssertNotNil(entry)
        XCTAssertFalse(entry?.isPosted ?? true, "Unbalanced entry should not be posted")

        let rows = dataStore.getMonthlySummary(year: 2025)

        // Since the only entry is unposted, all amounts should be zero
        for row in rows {
            XCTAssertEqual(row.total, 0, "Row '\(row.id)' total should be zero when only unposted entries exist")
            XCTAssertTrue(row.amounts.allSatisfy { $0 == 0 }, "Row '\(row.id)' monthly amounts should all be zero")
        }
    }

    // MARK: - 18. Purchases Total Combines Cash and Credit

    func testMonthlySummary_PurchasesTotal() {
        // Cash purchase 50k in April
        dataStore.addManualJournalEntry(
            date: date(2025, 4, 5),
            memo: "現金仕入",
            lines: [
                (accountId: "acct-purchases", debit: 50_000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 50_000, memo: ""),
            ]
        )

        // Credit purchase 30k in April
        dataStore.addManualJournalEntry(
            date: date(2025, 4, 15),
            memo: "掛仕入",
            lines: [
                (accountId: "acct-purchases", debit: 30_000, credit: 0, memo: ""),
                (accountId: "acct-ap", debit: 0, credit: 30_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        guard let purchasesTotal = findRow(rows, id: "purchases-total") else { return }
        XCTAssertEqual(purchasesTotal.amounts[3], 80_000, "April purchases total = 50k + 30k")
        XCTAssertEqual(purchasesTotal.total, 80_000)
        XCTAssertTrue(purchasesTotal.isSubtotal)
    }

    // MARK: - 19. Multiple Expense Types

    func testMonthlySummary_MultipleExpenseTypes() {
        // Rent 80k in January
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 5),
            memo: "家賃",
            lines: [
                (accountId: "acct-rent", debit: 80_000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 80_000, memo: ""),
            ]
        )

        // Travel 15k in January
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 10),
            memo: "交通費",
            lines: [
                (accountId: "acct-travel", debit: 15_000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 15_000, memo: ""),
            ]
        )

        // Supplies 10k in January
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 15),
            memo: "消耗品",
            lines: [
                (accountId: "acct-supplies", debit: 10_000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 10_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        // Each expense account should have its own row
        guard let rentRow = findRow(rows, id: "expense-acct-rent") else { return }
        XCTAssertEqual(rentRow.amounts[0], 80_000)

        guard let travelRow = findRow(rows, id: "expense-acct-travel") else { return }
        XCTAssertEqual(travelRow.amounts[0], 15_000)

        guard let suppliesRow = findRow(rows, id: "expense-acct-supplies") else { return }
        XCTAssertEqual(suppliesRow.amounts[0], 10_000)

        // Expense total should be the sum
        guard let expenseTotal = findRow(rows, id: "expense-total") else { return }
        XCTAssertEqual(expenseTotal.amounts[0], 105_000, "January expense total = 80k + 15k + 10k")
        XCTAssertEqual(expenseTotal.total, 105_000)
    }

    // MARK: - 20. Row Order Matches NTA Structure

    func testMonthlySummary_RowOrder() {
        // Create entries that populate all major row groups
        // Cash sale
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 1),
            memo: "現金売上",
            lines: [
                (accountId: "acct-cash", debit: 10_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 10_000, memo: ""),
            ]
        )
        // Credit sale
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 2),
            memo: "掛売上",
            lines: [
                (accountId: "acct-ar", debit: 5_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 5_000, memo: ""),
            ]
        )
        // Other income
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 3),
            memo: "雑収入",
            lines: [
                (accountId: "acct-cash", debit: 1_000, credit: 0, memo: ""),
                (accountId: "acct-other-income", debit: 0, credit: 1_000, memo: ""),
            ]
        )
        // Cash purchase
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 4),
            memo: "現金仕入",
            lines: [
                (accountId: "acct-purchases", debit: 3_000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 3_000, memo: ""),
            ]
        )
        // Expense (rent)
        dataStore.addManualJournalEntry(
            date: date(2025, 1, 5),
            memo: "家賃",
            lines: [
                (accountId: "acct-rent", debit: 2_000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 2_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)
        let ids = rows.map(\.id)

        // Expected order: sales-cash, sales-credit, sales-total, other-income,
        //                 purchases-cash, purchases-credit, purchases-total,
        //                 expense-acct-rent, expense-total
        let expectedOrder = [
            "sales-cash",
            "sales-credit",
            "sales-total",
            "other-income",
            "purchases-cash",
            "purchases-credit",
            "purchases-total",
            "expense-acct-rent",
            "expense-total",
        ]

        // Verify all expected rows exist and are in order
        var lastIndex = -1
        for expectedId in expectedOrder {
            guard let index = ids.firstIndex(of: expectedId) else {
                XCTFail("Expected row '\(expectedId)' not found")
                continue
            }
            XCTAssertGreaterThan(index, lastIndex, "'\(expectedId)' should come after previous row")
            lastIndex = index
        }
    }

    // MARK: - 21. Amounts Array Always Has 12 Elements

    func testMonthlySummary_AmountsArraySize() {
        dataStore.addManualJournalEntry(
            date: date(2025, 6, 15),
            memo: "テスト",
            lines: [
                (accountId: "acct-cash", debit: 10_000, credit: 0, memo: ""),
                (accountId: "acct-sales", debit: 0, credit: 10_000, memo: ""),
            ]
        )

        let rows = dataStore.getMonthlySummary(year: 2025)

        for row in rows {
            XCTAssertEqual(row.amounts.count, 12, "Row '\(row.id)' should have exactly 12 elements in amounts array")
        }
    }
}
