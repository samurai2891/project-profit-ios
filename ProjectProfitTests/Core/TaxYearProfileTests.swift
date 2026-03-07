import XCTest
@testable import ProjectProfit

final class TaxYearProfileTests: XCTestCase {

    private let businessId = UUID()

    // MARK: - 生成テスト

    func testBlueGeneral65万() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            filingStyle: .blueGeneral,
            blueDeductionLevel: .sixtyFive,
            bookkeepingBasis: .doubleEntry
        )
        XCTAssertTrue(profile.isBlueReturn)
        XCTAssertEqual(profile.blueDeductionLevel.amount, 650000)
        XCTAssertEqual(profile.filingStyle, .blueGeneral)
    }

    func testBlueGeneral55万() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            filingStyle: .blueGeneral,
            blueDeductionLevel: .fiftyFive,
            bookkeepingBasis: .doubleEntry
        )
        XCTAssertTrue(profile.isBlueReturn)
        XCTAssertEqual(profile.blueDeductionLevel.amount, 550000)
    }

    func testBlueGeneral10万() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            filingStyle: .blueGeneral,
            blueDeductionLevel: .ten,
            bookkeepingBasis: .singleEntry
        )
        XCTAssertTrue(profile.isBlueReturn)
        XCTAssertEqual(profile.blueDeductionLevel.amount, 100000)
    }

    func testBlueCashBasis() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            filingStyle: .blueCashBasis,
            blueDeductionLevel: .ten,
            bookkeepingBasis: .cashBasis
        )
        XCTAssertTrue(profile.isBlueReturn)
        XCTAssertEqual(profile.filingStyle, .blueCashBasis)
    }

    func testWhiteReturn() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            filingStyle: .white,
            blueDeductionLevel: .none,
            bookkeepingBasis: .singleEntry
        )
        XCTAssertFalse(profile.isBlueReturn)
        XCTAssertEqual(profile.blueDeductionLevel.amount, 0)
    }

    // MARK: - 消費税ステータス

    func testExemptBusiness() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .exempt
        )
        XCTAssertFalse(profile.isTaxable)
        XCTAssertFalse(profile.isSimplifiedTaxation)
        XCTAssertFalse(profile.isTwoTenthsSpecial)
    }

    func testTaxableGeneral() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .taxable,
            vatMethod: .general
        )
        XCTAssertTrue(profile.isTaxable)
        XCTAssertFalse(profile.isSimplifiedTaxation)
    }

    func testSimplifiedTaxation() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .taxable,
            vatMethod: .simplified,
            simplifiedBusinessCategory: 5
        )
        XCTAssertTrue(profile.isTaxable)
        XCTAssertTrue(profile.isSimplifiedTaxation)
    }

    func testTwoTenthsSpecial() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .taxable,
            vatMethod: .twoTenths
        )
        XCTAssertTrue(profile.isTwoTenthsSpecial)
    }

    // MARK: - イミュータブル更新

    func testImmutableUpdate() {
        let original = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            filingStyle: .white,
            blueDeductionLevel: .none
        )

        let updated = original.updated(
            filingStyle: .blueGeneral,
            blueDeductionLevel: .sixtyFive
        )

        // 元のオブジェクトは変更されない
        XCTAssertEqual(original.filingStyle, .white)
        XCTAssertEqual(original.blueDeductionLevel, .none)

        // 新しいオブジェクトに変更が反映
        XCTAssertEqual(updated.filingStyle, .blueGeneral)
        XCTAssertEqual(updated.blueDeductionLevel, .sixtyFive)

        // IDは同一
        XCTAssertEqual(original.id, updated.id)
    }
}
