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
}
