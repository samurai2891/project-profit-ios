import XCTest
@testable import ProjectProfit

final class WithholdingTaxCalculatorTests: XCTestCase {

    // MARK: - 基本計算テスト

    func testZeroAmountReturnsZeroTax() {
        let result = WithholdingTaxCalculator.calculate(grossAmount: 0, code: .designFee)
        XCTAssertEqual(result.withholdingAmount, 0)
        XCTAssertEqual(result.netAmount, 0)
        XCTAssertEqual(result.appliedRate, 0)
        XCTAssertFalse(result.isOverThreshold)
    }

    func testNegativeAmountReturnsZeroTax() {
        let result = WithholdingTaxCalculator.calculate(grossAmount: -100_000, code: .designFee)
        XCTAssertEqual(result.withholdingAmount, 0)
        XCTAssertEqual(result.netAmount, -100_000)
        XCTAssertFalse(result.isOverThreshold)
    }

    // MARK: - 100万円以下（標準税率 10.21%）

    func testStandardRateForSmallAmount() {
        // 100,000円 × 10.21% = 10,210円
        let result = WithholdingTaxCalculator.calculate(grossAmount: 100_000, code: .designFee)
        XCTAssertEqual(result.withholdingAmount, Decimal(10_210))
        XCTAssertEqual(result.netAmount, Decimal(89_790))
        XCTAssertFalse(result.isOverThreshold)
    }

    func testStandardRateAt1Million() {
        // 1,000,000円 × 10.21% = 102,100円（ちょうど100万は超過なし）
        let result = WithholdingTaxCalculator.calculate(grossAmount: 1_000_000, code: .writingFee)
        XCTAssertEqual(result.withholdingAmount, Decimal(102_100))
        XCTAssertEqual(result.netAmount, Decimal(897_900))
        XCTAssertFalse(result.isOverThreshold)
    }

    func testStandardRateWithFractionRoundsDown() {
        // 333,333円 × 10.21% = 34,033.3093 → 切捨て = 34,033円
        let result = WithholdingTaxCalculator.calculate(grossAmount: 333_333, code: .lectureFee)
        XCTAssertEqual(result.withholdingAmount, Decimal(34_033))
        XCTAssertEqual(result.netAmount, Decimal(299_300))
    }

    // MARK: - 100万円超過（20.42%）

    func testExcessRateOver1Million() {
        // 2,000,000円:
        //   100万以下: 1,000,000 × 10.21% = 102,100
        //   100万超過: 1,000,000 × 20.42% = 204,200
        //   合計: 306,300
        let result = WithholdingTaxCalculator.calculate(grossAmount: 2_000_000, code: .professionalFee)
        XCTAssertEqual(result.withholdingAmount, Decimal(306_300))
        XCTAssertEqual(result.netAmount, Decimal(1_693_700))
        XCTAssertTrue(result.isOverThreshold)
    }

    func testExcessRateJustOver1Million() {
        // 1,000,001円:
        //   100万以下: 1,000,000 × 10.21% = 102,100
        //   超過分: 1 × 20.42% = 0.2042 → 切捨て = 0
        //   合計: 102,100
        let result = WithholdingTaxCalculator.calculate(grossAmount: 1_000_001, code: .designFee)
        XCTAssertEqual(result.withholdingAmount, Decimal(102_100))
        XCTAssertTrue(result.isOverThreshold)
    }

    func testExcessRateWithFractionRoundsDown() {
        // 1,500,000円:
        //   100万以下: 1,000,000 × 10.21% = 102,100
        //   超過分: 500,000 × 20.42% = 102,100
        //   合計: 204,200
        let result = WithholdingTaxCalculator.calculate(grossAmount: 1_500_000, code: .performanceFee)
        XCTAssertEqual(result.withholdingAmount, Decimal(204_200))
        XCTAssertEqual(result.netAmount, Decimal(1_295_800))
        XCTAssertTrue(result.isOverThreshold)
    }

    // MARK: - 全区分コードの税率が同一であることの確認

    func testAllCodesHaveSameRates() {
        let amount = Decimal(500_000)
        let referenceResult = WithholdingTaxCalculator.calculate(grossAmount: amount, code: .designFee)

        for code in WithholdingTaxCode.allCases {
            let result = WithholdingTaxCalculator.calculate(grossAmount: amount, code: code)
            XCTAssertEqual(
                result.withholdingAmount,
                referenceResult.withholdingAmount,
                "\(code.displayName) の税額が基準と異なります"
            )
        }
    }

    // MARK: - 手取り額からの逆算

    func testGrossFromNetUnderThreshold() {
        // 手取り 89,790円 → 支払総額 100,000円
        let gross = WithholdingTaxCalculator.grossFromNet(netAmount: 89_790, code: .designFee)
        let verify = WithholdingTaxCalculator.calculate(grossAmount: gross, code: .designFee)
        XCTAssertTrue(verify.netAmount >= 89_790, "逆算した支払総額から源泉徴収後の手取りが元の手取り以上であること")
    }

    func testGrossFromNetOverThreshold() {
        // 手取り 1,693,700円 → 支払総額 2,000,000円
        let gross = WithholdingTaxCalculator.grossFromNet(netAmount: 1_693_700, code: .designFee)
        let verify = WithholdingTaxCalculator.calculate(grossAmount: gross, code: .designFee)
        XCTAssertTrue(verify.netAmount >= 1_693_700, "逆算した支払総額から源泉徴収後の手取りが元の手取り以上であること")
    }

    func testGrossFromNetZero() {
        let gross = WithholdingTaxCalculator.grossFromNet(netAmount: 0, code: .writingFee)
        XCTAssertEqual(gross, 0)
    }

    func testGrossFromNetNegative() {
        let gross = WithholdingTaxCalculator.grossFromNet(netAmount: -50_000, code: .writingFee)
        XCTAssertEqual(gross, -50_000)
    }

    // MARK: - WithholdingTaxResult の等値性

    func testResultEquality() {
        let result1 = WithholdingTaxCalculator.calculate(grossAmount: 100_000, code: .designFee)
        let result2 = WithholdingTaxCalculator.calculate(grossAmount: 100_000, code: .designFee)
        XCTAssertEqual(result1, result2)
    }

    // MARK: - WithholdingTaxCode プロパティテスト

    func testWithholdingTaxCodeDisplayNames() {
        XCTAssertEqual(WithholdingTaxCode.designFee.displayName, "デザイン料")
        XCTAssertEqual(WithholdingTaxCode.writingFee.displayName, "原稿料・執筆料")
        XCTAssertEqual(WithholdingTaxCode.lectureFee.displayName, "講演料")
        XCTAssertEqual(WithholdingTaxCode.professionalFee.displayName, "弁護士・税理士等報酬")
        XCTAssertEqual(WithholdingTaxCode.performanceFee.displayName, "芸能・スポーツ等報酬")
        XCTAssertEqual(WithholdingTaxCode.other.displayName, "その他報酬・料金")
    }

    func testWithholdingTaxCodeResolve() {
        XCTAssertEqual(WithholdingTaxCode.resolve(id: "WH-DESIGN"), .designFee)
        XCTAssertEqual(WithholdingTaxCode.resolve(id: "WH-WRITING"), .writingFee)
        XCTAssertNil(WithholdingTaxCode.resolve(id: nil))
        XCTAssertNil(WithholdingTaxCode.resolve(id: ""))
        XCTAssertNil(WithholdingTaxCode.resolve(id: "INVALID"))
    }

    func testWithholdingTaxCodeRawValues() {
        XCTAssertEqual(WithholdingTaxCode.designFee.rawValue, "WH-DESIGN")
        XCTAssertEqual(WithholdingTaxCode.writingFee.rawValue, "WH-WRITING")
        XCTAssertEqual(WithholdingTaxCode.lectureFee.rawValue, "WH-LECTURE")
        XCTAssertEqual(WithholdingTaxCode.professionalFee.rawValue, "WH-PROFESSIONAL")
        XCTAssertEqual(WithholdingTaxCode.performanceFee.rawValue, "WH-PERFORMANCE")
        XCTAssertEqual(WithholdingTaxCode.other.rawValue, "WH-OTHER")
    }

    func testWithholdingTaxCodeThreshold() {
        for code in WithholdingTaxCode.allCases {
            XCTAssertEqual(code.threshold, Decimal(1_000_000), "\(code.displayName) の基準額が100万円であること")
        }
    }

    func testWithholdingTaxCodeStandardRate() {
        for code in WithholdingTaxCode.allCases {
            XCTAssertEqual(code.standardRate, Decimal(string: "0.1021")!, "\(code.displayName) の標準税率が10.21%であること")
        }
    }

    func testWithholdingTaxCodeExcessRate() {
        for code in WithholdingTaxCode.allCases {
            XCTAssertEqual(code.excessRate, Decimal(string: "0.2042")!, "\(code.displayName) の超過税率が20.42%であること")
        }
    }

    // MARK: - PayeeInfo テスト

    func testPayeeInfoDefaults() {
        let info = PayeeInfo()
        XCTAssertFalse(info.isWithholdingSubject)
        XCTAssertNil(info.withholdingCategory)
    }

    func testPayeeInfoUpdated() {
        let original = PayeeInfo()
        let updated = original.updated(
            isWithholdingSubject: true,
            withholdingCategory: .designFee
        )
        XCTAssertTrue(updated.isWithholdingSubject)
        XCTAssertEqual(updated.withholdingCategory, .designFee)
        // original は変更されないこと（イミュータブル）
        XCTAssertFalse(original.isWithholdingSubject)
        XCTAssertNil(original.withholdingCategory)
    }

    func testPayeeInfoPartialUpdate() {
        let original = PayeeInfo(isWithholdingSubject: true, withholdingCategory: .designFee)
        let updated = original.updated(withholdingCategory: .writingFee)
        XCTAssertTrue(updated.isWithholdingSubject) // 変更なし
        XCTAssertEqual(updated.withholdingCategory, .writingFee)
    }

    func testPayeeInfoClearCategory() {
        let original = PayeeInfo(isWithholdingSubject: true, withholdingCategory: .designFee)
        let updated = original.updated(withholdingCategory: .some(nil))
        XCTAssertTrue(updated.isWithholdingSubject)
        XCTAssertNil(updated.withholdingCategory)
    }

    // MARK: - WithholdingTaxResult Codable テスト

    func testResultCodable() throws {
        let result = WithholdingTaxCalculator.calculate(grossAmount: 500_000, code: .designFee)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(WithholdingTaxResult.self, from: data)
        XCTAssertEqual(result, decoded)
    }
}
