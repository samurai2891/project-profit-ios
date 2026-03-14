import Foundation

/// canonical candidate/evidence を TaxLine に自動分類するエンジン
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
        var needsReview: Bool { confidence < 0.90 }
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
        candidate: PostingCandidate,
        evidence: EvidenceDocument?,
        categories: [PPCategory],
        accounts: [PPAccount],
        userRules: [PPUserRule]
    ) -> ClassificationResult {
        let input = ClassificationInput(
            searchText: searchText(candidate: candidate, evidence: evidence),
            transactionType: transactionType(candidate: candidate, evidence: evidence, accounts: accounts),
            categoryId: candidate.legacySnapshot?.categoryId ?? ""
        )
        return classify(input: input, categories: categories, accounts: accounts, userRules: userRules)
    }

    /// バッチ分類: 複数候補を一括分類
    static func classifyBatch(
        candidates: [PostingCandidate],
        evidencesById: [UUID: EvidenceDocument],
        categories: [PPCategory],
        accounts: [PPAccount],
        userRules: [PPUserRule]
    ) -> [(candidate: PostingCandidate, evidence: EvidenceDocument?, result: ClassificationResult)] {
        candidates.map { candidate in
            let evidence = candidate.evidenceId.flatMap { evidencesById[$0] }
            return (
                candidate,
                evidence,
                classify(
                    candidate: candidate,
                    evidence: evidence,
                    categories: categories,
                    accounts: accounts,
                    userRules: userRules
                )
            )
        }
    }

    private static func classify(
        input: ClassificationInput,
        categories: [PPCategory],
        accounts: [PPAccount],
        userRules: [PPUserRule]
    ) -> ClassificationResult {
        let searchText = input.searchText

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
        if let category = categories.first(where: { $0.id == input.categoryId }),
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
        let fallback: TaxLine = input.transactionType == .income ? .salesRevenue : .miscExpense
        return ClassificationResult(
            taxLine: fallback,
            source: .fallback,
            confidence: 0.1
        )
    }
}

@MainActor
enum ClassificationEngineCompatibilityAdapter {
    static func classify(
        transaction: PPTransaction,
        categories: [PPCategory],
        accounts: [PPAccount],
        userRules: [PPUserRule]
    ) -> ClassificationEngine.ClassificationResult {
        ClassificationEngine.classify(
            candidate: PostingCandidate(
                businessId: UUID(),
                taxYear: fiscalYear(for: transaction.date, startMonth: FiscalYearSettings.startMonth),
                candidateDate: transaction.date,
                status: .needsReview,
                source: .manual,
                memo: transaction.memo,
                legacySnapshot: PostingCandidateLegacySnapshot(
                    type: transaction.type,
                    categoryId: transaction.categoryId,
                    recurringId: transaction.recurringId,
                    paymentAccountId: transaction.paymentAccountId,
                    transferToAccountId: transaction.transferToAccountId,
                    taxDeductibleRate: transaction.taxDeductibleRate,
                    taxAmount: transaction.taxAmount,
                    taxCodeId: transaction.taxCodeId,
                    taxRate: transaction.taxRate,
                    isTaxIncluded: transaction.isTaxIncluded,
                    taxCategory: transaction.taxCategory,
                    receiptImagePath: transaction.receiptImagePath,
                    lineItems: transaction.lineItems,
                    counterpartyName: transaction.counterparty
                )
            ),
            evidence: nil,
            categories: categories,
            accounts: accounts,
            userRules: userRules
        )
    }

    static func classifyBatch(
        transactions: [PPTransaction],
        categories: [PPCategory],
        accounts: [PPAccount],
        userRules: [PPUserRule]
    ) -> [(transaction: PPTransaction, result: ClassificationEngine.ClassificationResult)] {
        transactions.map { transaction in
            (
                transaction,
                classify(
                    transaction: transaction,
                    categories: categories,
                    accounts: accounts,
                    userRules: userRules
                )
            )
        }
    }
}

private extension ClassificationEngine {
    struct ClassificationInput {
        let searchText: String
        let transactionType: TransactionType
        let categoryId: String
    }

    static func searchText(candidate: PostingCandidate, evidence: EvidenceDocument?) -> String {
        let orderedSources = [
            candidate.memo,
            candidate.legacySnapshot?.counterpartyName,
            evidence?.structuredFields?.counterpartyName,
            evidence?.ocrText,
            evidence?.searchTokens.joined(separator: " ")
        ]

        let normalized = orderedSources.compactMap { normalizeSearchFragment($0) }
        return normalized.joined(separator: " ")
    }

    static func normalizeSearchFragment(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func transactionType(
        candidate: PostingCandidate,
        evidence: EvidenceDocument?,
        accounts: [PPAccount]
    ) -> TransactionType {
        if let explicitType = candidate.legacySnapshot?.type {
            return explicitType
        }

        let taxLinesBySubtype = Dictionary(uniqueKeysWithValues: TaxLine.allCases.map { ($0.accountSubtype, $0) })
        let accountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        if let categoryId = candidate.legacySnapshot?.categoryId,
           let subtype = categoriesSubtype(for: categoryId, accountsById: accountsById),
           let taxLine = taxLinesBySubtype[subtype] {
            return taxLine.accountSubtype == .salesRevenue ? .income : .expense
        }

        return .expense
    }

    static func categoriesSubtype(for categoryId: String, accountsById: [String: PPAccount]) -> AccountSubtype? {
        guard let linkedAccountId = AccountingConstants.categoryToAccountMapping[categoryId] else {
            return nil
        }
        return accountsById[linkedAccountId]?.subtype
    }
}
