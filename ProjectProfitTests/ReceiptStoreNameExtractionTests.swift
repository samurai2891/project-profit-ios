import XCTest
@testable import ProjectProfit

final class ReceiptStoreNameExtractionTests: XCTestCase {

    // MARK: - Basic Store Name

    func testExtractStoreNameFromFirstLine() {
        let text = """
        テスト商店
        2026/01/15 12:30
        コーヒー ¥350
        合計 ¥350
        """
        XCTAssertEqual(RegexReceiptParser.extractStoreName(from: text), "テスト商店")
    }

    func testExtractStoreNameSkipsDateLine() {
        let text = """
        2026/01/15
        テスト商店
        コーヒー ¥350
        """
        XCTAssertEqual(RegexReceiptParser.extractStoreName(from: text), "テスト商店")
    }

    func testExtractStoreNameSkipsTimeLine() {
        let text = """
        12:30
        テスト商店
        商品 ¥100
        """
        XCTAssertEqual(RegexReceiptParser.extractStoreName(from: text), "テスト商店")
    }

    func testExtractStoreNameSkipsTelLine() {
        let text = """
        TEL 03-1234-5678
        テスト商店
        商品 ¥100
        """
        XCTAssertEqual(RegexReceiptParser.extractStoreName(from: text), "テスト商店")
    }

    func testExtractStoreNameSkipsYenPrefixLine() {
        let text = """
        ¥500
        テスト商店
        商品 ¥100
        """
        XCTAssertEqual(RegexReceiptParser.extractStoreName(from: text), "テスト商店")
    }

    func testExtractStoreNameSkipsReceiptKeyword() {
        let text = """
        レシート
        テスト商店
        商品 ¥100
        """
        XCTAssertEqual(RegexReceiptParser.extractStoreName(from: text), "テスト商店")
    }

    func testExtractStoreNameSkipsTaxIdLine() {
        let text = """
        T1234567890123
        テスト商店
        商品 ¥100
        """
        XCTAssertEqual(RegexReceiptParser.extractStoreName(from: text), "テスト商店")
    }

    // MARK: - Edge Cases

    func testExtractStoreNameReturnsEmptyWhenNotFound() {
        let text = """
        ¥100
        ¥200
        ¥300
        ¥400
        ¥500
        """
        XCTAssertEqual(RegexReceiptParser.extractStoreName(from: text), "")
    }

    func testExtractStoreNameEmptyText() {
        XCTAssertEqual(RegexReceiptParser.extractStoreName(from: ""), "")
    }

    func testExtractStoreNameWithBranchName() {
        let text = """
        セブン-イレブン 渋谷道玄坂店
        2026/01/15
        """
        let name = RegexReceiptParser.extractStoreName(from: text)
        XCTAssertTrue(name.contains("セブン"), "店名が取得できるべき")
    }
}
