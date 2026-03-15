import SwiftData
import Foundation

/// ユーザーの分類修正から学習し、PPUserRuleを自動生成・更新するサービス
@MainActor
enum ClassificationLearningService {

    @discardableResult
    static func learnFromCorrection(
        candidate: PostingCandidate,
        evidence: EvidenceDocument? = nil,
        correctedTaxLine: TaxLine,
        existingRules: [PPUserRule],
        modelContext: ModelContext
    ) -> PPUserRule? {
        learnFromKeyword(
            extractKeyword(from: candidate, evidence: evidence),
            correctedTaxLine: correctedTaxLine,
            existingRules: existingRules,
            modelContext: modelContext
        )
    }

    /// 互換用途。production の main path では candidate/evidence 版を使う。
    @discardableResult
    static func learnFromTransactionCorrection(
        transaction: PPTransaction,
        correctedTaxLine: TaxLine,
        existingRules: [PPUserRule],
        modelContext: ModelContext
    ) -> PPUserRule? {
        learnFromKeyword(
            extractKeyword(from: transaction.memo),
            correctedTaxLine: correctedTaxLine,
            existingRules: existingRules,
            modelContext: modelContext
        )
    }

    /// canonical candidate の承認結果から PPUserRule を生成または更新する
    @discardableResult
    static func learnFromApprovedCandidate(
        candidate: PostingCandidate,
        evidence: EvidenceDocument? = nil,
        resolvedTaxLine: TaxLine,
        existingRules: [PPUserRule],
        modelContext: ModelContext
    ) -> PPUserRule? {
        learnFromKeyword(
            extractKeyword(from: candidate, evidence: evidence),
            correctedTaxLine: resolvedTaxLine,
            existingRules: existingRules,
            modelContext: modelContext
        )
    }

    // MARK: - Keyword Extraction

    static func extractKeyword(from candidate: PostingCandidate, evidence: EvidenceDocument? = nil) -> String {
        let candidates = [
            candidate.memo,
            candidate.legacySnapshot?.counterpartyName,
            evidence?.structuredFields?.counterpartyName,
        ]

        for candidateText in candidates {
            let keyword = extractKeyword(from: candidateText ?? "")
            if !keyword.isEmpty {
                return keyword
            }
        }

        return ""
    }

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

    @discardableResult
    private static func learnFromKeyword(
        _ keyword: String,
        correctedTaxLine: TaxLine,
        existingRules: [PPUserRule],
        modelContext: ModelContext
    ) -> PPUserRule? {
        guard !keyword.isEmpty else { return nil }

        if let existingRule = existingRules.first(where: {
            $0.keyword.lowercased() == keyword.lowercased()
        }) {
            existingRule.taxLine = correctedTaxLine
            existingRule.isActive = true
            existingRule.updatedAt = Date()
            return existingRule
        }

        let newRule = PPUserRule(
            keyword: keyword,
            taxLine: correctedTaxLine,
            priority: 100
        )
        modelContext.insert(newRule)
        return newRule
    }
}
