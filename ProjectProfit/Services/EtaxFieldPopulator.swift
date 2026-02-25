import Foundation

/// P&L / B/S レポートデータを e-Tax フィールドにマッピングする
@MainActor
enum EtaxFieldPopulator {

    /// P&Lレポートからe-Taxフォームを生成
    static func populate(
        fiscalYear: Int,
        profitLoss: ProfitLossReport,
        balanceSheet: BalanceSheetReport?,
        formType: EtaxFormType = .blueReturn,
        accounts: [PPAccount]
    ) -> EtaxForm {
        var fields: [EtaxField] = []

        // 収入セクション — 同じTaxLineの項目は合算
        var revenueByTaxLine: [TaxLine: Int] = [:]
        for item in profitLoss.revenueItems {
            if let taxLine = taxLineForAccountId(item.id, accounts: accounts) {
                revenueByTaxLine[taxLine, default: 0] += item.amount
            }
        }
        for (taxLine, amount) in revenueByTaxLine.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            fields.append(EtaxField(
                id: "revenue_\(taxLine.rawValue)",
                fieldLabel: TaxYearDefinitionLoader.fieldLabel(for: taxLine, fiscalYear: fiscalYear),
                taxLine: taxLine,
                value: amount,
                section: .revenue
            ))
        }

        // 経費セクション — 同じTaxLineの項目は合算
        var expenseByTaxLine: [TaxLine: Int] = [:]
        for item in profitLoss.expenseItems {
            if let taxLine = taxLineForAccountId(item.id, accounts: accounts) {
                expenseByTaxLine[taxLine, default: 0] += item.amount
            }
        }
        for (taxLine, amount) in expenseByTaxLine.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            fields.append(EtaxField(
                id: "expense_\(taxLine.rawValue)",
                fieldLabel: TaxYearDefinitionLoader.fieldLabel(for: taxLine, fiscalYear: fiscalYear),
                taxLine: taxLine,
                value: amount,
                section: .expenses
            ))
        }

        // 所得金額セクション
        fields.append(EtaxField(
            id: "income_total_revenue",
            fieldLabel: "収入金額合計",
            taxLine: nil,
            value: profitLoss.totalRevenue,
            section: .income
        ))
        fields.append(EtaxField(
            id: "income_total_expenses",
            fieldLabel: "必要経費合計",
            taxLine: nil,
            value: profitLoss.totalExpenses,
            section: .income
        ))
        fields.append(EtaxField(
            id: "income_net",
            fieldLabel: "所得金額",
            taxLine: nil,
            value: profitLoss.netIncome,
            section: .income
        ))

        return EtaxForm(
            fiscalYear: fiscalYear,
            formType: formType,
            fields: fields,
            generatedAt: Date()
        )
    }

    // MARK: - Helpers

    private static func taxLineForAccountId(_ accountId: String, accounts: [PPAccount]) -> TaxLine? {
        guard let account = accounts.first(where: { $0.id == accountId }),
              let subtype = account.subtype
        else { return nil }

        return TaxLine.allCases.first { $0.accountSubtype == subtype }
    }
}
