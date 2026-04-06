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

    func testEtaxSupportStatusRows_returnsBundledYearsInOrder() {
        let rows = TaxYearDefinitionLoader.etaxSupportStatusRows()

        XCTAssertEqual(rows.map(\.fiscalYear), [2025, 2026])
    }

    func testEtaxSupportStatusRows_includeThreeFormStatuses() {
        let rows = TaxYearDefinitionLoader.etaxSupportStatusRows()
        let row2025 = rows.first { $0.fiscalYear == 2025 }
        let row2026 = rows.first { $0.fiscalYear == 2026 }

        XCTAssertEqual(row2025?.blueReturnSupported, true)
        XCTAssertEqual(row2025?.blueCashBasisSupported, true)
        XCTAssertEqual(row2025?.whiteReturnSupported, true)
        XCTAssertEqual(row2026?.blueReturnSupported, true)
        XCTAssertEqual(row2026?.blueCashBasisSupported, true)
        XCTAssertEqual(row2026?.whiteReturnSupported, true)
    }

    // MARK: - Excel Template Preparation

    func testLedgerTemplateAssetLocator_findsBSPLSampleTemplate() {
        let url = LedgerTemplateAssetLocator.url(for: .bsPlAnalysisSample, bundle: .main)

        XCTAssertNotNil(url, "BS/PL analysis template should be locatable for staged implementation work")
        XCTAssertEqual(url?.lastPathComponent, LedgerTemplateAsset.bsPlAnalysisSample.fileName)
    }

    func testLedgerTemplateAssetLocator_findsBalanceSheetTemplate() {
        let url = LedgerTemplateAssetLocator.url(for: .balanceSheet, bundle: .main)

        XCTAssertNotNil(url, "Balance sheet template should be locatable as a standalone workbook")
        XCTAssertEqual(url?.lastPathComponent, LedgerTemplateAsset.balanceSheet.fileName)
    }

    func testLedgerTemplateAssetLocator_findsProfitLossTemplate() {
        let url = LedgerTemplateAssetLocator.url(for: .profitLoss, bundle: .main)

        XCTAssertNotNil(url, "Profit and loss template should be locatable as a standalone workbook")
        XCTAssertEqual(url?.lastPathComponent, LedgerTemplateAsset.profitLoss.fileName)
    }

    func testLedgerTemplateAssetLocator_findsConsolidatedSpreadsheetSample() {
        let url = LedgerTemplateAssetLocator.url(for: .consolidatedSpreadsheetSample, bundle: .main)

        XCTAssertNotNil(url, "Consolidated spreadsheet template should be locatable for staged implementation work")
        XCTAssertEqual(url?.lastPathComponent, LedgerTemplateAsset.consolidatedSpreadsheetSample.fileName)
    }

    func testLedgerTemplateAssetLocator_findsTrialBalanceTemplate() {
        let url = LedgerTemplateAssetLocator.url(for: .trialBalance, bundle: .main)

        XCTAssertNotNil(url, "Trial balance template should be locatable as a standalone workbook")
        XCTAssertEqual(url?.lastPathComponent, LedgerTemplateAsset.trialBalance.fileName)
    }

    func testLedgerWorkbookTemplateDescriptor_mapsLedgersToStandaloneTemplateAssets() {
        let expectedAssets: [(LedgerType, LedgerTemplateAsset)] = [
            (.cashBook, .cashBook),
            (.cashBookInvoice, .cashBookInvoice),
            (.bankAccountBook, .bankAccountBook),
            (.bankAccountBookInvoice, .bankAccountBookInvoice),
            (.expenseBook, .expenseBook),
            (.expenseBookInvoice, .expenseBookInvoice),
            (.whiteTaxBookkeeping, .whiteTaxBookkeeping),
            (.whiteTaxBookkeepingInvoice, .whiteTaxBookkeepingInvoice),
            (.accountsReceivable, .accountsReceivable),
            (.accountsPayable, .accountsPayable),
            (.generalLedger, .generalLedger),
            (.generalLedgerInvoice, .generalLedgerInvoice),
            (.journal, .journal),
            (.fixedAssetRegister, .fixedAssetRegister),
            (.fixedAssetDepreciation, .fixedAssetDepreciation),
            (.transportationExpense, .transportationExpense)
        ]

        for (ledgerType, expectedAsset) in expectedAssets {
            let descriptor = LedgerExcelExportService.templateDescriptor(for: ledgerType)

            XCTAssertNotNil(descriptor, "\(ledgerType.rawValue) should resolve to a workbook template descriptor")
            XCTAssertEqual(descriptor?.asset, expectedAsset)
            XCTAssertFalse(descriptor?.formSheetName.isEmpty ?? true)
            XCTAssertFalse(descriptor?.worksheetName.isEmpty ?? true)
        }
    }

    func testLedgerWorkbookTemplateDescriptor_mapsTransportationTemplateSheet() {
        let descriptor = LedgerExcelExportService.templateDescriptor(for: .transportationExpense)

        XCTAssertEqual(descriptor?.asset, .transportationExpense)
        XCTAssertEqual(descriptor?.formSheetName, "L16_Travel_Form")
        XCTAssertEqual(descriptor?.worksheetName, "交通費精算書")
    }

    func testLedgerWorkbookTemplateDescriptor_carriesLayoutMetadataForExcelEnabledLedgers() {
        let excelEnabledLedgers: [LedgerType] = [
            .cashBook, .cashBookInvoice,
            .bankAccountBook, .bankAccountBookInvoice,
            .expenseBook, .expenseBookInvoice,
            .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice,
            .accountsReceivable, .accountsPayable,
            .generalLedger, .generalLedgerInvoice,
            .journal,
            .transportationExpense,
            .fixedAssetRegister,
            .fixedAssetDepreciation
        ]

        for ledgerType in excelEnabledLedgers {
            let descriptor = LedgerExcelExportService.templateDescriptor(for: ledgerType)

            XCTAssertNotNil(descriptor)
            XCTAssertFalse(descriptor?.columnHeaders.isEmpty ?? true, "\(ledgerType.rawValue) should define headers")
            XCTAssertEqual(descriptor?.columnHeaders.count, descriptor?.columnWidths.count)
            XCTAssertEqual(descriptor?.titleEndColumn, (descriptor?.columnHeaders.count ?? 1) - 1)
            XCTAssertFalse(descriptor?.auxiliarySheets.isEmpty ?? true)
            XCTAssertGreaterThan(descriptor?.dataStartRow ?? 0, descriptor?.headerRows.upperBound ?? 0)
        }
    }

    func testReportWorkbookTemplateDescriptor_carriesLayoutMetadataForReportExports() {
        let targets: [ReportWorkbookTemplateID] = [
            .profitLoss,
            .balanceSheet,
            .trialBalance,
            .journal,
            .ledger,
            .fixedAssets
        ]

        for target in targets {
            let descriptor = LedgerExcelExportService.reportTemplateDescriptor(for: target)

            XCTAssertNotNil(descriptor)
            XCTAssertFalse(descriptor?.columnHeaders.isEmpty ?? true, "\(target.rawValue) should define headers")
            XCTAssertEqual(descriptor?.columnHeaders.count, descriptor?.columnWidths.count)
            XCTAssertEqual(descriptor?.titleEndColumn, (descriptor?.columnHeaders.count ?? 1) - 1)
            XCTAssertFalse(descriptor?.auxiliarySheets.isEmpty ?? true)
            XCTAssertGreaterThan(descriptor?.dataStartRow ?? 0, descriptor?.headerRows.upperBound ?? 0)
        }
    }

    func testReportWorkbookTemplateDescriptor_matchesSingleYearBSPLTemplates() throws {
        let profitLoss = try XCTUnwrap(LedgerExcelExportService.reportTemplateDescriptor(for: .profitLoss))
        XCTAssertEqual(profitLoss.workbookTitle, "損益計算書")
        XCTAssertEqual(profitLoss.subtitle, "※ 単年度出力用。収入と費用を分けて表示。")
        XCTAssertEqual(profitLoss.columnHeaders, ["科目", "収入", "費用"])
        XCTAssertEqual(profitLoss.columnWidths, [34, 16, 16])
        XCTAssertEqual(profitLoss.headerRows, 3...3)
        XCTAssertEqual(profitLoss.dataStartRow, 4)

        let balanceSheet = try XCTUnwrap(LedgerExcelExportService.reportTemplateDescriptor(for: .balanceSheet))
        XCTAssertEqual(balanceSheet.workbookTitle, "貸借対照表")
        XCTAssertEqual(balanceSheet.subtitle, "※ 単年度出力用。資産の部と負債・純資産の部を左右に分けて表示。")
        XCTAssertEqual(balanceSheet.columnHeaders, ["資産の部", "金額", "", "負債・純資産の部", "金額"])
        XCTAssertEqual(balanceSheet.columnWidths, [28, 16, 4, 28, 16])
        XCTAssertEqual(balanceSheet.headerRows, 3...3)
        XCTAssertEqual(balanceSheet.dataStartRow, 4)
    }

    func testReportWorkbookTemplateDescriptor_mapsLedgerBackedReportTemplates() throws {
        let journal = try XCTUnwrap(LedgerExcelExportService.reportTemplateDescriptor(for: .journal))
        XCTAssertEqual(journal.asset, .journal)
        XCTAssertEqual(journal.headerRows, 8...8)
        XCTAssertEqual(journal.columnHeaders, ["月", "日", "借方科目", "借方金額", "貸方科目", "貸方金額", "摘要"])

        let ledger = try XCTUnwrap(LedgerExcelExportService.reportTemplateDescriptor(for: .ledger))
        XCTAssertEqual(ledger.asset, .generalLedger)
        XCTAssertEqual(ledger.headerRows, 9...9)
        XCTAssertEqual(ledger.columnHeaders, ["月", "日", "相手科目", "摘要", "借方", "貸方", "差引残高"])

        let fixedAssets = try XCTUnwrap(LedgerExcelExportService.reportTemplateDescriptor(for: .fixedAssets))
        XCTAssertEqual(fixedAssets.asset, .fixedAssetDepreciation)
        XCTAssertEqual(fixedAssets.headerRows, 8...8)
        XCTAssertEqual(fixedAssets.columnHeaders.count, 21)

        let trialBalance = try XCTUnwrap(LedgerExcelExportService.reportTemplateDescriptor(for: .trialBalance))
        XCTAssertEqual(trialBalance.asset, .trialBalance)
        XCTAssertEqual(trialBalance.headerRows, 8...8)
        XCTAssertEqual(trialBalance.dataStartRow, 9)
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
        XCTAssertEqual(pack.simplifiedDeemedPurchaseRates[2], Decimal(string: "0.80")!)
        XCTAssertEqual(pack.simplifiedDeemedPurchaseRates[6], Decimal(string: "0.40")!)
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
