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
    static func loadDefinition(for fiscalYear: Int) -> TaxYearDefinition? {
        if let cached = cache[fiscalYear] { return cached }

        let fileName = "TaxYear\(fiscalYear)"
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let definition = try JSONDecoder().decode(TaxYearDefinition.self, from: data)
            cache[fiscalYear] = definition
            return definition
        } catch {
            return nil
        }
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
        var years = jsonSupportedYears()
        years.formUnion(supportedPackYears())

        let sorted = years.sorted()
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

    private static func jsonSupportedYears() -> Set<Int> {
        let filePaths = Bundle.main.paths(forResourcesOfType: "json", inDirectory: nil)
        let prefix = "TaxYear"
        let suffix = ".json"

        var years = Set(cache.keys)
        for path in filePaths {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            guard fileName.hasPrefix(prefix), fileName.hasSuffix(suffix) else { continue }
            let raw = fileName
                .replacingOccurrences(of: prefix, with: "")
                .replacingOccurrences(of: suffix, with: "")
            if let year = Int(raw) {
                years.insert(year)
            }
        }
        return years
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
