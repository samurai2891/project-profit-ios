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

        let summary = app.otherElements["approval.candidate.withholdingSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
    }

    func testFilingDashboardNavigatesToWithholdingStatement() {
        app.tabBars.buttons["その他"].tap()
        app.buttons["確定申告"].tap()

        let route = app.descendants(matching: .any).matching(identifier: "filing.workflow.withholding").firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.tap()

        let screen = app.descendants(matching: .any).matching(identifier: "withholding.statement.screen").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["支払先別"].waitForExistence(timeout: 10))
    }
}
