import Foundation

/// 現金主義用の青色申告決算書ビルダー
/// 現金主義簡易簿記: 実際の入出金日ベースで収支を計算
@MainActor
enum CashBasisReturnBuilder {

    enum BuildError: LocalizedError {
        case noTransactions

        var errorDescription: String? {
            switch self {
            case .noTransactions:
                return "対象年度の取引データがありません"
            }
        }
    }

    /// 現金主義用の EtaxForm を生成（canonical profile ベース）
    static func build(
        input: FormEngine.BuildInput
    ) throws -> EtaxForm {
        var fields = try buildCoreFields(input: input)

        if let businessProfile = input.businessProfile {
            fields.append(contentsOf: EtaxFieldPopulator.populateDeclarantInfo(
                businessProfile: businessProfile,
                sensitivePayload: input.sensitivePayload
            ))
        }

        return EtaxForm(
            fiscalYear: input.fiscalYear,
            formType: .blueCashBasis,
            fields: fields,
            generatedAt: Date()
        )
    }

    /// 収支フィールドの共通生成ロジック
    private static func buildCoreFields(
        input: FormEngine.BuildInput
    ) throws -> [EtaxField] {
        var totalIncome = 0
        var totalExpense = 0
        var expenseByCategory: [String: Int] = [:]

        for journal in input.canonicalJournals where journal.approvedAt != nil {
            guard let candidateId = journal.sourceCandidateId,
                  let summary = input.candidateSummariesById[candidateId]
            else {
                continue
            }

            let amount = journal.lines.reduce(0) { partialResult, line in
                switch summary.transactionType {
                case .income:
                    guard line.creditAmount > 0 else { return partialResult }
                    return partialResult + NSDecimalNumber(decimal: line.creditAmount).intValue
                case .expense:
                    guard line.debitAmount > 0 else { return partialResult }
                    return partialResult + NSDecimalNumber(decimal: line.debitAmount).intValue
                case .transfer:
                    return partialResult
                }
            }

            guard amount != 0 else {
                continue
            }

            switch summary.transactionType {
            case .income:
                totalIncome += amount
            case .expense:
                totalExpense += amount
                expenseByCategory[summary.resolvedCategoryId, default: 0] += amount
            case .transfer:
                break
            }
        }

        guard totalIncome > 0 || totalExpense > 0 else {
            throw BuildError.noTransactions
        }

        var fields: [EtaxField] = []

        // 収入金額
        fields.append(EtaxField(
            id: "cash_basis_revenue",
            fieldLabel: "ア 収入金額",
            taxLine: nil,
            value: totalIncome,
            section: .revenue
        ))

        // 必要経費
        var expenseIndex = 1
        for (categoryId, amount) in expenseByCategory.sorted(by: {
            if $0.value == $1.value {
                return $0.key < $1.key
            }
            return $0.value > $1.value
        }) {
            let categoryName = input.categoryNamesById[categoryId] ?? categoryId
            let label = "\(expenseFieldLabel(index: expenseIndex)) \(categoryName)"
            fields.append(EtaxField(
                id: "cash_basis_expense_\(expenseIndex)",
                fieldLabel: label,
                taxLine: nil,
                value: amount,
                section: .expenses
            ))
            expenseIndex += 1
        }

        fields.append(EtaxField(
            id: "cash_basis_expense_total",
            fieldLabel: "経費合計",
            taxLine: nil,
            value: totalExpense,
            section: .expenses
        ))

        // 所得金額
        fields.append(EtaxField(
            id: "cash_basis_income",
            fieldLabel: "所得金額",
            taxLine: nil,
            value: totalIncome - totalExpense,
            section: .income
        ))

        return fields
    }

    // MARK: - Helpers

    static func expenseFieldLabel(index: Int) -> String {
        let labels = [
            "イ", "ウ", "エ", "オ", "カ", "キ", "ク", "ケ", "コ",
            "サ", "シ", "ス", "セ", "ソ",
        ]
        guard index > 0, index <= labels.count else { return "他" }
        return labels[index - 1]
    }
}
