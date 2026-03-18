import XCTest
@testable import ProjectProfit

final class EtaxXtxExporterTests: XCTestCase {

    private let blueXsdPath = "/Users/yutaro/project-profit-ios-local/e-taxall/19XMLスキーマ/shotoku/KOA210-011.xsd"
    private let cashBasisXsdPath = "/Users/yutaro/project-profit-ios-local/e-taxall/19XMLスキーマ/shotoku/KOA230-010.xsd"
    private let whiteXsdPath = "/Users/yutaro/project-profit-ios-local/e-taxall/19XMLスキーマ/shotoku/KOA110-012.xsd"

    private func makeForm(
        fields: [EtaxField] = [],
        formType: EtaxFormType = .blueReturn
    ) -> EtaxForm {
        EtaxForm(
            fiscalYear: 2025,
            formType: formType,
            fields: fields,
            generatedAt: Date()
        )
    }

    private func sampleFields() -> [EtaxField] {
        [
            EtaxField(id: "revenue_sales_revenue", fieldLabel: "売上（収入）金額", taxLine: .salesRevenue, value: 5_000_000, section: .revenue),
            EtaxField(id: "expense_communication", fieldLabel: "通信費", taxLine: .communicationExpense, value: 120_000, section: .expenses),
            EtaxField(id: "expense_travel", fieldLabel: "旅費交通費", taxLine: .travelExpense, value: 80_000, section: .expenses),
            EtaxField(id: "expense_insurance", fieldLabel: "損害保険料", taxLine: .insuranceExpense, value: 60_000, section: .expenses),
            EtaxField(id: "income_total_revenue", fieldLabel: "収入金額合計", taxLine: nil, value: 5_000_000, section: .income),
            EtaxField(id: "income_total_expenses", fieldLabel: "必要経費合計", taxLine: nil, value: 260_000, section: .income),
            EtaxField(id: "income_net", fieldLabel: "所得金額", taxLine: nil, value: 4_740_000, section: .income),
        ]
    }

    private func sampleBlueBalanceSheetFields() -> [EtaxField] {
        [
            EtaxField(id: "bs_asset_cash", fieldLabel: "現金", taxLine: nil, value: 3_000_000, section: .balanceSheet),
            EtaxField(id: "bs_asset_additional_1_name", fieldLabel: "資産追加科目1", taxLine: nil, value: "仮払金", section: .balanceSheet),
            EtaxField(id: "bs_asset_additional_1_closing", fieldLabel: "資産追加科目1金額", taxLine: nil, value: 5_000_000, section: .balanceSheet),
            EtaxField(id: "bs_total_assets", fieldLabel: "資産合計", taxLine: nil, value: 8_000_000, section: .balanceSheet),
            EtaxField(id: "bs_liability_accounts_payable", fieldLabel: "買掛金", taxLine: nil, value: 2_500_000, section: .balanceSheet),
            EtaxField(id: "bs_equity_owner_capital", fieldLabel: "元入金", taxLine: nil, value: 5_500_000, section: .balanceSheet),
            EtaxField(id: "bs_total_liabilities_and_equity", fieldLabel: "負債資本合計", taxLine: nil, value: 8_000_000, section: .balanceSheet),
        ]
    }

    private func sampleWhiteFields() -> [EtaxField] {
        [
            EtaxField(id: "shushi_revenue_sales", fieldLabel: "売上（収入）金額", taxLine: .salesRevenue, value: 3_000_000, section: .revenue),
            EtaxField(id: "shushi_revenue_home_consumption", fieldLabel: "家事消費", taxLine: nil, value: 0, section: .revenue),
            EtaxField(id: "shushi_revenue_other", fieldLabel: "その他の収入", taxLine: nil, value: 0, section: .revenue),
            EtaxField(id: "shushi_revenue_total", fieldLabel: "計", taxLine: .salesRevenue, value: 3_000_000, section: .revenue),
            EtaxField(id: "shushi_inventory_opening", fieldLabel: "期首商品（製品）棚卸高", taxLine: nil, value: 0, section: .inventory),
            EtaxField(id: "shushi_inventory_purchases", fieldLabel: "仕入金額（製品製造原価）", taxLine: nil, value: 0, section: .inventory),
            EtaxField(id: "shushi_inventory_subtotal", fieldLabel: "小計", taxLine: nil, value: 0, section: .inventory),
            EtaxField(id: "shushi_inventory_closing", fieldLabel: "期末商品（製品）棚卸高", taxLine: nil, value: 0, section: .inventory),
            EtaxField(id: "shushi_inventory_cogs", fieldLabel: "差引原価", taxLine: nil, value: 0, section: .inventory),
            EtaxField(id: "shushi_income_gross", fieldLabel: "差引金額", taxLine: nil, value: 3_000_000, section: .income),
            EtaxField(id: "shushi_expense_communication", fieldLabel: "通信費", taxLine: .communicationExpense, value: 120_000, section: .expenses),
            EtaxField(id: "shushi_expense_insurance", fieldLabel: "損害保険料", taxLine: .insuranceExpense, value: 50_000, section: .expenses),
            EtaxField(id: "shushi_expense_taxes", fieldLabel: "租税公課", taxLine: .taxesExpense, value: 80_000, section: .expenses),
            EtaxField(id: "shushi_expense_other_subtotal", fieldLabel: "小計", taxLine: nil, value: 250_000, section: .expenses),
            EtaxField(id: "shushi_expense_total", fieldLabel: "経費合計", taxLine: nil, value: 250_000, section: .expenses),
            EtaxField(id: "shushi_income_before_employee_deduction", fieldLabel: "専従者控除前の所得金額", taxLine: nil, value: 2_750_000, section: .income),
            EtaxField(id: "shushi_employee_deduction", fieldLabel: "専従者控除", taxLine: nil, value: 0, section: .income),
            EtaxField(id: "shushi_income_net", fieldLabel: "所得金額", taxLine: nil, value: 2_750_000, section: .income),
            EtaxField(id: "shushi_sales_detail_other_total", fieldLabel: "上記以外の売上先の計", taxLine: nil, value: 0, section: .revenue),
            EtaxField(id: "shushi_sales_detail_reduced_tax_total", fieldLabel: "右記(1)のうち軽減税率対象", taxLine: nil, value: 0, section: .revenue),
            EtaxField(id: "shushi_sales_detail_total", fieldLabel: "計", taxLine: nil, value: 0, section: .revenue),
            EtaxField(id: "shushi_purchase_detail_other_total", fieldLabel: "上記以外の仕入先の計", taxLine: nil, value: 0, section: .expenses),
            EtaxField(id: "shushi_purchase_detail_reduced_tax_total", fieldLabel: "右記(6)のうち軽減税率対象", taxLine: nil, value: 0, section: .expenses),
            EtaxField(id: "shushi_purchase_detail_total", fieldLabel: "計", taxLine: nil, value: 0, section: .expenses),
            EtaxField(id: "shushi_depreciation_detail_1_name", fieldLabel: "減価償却資産の名称等1", taxLine: nil, value: "MacBook Pro", section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_detail_1_acquired_year_month", fieldLabel: "取得年月1", taxLine: nil, value: "", section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_detail_1_acquisition_cost", fieldLabel: "取得価額1", taxLine: nil, value: 0, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_detail_1_method", fieldLabel: "償却方法1", taxLine: nil, value: "定額法", section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_detail_1_useful_life", fieldLabel: "耐用年数1", taxLine: nil, value: 0, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_detail_1_period_months", fieldLabel: "本年中の償却期間1", taxLine: nil, value: 12, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_detail_1_ordinary_amount", fieldLabel: "本年分の普通償却費1", taxLine: .depreciationExpense, value: 50_000, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_detail_1_necessary_expense_amount", fieldLabel: "本年分の必要経費算入額1", taxLine: .depreciationExpense, value: 50_000, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_detail_1_remaining_balance", fieldLabel: "未償却残高1", taxLine: nil, value: 0, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_total_ordinary", fieldLabel: "本年分の普通償却費", taxLine: nil, value: 50_000, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_total_special", fieldLabel: "特別償却費", taxLine: nil, value: 0, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_total_amount", fieldLabel: "本年分の償却費合計", taxLine: nil, value: 50_000, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_total_necessary_expense", fieldLabel: "本年分の必要経費算入額", taxLine: nil, value: 50_000, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_depreciation_total_remaining_balance", fieldLabel: "未償却残高", taxLine: nil, value: 0, section: .fixedAssetSchedule),
            EtaxField(id: "shushi_rent_detail_1_address", fieldLabel: "支払先住所1", taxLine: nil, value: "東京都港区1-2-3", section: .deductions),
            EtaxField(id: "shushi_rent_detail_1_name", fieldLabel: "支払先氏名1", taxLine: nil, value: "大家太郎", section: .deductions),
            EtaxField(id: "shushi_rent_detail_1_property", fieldLabel: "賃借物件1", taxLine: nil, value: "店舗", section: .deductions),
            EtaxField(id: "shushi_rent_detail_1_key_money", fieldLabel: "権利金1", taxLine: nil, value: 0, section: .deductions),
            EtaxField(id: "shushi_rent_detail_1_renewal_fee", fieldLabel: "更新料1", taxLine: nil, value: 0, section: .deductions),
            EtaxField(id: "shushi_rent_detail_1_rent", fieldLabel: "賃借料1", taxLine: nil, value: 120_000, section: .deductions),
            EtaxField(id: "shushi_rent_detail_1_necessary_expense", fieldLabel: "必要経費算入額1", taxLine: .rentExpense, value: 120_000, section: .deductions)
        ]
    }

    private func sampleCashBasisFields() -> [EtaxField] {
        [
            EtaxField(id: "cash_basis_revenue", fieldLabel: "ア 収入金額", taxLine: nil, value: 3_000_000, section: .revenue),
            EtaxField(id: "cash_basis_expense_1", fieldLabel: "イ 通信費", taxLine: nil, value: 120_000, section: .expenses),
            EtaxField(id: "cash_basis_expense_2", fieldLabel: "ウ 旅費交通費", taxLine: nil, value: 80_000, section: .expenses),
            EtaxField(id: "cash_basis_expense_3", fieldLabel: "エ 消耗品費", taxLine: nil, value: 50_000, section: .expenses),
            EtaxField(id: "cash_basis_expense_total", fieldLabel: "経費合計", taxLine: nil, value: 250_000, section: .expenses),
            EtaxField(id: "cash_basis_income", fieldLabel: "所得金額", taxLine: nil, value: 2_750_000, section: .income),
        ]
    }

    @MainActor
    private func sampleDeclarantFields() -> [EtaxField] {
        let businessProfile = BusinessProfile(
            ownerName: "山田太郎",
            ownerNameKana: "ヤマダタロウ",
            businessName: "山田商店",
            businessAddress: "東京都千代田区1-2-3",
            postalCode: "1234567",
            phoneNumber: "0312345678"
        )
        let sensitivePayload = ProfileSensitivePayload.fromLegacyProfile(
            ownerNameKana: "ヤマダタロウ",
            postalCode: "1234567",
            address: "東京都千代田区1-2-3",
            phoneNumber: "0312345678",
            dateOfBirth: nil,
            businessCategory: "小売業",
            myNumberFlag: true,
            includeSensitiveInExport: true
        )

        return EtaxFieldPopulator.populateDeclarantInfo(
            businessProfile: businessProfile,
            sensitivePayload: sensitivePayload
        )
    }

    /// Optional host-side copy for local debugging. CI/state validation should
    /// rely on the emitted base64 payload because simulator runs do not always
    /// persist the requested file path on the host.
    private func writeFixtureIfRequested(_ data: Data, envKey: String) throws {
        guard let path = ProcessInfo.processInfo.environment[envKey],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        try data.write(to: url, options: .atomic)
    }

    /// Canonical artifact channel for XSD validation. Downstream verification
    /// reconstructs the representative XML from these markers.
    private func emitFixturePayloadForCI(_ data: Data, marker: String) {
        let payload = data.base64EncodedString()
        print("ETAX_EXPORT_\(marker)_BASE64_BEGIN")
        print(payload)
        print("ETAX_EXPORT_\(marker)_BASE64_END")
    }

    // MARK: - XTX Generation

    @MainActor
    func testGenerateXtxSuccess() {
        let form = makeForm(fields: sampleFields() + sampleBlueBalanceSheetFields())
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
            XCTAssertTrue(xml.contains("<KOA210 "))
            XCTAssertTrue(xml.contains("VR=\"11.0\""))
            XCTAssertTrue(xml.contains("<KOA210-1>"))
            XCTAssertTrue(xml.contains("<AMF00100>5000000</AMF00100>"))
            XCTAssertTrue(xml.contains("<AMF00230>120000</AMF00230>"))
            XCTAssertTrue(xml.contains("<AMF00260>60000</AMF00260>"))
            XCTAssertTrue(xml.contains("<AMF00530>4740000</AMF00530>"))
            XCTAssertTrue(xml.contains("<KOA210-4>"))
            XCTAssertTrue(xml.contains("<AMG00025>"))
            XCTAssertTrue(xml.contains("<AMG00030>仮払金</AMG00030>"))
            XCTAssertTrue(xml.contains("<AMG00420>5000000</AMG00420>"))
            XCTAssertTrue(xml.contains("<AMG00260>3000000</AMG00260>"))
            XCTAssertTrue(xml.contains("<AMG00440>8000000</AMG00440>"))
            XCTAssertTrue(xml.contains("<AMG00650>2500000</AMG00650>"))
            XCTAssertTrue(xml.contains("<AMG00740>5500000</AMG00740>"))
            XCTAssertTrue(xml.contains("<AMG00760>8000000</AMG00760>"))
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateXtxEmptyFormFails() {
        let form = makeForm(fields: [])
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success:
            XCTFail("Expected failure for empty form")
        case .failure(let error):
            XCTAssertTrue(error.description.contains("データ"))
        }
    }

    @MainActor
    func testGenerateXtxUnsupportedYearFails() {
        let form = EtaxForm(
            fiscalYear: 1900,
            formType: .blueReturn,
            fields: sampleFields(),
            generatedAt: Date()
        )
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success:
            XCTFail("Expected failure for unsupported year")
        case .failure(let error):
            XCTAssertTrue(error.description.contains("未対応"))
        }
    }

    @MainActor
    func testGenerateXtxContainsTaxLineAttribute() {
        let form = makeForm(fields: sampleFields() + sampleBlueBalanceSheetFields())
        let result = EtaxXtxExporter.generateXtx(form: form)

        if case .success(let data) = result {
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<AMF00100>5000000</AMF00100>"))
            XCTAssertTrue(xml.contains("<AMF00230>120000</AMF00230>"))
            XCTAssertTrue(xml.contains("<AMG00440>8000000</AMG00440>"))
        } else {
            XCTFail("Expected success")
        }
    }

    @MainActor
    func testGenerateXtxWritesBlueFixtureWhenEnvIsSet() throws {
        let fields = sampleDeclarantFields() + sampleBlueBalanceSheetFields() + [
            EtaxField(
                id: "revenue_sales_revenue",
                fieldLabel: "売上（収入）金額",
                taxLine: .salesRevenue,
                value: 5_000_000,
                section: .revenue
            )
        ]
        let form = makeForm(fields: fields, formType: .blueReturn)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<KOA210 "))
            XCTAssertTrue(xml.contains("<AMA00000 IDREF=\"NENBUN\"/>"))
            XCTAssertTrue(xml.contains("<AMB00010>東京都千代田区1-2-3</AMB00010>"))
            XCTAssertTrue(xml.contains("<AMB00030 IDREF=\"NOZEISHA_NM_KN\"/>"))
            XCTAssertTrue(xml.contains("<AMB00040 IDREF=\"NOZEISHA_NM\"/>"))
            XCTAssertTrue(xml.contains("<AMB00050>1234567</AMB00050>"))
            XCTAssertTrue(xml.contains("<AMB00070>"))
            XCTAssertTrue(xml.contains("<gen:tel1>03</gen:tel1>"))
            XCTAssertTrue(xml.contains("<gen:tel2>1234</gen:tel2>"))
            XCTAssertTrue(xml.contains("<gen:tel3>5678</gen:tel3>"))
            XCTAssertTrue(xml.contains("<AMB00090 IDREF=\"SHOKUGYO\"/>"))
            XCTAssertTrue(xml.contains("<AMB00100 IDREF=\"NOZEISHA_YAGO\"/>"))
            XCTAssertFalse(xml.contains("<ABA"))
            XCTAssertTrue(xml.contains("<AMF00100>5000000</AMF00100>"))
            XCTAssertTrue(xml.contains("<KOA210-4>"))
            XCTAssertTrue(xml.contains("<AMG00025>"))
            XCTAssertTrue(xml.contains("<AMG00030>仮払金</AMG00030>"))
            XCTAssertTrue(xml.contains("<AMG00420>5000000</AMG00420>"))
            XCTAssertTrue(xml.contains("<AMG00260>3000000</AMG00260>"))
            XCTAssertTrue(xml.contains("<AMG00440>8000000</AMG00440>"))
            XCTAssertTrue(xml.contains("<AMG00450>"))
            XCTAssertTrue(xml.contains("<AMG00620>"))
            XCTAssertTrue(xml.contains("<AMG00650>2500000</AMG00650>"))
            XCTAssertTrue(xml.contains("<AMG00740>5500000</AMG00740>"))
            XCTAssertTrue(xml.contains("<AMG00760>8000000</AMG00760>"))
            emitFixturePayloadForCI(data, marker: "BLUE")
            try writeFixtureIfRequested(data, envKey: "ETAX_XSD_BLUE_EXPORT_XML")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateXtxWritesWhiteFixtureWhenEnvIsSet() throws {
        let fields = sampleDeclarantFields() + sampleWhiteFields()
        let form = makeForm(fields: fields, formType: .whiteReturn)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<KOA110 "))
            XCTAssertTrue(xml.contains("<AIA00000 IDREF=\"NENBUN\"/>"))
            XCTAssertTrue(xml.contains("<AIB00010>東京都千代田区1-2-3</AIB00010>"))
            XCTAssertTrue(xml.contains("<AIB00030 IDREF=\"NOZEISHA_NM_KN\"/>"))
            XCTAssertTrue(xml.contains("<AIB00040 IDREF=\"NOZEISHA_NM\"/>"))
            XCTAssertTrue(xml.contains("<AIB00050>1234567</AIB00050>"))
            XCTAssertTrue(xml.contains("<AIB00070>"))
            XCTAssertTrue(xml.contains("<gen:tel1>03</gen:tel1>"))
            XCTAssertTrue(xml.contains("<gen:tel2>1234</gen:tel2>"))
            XCTAssertTrue(xml.contains("<gen:tel3>5678</gen:tel3>"))
            XCTAssertTrue(xml.contains("<AIB00090 IDREF=\"SHOKUGYO\"/>"))
            XCTAssertTrue(xml.contains("<AIB00100 IDREF=\"NOZEISHA_YAGO\"/>"))
            XCTAssertFalse(xml.contains("<ABA"))
            XCTAssertTrue(xml.contains("<AIG00020>"))
            XCTAssertTrue(xml.contains("<AIG00030>3000000</AIG00030>"))
            XCTAssertTrue(xml.contains("<AIG00140>"))
            XCTAssertTrue(xml.contains("<AIG00210>"))
            XCTAssertTrue(xml.contains("<AIG00400>2750000</AIG00400>"))
            XCTAssertTrue(xml.contains("<KOA110-1>"))
            XCTAssertTrue(xml.contains("<KOA110-2>"))
            XCTAssertTrue(xml.contains("<AIK00000>"))
            XCTAssertTrue(xml.contains("<AIL00000>"))
            XCTAssertTrue(xml.contains("<AIM00000>"))
            XCTAssertTrue(xml.contains("<KOA110-2>\n    <AIK00000>"))
            XCTAssertTrue(xml.contains("<AIN00090>120000</AIN00090>"))
            XCTAssertFalse(xml.contains("<KOA110-1>\n    <AIN00000>"))
            emitFixturePayloadForCI(data, marker: "WHITE")
            try writeFixtureIfRequested(data, envKey: "ETAX_XSD_WHITE_EXPORT_XML")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateXtxWhiteReturnSplitsPagesAndMovesAinToPage2() {
        let form = makeForm(fields: sampleDeclarantFields() + sampleWhiteFields(), formType: .whiteReturn)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            guard let page1Range = xml.range(of: "<KOA110-1>"),
                  let page2Range = xml.range(of: "<KOA110-2>"),
                  let page1CloseRange = xml.range(of: "</KOA110-1>"),
                  let ainRange = xml.range(of: "<AIN00000>"),
                  let ainValueRange = xml.range(of: "<AIN00090>120000</AIN00090>")
            else {
                return XCTFail("Expected KOA110-1/2 and AIN00000 in generated white XML")
            }

            XCTAssertLessThan(page1Range.lowerBound, page1CloseRange.lowerBound)
            XCTAssertLessThan(page1CloseRange.lowerBound, page2Range.lowerBound)
            XCTAssertLessThan(page2Range.lowerBound, ainRange.lowerBound)
            XCTAssertLessThan(ainRange.lowerBound, ainValueRange.lowerBound)
            XCTAssertFalse(xml.contains("<KOA110-1>\n    <AIN00000>"))
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testWhitePackUsesOfficialCoverageFor2025And2026() {
        for fiscalYear in [2025, 2026] {
            let definitions = TaxYearDefinitionLoader.fieldDefinitions(for: .whiteReturn, fiscalYear: fiscalYear)
            let definitionsByKey = Dictionary(uniqueKeysWithValues: definitions.map { ($0.internalKey, $0) })

            XCTAssertEqual(definitionsByKey["shushi_revenue_sales"]?.xmlTag, "AIG00030")
            XCTAssertEqual(definitionsByKey["shushi_inventory_subtotal"]?.xmlTag, "AIG00100")
            XCTAssertEqual(definitionsByKey["shushi_expense_shipping"]?.xmlTag, "AIG00230")
            XCTAssertEqual(definitionsByKey["shushi_expense_repairs"]?.xmlTag, "AIG00300")
            XCTAssertEqual(definitionsByKey["shushi_sales_detail_total"]?.xmlTag, "AIK00060")
            XCTAssertEqual(definitionsByKey["shushi_purchase_detail_total"]?.xmlTag, "AIL00060")
            XCTAssertEqual(definitionsByKey["shushi_depreciation_total_necessary_expense"]?.xmlTag, "AIM00260")
            XCTAssertEqual(definitionsByKey["shushi_rent_detail_1_necessary_expense"]?.xmlTag, "AIN00090")
            XCTAssertNil(definitionsByKey["shushi_rent_breakdown"])
            XCTAssertNil(definitions.first(where: { $0.xmlTag == "AIG00020" && $0.internalKey == "shushi_revenue_total" }))
        }
    }

    @MainActor
    func testWhiteValidatorDetectsRequiredFieldsAndAcceptsDefinedDynamicKeys() {
        let validForm = makeForm(fields: sampleWhiteFields(), formType: .whiteReturn)
        let validErrors = EtaxCharacterValidator.validateForm(validForm)
        XCTAssertFalse(validErrors.contains(where: { $0.description.contains("未定義のinternalKey") }))
        XCTAssertFalse(validErrors.contains(where: { $0.description.contains("missingXmlTag") }))

        let incompleteForm = makeForm(fields: [
            EtaxField(id: "shushi_revenue_sales", fieldLabel: "売上（収入）金額", taxLine: .salesRevenue, value: 3_000_000, section: .revenue)
        ], formType: .whiteReturn)
        let incompleteErrors = EtaxCharacterValidator.validateForm(incompleteForm)
        XCTAssertTrue(incompleteErrors.contains(where: { $0.description.contains("shushi_revenue_total") }))
        XCTAssertTrue(incompleteErrors.contains(where: { $0.description.contains("shushi_sales_detail_total") }))
    }

    @MainActor
    func testGenerateXtxWhiteReturnProducesXmlForCurrentOfficialXsdValidation() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: whiteXsdPath), "white XSD should exist at \(whiteXsdPath)")

        let form = makeForm(fields: sampleDeclarantFields() + sampleWhiteFields(), formType: .whiteReturn)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<KOA110 "))
            XCTAssertTrue(xml.contains("<AIM00000>"))
            XCTAssertTrue(xml.contains("<AIN00000>"))
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateXtxBlueReturnProducesXmlForCurrentOfficialXsdValidation() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: blueXsdPath), "blue XSD should exist at \(blueXsdPath)")

        let form = makeForm(fields: sampleDeclarantFields() + sampleFields() + sampleBlueBalanceSheetFields(), formType: .blueReturn)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<KOA210 "))
            XCTAssertTrue(xml.contains("<KOA210-1>"))
            XCTAssertTrue(xml.contains("<KOA210-4>"))
            XCTAssertTrue(xml.contains("<AMG00000>"))
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateXtxBlueCashBasisUsesDedicatedKOA230Route() {
        let form = makeForm(fields: sampleCashBasisFields(), formType: .blueCashBasis)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<KOA230 "))
            XCTAssertTrue(xml.contains("VR=\"10.0\""))
            XCTAssertTrue(xml.contains("<KOA230-1>"))
            XCTAssertTrue(xml.contains("<AOF00000>"))
            XCTAssertTrue(xml.contains("<AOF00110>3000000</AOF00110>"))
            XCTAssertTrue(xml.contains("<AOF00050>通信費</AOF00050>"))
            XCTAssertTrue(xml.contains("<AOF00180>120000</AOF00180>"))
            XCTAssertTrue(xml.contains("<AOF00190>130000</AOF00190>"))
            XCTAssertTrue(xml.contains("<AOF00200>250000</AOF00200>"))
            XCTAssertTrue(xml.contains("<AOF00290>2750000</AOF00290>"))
            XCTAssertFalse(xml.contains("<KOA210-1>"))
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateXtxWritesCashFixtureWhenEnvIsSet() throws {
        let form = makeForm(fields: sampleDeclarantFields() + sampleCashBasisFields(), formType: .blueCashBasis)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<KOA230 "))
            XCTAssertTrue(xml.contains("<AOA00000 IDREF=\"NENBUN\"/>"))
            XCTAssertTrue(xml.contains("<AOB00010>東京都千代田区1-2-3</AOB00010>"))
            XCTAssertTrue(xml.contains("<AOB00030 IDREF=\"NOZEISHA_NM_KN\"/>"))
            XCTAssertTrue(xml.contains("<AOB00040 IDREF=\"NOZEISHA_NM\"/>"))
            XCTAssertTrue(xml.contains("<AOB00050>1234567</AOB00050>"))
            XCTAssertTrue(xml.contains("<gen:tel1>03</gen:tel1>"))
            XCTAssertTrue(xml.contains("<gen:tel2>1234</gen:tel2>"))
            XCTAssertTrue(xml.contains("<gen:tel3>5678</gen:tel3>"))
            XCTAssertTrue(xml.contains("<AOB00090 IDREF=\"SHOKUGYO\"/>"))
            XCTAssertTrue(xml.contains("<AOB00100 IDREF=\"NOZEISHA_YAGO\"/>"))
            XCTAssertFalse(xml.contains("<ABA"))
            XCTAssertTrue(xml.contains("<AOF00180>120000</AOF00180>"))
            XCTAssertTrue(xml.contains("<AOF00190>130000</AOF00190>"))
            emitFixturePayloadForCI(data, marker: "CASH")
            try writeFixtureIfRequested(data, envKey: "ETAX_XSD_CASH_EXPORT_XML")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateXtxBlueCashBasisProducesXmlForCurrentOfficialXsdValidation() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: cashBasisXsdPath), "cash basis XSD should exist at \(cashBasisXsdPath)")

        let form = makeForm(fields: sampleCashBasisFields(), formType: .blueCashBasis)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<KOA230 "))
            XCTAssertTrue(xml.contains("<AOF00110>3000000</AOF00110>"))
            emitFixturePayloadForCI(data, marker: "CASH")
            try writeFixtureIfRequested(data, envKey: "ETAX_XSD_CASH_EXPORT_XML")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateXtxXmlEscaping() {
        let fields = [
            EtaxField(id: "declarant_name", fieldLabel: "氏名", taxLine: nil, value: "テスト<>&'\"", section: .declarantInfo)
        ]
        let form = makeForm(fields: fields)
        let result = EtaxXtxExporter.generateXtx(form: form)

        if case .success(let data) = result {
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertFalse(xml.contains("<テスト<>"))
            XCTAssertTrue(xml.contains("&lt;"))
            XCTAssertTrue(xml.contains("&gt;"))
            XCTAssertTrue(xml.contains("&amp;"))
        } else {
            XCTFail("Expected success")
        }
    }

    @MainActor
    func testGenerateXtxBlueReturnSplitsPagesAndKeepsBalanceSheetOnPage4() {
        let form = makeForm(fields: sampleDeclarantFields() + sampleFields() + sampleBlueBalanceSheetFields())
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            guard let page1Range = xml.range(of: "<KOA210-1>"),
                  let page2Range = xml.range(of: "<KOA210-2>"),
                  let page3Range = xml.range(of: "<KOA210-3>"),
                  let page4Range = xml.range(of: "<KOA210-4>"),
                  let amfRange = xml.range(of: "<AMF00100>5000000</AMF00100>"),
                  let amgRange = xml.range(of: "<AMG00440>8000000</AMG00440>"),
                  let amgContainerRange = xml.range(of: "<AMG00000>")
            else {
                return XCTFail("Expected KOA210 page structure and blue tags")
            }

            XCTAssertLessThan(page1Range.lowerBound, amfRange.lowerBound)
            XCTAssertLessThan(page1Range.lowerBound, page2Range.lowerBound)
            XCTAssertLessThan(page2Range.lowerBound, page3Range.lowerBound)
            XCTAssertLessThan(page3Range.lowerBound, page4Range.lowerBound)
            XCTAssertLessThan(page4Range.lowerBound, amgRange.lowerBound)
            XCTAssertLessThan(page4Range.lowerBound, amgContainerRange.lowerBound)
            XCTAssertFalse(xml.contains("<ABA"))
            XCTAssertTrue(xml.contains("<AMA00000 IDREF=\"NENBUN\"/>"))
            XCTAssertTrue(xml.contains("<AMB00030 IDREF=\"NOZEISHA_NM_KN\"/>"))
            XCTAssertTrue(xml.contains("<AMB00040 IDREF=\"NOZEISHA_NM\"/>"))
            XCTAssertTrue(xml.contains("<KOA210-2>\n  </KOA210-2>"))
            XCTAssertTrue(xml.contains("<KOA210-3>\n  </KOA210-3>"))
            XCTAssertTrue(xml.contains("<AMG00025>"))
            XCTAssertTrue(xml.contains("<AMG00030>仮払金</AMG00030>"))
            XCTAssertTrue(xml.contains("<AMG00450>"))
            XCTAssertTrue(xml.contains("<AMG00620>"))
            XCTAssertTrue(xml.contains("<KOA210-4>\n    <AMG00000>"))
            XCTAssertTrue(xml.contains("<AMG00740>5500000</AMG00740>"))
            XCTAssertTrue(xml.contains("<AMG00760>8000000</AMG00760>"))
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testBlueGeneralPackUsesOfficialMappingsFor2025And2026() {
        for fiscalYear in [2025, 2026] {
            let definitions = TaxYearDefinitionLoader.fieldDefinitions(for: .blueReturn, fiscalYear: fiscalYear)
            let definitionsByKey = Dictionary(uniqueKeysWithValues: definitions.map { ($0.internalKey, $0) })

            XCTAssertEqual(definitionsByKey["expense_interest"]?.xmlTag, "AMF00330")
            XCTAssertEqual(definitionsByKey["expense_taxes"]?.xmlTag, "AMF00190")
            XCTAssertNil(definitionsByKey["income_total_revenue"]?.xmlTag)
            XCTAssertNil(definitionsByKey["inventory_cogs"]?.xmlTag)
            XCTAssertEqual(definitionsByKey["bs_equity_owner_capital"]?.xmlTag, "AMG00740")
            XCTAssertEqual(definitionsByKey["bs_total_liabilities_and_equity"]?.xmlTag, "AMG00760")
        }
    }

    @MainActor
    func testGenerateXtxBlueReturnOmitsDirectCompositeValueTags() {
        let fields = sampleFields() + [
            EtaxField(id: "inventory_opening", fieldLabel: "期首商品棚卸高", taxLine: nil, value: 100_000, section: .inventory),
            EtaxField(id: "inventory_purchases", fieldLabel: "仕入高", taxLine: nil, value: 450_000, section: .inventory),
            EtaxField(id: "inventory_closing", fieldLabel: "期末商品棚卸高", taxLine: nil, value: 50_000, section: .inventory),
            EtaxField(id: "inventory_cogs", fieldLabel: "売上原価", taxLine: nil, value: 500_000, section: .inventory),
        ]
        let form = makeForm(fields: fields)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertFalse(xml.contains("<AMF00970>5000000</AMF00970>"))
            XCTAssertFalse(xml.contains("<AMF00110>500000</AMF00110>"))
            XCTAssertTrue(xml.contains("<AMF00120>100000</AMF00120>"))
            XCTAssertTrue(xml.contains("<AMF00130>450000</AMF00130>"))
            XCTAssertTrue(xml.contains("<AMF00150>50000</AMF00150>"))
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    // MARK: - CSV Generation

    @MainActor
    func testGenerateCsvSuccess() {
        let form = makeForm(fields: sampleFields())
        let result = EtaxXtxExporter.generateCsv(form: form)

        switch result {
        case .success(let data):
            let csv = String(data: data, encoding: .utf8)!
            let lines = csv.components(separatedBy: "\n")
            XCTAssertEqual(lines[0], "internalKey,xmlTag,form,セクション,フィールド名,値")
            XCTAssertTrue(lines.count > 1)
            XCTAssertTrue(csv.contains("\"revenue_sales_revenue\",\"AMF00100\",\"blue_general\",\"収入金額\",\"売上（収入）金額\",\"5000000\""))
            XCTAssertFalse(csv.contains("\"income_total_revenue\",\"AMF00970\""))
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateCsvEmptyFormFails() {
        let form = makeForm(fields: [])
        let result = EtaxXtxExporter.generateCsv(form: form)

        switch result {
        case .success:
            XCTFail("Expected failure for empty form")
        case .failure:
            break // expected
        }
    }

    @MainActor
    func testGenerateCsvUnsupportedYearFails() {
        let form = EtaxForm(
            fiscalYear: 1900,
            formType: .blueReturn,
            fields: sampleFields(),
            generatedAt: Date()
        )
        let result = EtaxXtxExporter.generateCsv(form: form)

        switch result {
        case .success:
            XCTFail("Expected failure for unsupported year")
        case .failure(let error):
            XCTAssertTrue(error.description.contains("未対応"))
        }
    }

    @MainActor
    func testGenerateCsvFieldCount() {
        let form = makeForm(fields: sampleFields())
        let result = EtaxXtxExporter.generateCsv(form: form)

        if case .success(let data) = result {
            let csv = String(data: data, encoding: .utf8)!
            let lines = csv.components(separatedBy: "\n")
            // Header + 6 data rows (`income_total_revenue` is not directly exported)
            XCTAssertEqual(lines.count, 7)
        } else {
            XCTFail("Expected success")
        }
    }

    @MainActor
    func testGenerateCsvBlueReturnKeepsBalanceSheetDetailKeys() {
        let form = makeForm(fields: sampleBlueBalanceSheetFields())
        let result = EtaxXtxExporter.generateCsv(form: form)

        switch result {
        case .success(let data):
            let csv = String(data: data, encoding: .utf8)!
            XCTAssertTrue(csv.contains("\"bs_asset_cash\",\"AMG00260\",\"blue_general\""))
            XCTAssertTrue(csv.contains("\"bs_asset_additional_1_name\",\"AMG00030\",\"blue_general\""))
            XCTAssertTrue(csv.contains("\"bs_asset_additional_1_closing\",\"AMG00420\",\"blue_general\""))
            XCTAssertTrue(csv.contains("\"bs_liability_accounts_payable\",\"AMG00650\",\"blue_general\""))
            XCTAssertTrue(csv.contains("\"bs_equity_owner_capital\",\"AMG00740\",\"blue_general\""))
            XCTAssertTrue(csv.contains("\"bs_total_liabilities_and_equity\",\"AMG00760\",\"blue_general\""))
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateCsvBlueCashBasisKeepsDynamicExpenseRows() {
        let form = makeForm(fields: sampleCashBasisFields(), formType: .blueCashBasis)
        let result = EtaxXtxExporter.generateCsv(form: form)

        switch result {
        case .success(let data):
            let csv = String(data: data, encoding: .utf8)!
            XCTAssertTrue(csv.contains("\"cash_basis_expense_1\",\"AOF00180\",\"blue_cash_basis\""))
            XCTAssertTrue(csv.contains("\"cash_basis_expense_2\",\"AOF00190\",\"blue_cash_basis\""))
            XCTAssertTrue(csv.contains("\"cash_basis_expense_3\",\"AOF00190\",\"blue_cash_basis\""))
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }
}
