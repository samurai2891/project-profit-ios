import XCTest
@testable import ProjectProfit

final class EtaxXtxExporterTests: XCTestCase {

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

    private func sampleWhiteFields() -> [EtaxField] {
        [
            EtaxField(id: "shushi_revenue_total", fieldLabel: "収入金額", taxLine: .salesRevenue, value: 3_000_000, section: .revenue),
            EtaxField(id: "shushi_expense_communication", fieldLabel: "通信費", taxLine: .communicationExpense, value: 120_000, section: .expenses),
            EtaxField(id: "shushi_expense_insurance", fieldLabel: "損害保険料", taxLine: .insuranceExpense, value: 50_000, section: .expenses),
            EtaxField(id: "shushi_expense_taxes", fieldLabel: "租税公課", taxLine: .taxesExpense, value: 80_000, section: .expenses),
            EtaxField(id: "shushi_expense_total", fieldLabel: "経費合計", taxLine: nil, value: 250_000, section: .expenses),
            EtaxField(id: "shushi_income_net", fieldLabel: "所得金額", taxLine: nil, value: 2_750_000, section: .income),
        ]
    }

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

    // MARK: - XTX Generation

    @MainActor
    func testGenerateXtxSuccess() {
        let form = makeForm(fields: sampleFields())
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
        let form = makeForm(fields: sampleFields())
        let result = EtaxXtxExporter.generateXtx(form: form)

        if case .success(let data) = result {
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<AMF00100>5000000</AMF00100>"))
            XCTAssertTrue(xml.contains("<AMF00230>120000</AMF00230>"))
        } else {
            XCTFail("Expected success")
        }
    }

    @MainActor
    func testGenerateXtxWritesBlueFixtureWhenEnvIsSet() throws {
        let form = makeForm(fields: sampleFields(), formType: .blueReturn)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<KOA210 "))
            try writeFixtureIfRequested(data, envKey: "ETAX_XSD_BLUE_EXPORT_XML")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    @MainActor
    func testGenerateXtxWritesWhiteFixtureWhenEnvIsSet() throws {
        let form = makeForm(fields: sampleWhiteFields(), formType: .whiteReturn)
        let result = EtaxXtxExporter.generateXtx(form: form)

        switch result {
        case .success(let data):
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("<KOA110 "))
            XCTAssertTrue(xml.contains("<AIG00020>3000000</AIG00020>"))
            XCTAssertTrue(xml.contains("<AIG00290>50000</AIG00290>"))
            XCTAssertTrue(xml.contains("<AIG00220>80000</AIG00220>"))
            try writeFixtureIfRequested(data, envKey: "ETAX_XSD_WHITE_EXPORT_XML")
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
            // Header + 7 data rows
            XCTAssertEqual(lines.count, 8)
        } else {
            XCTFail("Expected success")
        }
    }
}
