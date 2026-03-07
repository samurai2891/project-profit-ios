import XCTest
@testable import ProjectProfit

/// ExportCoordinator のファイル命名とラベル・拡張子の検証
@MainActor
final class ExportCoordinatorTests: XCTestCase {

    // MARK: - File Naming

    /// ファイル名が {target}_{fiscalYear}_{yyyyMMdd}.{ext} の形式であることを確認
    func testMakeFileName() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let expectedDate = formatter.string(from: Date())

        // CSV
        let csvFileName = ExportCoordinator.makeFileName(
            target: .profitLoss, fiscalYear: 2026, format: .csv
        )
        XCTAssertEqual(csvFileName, "profit_loss_2026_\(expectedDate).csv")

        // PDF
        let pdfFileName = ExportCoordinator.makeFileName(
            target: .balanceSheet, fiscalYear: 2025, format: .pdf
        )
        XCTAssertEqual(pdfFileName, "balance_sheet_2025_\(expectedDate).pdf")

        // 各ターゲットの filePrefix を検証
        let journalFileName = ExportCoordinator.makeFileName(
            target: .journal, fiscalYear: 2026, format: .csv
        )
        XCTAssertTrue(journalFileName.hasPrefix("journal_2026_"))
        XCTAssertTrue(journalFileName.hasSuffix(".csv"))

        let trialBalanceFileName = ExportCoordinator.makeFileName(
            target: .trialBalance, fiscalYear: 2026, format: .pdf
        )
        XCTAssertTrue(trialBalanceFileName.hasPrefix("trial_balance_2026_"))
        XCTAssertTrue(trialBalanceFileName.hasSuffix(".pdf"))

        let ledgerFileName = ExportCoordinator.makeFileName(
            target: .ledger, fiscalYear: 2026, format: .csv
        )
        XCTAssertTrue(ledgerFileName.hasPrefix("ledger_2026_"))

        let fixedAssetsFileName = ExportCoordinator.makeFileName(
            target: .fixedAssets, fiscalYear: 2026, format: .csv
        )
        XCTAssertTrue(fixedAssetsFileName.hasPrefix("fixed_assets_2026_"))
    }

    // MARK: - Export Target Labels

    /// 各エクスポート対象の日本語ラベルが正しいことを確認
    func testExportTargetLabels() {
        XCTAssertEqual(ExportCoordinator.ExportTarget.profitLoss.label, "損益計算書")
        XCTAssertEqual(ExportCoordinator.ExportTarget.balanceSheet.label, "貸借対照表")
        XCTAssertEqual(ExportCoordinator.ExportTarget.trialBalance.label, "残高試算表")
        XCTAssertEqual(ExportCoordinator.ExportTarget.journal.label, "仕訳帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.ledger.label, "総勘定元帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.fixedAssets.label, "固定資産台帳")
    }

    // MARK: - Export Format Extensions

    /// 各エクスポート形式のファイル拡張子が正しいことを確認
    func testExportFormatExtensions() {
        XCTAssertEqual(ExportCoordinator.ExportFormat.csv.fileExtension, "csv")
        XCTAssertEqual(ExportCoordinator.ExportFormat.pdf.fileExtension, "pdf")

        // ラベルの確認
        XCTAssertEqual(ExportCoordinator.ExportFormat.csv.label, "CSV")
        XCTAssertEqual(ExportCoordinator.ExportFormat.pdf.label, "PDF")
    }
}
