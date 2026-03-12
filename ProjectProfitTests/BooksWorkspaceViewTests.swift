import XCTest
@testable import ProjectProfit

final class BooksWorkspaceViewTests: XCTestCase {
    func testBooksWorkspaceStaticCopyIsDefined() {
        XCTAssertEqual(BooksWorkspaceView.titleText, "帳簿ワークスペース")
        XCTAssertTrue(BooksWorkspaceView.descriptionText.contains("仕訳確認"))
        XCTAssertTrue(BooksWorkspaceView.descriptionText.contains("帳簿確認"))
        XCTAssertTrue(BooksWorkspaceView.descriptionText.contains("申告作業"))
    }

    func testFilingDashboardUsesBooksWorkspaceEntryCopy() {
        XCTAssertEqual(FilingDashboardView.booksWorkspaceTitle, "帳簿ワークスペース")
        XCTAssertEqual(FilingDashboardView.booksWorkspaceSubtitle, "レポート・帳簿・申告作業をまとめて確認")
    }
}
