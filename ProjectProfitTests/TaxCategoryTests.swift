import XCTest
@testable import ProjectProfit

final class TaxCategoryTests: XCTestCase {

    // MARK: - Cases

    func testAllCasesExist() {
        let allCases = TaxCategory.allCases
        XCTAssertTrue(allCases.contains(.standardRate))
        XCTAssertTrue(allCases.contains(.reducedRate))
        XCTAssertTrue(allCases.contains(.exempt))
        XCTAssertTrue(allCases.contains(.nonTaxable))
    }

    func testCaseIterableCount() {
        XCTAssertEqual(TaxCategory.allCases.count, 4)
    }

    // MARK: - Label

    func testLabelStandardRate() {
        XCTAssertEqual(TaxCategory.standardRate.label, "課税（10%）")
    }

    func testLabelReducedRate() {
        XCTAssertEqual(TaxCategory.reducedRate.label, "軽減税率（8%）")
    }

    func testLabelExempt() {
        XCTAssertEqual(TaxCategory.exempt.label, "非課税")
    }

    func testLabelNonTaxable() {
        XCTAssertEqual(TaxCategory.nonTaxable.label, "不課税")
    }

    // MARK: - Rate

    func testRateStandardRate() {
        XCTAssertEqual(TaxCategory.standardRate.rate, 10)
    }

    func testRateReducedRate() {
        XCTAssertEqual(TaxCategory.reducedRate.rate, 8)
    }

    func testRateExempt() {
        XCTAssertEqual(TaxCategory.exempt.rate, 0)
    }

    func testRateNonTaxable() {
        XCTAssertEqual(TaxCategory.nonTaxable.rate, 0)
    }

    // MARK: - IsTaxable

    func testIsTaxableStandardRate() {
        XCTAssertTrue(TaxCategory.standardRate.isTaxable)
    }

    func testIsTaxableReducedRate() {
        XCTAssertTrue(TaxCategory.reducedRate.isTaxable)
    }

    func testIsTaxableExempt() {
        XCTAssertFalse(TaxCategory.exempt.isTaxable)
    }

    func testIsTaxableNonTaxable() {
        XCTAssertFalse(TaxCategory.nonTaxable.isTaxable)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for category in TaxCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(TaxCategory.self, from: data)
            XCTAssertEqual(decoded, category)
        }
    }

    func testDecodingFromRawString() throws {
        let decoder = JSONDecoder()

        let standardData = Data("\"standardRate\"".utf8)
        XCTAssertEqual(try decoder.decode(TaxCategory.self, from: standardData), .standardRate)

        let reducedData = Data("\"reducedRate\"".utf8)
        XCTAssertEqual(try decoder.decode(TaxCategory.self, from: reducedData), .reducedRate)

        let exemptData = Data("\"exempt\"".utf8)
        XCTAssertEqual(try decoder.decode(TaxCategory.self, from: exemptData), .exempt)

        let nonTaxableData = Data("\"nonTaxable\"".utf8)
        XCTAssertEqual(try decoder.decode(TaxCategory.self, from: nonTaxableData), .nonTaxable)
    }

    func testDecodingInvalidRawValueFails() {
        let decoder = JSONDecoder()
        let invalidData = Data("\"unknown\"".utf8)
        XCTAssertThrowsError(try decoder.decode(TaxCategory.self, from: invalidData))
    }
}
