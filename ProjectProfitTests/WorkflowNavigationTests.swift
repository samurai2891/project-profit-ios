import XCTest
@testable import ProjectProfit

final class WorkflowNavigationTests: XCTestCase {
    func testFilingDashboardWorkflowDestinationsStayFixedToBooksAndFilingFlow() {
        XCTAssertEqual(
            FilingDashboardView.workflowItems.map(\.destinationID),
            [.booksWorkspace, .withholding, .closingEntry, .etaxExport]
        )
    }

    func testFilingDashboardWorkflowDoesNotExposeDirectJournalBrowserEntry() {
        XCTAssertFalse(
            FilingDashboardView.workflowItems.contains { $0.title == "仕訳ブラウザ" }
        )
    }

    func testBooksWorkspaceWorkflowRemovesLegacyJournalListRoute() {
        XCTAssertFalse(
            BooksWorkspaceView.workflowItems.contains { $0.title == "仕訳帳" }
        )
        XCTAssertEqual(
            BooksWorkspaceView.workflowItems.map(\.destinationID),
            [.reconciliation, .journalBrowser, .analytics]
        )
    }

    func testBooksWorkspaceReleaseBookRoutesExposeCanonicalLedgerEntries() {
        XCTAssertTrue(
            BooksWorkspaceView.releaseBookItems.contains { $0.title == "仕訳帳" && $0.destinationID == .journalBook }
        )
        XCTAssertEqual(
            BooksWorkspaceView.releaseBookItems.map(\.destinationID),
            [
                .journalBook,
                .generalLedger,
                .cashBook,
                .depositBook,
                .accountsReceivableBook,
                .accountsPayableBook,
                .expenseBook,
                .fixedAssetLedger,
                .inventoryLedger,
                .whiteTaxBookkeeping,
            ]
        )
    }
}
