import XCTest
@testable import ProjectProfit

final class BooksWorkspaceViewTests: XCTestCase {
    func testBooksWorkspaceStaticCopyIsDefined() {
        XCTAssertEqual(BooksWorkspaceView.titleText, "帳簿ワークスペース")
        XCTAssertTrue(BooksWorkspaceView.descriptionText.contains("仕訳確認"))
        XCTAssertTrue(BooksWorkspaceView.descriptionText.contains("帳簿確認"))
        XCTAssertTrue(BooksWorkspaceView.descriptionText.contains("申告作業"))
    }

    func testBooksWorkspaceIncludesReconciliationEntryCopy() {
        XCTAssertEqual(BooksWorkspaceView.reconciliationTitle, "銀行/カード照合")
        XCTAssertEqual(BooksWorkspaceView.reconciliationSubtitle, "明細取込と未照合チェック")
        XCTAssertEqual(BankCardReconciliationView.titleText, "銀行/カード照合")
    }

    func testFilingDashboardUsesBooksWorkspaceEntryCopy() {
        XCTAssertEqual(FilingDashboardView.booksWorkspaceTitle, "帳簿ワークスペース")
        XCTAssertEqual(FilingDashboardView.booksWorkspaceSubtitle, "レポート・帳簿・申告作業をまとめて確認")
    }
}
