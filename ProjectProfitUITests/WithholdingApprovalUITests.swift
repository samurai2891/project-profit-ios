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
}
