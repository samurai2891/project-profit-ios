import XCTest
@testable import ProjectProfit

final class TaxCodeTests: XCTestCase {
    func testResolveFromIdMapsToCanonicalCode() {
        XCTAssertEqual(TaxCode.resolve(id: TaxCode.standard10.rawValue), .standard10)
        XCTAssertEqual(TaxCode.resolve(id: TaxCode.reduced8.rawValue), .reduced8)
        XCTAssertNil(TaxCode.resolve(id: ""))
        XCTAssertNil(TaxCode.resolve(id: "INVALID"))
    }

    func testResolveFromLegacyCategoryMapsToCanonicalIds() {
        XCTAssertEqual(TaxCode.resolve(legacyCategory: .standardRate, taxRate: nil), .standard10)
        XCTAssertEqual(TaxCode.resolve(legacyCategory: .reducedRate, taxRate: nil), .reduced8)
        XCTAssertEqual(TaxCode.resolve(legacyCategory: .exempt, taxRate: nil), .exempt)
        XCTAssertEqual(TaxCode.resolve(legacyCategory: .nonTaxable, taxRate: nil), .nonTaxable)
    }

    func testResolveCompatibilityFallsBackToTaxRateWhenCategoryIsMissing() {
        XCTAssertEqual(
            TaxCode.resolveCompatibility(legacyCategory: nil, taxRate: 10),
            .standard10
        )
        XCTAssertEqual(
            TaxCode.resolveCompatibility(legacyCategory: nil, taxRate: 8),
            .reduced8
        )
        XCTAssertNil(TaxCode.resolveCompatibility(legacyCategory: nil, taxRate: 5))
    }

    func testRateBreakdownUsesTaxYearPackRates() {
        let pack = TaxYearPack(
            taxYear: 2025,
            version: "2025-v1",
            consumptionTaxStandardRate: Decimal(string: "0.10")!,
            consumptionTaxReducedRate: Decimal(string: "0.08")!,
            nationalRateStandard: Decimal(string: "0.078")!,
            localRateStandard: Decimal(string: "0.022")!,
            nationalRateReduced: Decimal(string: "0.0624")!,
            localRateReduced: Decimal(string: "0.0176")!
        )

        XCTAssertEqual(TaxCode.standard10.rateBreakdown(using: pack).totalRate, Decimal(string: "0.10"))
        XCTAssertEqual(TaxCode.reduced8.rateBreakdown(using: pack).nationalRate, Decimal(string: "0.0624"))
        XCTAssertEqual(TaxCode.exempt.rateBreakdown(using: pack).totalRate, 0)
    }
}
