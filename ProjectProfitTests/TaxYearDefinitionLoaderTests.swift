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

    func testIsSupportedYear() {
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2025))
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2026))
        XCTAssertFalse(TaxYearDefinitionLoader.isSupported(year: 1900))
    }

    func testIsSupportedYearByFormType() {
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2025, formType: .blueReturn))
        XCTAssertTrue(TaxYearDefinitionLoader.isSupported(year: 2025, formType: .whiteReturn))
        XCTAssertFalse(TaxYearDefinitionLoader.isSupported(year: 2026, formType: .blueReturn))
        XCTAssertFalse(TaxYearDefinitionLoader.isSupported(year: 1900, formType: .blueReturn))
    }

    func testSupportedYearsContains2025() {
        let years = TaxYearDefinitionLoader.supportedYears()
        XCTAssertTrue(years.contains(2025))
        XCTAssertTrue(years.contains(2026))
    }

    func testSupportedYearsByFormContains2025() {
        let years = TaxYearDefinitionLoader.supportedYears(formType: .whiteReturn)
        XCTAssertTrue(years.contains(2025))
        XCTAssertFalse(years.contains(2026))
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
        let targets: [ExportCoordinator.ExportTarget] = [
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
    }

    // MARK: - Coverage

    func testAllTaxLinesCovered_2025() {
        let uncovered = TaxYearDefinitionLoader.validateCoverage(for: 2025)
        XCTAssertTrue(uncovered.isEmpty, "All TaxLines should be covered in TaxYear2025.json. Missing: \(uncovered.map(\.rawValue))")
    }
}
