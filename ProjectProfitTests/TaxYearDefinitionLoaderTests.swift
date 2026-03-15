import XCTest
@testable import ProjectProfit

@MainActor
final class TaxYearDefinitionLoaderTests: XCTestCase {

    private struct FilingDefinitionFixture: Decodable {
        let filingDeadline: String
    }

    private func filingDefinition(named fileName: String, fiscalYear: Int = 2025) throws -> FilingDefinitionFixture {
        let baseURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = baseURL
            .appendingPathComponent("ProjectProfit/Resources/TaxYearPacks/\(fiscalYear)/filing", isDirectory: true)
            .appendingPathComponent(fileName)
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(FilingDefinitionFixture.self, from: data)
    }

    override func setUp() {
        super.setUp()
        TaxYearDefinitionLoader.clearCache()
    }

    override func tearDown() {
        TaxYearDefinitionLoader.clearCache()
        super.tearDown()
    }

    // MARK: - Pack Loading

    func testLoadDefinition_2025ReturnsNonNil() {
        let definition = TaxYearDefinitionLoader.loadDefinition(for: 2025)
        XCTAssertNotNil(definition, "2025 filing pack should be loadable from bundle")
        XCTAssertEqual(definition?.fiscalYear, 2025)
        XCTAssertNotNil(definition?.forms?["common"])
        XCTAssertNotNil(definition?.forms?["blue_general"])
        XCTAssertNotNil(definition?.forms?["white_shushi"])
    }

    func testLoadDefinition_unknownYearReturnsNil() {
        let definition = TaxYearDefinitionLoader.loadDefinition(for: 1900)
        XCTAssertNil(definition, "Unknown year should return nil")
    }

    // MARK: - Field Label

    func testFieldLabel_returnsPackLabel() {
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

    func testXmlTag_whiteTaxesTagIsCurrentSpec() {
        let xmlTag = TaxYearDefinitionLoader.xmlTag(for: "shushi_expense_taxes", formType: .whiteReturn, fiscalYear: 2025)
        XCTAssertEqual(xmlTag, "AIG00220")
    }

    func testXmlTag_blueInsuranceTagIsCurrentSpec() {
        let xmlTag = TaxYearDefinitionLoader.xmlTag(for: "expense_insurance", formType: .blueReturn, fiscalYear: 2025)
        XCTAssertEqual(xmlTag, "AMF00260")
    }

    func testXmlTag_whiteInsuranceTagIsCurrentSpec() {
        let xmlTag = TaxYearDefinitionLoader.xmlTag(for: "shushi_expense_insurance", formType: .whiteReturn, fiscalYear: 2025)
        XCTAssertEqual(xmlTag, "AIG00290")
    }

    func testXmlTag_commonDeclarantFieldComesFromPack() {
        let xmlTag = TaxYearDefinitionLoader.xmlTag(for: "declarant_name", formType: .blueReturn, fiscalYear: 2025)
        XCTAssertEqual(xmlTag, "ABA00140")
    }

    func testIsSupportedYear() {
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2025))
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2026))
        XCTAssertFalse(TaxYearDefinitionLoader.isSupported(year: 1900))
    }

    func testIsSupportedYearByFormType() {
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2025, formType: .blueReturn))
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2025, formType: .whiteReturn))
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2026, formType: .blueReturn))
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2026, formType: .whiteReturn))
        XCTAssertFalse(TaxYearDefinitionLoader.isSupported(year: 1900, formType: .blueReturn))
    }

    func testSupportedYearsContains2025() {
        let years = TaxYearDefinitionLoader.supportedYears()
        XCTAssertTrue(years.contains(2025))
        XCTAssertTrue(years.contains(2026))
    }

    func testSupportedYearsByFormContains2025And2026() {
        let years = TaxYearDefinitionLoader.supportedYears(formType: .whiteReturn)
        XCTAssertTrue(years.contains(2025))
        XCTAssertTrue(years.contains(2026))
    }

    // MARK: - TaxYearPack Bridge

    func testTaxYearPackProvider_availableYearsIncludes2026() async {
        let provider = BundledTaxYearPackProvider(bundle: .main)
        let years = await provider.availableYears()

        XCTAssertTrue(years.contains(2025))
        XCTAssertTrue(years.contains(2026))
    }

    func testTaxYearPackProvider_packFor2026LoadsProfile() async throws {
        let provider = BundledTaxYearPackProvider(bundle: .main)
        let pack = try await provider.pack(for: 2026)

        XCTAssertEqual(pack.taxYear, 2026)
        XCTAssertEqual(pack.version, "2026-v1")
        XCTAssertEqual(pack.transitionalMeasures.count, 2)
        XCTAssertEqual(pack.transitionalMeasures.first?.id, "transitional_80")
        XCTAssertEqual(pack.transitionalMeasures.last?.id, "transitional_50")
    }

    func testFilingDeadline_2025FilingPacksAreMarch16() throws {
        let fileNames = [
            "common.json",
            "blue_general.json",
            "white_shushi.json",
            "blue_cash_basis.json"
        ]

        for fileName in fileNames {
            let definition = try filingDefinition(named: fileName)
            XCTAssertEqual(definition.filingDeadline, "2026-03-16", "\(fileName) deadline should match the release task document")
        }
    }

    // MARK: - 2026 Pack-based Definition

    func testLoadDefinition_2026ReturnsNonNil() {
        let definition = TaxYearDefinitionLoader.loadDefinition(for: 2026)
        XCTAssertNotNil(definition, "2026 filing pack definition should be loadable")
        XCTAssertEqual(definition?.fiscalYear, 2026)
        XCTAssertNotNil(definition?.forms?["common"])
        XCTAssertNotNil(definition?.forms?["blue_general"])
        XCTAssertNotNil(definition?.forms?["white_shushi"])
    }

    func testFieldLabel_2026_blueReturnSalesRevenue() {
        let label = TaxYearDefinitionLoader.fieldLabel(
            for: .salesRevenue, formType: .blueReturn, fiscalYear: 2026
        )
        XCTAssertEqual(label, "ア 売上（収入）金額")
    }

    func testFieldLabel_2026_whiteReturnSalesRevenue() {
        let label = TaxYearDefinitionLoader.fieldLabel(
            for: .salesRevenue, formType: .whiteReturn, fiscalYear: 2026
        )
        XCTAssertEqual(label, "収入金額")
    }

    func testXmlTag_2026_blueReturnSalesRevenue() {
        let xmlTag = TaxYearDefinitionLoader.xmlTag(
            for: "revenue_sales_revenue", formType: .blueReturn, fiscalYear: 2026
        )
        XCTAssertEqual(xmlTag, "AMF00100")
    }

    func testXmlTag_2026_whiteReturnExpenseTaxes() {
        let xmlTag = TaxYearDefinitionLoader.xmlTag(
            for: "shushi_expense_taxes", formType: .whiteReturn, fiscalYear: 2026
        )
        XCTAssertEqual(xmlTag, "AIG00220")
    }

    func testFilingDeadline_2026IsMarch16() async throws {
        let provider = BundledTaxYearPackProvider(bundle: .main)
        let pack = try await provider.pack(for: 2026)
        XCTAssertEqual(pack.filingDeadlineMonth, 3)
        XCTAssertEqual(pack.filingDeadlineDay, 16)
    }

    // MARK: - Coverage

    func testAllTaxLinesCovered_2025() {
        let uncovered = TaxYearDefinitionLoader.validateCoverage(for: 2025)
        XCTAssertTrue(uncovered.isEmpty, "All TaxLines should be covered in the 2025 filing pack. Missing: \(uncovered.map(\.rawValue))")
    }

    func testAllTaxLinesCovered_2026() {
        let uncovered = TaxYearDefinitionLoader.validateCoverage(for: 2026)
        XCTAssertTrue(uncovered.isEmpty, "All TaxLines should be covered in the 2026 filing pack. Missing: \(uncovered.map(\.rawValue))")
    }
}
