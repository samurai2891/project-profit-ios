import Foundation
import SwiftData
import XCTest
@testable import ProjectProfit

/// ExportCoordinator のファイル命名とラベル・拡張子、および xlsx smoke test の検証
@MainActor
final class ExportCoordinatorTests: XCTestCase {
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

    // MARK: - File Naming

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

        let xlsxFileName = ExportCoordinator.makeFileName(
            target: .trialBalance, fiscalYear: 2026, format: .xlsx
        )
        XCTAssertEqual(xlsxFileName, "trial_balance_2026_\(expectedDate).xlsx")
    }

    // MARK: - Export Target Labels

    func testExportTargetLabels() {
        XCTAssertEqual(ExportCoordinator.ExportTarget.profitLoss.label, "損益計算書")
        XCTAssertEqual(ExportCoordinator.ExportTarget.balanceSheet.label, "貸借対照表")
        XCTAssertEqual(ExportCoordinator.ExportTarget.trialBalance.label, "残高試算表")
        XCTAssertEqual(ExportCoordinator.ExportTarget.journal.label, "仕訳帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.ledger.label, "総勘定元帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.fixedAssets.label, "固定資産台帳")
    }

    // MARK: - Export Format Extensions

    func testExportFormatExtensions() {
        XCTAssertEqual(ExportCoordinator.ExportFormat.csv.fileExtension, "csv")
        XCTAssertEqual(ExportCoordinator.ExportFormat.pdf.fileExtension, "pdf")
        XCTAssertEqual(ExportCoordinator.ExportFormat.xlsx.fileExtension, "xlsx")

        XCTAssertEqual(ExportCoordinator.ExportFormat.csv.label, "CSV")
        XCTAssertEqual(ExportCoordinator.ExportFormat.pdf.label, "PDF")
        XCTAssertEqual(ExportCoordinator.ExportFormat.xlsx.label, "Excel")
    }

    // MARK: - XLSX Smoke Tests

    func testExportProfitLossXLSX() throws {
        let fiscalYear = seedAccountingData()
        try assertReportXLSXExport(
            target: .profitLoss,
            fiscalYear: fiscalYear,
            expectedSheetName: "損益計算書"
        )
        try assertGoldenLayout(
            target: .profitLoss,
            fiscalYear: fiscalYear,
            expectedSheetName: "損益計算書",
            expectedRows: [
                1: ["損益計算書", nil, nil],
                2: ["※ 単年度出力用。収入と費用を分けて表示。", nil, nil],
                3: ["年度", "\(fiscalYear)年度", nil],
                4: ["科目", "収入", "費用"],
                5: ["【収益の部】", nil, nil],
            ],
            expectedWidths: ["A": 34, "B": 16, "C": 16]
        )
    }

    func testExportBalanceSheetXLSX() throws {
        let fiscalYear = seedAccountingData()
        try assertReportXLSXExport(
            target: .balanceSheet,
            fiscalYear: fiscalYear,
            expectedSheetName: "貸借対照表"
        )
        try assertGoldenLayout(
            target: .balanceSheet,
            fiscalYear: fiscalYear,
            expectedSheetName: "貸借対照表",
            expectedRows: [
                1: ["貸借対照表", nil, nil, nil, nil],
                2: ["※ 単年度出力用。資産の部と負債・純資産の部を左右に分けて表示。", nil, nil, nil, nil],
                3: ["年度", "\(fiscalYear)年度", nil, nil, nil],
                4: ["資産の部", "金額", "", "負債・純資産の部", "金額"],
                5: ["資産の部", nil, nil, "負債の部", nil],
            ],
            expectedWidths: ["A": 28, "B": 16, "C": 4, "D": 28, "E": 16]
        )
    }

    func testExportTrialBalanceXLSX() throws {
        let fiscalYear = seedAccountingData()
        try assertReportXLSXExport(
            target: .trialBalance,
            fiscalYear: fiscalYear,
            expectedSheetName: "残高試算表"
        )
        try assertGoldenLayout(
            target: .trialBalance,
            fiscalYear: fiscalYear,
            expectedSheetName: "残高試算表",
            expectedRows: [
                1: ["残高試算表", nil, nil, nil, nil, nil],
                4: ["帳簿名", "残高試算表", nil, "※ 青背景=入力、灰背景=計算、黄色背景=注意。Sample は見本入力です。", nil, nil],
                5: ["年度", "\(fiscalYear)年度", nil, nil, nil, nil],
                9: ["コード", "勘定科目", "区分", "借方", "貸方", "残高"],
            ],
            expectedWidths: ["A": 10, "B": 20, "C": 10, "D": 12, "E": 12, "F": 12]
        )
    }

    func testExportJournalXLSX() throws {
        let fiscalYear = seedAccountingData()
        try assertReportXLSXExport(
            target: .journal,
            fiscalYear: fiscalYear,
            expectedSheetName: "仕訳帳"
        )
        try assertGoldenLayout(
            target: .journal,
            fiscalYear: fiscalYear,
            expectedSheetName: "仕訳帳",
            expectedRows: [
                1: ["仕訳帳", nil, nil, nil, nil, nil, nil],
                4: ["帳簿名", "仕訳帳", nil, "※ 青背景=入力、灰背景=計算、黄色背景=注意。Sample は見本入力です。", nil, nil, nil],
                5: ["年度", "\(fiscalYear)年度", nil, nil, nil, nil, nil],
                9: ["月", "日", "借方科目", "借方金額", "貸方科目", "貸方金額", "摘要"],
            ],
            expectedWidths: ["A": 7, "B": 7, "C": 18, "D": 14, "E": 18, "F": 14, "G": 28]
        )
    }

    func testExportLedgerXLSX() throws {
        let fiscalYear = seedAccountingData()
        let account = try XCTUnwrap(dataStore.accounts.first(where: { $0.id == "acct-cash" }))
        let options = ExportCoordinator.LedgerExportOptions(
            accountId: account.id,
            accountName: account.name,
            accountCode: account.code
        )

        try assertReportXLSXExport(
            target: .ledger,
            fiscalYear: fiscalYear,
            expectedSheetName: "総勘定元帳",
            ledgerOptions: options
        )
        try assertGoldenLayout(
            target: .ledger,
            fiscalYear: fiscalYear,
            expectedSheetName: "総勘定元帳",
            ledgerOptions: options,
            expectedRows: [
                1: ["総勘定元帳（通常版）", nil, nil, nil, nil, nil, nil],
                4: ["帳簿名", "総勘定元帳", nil, nil, nil, nil, nil],
                5: ["年度", "\(fiscalYear)年度", nil, nil, nil, nil, nil],
                10: ["月", "日", "相手科目", "摘要", "借方", "貸方", "差引残高"],
            ],
            expectedWidths: ["A": 8, "B": 8, "C": 18, "D": 26, "E": 14, "F": 14, "G": 16]
        )
    }

    func testExportFixedAssetsXLSX() throws {
        let fiscalYear = seedAccountingData()
        _ = dataStore.addFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: Calendar.current.date(from: DateComponents(year: fiscalYear, month: 1, day: 10))!,
            acquisitionCost: 240000,
            usefulLifeYears: 4,
            depreciationMethod: .straightLine,
            memo: "開発機"
        )

        try assertReportXLSXExport(
            target: .fixedAssets,
            fiscalYear: fiscalYear,
            expectedSheetName: "固定資産台帳"
        )
        try assertGoldenLayout(
            target: .fixedAssets,
            fiscalYear: fiscalYear,
            expectedSheetName: "固定資産台帳",
            expectedRows: [
                1: ["固定資産台帳 兼 減価償却計算表", nil, nil, nil, nil, nil, nil, nil, nil, nil],
                4: ["帳簿名", "固定資産台帳 兼 減価償却計算表", nil, nil, nil, nil, nil, nil, nil, nil],
                5: ["年分", "\(fiscalYear)年", nil, nil, nil, nil, nil, nil, nil, nil],
                9: ["勘定科目", "資産コード", "資産名", "資産の種類", "状態", "数量", "取得日", "取得価額", "償却方法", "耐用年数"],
            ],
            expectedWidths: ["A": 14, "B": 12, "C": 18, "D": 14, "E": 10, "F": 8, "G": 12, "H": 14, "I": 12, "J": 10]
        )
    }

    func testMaterializeReportXLSXGoldenFixtures() throws {
        let fiscalYear = 2026
        _ = seedAccountingData(year: fiscalYear)
        _ = dataStore.addFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: Calendar.current.date(from: DateComponents(year: fiscalYear, month: 1, day: 10))!,
            acquisitionCost: 240000,
            usefulLifeYears: 4,
            depreciationMethod: .straightLine,
            memo: "開発機"
        )

        let account = try XCTUnwrap(dataStore.accounts.first(where: { $0.id == "acct-cash" }))
        let ledgerOptions = ExportCoordinator.LedgerExportOptions(
            accountId: account.id,
            accountName: account.name,
            accountCode: account.code
        )

        let outputDirectory = try makeGoldenOutputDirectory()

        try materializeReportFixture(
            target: .profitLoss,
            fiscalYear: fiscalYear,
            outputDirectory: outputDirectory
        )
        try materializeReportFixture(
            target: .balanceSheet,
            fiscalYear: fiscalYear,
            outputDirectory: outputDirectory
        )
        try materializeReportFixture(
            target: .trialBalance,
            fiscalYear: fiscalYear,
            outputDirectory: outputDirectory
        )
        try materializeReportFixture(
            target: .journal,
            fiscalYear: fiscalYear,
            outputDirectory: outputDirectory
        )
        try materializeReportFixture(
            target: .ledger,
            fiscalYear: fiscalYear,
            ledgerOptions: ledgerOptions,
            outputDirectory: outputDirectory
        )
        try materializeReportFixture(
            target: .fixedAssets,
            fiscalYear: fiscalYear,
            outputDirectory: outputDirectory
        )
    }

    private func seedAccountingData() -> Int {
        seedAccountingData(year: Calendar.current.component(.year, from: Date()))
    }

    @discardableResult
    private func seedAccountingData(year: Int) -> Int {
        let project = dataStore.addProject(name: "Export Test Project", description: "")

        _ = dataStore.addTransaction(
            type: .income,
            amount: 150000,
            date: Calendar.current.date(from: DateComponents(year: year, month: 3, day: 15))!,
            categoryId: "cat-project-income",
            memo: "制作売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        _ = dataStore.addTransaction(
            type: .expense,
            amount: 45000,
            date: Calendar.current.date(from: DateComponents(year: year, month: 4, day: 3))!,
            categoryId: "cat-tools",
            memo: "ソフトウェア",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxDeductibleRate: 100
        )

        _ = dataStore.addTransaction(
            type: .expense,
            amount: 12000,
            date: Calendar.current.date(from: DateComponents(year: year, month: 5, day: 12))!,
            categoryId: "cat-hosting",
            memo: "クラウド利用料",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxDeductibleRate: 100
        )

        return year
    }

    private func makeGoldenOutputDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root
            .appendingPathComponent(".golden-generated-xlsx", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func materializeReportFixture(
        target: ExportCoordinator.ExportTarget,
        fiscalYear: Int,
        ledgerOptions: ExportCoordinator.LedgerExportOptions? = nil,
        outputDirectory: URL
    ) throws {
        let exportedURL = try ExportCoordinator.export(
            target: target,
            format: .xlsx,
            fiscalYear: fiscalYear,
            dataStore: dataStore,
            ledgerOptions: ledgerOptions
        )

        let destination = outputDirectory.appendingPathComponent("\(target.filePrefix).xlsx")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: exportedURL, to: destination)
        try? FileManager.default.removeItem(at: exportedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    private func assertReportXLSXExport(
        target: ExportCoordinator.ExportTarget,
        fiscalYear: Int,
        expectedSheetName: String,
        ledgerOptions: ExportCoordinator.LedgerExportOptions? = nil
    ) throws {
        let url = try ExportCoordinator.export(
            target: target,
            format: .xlsx,
            fiscalYear: fiscalYear,
            dataStore: dataStore,
            ledgerOptions: ledgerOptions
        )
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "xlsx should be a ZIP archive")

        let descriptor = try XCTUnwrap(LedgerExcelExportService.reportTemplateDescriptor(for: target))
        XCTAssertEqual(descriptor.worksheetName, expectedSheetName)
    }

    private func assertGoldenLayout(
        target: ExportCoordinator.ExportTarget,
        fiscalYear: Int,
        expectedSheetName: String,
        ledgerOptions: ExportCoordinator.LedgerExportOptions? = nil,
        expectedRows: [Int: [Any?]],
        expectedWidths: [String: Double]
    ) throws {
#if os(macOS)
        let url = try ExportCoordinator.export(
            target: target,
            format: .xlsx,
            fiscalYear: fiscalYear,
            dataStore: dataStore,
            ledgerOptions: ledgerOptions
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = try inspectWorkbook(at: url)
        XCTAssertEqual(snapshot.sheetName, expectedSheetName)

        for (row, expectedCells) in expectedRows {
            let actual = snapshot.rows[row] ?? []
            for (index, expected) in expectedCells.enumerated() {
                let actualValue = index < actual.count ? actual[index] : nil
                XCTAssertEqual(actualValue, expected.map { String(describing: $0) }, "row \(row) col \(index + 1) mismatch")
            }
        }

        for (column, expectedWidth) in expectedWidths {
            let actualWidth = try XCTUnwrap(snapshot.widths[column], "missing width for column \(column)")
            XCTAssertEqual(actualWidth, expectedWidth, accuracy: 0.01, "column \(column) width mismatch")
        }
#else
        _ = target
        _ = fiscalYear
        _ = expectedSheetName
        _ = ledgerOptions
        _ = expectedRows
        _ = expectedWidths
#endif
    }

    private func inspectWorkbook(at url: URL) throws -> WorkbookSnapshot {
#if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "/Users/yutaro/project-profit-ios/scripts/inspect_xlsx_layout.py",
            url.path,
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return try JSONDecoder().decode(WorkbookSnapshot.self, from: data)
#else
        _ = url
        throw XCTSkip("Workbook layout inspection runs only on host macOS via openpyxl")
#endif
    }
}

private struct WorkbookSnapshot: Decodable {
    let sheetName: String
    let rows: [Int: [String?]]
    let widths: [String: Double]

    enum CodingKeys: String, CodingKey {
        case sheetName = "sheet_name"
        case rows
        case widths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sheetName = try container.decode(String.self, forKey: .sheetName)
        widths = try container.decode([String: Double].self, forKey: .widths)

        let rawRows = try container.decode([String: [JSONValue]].self, forKey: .rows)
        var parsed: [Int: [String?]] = [:]
        for (key, values) in rawRows {
            guard let row = Int(key) else { continue }
            parsed[row] = values.map(\.stringValue)
        }
        rows = parsed
    }
}

private enum JSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value): return String(value)
        case .null: return nil
        }
    }
}
