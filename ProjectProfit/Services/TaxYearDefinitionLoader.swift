import Foundation

/// 年度別TaxLine→フィールドラベル定義をバンドルJSONからロードするサービス
@MainActor
enum TaxYearDefinitionLoader {

    // MARK: - Cache

    private static var cache: [Int: TaxYearDefinition] = [:]

    /// 指定年度のTaxLine用フィールドラベルを返す
    /// JSON未定義またはロード失敗時は `taxLine.label` にフォールバック
    static func fieldLabel(for taxLine: TaxLine, fiscalYear: Int) -> String {
        let definition = loadDefinition(for: fiscalYear)
        guard let field = definition?.fields.first(where: {
            $0.taxLineRawValue == taxLine.rawValue
        }) else {
            return taxLine.label
        }
        return field.fieldLabel
    }

    /// 指定年度の internalKey に対応するフィールド定義を返す
    static func fieldDefinition(for internalKey: String, fiscalYear: Int) -> TaxFieldDefinition? {
        loadDefinition(for: fiscalYear)?.fields.first(where: { $0.internalKey == internalKey })
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
        loadDefinition(for: fiscalYear) != nil
    }

    /// バンドルに存在する対応年分一覧を返す
    static func supportedYears() -> [Int] {
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
        return years.sorted()
    }

    /// キャッシュをクリアする（テスト用）
    static func clearCache() {
        cache = [:]
    }

    /// 全TaxLineのラベルが定義されているか検証する
    static func validateCoverage(for fiscalYear: Int) -> [TaxLine] {
        guard let definition = loadDefinition(for: fiscalYear) else {
            return TaxLine.allCases.map { $0 }
        }
        let definedRawValues = Set(definition.fields.compactMap(\.taxLineRawValue))
        return TaxLine.allCases.filter { !definedRawValues.contains($0.rawValue) }
    }
}
