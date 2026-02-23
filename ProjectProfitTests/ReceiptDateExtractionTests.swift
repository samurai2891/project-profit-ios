import XCTest
@testable import ProjectProfit

final class ReceiptDateExtractionTests: XCTestCase {

    // MARK: - Slash Format

    func testDateSlashFormat() {
        let text = """
        テスト店
        2026/01/15 12:30
        コーヒー ¥350
        """
        XCTAssertEqual(RegexReceiptParser.extractDate(from: text), "2026-01-15")
    }

    func testDateHyphenFormat() {
        let text = """
        テスト店
        2026-02-28
        コーヒー ¥350
        """
        XCTAssertEqual(RegexReceiptParser.extractDate(from: text), "2026-02-28")
    }

    func testDateSingleDigitMonthDay() {
        let text = """
        2026/1/5
        テスト店
        """
        XCTAssertEqual(RegexReceiptParser.extractDate(from: text), "2026-01-05")
    }

    // MARK: - Japanese Format

    func testDateJapaneseFormat() {
        let text = """
        2026年3月15日
        テスト店
        """
        XCTAssertEqual(RegexReceiptParser.extractDate(from: text), "2026-03-15")
    }

    func testDateJapaneseFormatWithSpaces() {
        let text = """
        2026年 1月 5日
        テスト店
        """
        XCTAssertEqual(RegexReceiptParser.extractDate(from: text), "2026-01-05")
    }

    // MARK: - Fallback

    func testDateFallsBackToToday() {
        let text = """
        テスト店
        コーヒー ¥350
        """
        let result = RegexReceiptParser.extractDate(from: text)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        XCTAssertEqual(result, today)
    }

    // MARK: - Edge Cases

    func testDateWithTimeOnSameLine() {
        let text = """
        テスト店
        2026/12/31 23:59
        商品 ¥100
        """
        XCTAssertEqual(RegexReceiptParser.extractDate(from: text), "2026-12-31")
    }

    func testDatePicksFirstDateFound() {
        let text = """
        2026/01/10
        発行日: 2026/01/15
        """
        // 最初に見つかった日付を返す
        XCTAssertEqual(RegexReceiptParser.extractDate(from: text), "2026-01-10")
    }

    func testEmptyText() {
        let result = RegexReceiptParser.extractDate(from: "")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        XCTAssertEqual(result, today)
    }
}
