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
            EtaxField(id: "income_total_revenue", fieldLabel: "収入金額合計", taxLine: nil, value: 5_000_000, section: .income),
            EtaxField(id: "income_total_expenses", fieldLabel: "必要経費合計", taxLine: nil, value: 200_000, section: .income),
            EtaxField(id: "income_net", fieldLabel: "所得金額", taxLine: nil, value: 4_800_000, section: .income),
        ]
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
            XCTAssertTrue(xml.contains("<eTaxData year=\"2025\""))
            XCTAssertTrue(xml.contains("formType=\"青色申告決算書\""))
            XCTAssertTrue(xml.contains("<BlueRevenueSales>5000000</BlueRevenueSales>"))
            XCTAssertTrue(xml.contains("<BlueExpenseCommunication>120000</BlueExpenseCommunication>"))
            XCTAssertTrue(xml.contains("<BlueIncomeNet>4800000</BlueIncomeNet>"))
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
            XCTAssertTrue(xml.contains("<BlueRevenueSales>5000000</BlueRevenueSales>"))
            XCTAssertTrue(xml.contains("<BlueExpenseCommunication>120000</BlueExpenseCommunication>"))
        } else {
            XCTFail("Expected success")
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
            XCTAssertEqual(lines[0], "internalKey,xmlTag,セクション,フィールド名,値")
            XCTAssertTrue(lines.count > 1)
            XCTAssertTrue(csv.contains("\"revenue_sales_revenue\",\"BlueRevenueSales\",\"収入金額\",\"売上（収入）金額\",\"5000000\""))
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
            // Header + 6 data rows
            XCTAssertEqual(lines.count, 7)
        } else {
            XCTFail("Expected success")
        }
    }
}
