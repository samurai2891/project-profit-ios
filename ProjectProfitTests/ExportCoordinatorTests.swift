import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ExportCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var businessId: UUID!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        businessId = dataStore.businessProfile?.id
        XCTAssertNotNil(businessId)
    }

    override func tearDown() {
        businessId = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testMakeFileName() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let expectedDate = formatter.string(from: Date())

        let csvFileName = ExportCoordinator.makeFileName(
            target: .profitLoss, fiscalYear: 2026, format: .csv
        )
        XCTAssertEqual(csvFileName, "profit_loss_2026_\(expectedDate).csv")

        let pdfFileName = ExportCoordinator.makeFileName(
            target: .balanceSheet, fiscalYear: 2025, format: .pdf
        )
        XCTAssertEqual(pdfFileName, "balance_sheet_2025_\(expectedDate).pdf")

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

    func testExportTargetLabels() {
        XCTAssertEqual(ExportCoordinator.ExportTarget.profitLoss.label, "損益計算書")
        XCTAssertEqual(ExportCoordinator.ExportTarget.balanceSheet.label, "貸借対照表")
        XCTAssertEqual(ExportCoordinator.ExportTarget.trialBalance.label, "残高試算表")
        XCTAssertEqual(ExportCoordinator.ExportTarget.journal.label, "仕訳帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.ledger.label, "総勘定元帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.fixedAssets.label, "固定資産台帳")
    }

    func testExportFormatExtensions() {
        XCTAssertEqual(ExportCoordinator.ExportFormat.csv.fileExtension, "csv")
        XCTAssertEqual(ExportCoordinator.ExportFormat.pdf.fileExtension, "pdf")
        XCTAssertEqual(ExportCoordinator.ExportFormat.csv.label, "CSV")
        XCTAssertEqual(ExportCoordinator.ExportFormat.pdf.label, "PDF")
    }

    func testExportBlocksWhenPreflightFails() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        XCTAssertThrowsError(
            try ExportCoordinator.export(
                target: .trialBalance,
                format: .csv,
                fiscalYear: 2025,
                dataStore: dataStore
            )
        ) { error in
            guard let exportError = error as? ExportCoordinator.ExportError,
                  case .preflightBlocked(let messages) = exportError
            else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(messages, ["帳票出力は税務締め以降でのみ実行できます"])
        }
    }

    func testExportSucceedsAfterTaxClose() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)

        let url = try ExportCoordinator.export(
            target: .trialBalance,
            format: .csv,
            fiscalYear: 2025,
            dataStore: dataStore
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        XCTAssertFalse(data.isEmpty)
    }

    func testLedgerExportStillRequiresAccountOptionAfterPreflightPasses() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)

        XCTAssertThrowsError(
            try ExportCoordinator.export(
                target: .ledger,
                format: .pdf,
                fiscalYear: 2025,
                dataStore: dataStore
            )
        ) { error in
            guard let exportError = error as? ExportCoordinator.ExportError,
                  case .ledgerAccountRequired = exportError
            else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    private func seedTaxYearProfile(year: Int, state: YearLockState) {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: year,
            yearLockState: state,
            taxPackVersion: "\(year)-v1"
        )
        context.insert(TaxYearProfileEntityMapper.toEntity(profile))
        try! context.save()
    }
}
