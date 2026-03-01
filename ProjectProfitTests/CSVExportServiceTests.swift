import XCTest
@testable import ProjectProfit

final class ReportCSVExportServiceTests: XCTestCase {

    // MARK: - Helpers

    private let calendar = Calendar.current

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: components)!
    }

    // MARK: - BOM Prefix

    func testCSVHasBOMPrefix() {
        let csv = ReportCSVExportService.buildCSV(headers: ["A"], rows: [["1"]])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"), "CSV should start with BOM prefix")
    }

    func testCSVHasBOMPrefixEmptyRows() {
        let csv = ReportCSVExportService.buildCSV(headers: ["A", "B"], rows: [])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"), "CSV with empty rows should still have BOM prefix")
    }

    // MARK: - escapeField

    func testEscapeFieldPlainText() {
        let result = ReportCSVExportService.escapeField("hello")
        XCTAssertEqual(result, "hello")
    }

    func testEscapeFieldWithComma() {
        let result = ReportCSVExportService.escapeField("hello,world")
        XCTAssertEqual(result, "\"hello,world\"")
    }

    func testEscapeFieldWithQuotes() {
        let result = ReportCSVExportService.escapeField("say \"hello\"")
        XCTAssertEqual(result, "\"say \"\"hello\"\"\"")
    }

    func testEscapeFieldWithNewline() {
        let result = ReportCSVExportService.escapeField("line1\nline2")
        XCTAssertEqual(result, "\"line1\nline2\"")
    }

    func testEscapeFieldWithCarriageReturn() {
        let result = ReportCSVExportService.escapeField("line1\rline2")
        XCTAssertEqual(result, "\"line1\rline2\"")
    }

    func testEscapeFieldWithCommaAndQuotes() {
        let result = ReportCSVExportService.escapeField("a,\"b\"")
        XCTAssertEqual(result, "\"a,\"\"b\"\"\"")
    }

    func testEscapeFieldEmptyString() {
        let result = ReportCSVExportService.escapeField("")
        XCTAssertEqual(result, "")
    }

    // MARK: - buildCSV

    func testBuildCSVStructure() {
        let csv = ReportCSVExportService.buildCSV(
            headers: ["Name", "Amount"],
            rows: [["Item1", "100"], ["Item2", "200"]]
        )
        // Remove BOM for comparison
        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Name,Amount")
        XCTAssertEqual(lines[1], "Item1,100")
        XCTAssertEqual(lines[2], "Item2,200")
    }

    func testBuildCSVUsesWindowsLineEndings() {
        let csv = ReportCSVExportService.buildCSV(
            headers: ["A"],
            rows: [["1"], ["2"]]
        )
        let content = String(csv.dropFirst())
        XCTAssertTrue(content.contains("\r\n"), "CSV should use CRLF line endings")
    }

    // MARK: - Trial Balance CSV

    func testExportTrialBalanceCSV() {
        let rows = [
            TrialBalanceRow(
                id: "acct-cash",
                code: "101",
                name: "現金",
                accountType: .asset,
                debit: 50000,
                credit: 0,
                balance: 50000
            ),
            TrialBalanceRow(
                id: "acct-sales",
                code: "401",
                name: "売上高",
                accountType: .revenue,
                debit: 0,
                credit: 80000,
                balance: -80000
            ),
        ]

        let csv = ReportCSVExportService.exportTrialBalanceCSV(rows: rows)

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))

        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        XCTAssertEqual(lines.count, 3, "Header + 2 data rows")
        XCTAssertEqual(lines[0], "勘定科目コード,勘定科目名,借方残高,貸方残高")
        XCTAssertEqual(lines[1], "101,現金,50000,0")
        XCTAssertEqual(lines[2], "401,売上高,0,80000")
    }

    // MARK: - Ledger CSV

    func testExportLedgerCSV() {
        let entries = [
            DataStore.LedgerEntry(
                id: UUID(),
                date: makeDate(year: 2026, month: 1, day: 15),
                memo: "商品売上",
                entryType: .auto,
                debit: 10000,
                credit: 0,
                runningBalance: 10000
            ),
            DataStore.LedgerEntry(
                id: UUID(),
                date: makeDate(year: 2026, month: 2, day: 1),
                memo: "仕入代金支払",
                entryType: .auto,
                debit: 0,
                credit: 3000,
                runningBalance: 7000
            ),
        ]

        let csv = ReportCSVExportService.exportLedgerCSV(
            accountName: "現金",
            accountCode: "101",
            entries: entries
        )

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))

        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "日付,摘要,借方,貸方,残高")
        XCTAssertEqual(lines[1], "2026-01-15,商品売上,10000,0,10000")
        XCTAssertEqual(lines[2], "2026-02-01,仕入代金支払,0,3000,7000")
    }

    // MARK: - Profit & Loss CSV

    func testExportProfitLossCSV() {
        let report = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [
                ProfitLossItem(id: "acct-sales", code: "401", name: "売上高", amount: 500000, deductibleAmount: 0),
            ],
            expenseItems: [
                ProfitLossItem(id: "acct-rent", code: "601", name: "地代家賃", amount: 120000, deductibleAmount: 120000),
                ProfitLossItem(id: "acct-comm", code: "602", name: "通信費", amount: 30000, deductibleAmount: 30000),
            ]
        )

        let csv = ReportCSVExportService.exportProfitLossCSV(report: report)

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))

        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        // Header + section headers + items + subtotals + net income
        // ["勘定科目コード,勘定科目名,金額",
        //  ",【売上】,",
        //  "401,売上高,500000",
        //  ",売上合計,500000",
        //  ",【費用】,",
        //  "601,地代家賃,120000",
        //  "602,通信費,30000",
        //  ",費用合計,150000",
        //  ",当期純利益,350000"]
        XCTAssertEqual(lines.count, 9)
        XCTAssertEqual(lines[0], "勘定科目コード,勘定科目名,金額")
        XCTAssertTrue(lines[1].contains("【売上】"))
        XCTAssertTrue(lines[2].contains("売上高"))
        XCTAssertTrue(lines[3].contains("500000"))
        XCTAssertTrue(lines[8].contains("350000"), "Net income should be 500000 - 150000 = 350000")
    }

    func testExportProfitLossCSVNetIncomeCalculation() {
        let report = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [
                ProfitLossItem(id: "r1", code: "401", name: "売上", amount: 100000, deductibleAmount: 0),
            ],
            expenseItems: [
                ProfitLossItem(id: "e1", code: "601", name: "経費", amount: 40000, deductibleAmount: 40000),
            ]
        )

        let csv = ReportCSVExportService.exportProfitLossCSV(report: report)
        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        let lastLine = lines.last ?? ""
        XCTAssertTrue(lastLine.contains("60000"), "Net income: 100000 - 40000 = 60000")
    }

    // MARK: - Balance Sheet CSV

    func testExportBalanceSheetCSV() {
        let report = BalanceSheetReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            assetItems: [
                BalanceSheetItem(id: "acct-cash", code: "101", name: "現金", balance: 200000),
            ],
            liabilityItems: [
                BalanceSheetItem(id: "acct-ap", code: "201", name: "買掛金", balance: 50000),
            ],
            equityItems: [
                BalanceSheetItem(id: "acct-capital", code: "301", name: "元入金", balance: 150000),
            ]
        )

        let csv = ReportCSVExportService.exportBalanceSheetCSV(report: report)

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))

        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        // Header + 3 sections with headers + 3 items + 3 subtotals = 1 + 3 + 3 + 3 = 10
        XCTAssertEqual(lines.count, 10)
        XCTAssertEqual(lines[0], "勘定科目コード,勘定科目名,金額")
        XCTAssertTrue(lines[1].contains("【資産】"))
        XCTAssertTrue(lines[2].contains("現金"))
        XCTAssertTrue(lines[3].contains("200000"))
        XCTAssertTrue(lines[4].contains("【負債】"))
        XCTAssertTrue(lines[7].contains("【純資産】"))
    }

    // MARK: - Journal CSV

    func testExportJournalCSV() {
        let entryId = UUID()
        let entries = [
            PPJournalEntry(
                id: entryId,
                sourceKey: "tx:test-001",
                date: makeDate(year: 2026, month: 3, day: 1),
                entryType: .auto,
                memo: "テスト取引",
                isPosted: true
            ),
        ]
        let lines = [
            PPJournalLine(
                id: UUID(),
                entryId: entryId,
                accountId: "acct-cash",
                debit: 10000,
                credit: 0,
                displayOrder: 0
            ),
            PPJournalLine(
                id: UUID(),
                entryId: entryId,
                accountId: "acct-sales",
                debit: 0,
                credit: 10000,
                displayOrder: 1
            ),
        ]
        let accounts = [
            PPAccount(id: "acct-cash", code: "101", name: "現金", accountType: .asset),
            PPAccount(id: "acct-sales", code: "401", name: "売上高", accountType: .revenue),
        ]

        let csv = ReportCSVExportService.exportJournalCSV(
            entries: entries,
            lines: lines,
            accounts: accounts
        )

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))

        let content = String(csv.dropFirst())
        let csvLines = content.components(separatedBy: "\r\n")

        XCTAssertEqual(csvLines.count, 3, "Header + 2 journal lines")
        XCTAssertEqual(csvLines[0], "日付,仕訳番号,勘定科目コード,勘定科目名,借方金額,貸方金額,摘要")
        XCTAssertTrue(csvLines[1].contains("2026-03-01"))
        XCTAssertTrue(csvLines[1].contains("101"))
        XCTAssertTrue(csvLines[1].contains("現金"))
        XCTAssertTrue(csvLines[1].contains("10000"))
        XCTAssertTrue(csvLines[2].contains("401"))
        XCTAssertTrue(csvLines[2].contains("売上高"))
    }

    func testExportJournalCSVWithMemoContainingComma() {
        let entryId = UUID()
        let entries = [
            PPJournalEntry(
                id: entryId,
                sourceKey: "manual:m1",
                date: makeDate(year: 2026, month: 1, day: 10),
                entryType: .manual,
                memo: "備品購入,振込手数料含む",
                isPosted: true
            ),
        ]
        let journalLines = [
            PPJournalLine(
                id: UUID(),
                entryId: entryId,
                accountId: "acct-supplies",
                debit: 5000,
                credit: 0,
                displayOrder: 0
            ),
        ]
        let accounts = [
            PPAccount(id: "acct-supplies", code: "501", name: "消耗品費", accountType: .expense),
        ]

        let csv = ReportCSVExportService.exportJournalCSV(
            entries: entries,
            lines: journalLines,
            accounts: accounts
        )

        let content = String(csv.dropFirst())
        let csvLines = content.components(separatedBy: "\r\n")

        // Memo with comma should be escaped with quotes
        XCTAssertTrue(
            csvLines[1].contains("\"備品購入,振込手数料含む\""),
            "Memo containing comma should be quoted"
        )
    }

    func testExportJournalCSVSortsByDate() {
        let entryId1 = UUID()
        let entryId2 = UUID()
        let entries = [
            PPJournalEntry(
                id: entryId2,
                sourceKey: "tx:002",
                date: makeDate(year: 2026, month: 3, day: 15),
                entryType: .auto,
                memo: "後の取引"
            ),
            PPJournalEntry(
                id: entryId1,
                sourceKey: "tx:001",
                date: makeDate(year: 2026, month: 1, day: 5),
                entryType: .auto,
                memo: "先の取引"
            ),
        ]
        let journalLines = [
            PPJournalLine(id: UUID(), entryId: entryId1, accountId: "acct-cash", debit: 1000, credit: 0),
            PPJournalLine(id: UUID(), entryId: entryId2, accountId: "acct-cash", debit: 2000, credit: 0),
        ]
        let accounts = [
            PPAccount(id: "acct-cash", code: "101", name: "現金", accountType: .asset),
        ]

        let csv = ReportCSVExportService.exportJournalCSV(
            entries: entries,
            lines: journalLines,
            accounts: accounts
        )

        let content = String(csv.dropFirst())
        let csvLines = content.components(separatedBy: "\r\n")

        XCTAssertTrue(csvLines[1].contains("2026-01-05"), "First data row should be the earlier date")
        XCTAssertTrue(csvLines[2].contains("2026-03-15"), "Second data row should be the later date")
    }

    // MARK: - Fixed Assets CSV

    func testExportFixedAssetsCSV() {
        let asset = PPFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: makeDate(year: 2025, month: 4, day: 1),
            acquisitionCost: 300000,
            usefulLifeYears: 4,
            depreciationMethod: .straightLine,
            salvageValue: 1
        )

        let csv = ReportCSVExportService.exportFixedAssetsCSV(
            assets: [asset],
            calculateAccumulated: { _ in 75000 },
            calculateCurrentYear: { _ in 75000 }
        )

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))

        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        XCTAssertEqual(lines.count, 2, "Header + 1 asset row")
        XCTAssertEqual(lines[0], "資産名,取得日,取得価額,耐用年数,償却方法,当期償却額,累計償却額,帳簿価額")

        let dataLine = lines[1]
        XCTAssertTrue(dataLine.contains("MacBook Pro"))
        XCTAssertTrue(dataLine.contains("2025-04-01"))
        XCTAssertTrue(dataLine.contains("300000"))
        XCTAssertTrue(dataLine.contains("4"))
        XCTAssertTrue(dataLine.contains("定額法"))
        XCTAssertTrue(dataLine.contains("75000"))
        // Book value = 300000 - 75000 = 225000
        XCTAssertTrue(dataLine.contains("225000"))
    }

    func testExportFixedAssetsCSVDecliningBalance() {
        let asset = PPFixedAsset(
            name: "サーバー機器",
            acquisitionDate: makeDate(year: 2024, month: 7, day: 1),
            acquisitionCost: 500000,
            usefulLifeYears: 5,
            depreciationMethod: .decliningBalance,
            salvageValue: 1
        )

        let csv = ReportCSVExportService.exportFixedAssetsCSV(
            assets: [asset],
            calculateAccumulated: { _ in 200000 },
            calculateCurrentYear: { _ in 120000 }
        )

        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        XCTAssertTrue(lines[1].contains("定率法"))
        // Book value = 500000 - 200000 = 300000
        XCTAssertTrue(lines[1].contains("300000"))
    }

    func testExportFixedAssetsCSVMultipleAssets() {
        let asset1 = PPFixedAsset(
            name: "デスク",
            acquisitionDate: makeDate(year: 2025, month: 1, day: 1),
            acquisitionCost: 100000,
            usefulLifeYears: 8,
            depreciationMethod: .straightLine
        )
        let asset2 = PPFixedAsset(
            name: "椅子",
            acquisitionDate: makeDate(year: 2025, month: 6, day: 1),
            acquisitionCost: 80000,
            usefulLifeYears: 8,
            depreciationMethod: .straightLine
        )

        let csv = ReportCSVExportService.exportFixedAssetsCSV(
            assets: [asset1, asset2],
            calculateAccumulated: { $0.name == "デスク" ? 12500 : 5000 },
            calculateCurrentYear: { $0.name == "デスク" ? 12500 : 5000 }
        )

        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        XCTAssertEqual(lines.count, 3, "Header + 2 asset rows")
        XCTAssertTrue(lines[1].contains("デスク"))
        XCTAssertTrue(lines[2].contains("椅子"))
    }

    // MARK: - Edge Cases

    func testExportTrialBalanceCSVEmpty() {
        let csv = ReportCSVExportService.exportTrialBalanceCSV(rows: [])

        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"))

        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        XCTAssertEqual(lines.count, 1, "Only header row when no data")
        XCTAssertEqual(lines[0], "勘定科目コード,勘定科目名,借方残高,貸方残高")
    }

    func testExportLedgerCSVEmpty() {
        let csv = ReportCSVExportService.exportLedgerCSV(
            accountName: "現金",
            accountCode: "101",
            entries: []
        )

        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        XCTAssertEqual(lines.count, 1, "Only header row when no entries")
    }

    func testExportFixedAssetsCSVEmpty() {
        let csv = ReportCSVExportService.exportFixedAssetsCSV(
            assets: [],
            calculateAccumulated: { _ in 0 },
            calculateCurrentYear: { _ in 0 }
        )

        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        XCTAssertEqual(lines.count, 1, "Only header row when no assets")
    }

    func testExportProfitLossCSVEmptyReport() {
        let report = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: []
        )

        let csv = ReportCSVExportService.exportProfitLossCSV(report: report)
        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        // Header + section headers + subtotals + net income (no data items)
        // header, 【売上】, 売上合計, 【費用】, 費用合計, 当期純利益 = 6
        XCTAssertEqual(lines.count, 6)
        XCTAssertTrue(lines.last?.contains("0") == true, "Net income should be 0")
    }

    func testExportBalanceSheetCSVEmptyReport() {
        let report = BalanceSheetReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            assetItems: [],
            liabilityItems: [],
            equityItems: []
        )

        let csv = ReportCSVExportService.exportBalanceSheetCSV(report: report)
        let content = String(csv.dropFirst())
        let lines = content.components(separatedBy: "\r\n")

        // Header + 3 section headers + 3 subtotals = 7
        XCTAssertEqual(lines.count, 7)
    }
}
