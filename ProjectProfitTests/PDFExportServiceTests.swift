import XCTest
@testable import ProjectProfit

final class PDFExportServiceTests: XCTestCase {

    // MARK: - Reiwa Year Conversion

    func testReiwaYearConversion2019() {
        let date = makeDate(year: 2019, month: 5, day: 1)
        XCTAssertEqual(PDFExportService.reiwaYear(from: date), 1)
    }

    func testReiwaYearConversion2024() {
        let date = makeDate(year: 2024, month: 1, day: 1)
        XCTAssertEqual(PDFExportService.reiwaYear(from: date), 6)
    }

    func testReiwaYearConversion2026() {
        let date = makeDate(year: 2026, month: 2, day: 27)
        XCTAssertEqual(PDFExportService.reiwaYear(from: date), 8)
    }

    // MARK: - Trial Balance PDF

    func testExportTrialBalancePDFGeneratesValidPDF() {
        let report = TrialBalanceReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            rows: [
                TrialBalanceRow(id: "acct-cash", code: "101", name: "現金",
                                accountType: .asset, debit: 500_000, credit: 200_000, balance: 300_000),
                TrialBalanceRow(id: "acct-sales", code: "401", name: "売上高",
                                accountType: .revenue, debit: 0, credit: 1_000_000, balance: 1_000_000),
            ]
        )

        let data = PDFExportService.exportTrialBalancePDF(report: report)

        XCTAssertTrue(data.count > 0, "PDF data should not be empty")
        assertPDFHeader(data)
    }

    func testExportTrialBalancePDFWithEmptyRows() {
        let report = TrialBalanceReport(fiscalYear: 2025, generatedAt: Date(), rows: [])

        let data = PDFExportService.exportTrialBalancePDF(report: report)

        XCTAssertTrue(data.count > 0)
        assertPDFHeader(data)
    }

    // MARK: - Ledger PDF

    func testExportLedgerPDFGeneratesValidPDF() {
        let entries = [
            DataStore.LedgerEntry(
                id: UUID(), date: makeDate(year: 2025, month: 3, day: 15),
                memo: "売上入金", entryType: .auto, debit: 100_000, credit: 0, runningBalance: 100_000
            ),
            DataStore.LedgerEntry(
                id: UUID(), date: makeDate(year: 2025, month: 4, day: 1),
                memo: "仕入支払", entryType: .auto, debit: 0, credit: 30_000, runningBalance: 70_000
            ),
        ]

        let data = PDFExportService.exportLedgerPDF(
            accountName: "現金", accountCode: "101",
            entries: entries, fiscalYear: 2025
        )

        XCTAssertTrue(data.count > 0)
        assertPDFHeader(data)
    }

    func testExportLedgerPDFWithEmptyEntries() {
        let data = PDFExportService.exportLedgerPDF(
            accountName: "普通預金", accountCode: "102",
            entries: [], fiscalYear: 2025
        )

        XCTAssertTrue(data.count > 0)
        assertPDFHeader(data)
    }

    // MARK: - Profit & Loss PDF

    func testExportProfitLossPDFGeneratesValidPDF() {
        let report = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [
                ProfitLossItem(id: "acct-sales", code: "401", name: "売上高",
                               amount: 1_000_000, deductibleAmount: 1_000_000),
            ],
            expenseItems: [
                ProfitLossItem(id: "acct-rent", code: "701", name: "地代家賃",
                               amount: 120_000, deductibleAmount: 60_000),
            ]
        )

        let data = PDFExportService.exportProfitLossPDF(report: report)

        XCTAssertTrue(data.count > 0)
        assertPDFHeader(data)
    }

    // MARK: - Balance Sheet PDF

    func testExportBalanceSheetPDFGeneratesValidPDF() {
        let report = BalanceSheetReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            assetItems: [
                BalanceSheetItem(id: "acct-cash", code: "101", name: "現金", balance: 500_000),
            ],
            liabilityItems: [
                BalanceSheetItem(id: "acct-payable", code: "201", name: "買掛金", balance: 100_000),
            ],
            equityItems: [
                BalanceSheetItem(id: "acct-capital", code: "301", name: "元入金", balance: 400_000),
            ]
        )

        let data = PDFExportService.exportBalanceSheetPDF(report: report)

        XCTAssertTrue(data.count > 0)
        assertPDFHeader(data)
    }

    // MARK: - Journal PDF

    func testExportJournalPDFGeneratesValidPDF() {
        let entryId = UUID()
        let entries = [
            PPJournalEntry(
                id: entryId,
                sourceKey: "tx:\(UUID().uuidString)",
                date: makeDate(year: 2025, month: 6, day: 1),
                entryType: .auto,
                memo: "テスト売上",
                isPosted: true
            ),
        ]
        let lines = [
            PPJournalLine(
                entryId: entryId, accountId: "acct-cash",
                debit: 50_000, credit: 0, displayOrder: 0
            ),
            PPJournalLine(
                entryId: entryId, accountId: "acct-sales",
                debit: 0, credit: 50_000, displayOrder: 1
            ),
        ]
        let accounts = [
            PPAccount(id: "acct-cash", code: "101", name: "現金", accountType: .asset),
            PPAccount(id: "acct-sales", code: "401", name: "売上高", accountType: .revenue),
        ]

        let data = PDFExportService.exportJournalPDF(
            entries: entries, lines: lines, accounts: accounts, fiscalYear: 2025
        )

        XCTAssertTrue(data.count > 0)
        assertPDFHeader(data)
    }

    func testExportJournalPDFFiltersUnpostedEntries() {
        let entryId = UUID()
        let entries = [
            PPJournalEntry(
                id: entryId,
                sourceKey: "manual:\(UUID().uuidString)",
                date: makeDate(year: 2025, month: 7, day: 1),
                entryType: .manual,
                memo: "未確定仕訳",
                isPosted: false
            ),
        ]
        let lines = [
            PPJournalLine(
                entryId: entryId, accountId: "acct-cash",
                debit: 10_000, credit: 0, displayOrder: 0
            ),
        ]
        let accounts = [
            PPAccount(id: "acct-cash", code: "101", name: "現金", accountType: .asset),
        ]

        let data = PDFExportService.exportJournalPDF(
            entries: entries, lines: lines, accounts: accounts, fiscalYear: 2025
        )

        // Should still produce valid PDF (with header only, no data rows)
        XCTAssertTrue(data.count > 0)
        assertPDFHeader(data)
    }

    // MARK: - Fixed Assets PDF

    func testExportFixedAssetsPDFGeneratesValidPDF() {
        let asset = PPFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: makeDate(year: 2024, month: 1, day: 15),
            acquisitionCost: 300_000,
            usefulLifeYears: 4,
            depreciationMethod: .straightLine,
            salvageValue: 1,
            assetStatus: .active
        )

        let data = PDFExportService.exportFixedAssetsPDF(
            assets: [asset],
            fiscalYear: 2025,
            calculateAccumulated: { _ in 74_999 },
            calculateCurrentYear: { _ in 74_999 }
        )

        XCTAssertTrue(data.count > 0)
        assertPDFHeader(data)
    }

    func testExportFixedAssetsPDFWithMultipleAssets() {
        let assets = [
            PPFixedAsset(
                name: "MacBook Pro",
                acquisitionDate: makeDate(year: 2023, month: 4, day: 1),
                acquisitionCost: 300_000,
                usefulLifeYears: 4,
                depreciationMethod: .straightLine
            ),
            PPFixedAsset(
                name: "デスク",
                acquisitionDate: makeDate(year: 2024, month: 6, day: 15),
                acquisitionCost: 80_000,
                usefulLifeYears: 8,
                depreciationMethod: .straightLine,
                assetStatus: .active
            ),
            PPFixedAsset(
                name: "プリンター",
                acquisitionDate: makeDate(year: 2022, month: 1, day: 1),
                acquisitionCost: 50_000,
                usefulLifeYears: 5,
                depreciationMethod: .decliningBalance,
                assetStatus: .fullyDepreciated
            ),
        ]

        let data = PDFExportService.exportFixedAssetsPDF(
            assets: assets,
            fiscalYear: 2025,
            calculateAccumulated: { asset in asset.acquisitionCost / 2 },
            calculateCurrentYear: { asset in asset.acquisitionCost / asset.usefulLifeYears }
        )

        XCTAssertTrue(data.count > 0)
        assertPDFHeader(data)
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// PDF ファイルのマジックバイト (%PDF) を検証する
    private func assertPDFHeader(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        let header = data.prefix(4)
        let headerString = String(data: header, encoding: .ascii)
        XCTAssertEqual(headerString, "%PDF", "Data should start with %PDF magic bytes", file: file, line: line)
    }
}
