import Foundation

/// 青色申告決算書/収支内訳書の .xtx (XML) ファイルを生成するエクスポーター
@MainActor
enum EtaxXtxExporter {

    private struct MappedEtaxField {
        let field: EtaxField
        let definition: TaxFieldDefinition
        let xmlTag: String
    }

    // MARK: - Public API

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
            let xml = try buildXml(form: form, definition: definition, fields: mappedFields)
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

    /// CSVエクスポート（内部キー・タグ・値の検証用）
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
        lines.append("internalKey,xmlTag,form,セクション,フィールド名,値")

        for mapped in mappedFields {
            let section = csvQuote(mapped.field.section.rawValue)
            let key = csvQuote(mapped.field.id)
            let xmlTag = csvQuote(mapped.xmlTag)
            let formName = csvQuote(mapped.definition.form ?? form.formType.definitionFormKey)
            let label = csvQuote(EtaxCharacterValidator.sanitize(mapped.field.fieldLabel))
            let value = csvQuote(EtaxCharacterValidator.sanitize(mapped.field.value.exportText))
            lines.append("\(key),\(xmlTag),\(formName),\(section),\(label),\(value)")
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

    private static func buildXml(
        form: EtaxForm,
        definition: TaxYearDefinition,
        fields: [MappedEtaxField]
    ) throws -> String {
        switch form.formType {
        case .blueReturn:
            return buildBlueReturnXml(form: form, definition: definition, fields: fields)
        case .whiteReturn:
            return buildWhiteReturnXml(form: form, definition: definition, fields: fields)
        }
    }

    private static func buildBlueReturnXml(
        form: EtaxForm,
        definition: TaxYearDefinition,
        fields: [MappedEtaxField]
    ) -> String {
        let formDef = definition.forms?["blue_general"]
        let rootTag = formDef?.rootTag ?? "KOA210"
        let vr = formDef?.formVer ?? "11.0"

        let formDate = ymd(form.generatedAt)
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<\(rootTag) xmlns=\"http://xml.e-tax.nta.go.jp/XSD/shotoku\" xmlns:gen=\"http://xml.e-tax.nta.go.jp/XSD/general\" VR=\"\(xmlEscape(vr))\" softNM=\"ProjectProfit\" sakuseiNM=\"Project Profit iOS\" sakuseiDay=\"\(formDate)\">")
        lines.append("  <KOA210-1>")

        let mappedByPrefix = Dictionary(grouping: fields, by: { prefix(of: $0.xmlTag) })

        // 損益計算書セクション（AMF系）
        if let amfFields = mappedByPrefix["AMF"], !amfFields.isEmpty {
            lines.append("    <AMF00000>")
            lines.append("      <AMF00010>")
            lines.append("        <AMF00090>")
            lines.append(contentsOf: xmlElementLines(for: amfFields, indent: "          "))
            lines.append("        </AMF00090>")
            lines.append("      </AMF00010>")
            lines.append("    </AMF00000>")
        }

        // 貸借対照表セクション（AMG系）
        if let amgFields = mappedByPrefix["AMG"], !amgFields.isEmpty {
            lines.append("    <AMG00000>")
            lines.append("      <AMG00020>")
            lines.append("        <AMG00240>")
            lines.append(contentsOf: xmlElementLines(for: amgFields, indent: "          "))
            lines.append("        </AMG00240>")
            lines.append("      </AMG00020>")
            lines.append("    </AMG00000>")
        }

        // 共通情報（ABA系）は現行TaxYearマッピングを維持して出力
        if let abaFields = mappedByPrefix["ABA"], !abaFields.isEmpty {
            lines.append("    <ABA00000>")
            lines.append(contentsOf: xmlElementLines(for: abaFields, indent: "      "))
            lines.append("    </ABA00000>")
        }

        // 未知プレフィックスはKOA210-1直下に出力
        let handled = Set(["AMF", "AMG", "ABA"])
        let unknown = fields.filter { !handled.contains(prefix(of: $0.xmlTag)) }
        lines.append(contentsOf: xmlElementLines(for: unknown, indent: "    "))

        lines.append("  </KOA210-1>")
        lines.append("</\(rootTag)>")
        return lines.joined(separator: "\n")
    }

    private static func buildWhiteReturnXml(
        form: EtaxForm,
        definition: TaxYearDefinition,
        fields: [MappedEtaxField]
    ) -> String {
        let formDef = definition.forms?["white_shushi"]
        let rootTag = formDef?.rootTag ?? "KOA110"
        let vr = formDef?.formVer ?? "12.0"

        let formDate = ymd(form.generatedAt)
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<\(rootTag) xmlns=\"http://xml.e-tax.nta.go.jp/XSD/shotoku\" xmlns:gen=\"http://xml.e-tax.nta.go.jp/XSD/general\" VR=\"\(xmlEscape(vr))\" softNM=\"ProjectProfit\" sakuseiNM=\"Project Profit iOS\" sakuseiDay=\"\(formDate)\">")
        lines.append("  <KOA110-1>")

        let mappedByPrefix = Dictionary(grouping: fields, by: { prefix(of: $0.xmlTag) })

        if let aigFields = mappedByPrefix["AIG"], !aigFields.isEmpty {
            lines.append("    <AIG00000>")
            lines.append(contentsOf: xmlElementLines(for: aigFields, indent: "      "))
            lines.append("    </AIG00000>")
        }

        if let ainFields = mappedByPrefix["AIN"], !ainFields.isEmpty {
            lines.append("    <AIN00000>")
            lines.append(contentsOf: xmlElementLines(for: ainFields, indent: "      "))
            lines.append("    </AIN00000>")
        }

        // 未知プレフィックスはKOA110-1直下に出力
        let handled = Set(["AIG", "AIN"])
        let unknown = fields.filter { !handled.contains(prefix(of: $0.xmlTag)) }
        lines.append(contentsOf: xmlElementLines(for: unknown, indent: "    "))

        lines.append("  </KOA110-1>")
        lines.append("</\(rootTag)>")
        return lines.joined(separator: "\n")
    }

    private static func xmlElementLines(for fields: [MappedEtaxField], indent: String) -> [String] {
        fields
            .sorted { $0.xmlTag < $1.xmlTag }
            .map { mapped in
                let value = xmlEscape(EtaxCharacterValidator.sanitize(mapped.field.value.exportText))
                return "\(indent)<\(mapped.xmlTag)>\(value)</\(mapped.xmlTag)>"
            }
    }

    private static func resolveMappedFields(
        form: EtaxForm,
        definition: TaxYearDefinition
    ) -> Result<[MappedEtaxField], EtaxExportError> {
        guard !form.fields.isEmpty else {
            return .failure(.noData)
        }

        let definitions = TaxYearDefinitionLoader.fieldDefinitions(for: form.formType, fiscalYear: form.fiscalYear)
        guard !definitions.isEmpty else {
            return .failure(.unsupportedTaxYear(year: form.fiscalYear))
        }

        let definitionsByKey = Dictionary(uniqueKeysWithValues: definitions.map { ($0.internalKey, $0) })

        var mapped: [MappedEtaxField] = []
        for field in form.fields {
            guard let definitionField = definitionsByKey[field.id] else {
                return .failure(.validationFailed(reasons: ["未定義internalKey: \(field.id)"]))
            }
            guard let xmlTag = definitionField.xmlTag?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !xmlTag.isEmpty
            else {
                return .failure(.missingXmlTag(internalKey: field.id))
            }
            mapped.append(MappedEtaxField(field: field, definition: definitionField, xmlTag: xmlTag))
        }

        guard !mapped.isEmpty else {
            return .failure(.noData)
        }

        return .success(mapped)
    }

    // MARK: - Utilities

    private static func prefix(of xmlTag: String) -> String {
        String(xmlTag.prefix(3)).uppercased()
    }

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

    private static func ymd(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
