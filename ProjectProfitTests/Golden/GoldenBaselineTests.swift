import XCTest
@testable import ProjectProfit

@MainActor
final class GoldenBaselineTests: XCTestCase {
    private var previousFiscalYearStartMonth: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousFiscalYearStartMonth = UserDefaults.standard.object(forKey: FiscalYearSettings.userDefaultsKey)
        UserDefaults.standard.set(FiscalYearSettings.defaultStartMonth, forKey: FiscalYearSettings.userDefaultsKey)
    }

    override func tearDownWithError() throws {
        if let previousFiscalYearStartMonth {
            UserDefaults.standard.set(previousFiscalYearStartMonth, forKey: FiscalYearSettings.userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        }
        previousFiscalYearStartMonth = nil
        try super.tearDownWithError()
    }

    func testFixtureLoads() throws {
        let fixture = try GoldenFixtureLoader.load(testCase: self)
        XCTAssertEqual(fixture.businessProfile.fiscalYear, 2025)
        XCTAssertEqual(fixture.projects.count, 3)
        XCTAssertGreaterThanOrEqual(fixture.transactions.count, 12)
        XCTAssertGreaterThanOrEqual(fixture.categories.count, 5)
    }

    func testJournalBookMatchesExpected() async throws {
        let scenario = try await GoldenFixtureLoader.makeScenario(testCase: self)
        let snapshot = GoldenSnapshotBuilder.journalBookSnapshot(from: scenario)
        try GoldenSnapshotStore.assertSnapshot(snapshot, named: "journal_book_2025")
    }

    func testTrialBalanceMatchesExpected() async throws {
        let scenario = try await GoldenFixtureLoader.makeScenario(testCase: self)
        let snapshot = GoldenSnapshotBuilder.trialBalanceSnapshot(from: scenario)
        try GoldenSnapshotStore.assertSnapshot(snapshot, named: "trial_balance_2025")
    }

    func testBlueReturnMatchesExpected() async throws {
        let scenario = try await GoldenFixtureLoader.makeScenario(testCase: self)
        let snapshot = GoldenSnapshotBuilder.blueReturnSnapshot(from: scenario)
        try GoldenSnapshotStore.assertSnapshot(snapshot, named: "blue_return_2025")
    }

    func testConsumptionTaxWorksheetMatchesExpected() async throws {
        let scenario = try await GoldenFixtureLoader.makeScenario(testCase: self)
        let snapshot = try await GoldenSnapshotBuilder.consumptionTaxWorksheetSnapshot(from: scenario)
        try GoldenSnapshotStore.assertSnapshot(snapshot, named: "consumption_tax_worksheet_2025")
    }

    func testMigrationDryRunMatchesExpected() async throws {
        let scenario = try await GoldenFixtureLoader.makeScenario(testCase: self)
        let snapshot = try GoldenSnapshotBuilder.migrationReportSnapshot(from: scenario)
        try GoldenSnapshotStore.assertSnapshot(snapshot, named: "migration_dry_run_2025")
    }

    func testLedgerExportsMatchExpected() async throws {
        let scenario = try await GoldenFixtureLoader.makeScenario(testCase: self)
        let snapshot = try GoldenSnapshotBuilder.ledgerExportSnapshot(from: scenario)
        XCTAssertEqual(snapshot.fiscalYear, 2025)
        XCTAssertEqual(snapshot.ledgers.count, 11)

        assertLedger(snapshot, target: "現金出納帳", csvContains: ["月,日,摘要,勘定科目", "前期より繰越"], pdfContains: ["現金出納帳"])
        assertLedger(snapshot, target: "預金出納帳", csvContains: ["銀行名,", "月,日,摘要,勘定科目", "前期より繰越"], pdfContains: ["預金出納帳"])
        assertLedger(snapshot, target: "売掛帳", csvContains: ["得意先名,", "月,日,相手科目,摘要", "前期より繰越"], pdfContains: ["売掛帳"])
        assertLedger(snapshot, target: "買掛帳", csvContains: ["仕入先名,", "月,日,相手科目,摘要", "前期より繰越"], pdfContains: ["買掛帳"])
        assertLedger(snapshot, target: "経費帳", csvContains: ["勘定科目名,", "月,日,相手科目,摘要", "金額合計"], pdfContains: ["経費帳"])
        assertLedger(snapshot, target: "総勘定元帳", csvContains: ["勘定科目,", "差引残高", "前期より繰越"], pdfContains: ["総勘定元帳"])
        assertLedger(snapshot, target: "仕訳帳", csvContains: ["月,日,借方科目,借方金額,貸方科目,貸方金額,摘要"], pdfContains: ["仕訳帳"])
        assertLedger(snapshot, target: "交通費精算書", csvContains: ["年,2025", "日付,行先,目的（用件）,交通機関（手段）"], pdfContains: ["交通費精算書"])
        assertLedger(snapshot, target: "白色申告用 簡易帳簿", csvContains: ["月,日,摘要,売上金額,雑収入等,仕入", "2025年分"], pdfContains: ["白色申告用", "簡易帳簿"])
        assertLedger(snapshot, target: "固定資産台帳", csvContains: ["名称,MacBook Pro", "年月日,摘要,取得数量,取得単価,取得金額,償却額,異動数量,異動金額,現在数量,現在金額,事業専用割合,必要経費算入額,備考", "2025/01/10,MacBook Pro,1,360000,360000,89999,,,1,360000,1.00,89999,golden fixture asset"], pdfContains: ["固定資産台帳", "名称: MacBook Pro", "必要経費算入額", "MacBook Pro"])
        assertLedger(snapshot, target: "減価償却明細表", csvContains: ["年分,2025年分", "勘定科目,資産コード,資産名,資産の種類,状態,数量,取得日,取得価額,償却方法,耐用年数,償却率,償却月数,期首帳簿価額,期中増減,減価償却費,特別(割増)償却費,償却費合計,事業専用割合,必要経費算入額,本年末残高,摘要", "減価償却費", "MacBook Pro"], pdfContains: ["固定資産台帳 兼 減価償却計算表", "年分: 2025年分", "特別(割増)償却費", "本年末残高", "MacBook Pro"])
    }

    private func assertLedger(
        _ snapshot: GoldenLedgerExportSnapshot,
        target: String,
        csvContains fragments: [String],
        pdfContains pdfFragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let artifact = snapshot.ledgers.first(where: { $0.target == target }) else {
            return XCTFail("missing target: \(target)", file: file, line: line)
        }
        XCTAssertEqual(artifact.formats, ["csv", "pdf"], file: file, line: line)
        XCTAssertGreaterThan(artifact.pdfPageCount, 0, file: file, line: line)

        let csvJoined = artifact.csvLines.joined(separator: "\n")
        for fragment in fragments {
            XCTAssertTrue(csvJoined.contains(fragment), "CSV missing fragment '\(fragment)' for \(target)", file: file, line: line)
        }

        let pdfJoined = artifact.pdfLines.joined(separator: "\n")
        for fragment in pdfFragments {
            XCTAssertTrue(pdfJoined.contains(fragment), "PDF missing fragment '\(fragment)' for \(target)", file: file, line: line)
        }
    }
}
