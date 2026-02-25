import Foundation

/// 分類辞書をバンドルJSONからロードするサービス
@MainActor
enum ClassificationDictionaryLoader {

    // MARK: - JSON Model

    private struct DictionaryEntry: Codable {
        let keyword: String
        let taxLine: String  // TaxLine.rawValue
    }

    // MARK: - Cache

    private static var cachedRules: [(keyword: String, taxLine: TaxLine)]?

    /// 分類辞書ルールをロードする
    /// JSON未定義またはロード失敗時はインラインフォールバックを返す
    static func load() -> [(keyword: String, taxLine: TaxLine)] {
        if let cached = cachedRules { return cached }

        guard let url = Bundle.main.url(forResource: "ClassificationDictionary", withExtension: "json") else {
            return inlineFallback
        }

        do {
            let data = try Data(contentsOf: url)
            let entries = try JSONDecoder().decode([DictionaryEntry].self, from: data)
            let rules = entries.compactMap { entry -> (keyword: String, taxLine: TaxLine)? in
                guard let taxLine = TaxLine(rawValue: entry.taxLine) else { return nil }
                return (keyword: entry.keyword, taxLine: taxLine)
            }
            guard !rules.isEmpty else { return inlineFallback }
            cachedRules = rules
            return rules
        } catch {
            return inlineFallback
        }
    }

    /// キャッシュをクリアする（テスト用）
    static func clearCache() {
        cachedRules = nil
    }

    // MARK: - Inline Fallback

    /// JSONロード失敗時のフォールバック（元のインラインルール）
    static let inlineFallback: [(keyword: String, taxLine: TaxLine)] = [
        ("AWS", .communicationExpense),
        ("GCP", .communicationExpense),
        ("Azure", .communicationExpense),
        ("Cloudflare", .communicationExpense),
        ("ドメイン", .communicationExpense),
        ("サーバー", .communicationExpense),
        ("インターネット", .communicationExpense),
        ("携帯", .communicationExpense),
        ("電話", .communicationExpense),
        ("JR", .travelExpense),
        ("Suica", .travelExpense),
        ("PASMO", .travelExpense),
        ("タクシー", .travelExpense),
        ("新幹線", .travelExpense),
        ("飛行機", .travelExpense),
        ("航空", .travelExpense),
        ("Amazon", .suppliesExpense),
        ("文房具", .suppliesExpense),
        ("USB", .suppliesExpense),
        ("ケーブル", .suppliesExpense),
        ("家賃", .rentExpense),
        ("賃料", .rentExpense),
        ("レンタルオフィス", .rentExpense),
        ("電気", .utilitiesExpense),
        ("ガス", .utilitiesExpense),
        ("水道", .utilitiesExpense),
        ("Google Ads", .advertisingExpense),
        ("Facebook広告", .advertisingExpense),
        ("広告", .advertisingExpense),
        ("会食", .entertainmentExpense),
        ("贈答", .entertainmentExpense),
        ("外注", .outsourcingExpense),
        ("業務委託", .outsourcingExpense),
        ("フリーランス", .outsourcingExpense),
    ]
}
