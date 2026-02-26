import XCTest
@testable import ProjectProfit

@MainActor
final class TaxYearDefinitionLoaderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TaxYearDefinitionLoader.clearCache()
    }

    override func tearDown() {
        TaxYearDefinitionLoader.clearCache()
        super.tearDown()
    }

    // MARK: - JSON Loading

    func testLoadDefinition_2025ReturnsNonNil() {
        let definition = TaxYearDefinitionLoader.loadDefinition(for: 2025)
        XCTAssertNotNil(definition, "TaxYear2025.json should be loadable from bundle")
        XCTAssertEqual(definition?.fiscalYear, 2025)
        XCTAssertNotNil(definition?.forms?["blue_general"])
        XCTAssertNotNil(definition?.forms?["white_shushi"])
    }

    func testLoadDefinition_unknownYearReturnsNil() {
        let definition = TaxYearDefinitionLoader.loadDefinition(for: 1900)
        XCTAssertNil(definition, "Unknown year should return nil")
    }

    // MARK: - Field Label

    func testFieldLabel_returnsJsonLabel() {
        let label = TaxYearDefinitionLoader.fieldLabel(for: .salesRevenue, formType: .blueReturn, fiscalYear: 2025)
        XCTAssertEqual(label, "ア 売上（収入）金額")
    }

    func testFieldLabel_whiteReturnReturnsWhiteLabel() {
        let label = TaxYearDefinitionLoader.fieldLabel(for: .salesRevenue, formType: .whiteReturn, fiscalYear: 2025)
        XCTAssertEqual(label, "収入金額")
    }

    func testFieldLabel_fallbackForUnknownYear() {
        let label = TaxYearDefinitionLoader.fieldLabel(for: .salesRevenue, fiscalYear: 1900)
        XCTAssertEqual(label, TaxLine.salesRevenue.label, "Should fall back to TaxLine.label for unknown year")
    }

    func testXmlTag_returnsMappedTag() {
        let xmlTag = TaxYearDefinitionLoader.xmlTag(for: "revenue_sales_revenue", formType: .blueReturn, fiscalYear: 2025)
        XCTAssertEqual(xmlTag, "AMF00100")
    }

    func testXmlTag_whiteTag() {
        let xmlTag = TaxYearDefinitionLoader.xmlTag(for: "shushi_revenue_total", formType: .whiteReturn, fiscalYear: 2025)
        XCTAssertEqual(xmlTag, "AIG00020")
    }

    func testIsSupportedYear() {
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2025))
        XCTAssertFalse(TaxYearDefinitionLoader.isSupported(year: 1900))
    }

    func testIsSupportedYearByFormType() {
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2025, formType: .blueReturn))
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2025, formType: .whiteReturn))
        XCTAssertFalse(TaxYearDefinitionLoader.isSupported(year: 1900, formType: .blueReturn))
    }

    func testSupportedYearsContains2025() {
        let years = TaxYearDefinitionLoader.supportedYears()
        XCTAssertTrue(years.contains(2025))
    }

    func testSupportedYearsByFormContains2025() {
        let years = TaxYearDefinitionLoader.supportedYears(formType: .whiteReturn)
        XCTAssertTrue(years.contains(2025))
    }

    // MARK: - Coverage

    func testAllTaxLinesCovered_2025() {
        let uncovered = TaxYearDefinitionLoader.validateCoverage(for: 2025)
        XCTAssertTrue(uncovered.isEmpty, "All TaxLines should be covered in TaxYear2025.json. Missing: \(uncovered.map(\.rawValue))")
    }
}
