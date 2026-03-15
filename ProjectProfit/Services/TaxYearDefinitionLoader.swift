import Foundation

/// 年度別TaxLine→フィールドラベル定義をバンドルJSONからロードするサービス
@MainActor
enum TaxYearDefinitionLoader {

    // MARK: - Cache

    private static var cache: [Int: TaxYearDefinition] = [:]
    private static var packYearsCache: [Int]?
    private static let commonFormKey = "common"
    private static let taxYearPackProvider = BundledTaxYearPackProvider(bundle: .main)

    /// 指定年度のTaxLine用フィールドラベルを返す
    /// JSON未定義またはロード失敗時は `taxLine.label` にフォールバック
    static func fieldLabel(for taxLine: TaxLine, fiscalYear: Int) -> String {
        fieldLabel(for: taxLine, formType: .blueReturn, fiscalYear: fiscalYear)
    }

    /// 指定年度・様式のTaxLine用フィールドラベルを返す
    static func fieldLabel(for taxLine: TaxLine, formType: EtaxFormType, fiscalYear: Int) -> String {
        let definition = loadDefinition(for: fiscalYear)
        let candidates = definition?.fields.filter { $0.taxLineRawValue == taxLine.rawValue } ?? []
        let formKey = formType.definitionFormKey

        // 先に対象フォームの定義を優先し、なければ共通定義を参照する
        if let matched = candidates.first(where: { resolvedFormKey(of: $0) == formKey }) {
            return matched.fieldLabel
        }
        if let common = candidates.first(where: { resolvedFormKey(of: $0) == commonFormKey }) {
            return common.fieldLabel
        }
        if let fallback = candidates.first {
            return fallback.fieldLabel
        }
        return taxLine.label
    }

    /// 指定年度の internalKey に対応するフィールド定義を返す
    static func fieldDefinition(for internalKey: String, fiscalYear: Int) -> TaxFieldDefinition? {
        loadDefinition(for: fiscalYear)?.fields.first(where: { $0.internalKey == internalKey })
    }

    /// 指定年度・様式の internalKey に対応するフィールド定義を返す
    static func fieldDefinition(for internalKey: String, formType: EtaxFormType, fiscalYear: Int) -> TaxFieldDefinition? {
        guard let definition = loadDefinition(for: fiscalYear) else {
            return nil
        }
        let formKey = formType.definitionFormKey

        // 対象フォームを優先し、存在しない場合はcommonを許容
        if let matched = definition.fields.first(where: {
            $0.internalKey == internalKey && resolvedFormKey(of: $0) == formKey
        }) {
            return matched
        }
        return definition.fields.first(where: {
            $0.internalKey == internalKey && resolvedFormKey(of: $0) == commonFormKey
        })
    }

    /// 指定年度・様式に対応する全フィールド定義を返す
    static func fieldDefinitions(for formType: EtaxFormType, fiscalYear: Int) -> [TaxFieldDefinition] {
        guard let definition = loadDefinition(for: fiscalYear) else {
            return []
        }
        let formKey = formType.definitionFormKey
        return definition.fields.filter {
            let resolved = resolvedFormKey(of: $0)
            return resolved == formKey || resolved == commonFormKey
        }
    }

    /// 指定年度の internalKey に対応する XML タグを返す
    static func xmlTag(for internalKey: String, fiscalYear: Int) -> String? {
        guard let definition = fieldDefinition(for: internalKey, fiscalYear: fiscalYear),
              let xmlTag = definition.xmlTag,
              !xmlTag.isEmpty
        else {
            return nil
        }
        return xmlTag
    }

    /// 指定年度・様式の internalKey に対応する XML タグを返す
    static func xmlTag(for internalKey: String, formType: EtaxFormType, fiscalYear: Int) -> String? {
        guard let definition = fieldDefinition(for: internalKey, formType: formType, fiscalYear: fiscalYear),
              let xmlTag = definition.xmlTag,
              !xmlTag.isEmpty
        else {
            return nil
        }
        return xmlTag
    }

    /// 指定年度の全フィールド定義をロードする
    /// filing pack のみを正本として組み立てる
    static func loadDefinition(for fiscalYear: Int) -> TaxYearDefinition? {
        if let cached = cache[fiscalYear] { return cached }

        if let packDefinition = loadDefinitionFromPack(for: fiscalYear) {
            cache[fiscalYear] = packDefinition
            return packDefinition
        }
        return nil
    }

    /// パック内の filing/*.json からフィールド定義を組み立てる
    private static func loadDefinitionFromPack(for fiscalYear: Int) -> TaxYearDefinition? {
        guard let filingDir = packFilingDirectoryURL(for: fiscalYear) else {
            return nil
        }

        let filingFiles: [(formKey: String, fileName: String)] = [
            (commonFormKey, "common.json"),
            ("blue_general", "blue_general.json"),
            ("blue_cash_basis", "blue_cash_basis.json"),
            ("white_shushi", "white_shushi.json")
        ]

        var allFields: [TaxFieldDefinition] = []
        var forms: [String: TaxFormDefinition] = [:]
        var foundAny = false

        for filing in filingFiles {
            let fileURL = filingDir.appendingPathComponent(filing.fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let parsed = try? JSONDecoder().decode(PackFilingDefinition.self, from: data)
            else {
                continue
            }
            foundAny = true

            forms[filing.formKey] = TaxFormDefinition(
                formId: parsed.formId,
                formVer: parsed.formVer,
                rootTag: parsed.rootTag,
                mappingFile: nil
            )

            for section in parsed.sections {
                for field in section.fields {
                    let taxFieldDef = TaxFieldDefinition(
                        internalKey: field.internalKey,
                        fieldLabel: field.fieldLabel,
                        xmlTag: field.xmlTag,
                        taxLineRawValue: field.taxLineRawValue ?? resolveTaxLineRawValue(for: field.internalKey),
                        section: section.id,
                        dataType: EtaxFieldDataType(rawValue: field.dataType),
                        form: filing.formKey,
                        idref: field.idref,
                        format: field.format,
                        requiredRule: field.requiredRule
                    )
                    allFields.append(taxFieldDef)
                }
            }
        }

        guard foundAny else { return nil }

        return TaxYearDefinition(
            fiscalYear: fiscalYear,
            forms: forms,
            fields: allFields
        )
    }

    /// パック内の filing ディレクトリ URL を返す
    private static func packFilingDirectoryURL(for fiscalYear: Int) -> URL? {
        // バンドルリソース内のフォルダ型パス
        if let bundledRoot = Bundle.main.resourceURL {
            let filingDir = bundledRoot
                .appendingPathComponent("TaxYearPacks", isDirectory: true)
                .appendingPathComponent(String(fiscalYear), isDirectory: true)
                .appendingPathComponent("filing", isDirectory: true)
            if FileManager.default.fileExists(atPath: filingDir.path) {
                return filingDir
            }
        }

        // ソースツリーからのフォールバック（テスト時）
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // ProjectProfit
        let sourceFiling = sourceRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("TaxYearPacks", isDirectory: true)
            .appendingPathComponent(String(fiscalYear), isDirectory: true)
            .appendingPathComponent("filing", isDirectory: true)
        return FileManager.default.fileExists(atPath: sourceFiling.path) ? sourceFiling : nil
    }

    /// internalKey から TaxLine.rawValue を逆引きする
    private static func resolveTaxLineRawValue(for internalKey: String) -> String? {
        // pack filing フィールドの internalKey と TaxLine.rawValue のマッピング
        let mappings: [String: String] = [
            "revenue_sales_revenue": "sales_revenue",
            "revenue_other_income": "other_income",
            "expense_rent": "rent",
            "expense_utilities": "utilities",
            "expense_travel": "travel",
            "expense_communication": "communication",
            "expense_advertising": "advertising",
            "expense_entertainment": "entertainment",
            "expense_depreciation": "depreciation",
            "expense_insurance": "insurance",
            "expense_interest": "interest",
            "expense_supplies": "supplies",
            "expense_taxes": "taxes",
            "expense_outsourcing": "outsourcing",
            "expense_misc": "misc",
            "shushi_revenue_total": "sales_revenue",
            "shushi_expense_rent": "rent",
            "shushi_expense_utilities": "utilities",
            "shushi_expense_travel": "travel",
            "shushi_expense_communication": "communication",
            "shushi_expense_advertising": "advertising",
            "shushi_expense_entertainment": "entertainment",
            "shushi_expense_depreciation": "depreciation",
            "shushi_expense_insurance": "insurance",
            "shushi_expense_interest": "interest",
            "shushi_expense_supplies": "supplies",
            "shushi_expense_taxes": "taxes",
            "shushi_expense_outsourcing": "outsourcing",
            "shushi_expense_misc": "misc",
            "shushi_rent_breakdown": "rent"
        ]
        return mappings[internalKey]
    }

    /// 対応済み年分かどうかを返す
    static func isSupported(year fiscalYear: Int) -> Bool {
        loadDefinition(for: fiscalYear) != nil || supportedPackYears().contains(fiscalYear)
    }

    /// 指定様式が対応済みかどうかを返す
    static func isSupported(year fiscalYear: Int, formType: EtaxFormType) -> Bool {
        guard let definition = loadDefinition(for: fiscalYear) else {
            return false
        }
        let formKey = formType.definitionFormKey

        // formsメタがあればそれを優先
        if let forms = definition.forms, forms[formKey] != nil {
            return true
        }
        // 旧定義との互換のため fields から判定
        return definition.fields.contains { resolvedFormKey(of: $0) == formKey }
    }

    /// バンドルに存在する対応年分一覧を返す
    static func supportedYears() -> [Int] {
        supportedYears(formType: nil)
    }

    /// 指定様式で利用可能な対応年分一覧を返す
    static func supportedYears(formType: EtaxFormType?) -> [Int] {
        let sorted = supportedPackYears().sorted()
        guard let formType else {
            return sorted
        }
        return sorted.filter { isSupported(year: $0, formType: formType) }
    }

    /// キャッシュをクリアする（テスト用）
    static func clearCache() {
        cache = [:]
        packYearsCache = nil
    }

    /// 全TaxLineのラベルが定義されているか検証する
    static func validateCoverage(for fiscalYear: Int) -> [TaxLine] {
        guard let definition = loadDefinition(for: fiscalYear) else {
            return TaxLine.allCases.map { $0 }
        }
        let definedRawValues = Set(definition.fields.compactMap(\.taxLineRawValue))
        return TaxLine.allCases.filter { !definedRawValues.contains($0.rawValue) }
    }

    // MARK: - Helpers

    private static func resolvedFormKey(of definition: TaxFieldDefinition) -> String {
        if let explicit = definition.form?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty
        {
            return explicit
        }

        // 後方互換: 旧TaxYear定義（formなし）を推定
        let key = definition.internalKey
        if key.hasPrefix("shushi_") {
            return "white_shushi"
        }
        if key.hasPrefix("declarant_") {
            return commonFormKey
        }
        return "blue_general"
    }

    private static func supportedPackYears() -> [Int] {
        if let cached = packYearsCache {
            return cached
        }
        let years = taxYearPackProvider.availableYearsSync()
        packYearsCache = years
        return years
    }
}

// MARK: - Pack Filing Definition (Decode-only)

/// パック内 filing/*.json のデコード用構造体
private struct PackFilingDefinition: Decodable {
    let formType: String
    let taxYear: Int
    let formId: String
    let formVer: String
    let rootTag: String
    let displayName: String
    let filingDeadline: String
    let sections: [PackFilingSection]
}

private struct PackFilingSection: Decodable {
    let id: String
    let label: String
    let fields: [PackFilingField]
}

private struct PackFilingField: Decodable {
    let internalKey: String
    let fieldLabel: String
    let xmlTag: String?
    let dataType: String
    let taxLineRawValue: String?
    let format: String?
    let requiredRule: String?
    let idref: String?
}
