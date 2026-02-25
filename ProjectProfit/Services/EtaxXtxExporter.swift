import Foundation

/// 青色申告決算書の .xtx (XML) ファイルを生成するエクスポーター
@MainActor
enum EtaxXtxExporter {

    private struct MappedEtaxField {
        let field: EtaxField
        let xmlTag: String
    }

    /// e-Tax .xtx 形式のXMLデータを生成
    static func generateXtx(form: EtaxForm) -> Result<Data, EtaxExportError> {
        guard let definition = TaxYearDefinitionLoader.loadDefinition(for: form.fiscalYear) else {
            return .failure(.unsupportedTaxYear(year: form.fiscalYear))
        }

        let mappedResult = resolveMappedFields(form: form, definition: definition)
        let mappedFields: [MappedEtaxField]
        switch mappedResult {
        case .success(let fields):
            mappedFields = fields
        case .failure(let error):
            return .failure(error)
        }

        // バリデーション
        let errors = EtaxCharacterValidator.validateForm(
            EtaxForm(
                fiscalYear: form.fiscalYear,
                formType: form.formType,
                fields: mappedFields.map(\.field),
                generatedAt: form.generatedAt
            )
        )
        guard errors.isEmpty else {
            return .failure(errors[0])
        }

        do {
            let xml = try buildXml(form: form, fields: mappedFields)
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
        guard let definition = TaxYearDefinitionLoader.loadDefinition(for: form.fiscalYear) else {
            return .failure(.unsupportedTaxYear(year: form.fiscalYear))
        }

        let mappedResult = resolveMappedFields(form: form, definition: definition)
        let mappedFields: [MappedEtaxField]
        switch mappedResult {
        case .success(let fields):
            mappedFields = fields
        case .failure(let error):
            return .failure(error)
        }

        let errors = EtaxCharacterValidator.validateForm(
            EtaxForm(
                fiscalYear: form.fiscalYear,
                formType: form.formType,
                fields: mappedFields.map(\.field),
                generatedAt: form.generatedAt
            )
        )
        guard errors.isEmpty else {
            return .failure(errors[0])
        }

        var lines: [String] = []
        lines.append("internalKey,xmlTag,セクション,フィールド名,値")

        for mapped in mappedFields {
            let section = csvQuote(mapped.field.section.rawValue)
            let key = csvQuote(mapped.field.id)
            let xmlTag = csvQuote(mapped.xmlTag)
            let label = csvQuote(EtaxCharacterValidator.sanitize(mapped.field.fieldLabel))
            let value = csvQuote(EtaxCharacterValidator.sanitize(mapped.field.value.exportText))
            lines.append("\(key),\(xmlTag),\(section),\(label),\(value)")
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

    private static func buildXml(form: EtaxForm, fields: [MappedEtaxField]) throws -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <eTaxData year="\(form.fiscalYear)" formType="\(xmlEscape(form.formType.rawValue))" generatedAt="\(iso8601(form.generatedAt))">
        """

        for mapped in fields {
            let value = xmlEscape(EtaxCharacterValidator.sanitize(mapped.field.value.exportText))
            xml += "\n  <\(mapped.xmlTag)>\(value)</\(mapped.xmlTag)>"
        }

        xml += "\n</eTaxData>"
        return xml
    }

    private static func resolveMappedFields(
        form: EtaxForm,
        definition: TaxYearDefinition
    ) -> Result<[MappedEtaxField], EtaxExportError> {
        guard !form.fields.isEmpty else {
            return .failure(.noData)
        }

        if let missingTagField = definition.fields.first(where: { ($0.xmlTag ?? "").isEmpty }) {
            return .failure(.missingXmlTag(internalKey: missingTagField.internalKey))
        }

        let definitionsByKey = Dictionary(uniqueKeysWithValues: definition.fields.map { ($0.internalKey, $0) })
        var mapped: [MappedEtaxField] = []

        for field in form.fields {
            guard let definitionField = definitionsByKey[field.id] else {
                continue
            }
            guard let xmlTag = definitionField.xmlTag, !xmlTag.isEmpty else {
                return .failure(.missingXmlTag(internalKey: field.id))
            }
            mapped.append(MappedEtaxField(field: field, xmlTag: xmlTag))
        }

        guard !mapped.isEmpty else {
            return .failure(.noData)
        }
        return .success(mapped.sorted {
            if $0.field.section.rawValue == $1.field.section.rawValue {
                return $0.field.id < $1.field.id
            }
            return $0.field.section.rawValue < $1.field.section.rawValue
        })
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
