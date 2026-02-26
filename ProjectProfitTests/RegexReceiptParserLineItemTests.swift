import XCTest
@testable import ProjectProfit

final class RegexReceiptParserLineItemTests: XCTestCase {

    // MARK: - Basic Line Item Extraction

    func testExtractLineItemsFromSimpleReceipt() {
        let text = """
        テストストア
        2026/01/15
        コーヒー ¥350
        サンドイッチ ¥480
        合計 ¥830
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        XCTAssertGreaterThanOrEqual(items.count, 2)

        let coffee = items.first(where: { $0.name.contains("コーヒー") })
        XCTAssertNotNil(coffee)
        XCTAssertEqual(coffee?.subtotal, 350)

        let sandwich = items.first(where: { $0.name.contains("サンドイッチ") })
        XCTAssertNotNil(sandwich)
        XCTAssertEqual(sandwich?.subtotal, 480)
    }

    func testExtractLineItemsSkipsTotalLine() {
        let text = """
        品目A ¥100
        品目B ¥200
        合計 ¥300
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        let totalLine = items.first(where: { $0.name.contains("合計") })
        XCTAssertNil(totalLine, "合計行は除外されるべき")
    }

    func testExtractLineItemsSkipsTaxLine() {
        let text = """
        品目A ¥1000
        消費税 ¥100
        合計 ¥1100
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        let taxLine = items.first(where: { $0.name.contains("税") })
        XCTAssertNil(taxLine, "税行は除外されるべき")
    }

    func testExtractLineItemsSkipsPaymentLines() {
        let text = """
        品目A ¥500
        現金 ¥1000
        お釣り ¥500
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].name.contains("品目A"))
    }

    // MARK: - Price Formats

    func testExtractLineItemsWithYenSuffix() {
        let text = """
        ペン 100円
        ノート 250円
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        XCTAssertGreaterThanOrEqual(items.count, 2)
    }

    func testExtractLineItemsWithCommaInPrice() {
        let text = """
        キーボード ¥12,800
        マウス ¥3,500
        """
        let items = RegexReceiptParser.extractLineItems(from: text)

        let keyboard = items.first(where: { $0.name.contains("キーボード") })
        XCTAssertNotNil(keyboard)
        XCTAssertEqual(keyboard?.subtotal, 12800)
    }

    func testExtractLineItemsWithPlainNumber() {
        let text = """
        コーラ 150
        おにぎり 120
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        XCTAssertGreaterThanOrEqual(items.count, 2)
    }

    // MARK: - Quantity Detection

    func testExtractLineItemsWithQuantity() {
        let text = """
        ボールペン x3 ¥300
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        guard let pen = items.first(where: { $0.name.contains("ボールペン") }) else {
            XCTFail("ボールペンが見つかりません")
            return
        }
        XCTAssertEqual(pen.quantity, 3)
        XCTAssertEqual(pen.subtotal, 300)
        XCTAssertEqual(pen.unitPrice, 100)
    }

    // MARK: - Empty / Edge Cases

    func testExtractLineItemsFromEmptyText() {
        let items = RegexReceiptParser.extractLineItems(from: "")
        XCTAssertTrue(items.isEmpty)
    }

    func testExtractLineItemsFromTextWithNoItems() {
        let text = """
        テスト店舗
        ありがとうございました
        またお越しください
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        XCTAssertTrue(items.isEmpty)
    }

    func testExtractLineItemsIgnoresVeryShortLines() {
        let text = """
        A 1
        品目名テスト ¥500
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        // Very short line "A 1" should be ignored
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].name.contains("品目名テスト"))
    }

    func testExtractLineItemsDefaultQuantityIsOne() {
        let text = """
        コーヒー ¥350
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        guard let coffee = items.first else {
            XCTFail("品目が見つかりません")
            return
        }
        XCTAssertEqual(coffee.quantity, 1)
    }

    // MARK: - Japanese Quantity Patterns

    func testExtractLineItemsWithJapaneseQuantity() {
        let text = """
        おにぎり 3個 ¥450
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        guard let onigiri = items.first(where: { $0.name.contains("おにぎり") }) else {
            XCTFail("おにぎりが見つかりません")
            return
        }
        XCTAssertEqual(onigiri.quantity, 3)
    }

    func testExtractLineItemsSkipsGreetingLines() {
        let text = """
        品目A ¥500
        いらっしゃいませ 100
        ありがとうございました 200
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].name.contains("品目A"))
    }

    func testExtractLineItemsSkipsPointLine() {
        let text = """
        品目A ¥500
        ポイント ¥50
        """
        let items = RegexReceiptParser.extractLineItems(from: text)
        XCTAssertEqual(items.count, 1)
    }

    // MARK: - Category Estimation

    func testEstimateCategoryFood() {
        let text = "セブンイレブン 東京店 コーヒー ¥150"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "food")
    }

    func testEstimateCategoryFoodCafe() {
        let text = "スターバックス 渋谷店 カフェラテ ¥550"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "food")
    }

    func testEstimateCategoryTransport() {
        let text = "タクシー 東京駅 ¥2,500"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "transport")
    }

    func testEstimateCategorySupplies() {
        let text = "コピー用紙 A4 500枚 ¥450"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "supplies")
    }

    func testEstimateCategoryTools() {
        let text = "Adobe Creative Cloud 月額 ¥6,480"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "tools")
    }

    func testEstimateCategoryHosting() {
        let text = "AWS 請求書 EC2 + S3 ¥15,000"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "hosting")
    }

    func testEstimateCategoryEntertainment() {
        let text = "忘年会 会費 ¥5,000"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "entertainment")
    }

    func testEstimateCategoryInsurance() {
        let text = "損害保険料 自動車保険 ¥12,000"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "insurance")
    }

    func testEstimateCategoryOtherExpense() {
        let text = "特殊な支出 ¥1,000"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "other-expense")
    }

    func testEstimateCategoryConvenienceStore() {
        let text = "ファミリーマート 弁当 ¥500"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "food")
    }

    func testEstimateCategoryCommunication() {
        let text = "NTTドコモ 通信料 ¥8,000"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text), "communication")
    }

    func testEstimateCategoryIncomeSales() {
        let text = "請求書 ご請求金額 ¥150,000 納品分"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text, type: .income), "sales")
    }

    func testEstimateCategoryIncomeService() {
        let text = "保守サービス 月額利用料 ¥30,000"
        XCTAssertEqual(RegexReceiptParser.estimateCategory(from: text, type: .income), "service")
    }

    func testNormalizeEstimatedCategoryFallsBackByType() {
        let text = "請求書 ご請求金額 ¥150,000"
        let normalized = RegexReceiptParser.normalizeEstimatedCategory(
            "tools",
            type: .income,
            fallbackText: text
        )
        XCTAssertEqual(normalized, "sales")
    }

    func testNormalizeEstimatedCategoryKeepsInsuranceForExpense() {
        let normalized = RegexReceiptParser.normalizeEstimatedCategory(
            "insurance",
            type: .expense,
            fallbackText: "保険料"
        )
        XCTAssertEqual(normalized, "insurance")
    }
}
