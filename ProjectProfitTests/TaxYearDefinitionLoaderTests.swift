import XCTest
@testable import ProjectProfit

@MainActor
final class TaxYearDefinitionLoaderTests: XCTestCase {

    private struct FilingDefinitionFixture: Decodable {
        let filingDeadline: String
        let formId: String
        let formVer: String
        let rootTag: String
    }

    private struct LegacyTaxYearFixture: Decodable {
        struct FormFixture: Decodable {
            let formId: String
            let formVer: String
            let rootTag: String
        }

        let forms: [String: FormFixture]
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

    private func legacyFormDefinition(formKey: String, fiscalYear: Int) throws -> LegacyTaxYearFixture.FormFixture? {
        let baseURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = baseURL
            .appendingPathComponent("ProjectProfit/Resources/TaxYear\(fiscalYear).json")
        let data = try Data(contentsOf: fileURL)
        let definition = try JSONDecoder().decode(LegacyTaxYearFixture.self, from: data)
        return definition.forms[formKey]
    }

    private func legacyFormKeys(fiscalYear: Int) throws -> Set<String> {
        let baseURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileURL = baseURL
            .appendingPathComponent("ProjectProfit/Resources/TaxYear\(fiscalYear).json")
        let data = try Data(contentsOf: fileURL)
        let definition = try JSONDecoder().decode(LegacyTaxYearFixture.self, from: data)
        return Set(definition.forms.keys)
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
        XCTAssertNotNil(definition?.forms?["blue_cash_basis"])
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
        XCTAssertEqual(label, "売上（収入）金額")
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
        XCTAssertEqual(xmlTag, "AIG00060")
    }

    func testBlueCashBasisMetadata_2025UsesKOA230CurrentSpec() {
        let definition = TaxYearDefinitionLoader.loadDefinition(for: 2025)
        let form = definition?.forms?["blue_cash_basis"]

        XCTAssertEqual(form?.formId, "KOA230")
        XCTAssertEqual(form?.formVer, "10.0")
        XCTAssertEqual(form?.rootTag, "KOA230")
    }

    func testBlueCashBasisXmlTags_2025ArePresent() {
        XCTAssertEqual(
            TaxYearDefinitionLoader.xmlTag(for: "cash_basis_revenue", formType: .blueCashBasis, fiscalYear: 2025),
            "AOF00110"
        )
        XCTAssertEqual(
            TaxYearDefinitionLoader.xmlTag(for: "cash_basis_expense_total", formType: .blueCashBasis, fiscalYear: 2025),
            "AOF00200"
        )
        XCTAssertEqual(
            TaxYearDefinitionLoader.xmlTag(for: "cash_basis_income", formType: .blueCashBasis, fiscalYear: 2025),
            "AOF00290"
        )
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
        XCTAssertEqual(xmlTag, "AMB00040")
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

    func testPackSupportedForms_2025And2026MatchExpectedSet() {
        let expected: Set<String> = ["common", "blue_general", "blue_cash_basis", "white_shushi"]
        for year in [2025, 2026] {
            let definition = TaxYearDefinitionLoader.loadDefinition(for: year)
            let actual = Set(definition?.forms?.keys.map { $0 } ?? [])
            XCTAssertEqual(actual, expected, "supported form keys mismatch for \(year)")
        }
    }

    func testLegacyForms_2025And2026IncludePackMajorFormKeys() throws {
        let expected: Set<String> = ["common", "blue_general", "blue_cash_basis", "white_shushi"]

        for year in [2025, 2026] {
            let present = try legacyFormKeys(fiscalYear: year)
            XCTAssertTrue(present.isSuperset(of: expected), "legacy forms missing keys for \(year): \(expected.subtracting(present))")
        }
    }

    func testLegacyAndPackFormMetadataStayAlignedForBlueAndWhite_2025And2026() throws {
        let legacyComparableForms = ["blue_general", "white_shushi"]

        for year in [2025, 2026] {
            for formKey in legacyComparableForms {
                let fileName = "\(formKey).json"
                let pack = try filingDefinition(named: fileName, fiscalYear: year)
                let legacy = try legacyFormDefinition(formKey: formKey, fiscalYear: year)

                XCTAssertNotNil(legacy, "legacy form is missing for \(year):\(formKey)")
                XCTAssertEqual(legacy?.formId, pack.formId, "formId mismatch for \(year):\(formKey)")
                XCTAssertEqual(legacy?.formVer, pack.formVer, "formVer mismatch for \(year):\(formKey)")
                XCTAssertEqual(legacy?.rootTag, pack.rootTag, "rootTag mismatch for \(year):\(formKey)")
            }
        }
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

    func testFilingDeadline_2026FilingPacksAreMarch16() throws {
        let fileNames = [
            "common.json",
            "blue_general.json",
            "white_shushi.json",
            "blue_cash_basis.json"
        ]

        for fileName in fileNames {
            let definition = try filingDefinition(named: fileName, fiscalYear: 2026)
            XCTAssertEqual(definition.filingDeadline, "2027-03-16", "\(fileName) deadline should stay aligned for 2026 pack")
        }
    }

    func testProfileDeadlineAndFilingDeadlineStayConsistent_perTaxYear() async throws {
        let provider = BundledTaxYearPackProvider(bundle: .main)
        let filingFiles = ["common.json", "blue_general.json", "white_shushi.json", "blue_cash_basis.json"]

        for year in [2025, 2026] {
            let pack = try await provider.pack(for: year)
            let expectedDeadline = String(
                format: "%04d-%02d-%02d",
                locale: Locale(identifier: "en_US_POSIX"),
                year + 1,
                pack.filingDeadlineMonth,
                pack.filingDeadlineDay
            )

            for fileName in filingFiles {
                let definition = try filingDefinition(named: fileName, fiscalYear: year)
                XCTAssertEqual(
                    definition.filingDeadline,
                    expectedDeadline,
                    "profile/filling deadline mismatch for \(year):\(fileName)"
                )
            }
        }
    }

    // MARK: - 2026 Pack-based Definition

    func testLoadDefinition_2026ReturnsNonNil() {
        let definition = TaxYearDefinitionLoader.loadDefinition(for: 2026)
        XCTAssertNotNil(definition, "2026 filing pack definition should be loadable")
        XCTAssertEqual(definition?.fiscalYear, 2026)
        XCTAssertNotNil(definition?.forms?["common"])
        XCTAssertNotNil(definition?.forms?["blue_general"])
        XCTAssertNotNil(definition?.forms?["blue_cash_basis"])
        XCTAssertNotNil(definition?.forms?["white_shushi"])
    }

    func testBlueCashBasisMetadata_2026UsesKOA230CurrentSpec() {
        let definition = TaxYearDefinitionLoader.loadDefinition(for: 2026)
        let form = definition?.forms?["blue_cash_basis"]

        XCTAssertEqual(form?.formId, "KOA230")
        XCTAssertEqual(form?.formVer, "10.0")
        XCTAssertEqual(form?.rootTag, "KOA230")
    }

    func testBlueCashBasisXmlTags_2026ArePresent() {
        XCTAssertEqual(
            TaxYearDefinitionLoader.xmlTag(for: "cash_basis_revenue", formType: .blueCashBasis, fiscalYear: 2026),
            "AOF00110"
        )
        XCTAssertEqual(
            TaxYearDefinitionLoader.xmlTag(for: "cash_basis_expense_total", formType: .blueCashBasis, fiscalYear: 2026),
            "AOF00200"
        )
        XCTAssertEqual(
            TaxYearDefinitionLoader.xmlTag(for: "cash_basis_income", formType: .blueCashBasis, fiscalYear: 2026),
            "AOF00290"
        )
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
        XCTAssertEqual(label, "売上（収入）金額")
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

    func testPackCoverage_2025IncludesBlueCashBasisAndBuilderCoverage() {
        let report = TaxYearDefinitionLoader.validatePackCoverage(for: 2025)

        XCTAssertTrue(report.missingForms.isEmpty, "Missing forms: \(report.missingForms)")
        XCTAssertTrue(report.missingPackKeysByForm["blue_cash_basis", default: []].isEmpty)
        XCTAssertTrue(report.unresolvedBuilderKeysByForm["blue_cash_basis", default: []].isEmpty)
    }

    func testPackCoverage_2025WhitePage2AndRequiredRulesArePresent() {
        let report = TaxYearDefinitionLoader.validatePackCoverage(for: 2025)

        XCTAssertTrue(report.whitePage2MissingKeys.isEmpty, "Missing white page2 keys: \(report.whitePage2MissingKeys)")
        XCTAssertTrue(report.missingRequiredRulesByForm["white_shushi", default: []].isEmpty)
        XCTAssertTrue(report.whiteLeafOnlyMappingViolations.isEmpty, "Leaf-only mapping violations: \(report.whiteLeafOnlyMappingViolations)")
        XCTAssertTrue(report.unresolvedBuilderKeysByForm["white_shushi", default: []].isEmpty)
    }

    func testPackCoverage_2026RemainsClean() {
        let report = TaxYearDefinitionLoader.validatePackCoverage(for: 2026)

        XCTAssertTrue(report.isClean, """
        missingForms=\(report.missingForms)
        missingPackKeys=\(report.missingPackKeysByForm)
        unresolvedBuilderKeys=\(report.unresolvedBuilderKeysByForm)
        missingRequiredRules=\(report.missingRequiredRulesByForm)
        whitePage2MissingKeys=\(report.whitePage2MissingKeys)
        whiteLeafOnlyMappingViolations=\(report.whiteLeafOnlyMappingViolations)
        """)
    }
}
