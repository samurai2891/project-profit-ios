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
            EtaxField(id: "revenue_sales", fieldLabel: "売上（収入）金額", taxLine: .salesRevenue, value: 5_000_000, section: .revenue),
            EtaxField(id: "expense_comm", fieldLabel: "通信費", taxLine: .communicationExpense, value: 120_000, section: .expenses),
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
            XCTAssertTrue(xml.contains("<税務申告データ>"))
            XCTAssertTrue(xml.contains("<年度>2025</年度>"))
            XCTAssertTrue(xml.contains("<申告書種類>青色申告決算書</申告書種類>"))
            XCTAssertTrue(xml.contains("<収入金額>"))
            XCTAssertTrue(xml.contains("<必要経費>"))
            XCTAssertTrue(xml.contains("<所得金額>"))
            XCTAssertTrue(xml.contains("<金額>5000000</金額>"))
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
    func testGenerateXtxContainsTaxLineAttribute() {
        let form = makeForm(fields: sampleFields())
        let result = EtaxXtxExporter.generateXtx(form: form)

        if case .success(let data) = result {
            let xml = String(data: data, encoding: .utf8)!
            XCTAssertTrue(xml.contains("taxLine=\"sales_revenue\""))
            XCTAssertTrue(xml.contains("taxLine=\"communication\""))
        } else {
            XCTFail("Expected success")
        }
    }

    @MainActor
    func testGenerateXtxXmlEscaping() {
        let fields = [
            EtaxField(id: "test", fieldLabel: "テスト<>&'\"", taxLine: .salesRevenue, value: 100, section: .revenue)
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
            XCTAssertEqual(lines[0], "セクション,フィールド名,税区分,金額")
            XCTAssertTrue(lines.count > 1)
            // Check revenue line (values are now RFC 4180 quoted)
            XCTAssertTrue(csv.contains("\"収入金額\",\"売上（収入）金額\",\"sales_revenue\",5000000"))
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
