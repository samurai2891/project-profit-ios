import XCTest
@testable import ProjectProfit

final class BooksWorkspaceViewTests: XCTestCase {
    func testBooksWorkspaceStaticCopyIsDefined() {
        XCTAssertEqual(BooksWorkspaceView.titleText, "帳簿ワークスペース")
        XCTAssertTrue(BooksWorkspaceView.descriptionText.contains("未照合"))
        XCTAssertTrue(BooksWorkspaceView.descriptionText.contains("分析"))
        XCTAssertTrue(BooksWorkspaceView.descriptionText.contains("申告準備"))
    }

    func testBooksWorkspaceIncludesReconciliationEntryCopy() {
        XCTAssertEqual(BooksWorkspaceView.reconciliationTitle, "銀行/カード照合")
        XCTAssertEqual(BooksWorkspaceView.reconciliationSubtitle, "明細取込と未照合チェック")
        XCTAssertEqual(BankCardReconciliationView.titleText, "銀行/カード照合")
    }

    func testBooksWorkspaceWorkflowMetadataUsesCanonicalEntries() {
        XCTAssertEqual(
            BooksWorkspaceView.workflowItems.map(\.destinationID),
            [.reconciliation, .journalBrowser, .analytics]
        )
        XCTAssertEqual(
            BooksWorkspaceView.workflowItems.map(\.title),
            ["銀行/カード照合", "仕訳ブラウザ", "分析レポート"]
        )
        XCTAssertFalse(BooksWorkspaceView.workflowItems.map(\.title).contains("仕訳帳"))
        XCTAssertEqual(BooksWorkspaceView.analyticsSubtitle, "収益・費用・月別推移を確認")
        XCTAssertEqual(ReportView.titleText, "分析レポート")
    }

    func testFilingDashboardUsesBooksWorkspaceEntryCopy() {
        XCTAssertEqual(FilingDashboardView.booksWorkspaceTitle, "帳簿ワークスペース")
        XCTAssertEqual(FilingDashboardView.booksWorkspaceSubtitle, "仕訳確認・分析・申告準備の入口")
    }
}
