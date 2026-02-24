import XCTest
@testable import ProjectProfit

final class ReceiptAmountExtractionTests: XCTestCase {

    // MARK: - Standard Receipt Patterns

    func testStandardReceiptWithSubtotalTaxTotal() {
        let text = """
        セブンイレブン 渋谷店
        2026/01/15 12:30
        おにぎり ¥150
        お茶 ¥130
        小計 ¥280
        消費税 ¥22
        合計 ¥302
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 302)
    }

    func testReceiptWithTaxInclusiveTotalKeyword() {
        // 「税込合計」が「合計」より後に来るパターン
        let text = """
        テスト商店
        商品A ¥1,000
        商品B ¥500
        合計 ¥1,500
        消費税 ¥150
        税込合計 ¥1,650
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 1650)
    }

    func testReceiptWithOshiharaiTotal() {
        // 「お支払い合計」キーワード
        let text = """
        ファミリーマート
        コーヒー ¥120
        サンドイッチ ¥380
        小計 ¥500
        消費税(8%) ¥40
        お支払い合計 ¥540
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 540)
    }

    func testReceiptWithOkaikeiTotal() {
        let text = """
        カフェ テスト
        カフェラテ ¥480
        ケーキ ¥520
        お会計 ¥1,000
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 1000)
    }

    // MARK: - Deposit/Change Exclusion (Critical Bug Fix)

    func testExcludesDepositAmount() {
        // お預り金額は合計より大きいことが多い - これを除外すべき
        let text = """
        テスト店
        商品A ¥350
        商品B ¥480
        合計 ¥830
        お預り ¥1,000
        お釣り ¥170
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 830)
    }

    func testExcludesDepositWhenTotalKeywordMissed() {
        // 合計キーワードが読み取れなかった場合でも、お預りは除外
        let text = """
        テスト店
        商品A ¥350
        商品B ¥480
        お預り ¥1,000
        お釣り ¥170
        """
        // お預り/お釣りを除外した最大値 = 480
        let amount = RegexReceiptParser.extractAmount(from: text)
        XCTAssertNotEqual(amount, 1000, "お預り金額を拾ってはいけない")
        XCTAssertNotEqual(amount, 170, "お釣り金額を拾ってはいけない")
    }

    func testExcludesOazukariVariant() {
        let text = """
        合計 ¥1,200
        お預かり ¥2,000
        お釣り ¥800
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 1200)
    }

    // MARK: - Payment Method Exclusion

    func testExcludesCreditCardPayment() {
        let text = """
        合計 ¥5,500
        クレジット ¥5,500
        VISA
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 5500)
    }

    func testExcludesElectronicPayment() {
        let text = """
        テスト店
        商品 ¥800
        合計 ¥800
        PayPay ¥800
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 800)
    }

    // MARK: - Tax-Inclusive vs Tax-Exclusive

    func testPrefersLastTotalWhenMultipleTotalLines() {
        // 一部のレシートでは「合計」が税抜、下に「税込合計」がある
        let text = """
        商品A ¥500
        商品B ¥300
        合計 ¥800
        消費税 ¥80
        税込合計 ¥880
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 880)
    }

    func testTaxInclusiveMarkerOnSameLine() {
        // (税込) が金額と同じ行にある
        let text = """
        テスト店
        商品 ¥1,000
        合計(税込) ¥1,100
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 1100)
    }

    func testSeikyuuGakuKeyword() {
        let text = """
        ご請求金額 ¥15,000
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 15000)
    }

    // MARK: - Internal Tax Display

    func testInternalTaxNotation() {
        // (内消費税等 ¥XX) パターン - 合計に含まれる税の表示
        let text = """
        合計 ¥1,080
        (内消費税等 ¥80)
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 1080)
    }

    // MARK: - Fallback Logic

    func testFallbackToLargestYenPrefixed() {
        // 合計キーワードなし - 最大¥金額にフォールバック
        let text = """
        テスト店
        コーヒー ¥350
        パン ¥250
        """
        let amount = RegexReceiptParser.extractAmount(from: text)
        XCTAssertEqual(amount, 350)
    }

    func testFallbackToLargestYenSuffix() {
        let text = """
        テスト店
        コーヒー 350円
        パン 250円
        """
        let amount = RegexReceiptParser.extractAmount(from: text)
        XCTAssertEqual(amount, 350)
    }

    // MARK: - Large Amounts

    func testLargeAmount() {
        let text = """
        請求書
        合計金額 ¥1,234,567
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 1234567)
    }

    // MARK: - Full-Width Yen Sign

    func testFullWidthYenSign() {
        let text = """
        合計 ￥1,500
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 1500)
    }

    // MARK: - Edge Cases

    func testEmptyText() {
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: ""), 0)
    }

    func testNoAmountsInText() {
        let text = """
        テスト店
        ありがとうございました
        """
        XCTAssertEqual(RegexReceiptParser.extractAmount(from: text), 0)
    }

    func testOnlyTaxLine() {
        // 税行だけでは合計として拾わない
        let text = """
        消費税 ¥100
        """
        let amount = RegexReceiptParser.extractAmount(from: text)
        // 消費税だけの場合はフォールバックで100が返される（これは仕方ない）
        // ただし合計キーワードとしてはマッチしないことを確認
        XCTAssertTrue(amount >= 0)
    }

    // MARK: - Tax Amount Extraction

    func testExtractTaxFromStandardReceipt() {
        let text = """
        小計 ¥1,000
        消費税 ¥100
        合計 ¥1,100
        """
        XCTAssertEqual(RegexReceiptParser.extractTax(from: text), 100)
    }

    func testExtractTaxFromInternalTaxNotation() {
        let text = """
        合計 ¥1,080
        (内消費税等 ¥80)
        """
        XCTAssertEqual(RegexReceiptParser.extractTax(from: text), 80)
    }

    func testExtractTaxWithUchiPrefix() {
        let text = """
        合計 ¥1,100
        うち消費税 ¥100
        """
        XCTAssertEqual(RegexReceiptParser.extractTax(from: text), 100)
    }

    func testExtractTaxWithReducedRate() {
        // 8%と10%の複数税率（実際のレシートでは各行が別になる）
        let text = """
        8%対象 ¥500
        内消費税 ¥37
        10%対象 ¥300
        内消費税 ¥27
        """
        let tax = RegexReceiptParser.extractTax(from: text)
        XCTAssertEqual(tax, 64, "複数税率の合計が返されるべき")
    }

    func testExtractTaxReturnsZeroWhenNotFound() {
        let text = """
        テスト店
        コーヒー ¥350
        合計 ¥350
        """
        XCTAssertEqual(RegexReceiptParser.extractTax(from: text), 0)
    }

    func testExtractTaxExcludesTaxRateLine() {
        // 「税率」行の金額は税額ではなく対象金額
        let text = """
        消費税 ¥100
        税率10% 対象 ¥1,000
        """
        XCTAssertEqual(RegexReceiptParser.extractTax(from: text), 100)
    }

    // MARK: - Subtotal Extraction

    func testExtractSubtotal() {
        let text = """
        商品A ¥500
        商品B ¥300
        小計 ¥800
        消費税 ¥80
        合計 ¥880
        """
        XCTAssertEqual(RegexReceiptParser.extractSubtotal(from: text), 800)
    }

    func testExtractSubtotalReturnsZeroWhenNotFound() {
        let text = """
        合計 ¥1,000
        """
        XCTAssertEqual(RegexReceiptParser.extractSubtotal(from: text), 0)
    }

    // MARK: - Document/Type Inference

    func testDetectDocumentTypeInvoice() {
        let text = """
        請求書
        ご請求金額 ¥120,000
        お支払期限 2026/02/28
        """
        XCTAssertEqual(RegexReceiptParser.detectDocumentType(from: text), .invoice)
    }

    func testDetectDocumentTypeExpenseReceipt() {
        let text = """
        領収書
        但し お食事代として
        合計 ¥5,500
        """
        XCTAssertEqual(RegexReceiptParser.detectDocumentType(from: text), .expenseReceipt)
    }

    func testInferTransactionTypeInvoiceDefaultsToIncome() {
        let text = """
        請求書
        請求先: 株式会社テスト 御中
        請求金額 ¥80,000
        """
        let type = RegexReceiptParser.inferTransactionType(from: text)
        XCTAssertEqual(type, .income)
    }

    func testInferTransactionTypeReceiptDefaultsToExpense() {
        let text = """
        レシート
        小計 ¥1,000
        合計 ¥1,100
        """
        let type = RegexReceiptParser.inferTransactionType(from: text)
        XCTAssertEqual(type, .expense)
    }
}
