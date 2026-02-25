import SwiftData
import Foundation

/// ユーザーの分類修正から学習し、PPUserRuleを自動生成・更新するサービス
@MainActor
enum ClassificationLearningService {

    /// ユーザーの手動分類修正からPPUserRuleを生成または更新する
    /// - Parameters:
    ///   - transaction: 修正対象のトランザクション
    ///   - correctedTaxLine: ユーザーが選択した正しいTaxLine
    ///   - existingRules: 既存のPPUserRule一覧
    ///   - modelContext: SwiftData永続化コンテキスト
    /// - Returns: 生成または更新されたPPUserRule（memoが空の場合nil）
    @discardableResult
    static func learnFromCorrection(
        transaction: PPTransaction,
        correctedTaxLine: TaxLine,
        existingRules: [PPUserRule],
        modelContext: ModelContext
    ) -> PPUserRule? {
        let keyword = extractKeyword(from: transaction.memo)
        guard !keyword.isEmpty else { return nil }

        // 同一キーワードの既存ルールがあれば直接更新
        if let existingRule = existingRules.first(where: {
            $0.keyword.lowercased() == keyword.lowercased()
        }) {
            existingRule.taxLine = correctedTaxLine
            existingRule.isActive = true
            existingRule.updatedAt = Date()
            return existingRule
        }

        // 新規ルール作成
        let newRule = PPUserRule(
            keyword: keyword,
            taxLine: correctedTaxLine,
            priority: 100
        )
        modelContext.insert(newRule)
        return newRule
    }

    // MARK: - Keyword Extraction

    /// memoからキーワードを抽出する
    /// 短い（20文字以下）memoはそのまま、長い場合は先頭トークンを使用
    static func extractKeyword(from memo: String) -> String {
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // [定期] プレフィックスを除去
        let cleaned = trimmed
            .replacingOccurrences(of: "[定期] ", with: "")
            .replacingOccurrences(of: "[定期]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "" }

        // 短いmemoはそのまま使用
        if cleaned.count <= 20 { return cleaned }

        // 長いmemoは区切り文字で分割し先頭トークンを使用
        let separators = CharacterSet(charactersIn: " 　・-/|,、。")
        let tokens = cleaned.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return tokens.first ?? cleaned
    }
}
