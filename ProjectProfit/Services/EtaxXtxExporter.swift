import Foundation

/// 青色申告決算書の .xtx (XML) ファイルを生成するエクスポーター
@MainActor
enum EtaxXtxExporter {

    /// e-Tax .xtx 形式のXMLデータを生成
    static func generateXtx(form: EtaxForm) -> Result<Data, EtaxExportError> {
        // バリデーション
        let errors = EtaxCharacterValidator.validateForm(form)
        guard errors.isEmpty else {
            return .failure(errors[0])
        }

        do {
            let xml = try buildXml(form: form)
            guard let data = xml.data(using: .utf8) else {
                return .failure(.xmlGenerationFailed(underlying: NSError(
                    domain: "EtaxXtxExporter",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "UTF-8エンコードに失敗"]
                )))
            }
            return .success(data)
        } catch {
            return .failure(.xmlGenerationFailed(underlying: error))
        }
    }

    /// CSVエクスポート（簡易形式）
    static func generateCsv(form: EtaxForm) -> Result<Data, EtaxExportError> {
        let errors = EtaxCharacterValidator.validateForm(form)
        guard errors.isEmpty else {
            return .failure(errors[0])
        }

        var lines: [String] = []
        lines.append("セクション,フィールド名,税区分,金額")

        for field in form.fields {
            let section = csvQuote(field.section.rawValue)
            let label = csvQuote(EtaxCharacterValidator.sanitize(field.fieldLabel))
            let taxLine = csvQuote(field.taxLine?.rawValue ?? "")
            lines.append("\(section),\(label),\(taxLine),\(field.value)")
        }

        let csv = lines.joined(separator: "\n")
        guard let data = csv.data(using: .utf8) else {
            return .failure(.xmlGenerationFailed(underlying: NSError(
                domain: "EtaxXtxExporter",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "CSVエンコードに失敗"]
            )))
        }
        return .success(data)
    }

    // MARK: - XML Builder

    private static func buildXml(form: EtaxForm) throws -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <税務申告データ>
          <申告書情報>
            <年度>\(form.fiscalYear)</年度>
            <申告書種類>\(xmlEscape(form.formType.rawValue))</申告書種類>
            <生成日時>\(iso8601(form.generatedAt))</生成日時>
          </申告書情報>
        """

        // 収入セクション
        let revenueFields = form.fields.filter { $0.section == .revenue }
        if !revenueFields.isEmpty {
            xml += "\n  <収入金額>"
            for field in revenueFields {
                xml += buildFieldXml(field: field)
            }
            xml += "\n  </収入金額>"
        }

        // 経費セクション
        let expenseFields = form.fields.filter { $0.section == .expenses }
        if !expenseFields.isEmpty {
            xml += "\n  <必要経費>"
            for field in expenseFields {
                xml += buildFieldXml(field: field)
            }
            xml += "\n  </必要経費>"
        }

        // 所得セクション
        let incomeFields = form.fields.filter { $0.section == .income }
        if !incomeFields.isEmpty {
            xml += "\n  <所得金額>"
            for field in incomeFields {
                xml += buildFieldXml(field: field)
            }
            xml += "\n  </所得金額>"
        }

        xml += "\n</税務申告データ>"
        return xml
    }

    private static func buildFieldXml(field: EtaxField) -> String {
        let sanitizedLabel = EtaxCharacterValidator.sanitize(field.fieldLabel)
        let taxLineAttr = field.taxLine.map { " taxLine=\"\(xmlEscape($0.rawValue))\"" } ?? ""
        return """

            <フィールド id="\(xmlEscape(field.id))"\(taxLineAttr)>
              <ラベル>\(xmlEscape(sanitizedLabel))</ラベル>
              <金額>\(field.value)</金額>
            </フィールド>
        """
    }

    // MARK: - Utilities

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func csvQuote(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
