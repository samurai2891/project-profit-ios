import XCTest

final class AnnualFourProjectAccountingE2EUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--seed-annual-four-projects"]
        app.launch()
    }

    func testAnnualFourProjectScenarioShowsDashboardProjectsAndTotals() {
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "screen.dashboard").firstMatch.waitForExistence(timeout: 20))

        tapTab("案件")
        XCTAssertVisibleText("UI年次 Web制作 A")
        XCTAssertVisibleText("UI年次 iOS開発 B")
        XCTAssertVisibleText("UI年次 顧問 C")
        XCTAssertVisibleText("UI年次 保守運用 D")

        tapTab("ダッシュボード")
        XCTAssertVisibleText("進行中のプロジェクト")
        XCTAssertVisibleText("4件")
        XCTAssertVisibleText("UI年次 Web制作 A")
        XCTAssertVisibleText("UI年次 iOS開発 B")
        XCTAssertVisibleText("UI年次 顧問 C")
        XCTAssertVisibleText("UI年次 保守運用 D")
    }

    func testAnnualFourProjectScenarioShowsTransactionsAndAccountingWorkspace() {
        tapTab("取引履歴")
        XCTAssertVisibleText("40件")
        XCTAssertVisibleText("UI年次 12月 売上")
        XCTAssertVisibleText("UI年次 12月 業務ツール")
        XCTAssertVisibleText("収益")
        XCTAssertVisibleText("経費")
        XCTAssertVisibleText("差引")

        tapTab("確定申告")
        let booksRoute = app.descendants(matching: .any).matching(identifier: "filing.workflow.booksWorkspace").firstMatch
        XCTAssertTrue(booksRoute.waitForExistence(timeout: 10))
        booksRoute.tap()

        XCTAssertVisibleText("帳簿ワークスペース")
        XCTAssertVisibleText("会計ステータス")
        XCTAssertVisibleText("正常")
        XCTAssertVisibleText("帳簿・台帳")
        XCTAssertVisibleText("仕訳帳")
        XCTAssertVisibleText("総勘定元帳")
        XCTAssertVisibleText("現金出納帳")
        XCTAssertVisibleText("売掛帳")
        XCTAssertVisibleText("経費帳")
        XCTAssertVisibleText("固定資産台帳")
        XCTAssertVisibleText("月別総括集計表")
        XCTAssertVisibleText("試算表")
    }

    func testAnnualFourProjectScenarioNavigatesThroughReleaseBooks() {
        openBooksWorkspace()

        tapVisibleText("総勘定元帳")
        XCTAssertVisibleText("総勘定元帳")

        relaunchScenario()
        openBooksWorkspace()
        tapVisibleText("月別総括集計表")
        XCTAssertVisibleText("月別総括集計表")

        relaunchScenario()
        openBooksWorkspace()
        tapVisibleText("固定資産台帳")
        XCTAssertVisibleText("固定資産台帳")
        XCTAssertVisibleText("UI年次 MacBook Pro")
    }

    private func openBooksWorkspace() {
        tapTab("確定申告")
        let booksRoute = app.descendants(matching: .any).matching(identifier: "filing.workflow.booksWorkspace").firstMatch
        XCTAssertTrue(booksRoute.waitForExistence(timeout: 10))
        booksRoute.tap()
        XCTAssertVisibleText("帳簿ワークスペース")
    }

    private func tapTab(_ title: String) {
        let button = app.tabBars.buttons[title].firstMatch
        if button.waitForExistence(timeout: 3) {
            button.tap()
            return
        }

        let moreButton = app.tabBars.buttons["その他"].firstMatch
        XCTAssertTrue(moreButton.waitForExistence(timeout: 10), "\(title)タブもその他タブも見つかりません")
        moreButton.tap()

        let cell = app.cells.containing(.staticText, identifier: title).firstMatch
        if cell.waitForExistence(timeout: 5) {
            cell.tap()
            return
        }

        let staticText = app.staticTexts[title].firstMatch
        XCTAssertTrue(staticText.waitForExistence(timeout: 5), "\(title)がその他画面に見つかりません")
        staticText.tap()
    }

    private func relaunchScenario() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--seed-annual-four-projects"]
        app.launch()
    }

    private func tapVisibleText(_ text: String) {
        let element = visibleText(text)
        XCTAssertTrue(waitForVisibleText(text), "\(text) が表示されません")
        element.tap()
    }

    private func XCTAssertVisibleText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForVisibleText(text), "\(text) が表示されません", file: file, line: line)
    }

    private func waitForVisibleText(_ text: String) -> Bool {
        let element = visibleText(text)
        if element.waitForExistence(timeout: 3) {
            return true
        }

        for _ in 0..<8 {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }
        for _ in 0..<4 {
            app.swipeDown()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }
        return false
    }

    private func visibleText(_ text: String) -> XCUIElement {
        app.staticTexts[text].firstMatch
    }
}
