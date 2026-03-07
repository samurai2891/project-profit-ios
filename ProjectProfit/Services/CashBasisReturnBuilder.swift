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

    /// 現金主義用の EtaxForm を生成
    static func build(
        fiscalYear: Int,
        dataStore: DataStore,
        profile: PPAccountingProfile?
    ) throws -> EtaxForm {
        let startMonth = FiscalYearSettings.startMonth
        let startDate = startOfFiscalYear(fiscalYear, startMonth: startMonth)
        let endDate = endOfFiscalYear(fiscalYear, startMonth: startMonth)

        // 現金主義: 取引の date ベースで集計（発生主義ではなく入出金日）
        let yearTransactions = dataStore.transactions.filter { tx in
            tx.date >= startDate && tx.date <= endDate
        }

        guard !yearTransactions.isEmpty else {
            throw BuildError.noTransactions
        }

        let totalIncome = yearTransactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
        let totalExpense = yearTransactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }

        // 経費をカテゴリ別に集計
        let expenseByCategory = Dictionary(
            grouping: yearTransactions.filter { $0.type == .expense },
            by: \.categoryId
        ).mapValues { txs in txs.reduce(0) { $0 + $1.amount } }

        let categoryMap = Dictionary(
            uniqueKeysWithValues: dataStore.categories.map { ($0.id, $0.name) }
        )

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
        for (categoryId, amount) in expenseByCategory.sorted(by: { $0.value > $1.value }) {
            let categoryName = categoryMap[categoryId] ?? categoryId
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

        // 申告者情報
        if let profile {
            fields.append(contentsOf: EtaxFieldPopulator.populateDeclarantInfo(profile: profile))
        }

        return EtaxForm(
            fiscalYear: fiscalYear,
            formType: .blueCashBasis,
            fields: fields,
            generatedAt: Date()
        )
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
