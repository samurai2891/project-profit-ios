import Foundation

/// トランザクションを TaxLine に自動分類するエンジン
///
/// ルール優先度:
/// 1. ユーザー定義ルール（PPUserRule、priority順）
/// 2. 辞書ルール（ClassificationDictionary）
/// 3. カテゴリ → 勘定科目 → TaxLine のフォールバック
@MainActor
enum ClassificationEngine {

    // MARK: - Confidence Thresholds

    /// 高信頼度閾値: この値以上なら自動分類として確定扱い
    static let highConfidenceThreshold = 0.90
    /// 低信頼度閾値: この値未満は要レビュー
    static let lowConfidenceThreshold = 0.60

    struct ClassificationResult {
        let taxLine: TaxLine
        let source: ClassificationSource
        let confidence: Double  // 0.0 ~ 1.0

        /// 信頼度が高信頼度閾値未満の場合 true（ユーザー確認が必要）
        var needsReview: Bool { confidence < ClassificationEngine.highConfidenceThreshold }
    }

    enum ClassificationSource: String {
        case userRule = "ユーザールール"
        case dictionary = "辞書マッチ"
        case categoryMapping = "カテゴリ紐付け"
        case fallback = "フォールバック"
    }

    // MARK: - Dictionary Rules

    /// 辞書ルール: バンドルJSONからロード、失敗時はインラインフォールバック
    static var dictionaryRules: [(keyword: String, taxLine: TaxLine)] {
        ClassificationDictionaryLoader.load()
    }

    // MARK: - Classify

    static func classify(
        transaction: PPTransaction,
        categories: [PPCategory],
        accounts: [PPAccount],
        userRules: [PPUserRule]
    ) -> ClassificationResult {
        let searchText = transaction.memo.lowercased()

        // 1. ユーザー定義ルール
        let activeRules = userRules
            .filter(\.isActive)
            .sorted { $0.priority > $1.priority }

        for rule in activeRules {
            if searchText.contains(rule.keyword.lowercased()) {
                return ClassificationResult(
                    taxLine: rule.taxLine,
                    source: .userRule,
                    confidence: 1.0
                )
            }
        }

        // 2. 辞書マッチ
        for rule in dictionaryRules {
            if searchText.contains(rule.keyword.lowercased()) {
                return ClassificationResult(
                    taxLine: rule.taxLine,
                    source: .dictionary,
                    confidence: 0.8
                )
            }
        }

        // 3. カテゴリ → 勘定科目 → TaxLine
        if let category = categories.first(where: { $0.id == transaction.categoryId }),
           let linkedAccountId = category.linkedAccountId,
           let account = accounts.first(where: { $0.id == linkedAccountId }),
           let subtype = account.subtype,
           let matchedTaxLine = TaxLine.allCases.first(where: { $0.accountSubtype == subtype })
        {
            return ClassificationResult(
                taxLine: matchedTaxLine,
                source: .categoryMapping,
                confidence: 0.6
            )
        }

        // 4. フォールバック
        let fallback: TaxLine = transaction.type == .income ? .salesRevenue : .miscExpense
        return ClassificationResult(
            taxLine: fallback,
            source: .fallback,
            confidence: 0.1
        )
    }

    /// バッチ分類: 複数トランザクションを一括分類
    static func classifyBatch(
        transactions: [PPTransaction],
        categories: [PPCategory],
        accounts: [PPAccount],
        userRules: [PPUserRule]
    ) -> [(transaction: PPTransaction, result: ClassificationResult)] {
        transactions.map { tx in
            (tx, classify(transaction: tx, categories: categories, accounts: accounts, userRules: userRules))
        }
    }
}
