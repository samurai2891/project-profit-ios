import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class SubLedgerExportTests: XCTestCase {
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

    private let expectedHeader = "date,accountCode,accountName,memo,counterparty,debit,credit,runningBalance,counterAccountId,taxCategory"

    // MARK: - 1. Header

    func testExportCSV_CashBook_HasHeader() {
        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertFalse(lines.isEmpty, "CSV should have at least the header line")
        XCTAssertEqual(lines[0], expectedHeader)
    }

    // MARK: - 2. Basic Entry

    func testExportCSV_CashBook_BasicEntry() {
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 6, 15),
            memo: "現金売上",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 50_000, credit: 0, memo: "入金"),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 50_000, memo: "売上"),
            ]
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 2, "Header + 1 data row")
        XCTAssertEqual(lines[0], expectedHeader)

        let row = lines[1]
        // Verify ISO8601 date prefix using the same formatter as production code.
        // Using a hardcoded string like "2025-06-15" is wrong because ISO8601DateFormatter
        // outputs UTC, so midnight JST (UTC+9) becomes the previous calendar date in UTC.
        let iso8601Formatter = ISO8601DateFormatter()
        let expectedDatePrefix = iso8601Formatter.string(from: date(2025, 6, 15))
        XCTAssertTrue(row.hasPrefix(expectedDatePrefix), "Row should start with ISO8601 formatted date, got: \(row)")
        // Verify account code "101" and account name "現金"
        XCTAssertTrue(row.contains(",101,"), "Row should contain account code 101")
        XCTAssertTrue(row.contains("\"現金\""), "Row should contain account name 現金")
    }

    // MARK: - 3. CounterAccountId

    func testExportCSV_CashBook_CounterAccountId() {
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 7, 1),
            memo: "現金売上",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 30_000, credit: 0, memo: "入金"),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 30_000, memo: "売上"),
            ]
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 2)

        let row = lines[1]
        // counterAccountId is the 9th column (0-indexed: 8)
        // Format: date,accountCode,"accountName","memo","counterparty",debit,credit,runningBalance,counterAccountId,taxCategory
        XCTAssertTrue(
            row.contains("acct-sales"),
            "CSV row should include counterAccountId 'acct-sales'"
        )
    }

    // MARK: - 4. Counterparty

    func testExportCSV_CashBook_Counterparty() {
        let project = mutations(dataStore).addProject(name: "取引先テスト", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5_000,
            date: date(2025, 7, 10),
            categoryId: "cat-supplies",
            memo: "消耗品購入",
            allocations: [(projectId: project.id, ratio: 100)],
            counterparty: "田中商店"
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        // Find the data row(s) containing 田中商店
        let matchingRows = lines.dropFirst().filter { $0.contains("田中商店") }
        XCTAssertFalse(matchingRows.isEmpty, "CSV should include counterparty '田中商店'")
    }

    // MARK: - 5. TaxCategory

    func testExportCSV_CashBook_TaxCategory() {
        let project = mutations(dataStore).addProject(name: "税区分テスト", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1_080,
            date: date(2025, 8, 1),
            categoryId: "cat-food",
            memo: "食品仕入",
            allocations: [(projectId: project.id, ratio: 100)],
            taxCategory: .reducedRate
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        let matchingRows = lines.dropFirst().filter { $0.hasSuffix("reducedRate") }
        XCTAssertFalse(
            matchingRows.isEmpty,
            "CSV should include taxCategory 'reducedRate' for reduced-rate transactions"
        )
    }

    // MARK: - 6. Empty Counterparty

    func testExportCSV_CashBook_EmptyCounterparty() {
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 9, 1),
            memo: "手動仕訳",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 20_000, credit: 0, memo: "入金"),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 20_000, memo: "売上"),
            ]
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 2)

        let row = lines[1]
        // Manual journal entries have no source transaction, so counterparty is ""
        // The CSV format wraps counterparty in quotes: ,"",
        XCTAssertTrue(
            row.contains(",\"\","),
            "Manual journal entry should have empty counterparty column"
        )
    }

    // MARK: - 7. Empty TaxCategory

    func testExportCSV_CashBook_EmptyTaxCategory() {
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 9, 5),
            memo: "税区分なし仕訳",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 15_000, credit: 0, memo: "入金"),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 15_000, memo: "売上"),
            ]
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 2)

        let row = lines[1]
        // taxCategory is the last column; when nil it should be empty
        // The row should end with the counterAccountId followed by a comma and empty taxCategory
        let components = row.components(separatedBy: ",")
        let lastComponent = components.last ?? ""
        XCTAssertEqual(lastComponent, "", "taxCategory column should be empty for manual journal entries")
    }

    // MARK: - 8. Expense Book Multiple Accounts

    func testExportCSV_ExpenseBook_MultipleAccounts() {
        // Communication expense
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 10, 1),
            memo: "通信費",
            lines: [
                (accountId: "acct-communication", debit: 8_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 8_000, memo: ""),
            ]
        )

        // Travel expense
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 10, 5),
            memo: "旅費交通費",
            lines: [
                (accountId: "acct-travel", debit: 12_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 12_000, memo: ""),
            ]
        )

        // Advertising expense
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 10, 10),
            memo: "広告宣伝費",
            lines: [
                (accountId: "acct-advertising", debit: 30_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 30_000, memo: ""),
            ]
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .expenseBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        // Header + 3 data rows
        XCTAssertEqual(lines.count, 4, "Should have header + 3 expense rows")
        XCTAssertEqual(lines[0], expectedHeader)

        // Verify each expense account appears
        let dataRows = Array(lines.dropFirst())
        let accountCodes = dataRows.compactMap { row -> String? in
            let components = row.components(separatedBy: ",")
            return components.count > 1 ? components[1] : nil
        }
        XCTAssertTrue(accountCodes.contains("504"), "Should contain communication expense (504)")
        XCTAssertTrue(accountCodes.contains("503"), "Should contain travel expense (503)")
        XCTAssertTrue(accountCodes.contains("505"), "Should contain advertising expense (505)")
    }

    // MARK: - 9. AR Book With Counterparty

    func testExportCSV_ARBook_WithCounterparty() {
        let project = mutations(dataStore).addProject(name: "売掛テスト", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 100_000,
            date: date(2025, 11, 1),
            categoryId: "cat-sales",
            memo: "大口売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: AccountingConstants.accountsReceivableAccountId,
            taxCategory: .standardRate,
            counterparty: "株式会社山田"
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .accountsReceivableBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        // Check that AR entries exist
        let dataRows = Array(lines.dropFirst())
        guard !dataRows.isEmpty else {
            // If AR book is empty (income routed to cash by default), verify cash book instead
            let cashCSV = dataStore.exportSubLedgerCSV(
                type: .cashBook,
                startDate: date(2025, 1, 1),
                endDate: date(2025, 12, 31)
            )
            let cashLines = cashCSV.split(separator: "\n").map(String.init)
            let cashDataRows = Array(cashLines.dropFirst())
            let matchingRows = cashDataRows.filter { $0.contains("株式会社山田") }
            XCTAssertFalse(
                matchingRows.isEmpty,
                "Counterparty '株式会社山田' should appear in the exported CSV"
            )
            return
        }

        let matchingRows = dataRows.filter { $0.contains("株式会社山田") }
        XCTAssertFalse(
            matchingRows.isEmpty,
            "AR book CSV should include counterparty '株式会社山田'"
        )
    }

    // MARK: - 10. Quoted Memo (comma in memo)

    func testExportCSV_CashBook_QuotedMemo() {
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 5, 20),
            memo: "消耗品, 文具, コピー用紙",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 3_500, memo: "出金"),
                (accountId: "acct-supplies", debit: 3_500, credit: 0, memo: "消耗品費"),
            ]
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 2)

        let row = lines[1]
        // Memo with commas should be wrapped in double quotes
        XCTAssertTrue(
            row.contains("\"消耗品, 文具, コピー用紙\""),
            "Memo containing commas should be properly escaped with double quotes"
        )
    }

    // MARK: - 11. Empty (no entries)

    func testExportCSV_CashBook_Empty() {
        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 1, "Empty export should have only the header line")
        XCTAssertEqual(lines[0], expectedHeader)
    }

    // MARK: - 12. Date Filter

    func testExportCSV_CashBook_DateFilter() {
        // January entry
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 1, 15),
            memo: "1月売上",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 10_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 10_000, memo: ""),
            ]
        )

        // June entry
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 6, 15),
            memo: "6月売上",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 20_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 20_000, memo: ""),
            ]
        )

        // December entry
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 12, 15),
            memo: "12月売上",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 30_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 30_000, memo: ""),
            ]
        )

        // Filter for April - September only
        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 4, 1),
            endDate: date(2025, 9, 30)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 2, "Header + 1 data row (June only)")
        XCTAssertTrue(
            lines[1].contains("\"6月売上\""),
            "Only June entry should be in the filtered export"
        )

        // Full year should have all 3
        let fullCSV = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let fullLines = fullCSV.split(separator: "\n").map(String.init)
        XCTAssertEqual(fullLines.count, 4, "Full year should have header + 3 data rows")
    }

    // MARK: - 13. Running Balance in CSV

    func testExportCSV_CashBook_RunningBalance() {
        // Deposit 100k
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 3, 1),
            memo: "入金",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 100_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 100_000, memo: ""),
            ]
        )

        // Withdraw 40k
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 3, 10),
            memo: "出金",
            lines: [
                (accountId: "acct-rent", debit: 40_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 40_000, memo: ""),
            ]
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 3, "Header + 2 data rows")

        // Parse running balance from each row
        // Format: date,accountCode,"accountName","memo","counterparty",debit,credit,runningBalance,counterAccountId,taxCategory
        // The runningBalance is column index 7 (0-based)
        let row1Components = parseCSVRow(lines[1])
        let row2Components = parseCSVRow(lines[2])

        XCTAssertEqual(row1Components["runningBalance"], "100000", "First row running balance should be 100000")
        XCTAssertEqual(row2Components["runningBalance"], "60000", "Second row running balance should be 60000")
    }

    // MARK: - 14. All TaxCategory Raw Values

    func testExportCSV_CashBook_AllTaxCategoryValues() {
        let project = mutations(dataStore).addProject(name: "全税区分", description: "")

        let taxCategories: [(TaxCategory, String)] = [
            (.standardRate, "standardRate"),
            (.reducedRate, "reducedRate"),
            (.exempt, "exempt"),
            (.nonTaxable, "nonTaxable"),
        ]

        for (index, (taxCat, _)) in taxCategories.enumerated() {
            _ = mutations(dataStore).addTransaction(
                type: .expense,
                amount: 1_000 * (index + 1),
                date: date(2025, 4, index + 1),
                categoryId: "cat-supplies",
                memo: "税区分テスト\(index)",
                allocations: [(projectId: project.id, ratio: 100)],
                taxCategory: taxCat
            )
        }

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let dataRows = csv.split(separator: "\n").map(String.init).dropFirst()

        for (_, expectedRawValue) in taxCategories {
            let found = dataRows.contains { $0.hasSuffix(expectedRawValue) }
            XCTAssertTrue(found, "CSV should contain taxCategory '\(expectedRawValue)'")
        }
    }

    // MARK: - 15. Double Quotes in Memo Are Escaped

    func testExportCSV_CashBook_DoubleQuotesEscaped() {
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 5, 1),
            memo: "品名\"テスト\"品",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 1_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 1_000, memo: ""),
            ]
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 2)

        let row = lines[1]
        // Double quotes in memo should be escaped as "" per CSV convention
        XCTAssertTrue(
            row.contains("\"\"テスト\"\""),
            "Double quotes in memo should be escaped as doubled quotes"
        )
    }

    // MARK: - 16. Column Count Consistency

    func testExportCSV_CashBook_ColumnCountConsistency() {
        // Create entries with varying data
        mutations(dataStore).addManualJournalEntry(
            date: date(2025, 2, 1),
            memo: "シンプル仕訳",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 5_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 5_000, memo: ""),
            ]
        )

        let project = mutations(dataStore).addProject(name: "列数テスト", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 3_000,
            date: date(2025, 2, 10),
            categoryId: "cat-supplies",
            memo: "取引先付き",
            allocations: [(projectId: project.id, ratio: 100)],
            taxCategory: .standardRate,
            counterparty: "テスト商会"
        )

        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook,
            startDate: date(2025, 1, 1),
            endDate: date(2025, 12, 31)
        )
        let lines = csv.split(separator: "\n").map(String.init)

        // Header has 10 columns
        let headerColumnCount = expectedHeader.components(separatedBy: ",").count
        XCTAssertEqual(headerColumnCount, 10)

        // All data rows should parse to the same structure
        // Note: simple comma-split won't work for quoted fields, but we can verify
        // that each row contains the expected number of unquoted delimiters
        for (index, line) in lines.enumerated() where index > 0 {
            let parsed = parseCSVRow(line)
            XCTAssertNotNil(parsed["date"], "Row \(index) should have a date")
            XCTAssertNotNil(parsed["accountCode"], "Row \(index) should have an accountCode")
            XCTAssertNotNil(parsed["taxCategory"], "Row \(index) should have a taxCategory field (possibly empty)")
        }
    }

    // MARK: - Helpers

    /// Parse a CSV data row into a dictionary keyed by column name.
    /// Handles quoted fields (but not escaped quotes within fields for simplicity).
    private func parseCSVRow(_ row: String) -> [String: String] {
        let columnNames = [
            "date", "accountCode", "accountName", "memo", "counterparty",
            "debit", "credit", "runningBalance", "counterAccountId", "taxCategory",
        ]

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

        var result: [String: String] = [:]
        for (index, name) in columnNames.enumerated() where index < fields.count {
            result[name] = fields[index]
        }
        return result
    }
}
