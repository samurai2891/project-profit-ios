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
