import XCTest

final class WithholdingApprovalUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--seed-withholding-flow"]
        app.launch()
    }

    func testApprovalQueueShowsWithholdingBadgeAndDetailSummary() {
        app.tabBars.buttons["承認"].tap()

        let badge = app.descendants(matching: .any).matching(identifier: "approval.candidate.withholdingBadge").firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 10))

        app.staticTexts["UIテスト税理士"].firstMatch.tap()

        let summary = app.descendants(matching: .any).matching(identifier: "approval.candidate.withholdingSummary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
    }

    func testFilingDashboardNavigatesToWithholdingStatement() {
        openFilingDashboard()

        let route = app.descendants(matching: .any).matching(identifier: "filing.workflow.withholding").firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()

        let screen = app.descendants(matching: .any).matching(identifier: "withholding.statement.screen").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["支払先別"].waitForExistence(timeout: 10))
    }

    func testSettingsTabShowsStableScreenIdentifier() {
        openSettings()

        let screen = app.descendants(matching: .any).matching(identifier: "screen.settings.main").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10))
    }

    func testApprovalTabShowsStableScreenIdentifier() {
        app.tabBars.buttons["承認"].tap()

        let screen = app.descendants(matching: .any).matching(identifier: "screen.approval.queue").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10))
    }

    func testFilingBooksWorkflowNavigatesToJournalBrowser() {
        openFilingDashboard()

        let booksRoute = app.descendants(matching: .any).matching(identifier: "filing.workflow.booksWorkspace").firstMatch
        XCTAssertTrue(booksRoute.waitForExistence(timeout: 10))
        booksRoute.tap()

        let journalBrowserRow = app.staticTexts["仕訳ブラウザ"].firstMatch
        XCTAssertTrue(journalBrowserRow.waitForExistence(timeout: 10))
        journalBrowserRow.tap()

        XCTAssertTrue(app.navigationBars["仕訳一覧"].firstMatch.waitForExistence(timeout: 10))
    }

    func testFilingDashboardNavigatesToEtaxExportScreen() {
        openFilingDashboard()

        let route = app.descendants(matching: .any).matching(identifier: "filing.workflow.etaxExport").firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()

        let screen = app.descendants(matching: .any).matching(identifier: "screen.etax.export").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10))
    }

    func testEtaxExportScreenShowsSupportMatrixAndNotes() {
        openFilingDashboard()

        let route = app.descendants(matching: .any).matching(identifier: "filing.workflow.etaxExport").firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()

        let matrix = app.descendants(matching: .any).matching(identifier: "etax.support.matrix").firstMatch
        XCTAssertTrue(matrix.waitForExistence(timeout: 10))

        let note = app.staticTexts["etax.support.note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))

        let selectedFormDescription = app.staticTexts["etax.support.selectedFormDescription"].firstMatch
        XCTAssertTrue(selectedFormDescription.waitForExistence(timeout: 10))

        let row2025 = app.descendants(matching: .any).matching(identifier: "etax.support.row.2025").firstMatch
        let row2026 = app.descendants(matching: .any).matching(identifier: "etax.support.row.2026").firstMatch
        XCTAssertTrue(row2025.waitForExistence(timeout: 10))
        XCTAssertTrue(row2026.waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts["etax.support.row.2025.blueReturn"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["etax.support.row.2025.blueCashBasis"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["etax.support.row.2025.whiteReturn"].firstMatch.waitForExistence(timeout: 10))
    }

    func testLockedYearDisablesSaveAndApproveAndShowsYearLockMessage() {
        relaunchWithLockedYearSeed()
        let approvalTab = app.tabBars.buttons["承認"].firstMatch
        XCTAssertTrue(approvalTab.waitForExistence(timeout: 10))
        approvalTab.tap()

        let counterparty = app.staticTexts["UIテスト税理士"].firstMatch
        XCTAssertTrue(counterparty.waitForExistence(timeout: 10))
        counterparty.tap()

        let saveButton = app.buttons["approval.candidate.saveButton"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10))
        XCTAssertFalse(saveButton.isEnabled)

        let approveButton = app.buttons["approval.candidate.approveButton"].firstMatch
        XCTAssertTrue(approveButton.waitForExistence(timeout: 10))
        XCTAssertFalse(approveButton.isEnabled)

        let lockMessage = app.staticTexts["approval.candidate.yearLockMessage"].firstMatch
        XCTAssertTrue(lockMessage.waitForExistence(timeout: 10))
    }

    func testFilingDashboardNavigatesToEtaxExportAndShowsSupportMatrix() {
        openFilingDashboard()

        let route = app.descendants(matching: .any).matching(identifier: "filing.workflow.etaxExport").firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()

        let screen = app.descendants(matching: .any).matching(identifier: "screen.etax.export").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10))

        let matrix = app.descendants(matching: .any).matching(identifier: "etax.support.matrix").firstMatch
        XCTAssertTrue(matrix.waitForExistence(timeout: 10))

        let note = app.descendants(matching: .any).matching(identifier: "etax.support.note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))

        let yearRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier MATCHES %@", #"^etax\.support\.row\.[0-9]{4}$"#)
        ).firstMatch
        XCTAssertTrue(yearRow.waitForExistence(timeout: 10))
    }

    private func openFilingDashboard() {
        let filingTab = app.tabBars.buttons["確定申告"].firstMatch
        if filingTab.exists {
            filingTab.tap()
            return
        }

        app.tabBars.buttons["その他"].tap()

        let filingCell = app.cells.containing(.staticText, identifier: "確定申告").firstMatch
        if filingCell.waitForExistence(timeout: 10) {
            filingCell.tap()
            return
        }

        let filingStaticText = app.staticTexts["確定申告"].firstMatch
        XCTAssertTrue(filingStaticText.waitForExistence(timeout: 10))
        filingStaticText.tap()
    }

    private func openSettings() {
        let settingsTab = app.tabBars.buttons["設定"].firstMatch
        if settingsTab.exists {
            settingsTab.tap()
            return
        }

        app.tabBars.buttons["その他"].tap()

        let settingsCell = app.cells.containing(.staticText, identifier: "設定").firstMatch
        if settingsCell.waitForExistence(timeout: 10) {
            settingsCell.tap()
            return
        }

        let settingsStaticText = app.staticTexts["設定"].firstMatch
        XCTAssertTrue(settingsStaticText.waitForExistence(timeout: 10))
        settingsStaticText.tap()
    }

    private func relaunchWithLockedYearSeed() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--seed-withholding-flow-locked-year"]
        app.launch()
    }
}
