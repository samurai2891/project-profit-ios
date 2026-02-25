import Foundation

/// 白色申告 収支内訳書ビルダー
/// 白色申告の場合、青色と異なりフィールド構成がシンプル
@MainActor
enum ShushiNaiyakushoBuilder {

    /// 白色申告 収支内訳書用のEtaxFormを生成
    static func build(
        fiscalYear: Int,
        profitLoss: ProfitLossReport,
        accounts: [PPAccount],
        fixedAssets: [PPFixedAsset] = [],
        journalLines: [PPJournalLine] = [],
        journalEntries: [PPJournalEntry] = []
    ) -> EtaxForm {
        var fields: [EtaxField] = []

        // 収入 — 売上のみ（白色は簡易）
        let totalRevenue = profitLoss.totalRevenue
        fields.append(EtaxField(
            id: "shushi_revenue_total",
            fieldLabel: "収入金額",
            taxLine: .salesRevenue,
            value: totalRevenue,
            section: .revenue
        ))

        // 経費 — e-Tax 12区分でマッピング（同じTaxLineは合算）
        var expenseByTaxLine: [TaxLine: Int] = [:]
        for item in profitLoss.expenseItems {
            if let account = accounts.first(where: { $0.id == item.id }),
               let subtype = account.subtype,
               let taxLine = TaxLine.allCases.first(where: { $0.accountSubtype == subtype })
            {
                expenseByTaxLine[taxLine, default: 0] += item.amount
            }
        }
        for (taxLine, amount) in expenseByTaxLine.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            fields.append(EtaxField(
                id: "shushi_expense_\(taxLine.rawValue)",
                fieldLabel: TaxYearDefinitionLoader.fieldLabel(for: taxLine, fiscalYear: fiscalYear),
                taxLine: taxLine,
                value: amount,
                section: .expenses
            ))
        }

        // 経費合計
        let totalExpenses = profitLoss.totalExpenses
        fields.append(EtaxField(
            id: "shushi_expense_total",
            fieldLabel: "経費合計",
            taxLine: nil,
            value: totalExpenses,
            section: .expenses
        ))

        // 所得金額
        fields.append(EtaxField(
            id: "shushi_income_net",
            fieldLabel: "所得金額",
            taxLine: nil,
            value: totalRevenue - totalExpenses,
            section: .income
        ))

        // 付表: 減価償却明細
        if !fixedAssets.isEmpty {
            let scheduleRows = DepreciationScheduleBuilder.build(assets: fixedAssets, fiscalYear: fiscalYear)
            for (index, row) in scheduleRows.enumerated() {
                fields.append(EtaxField(
                    id: "shushi_depreciation_\(index)",
                    fieldLabel: "\(row.assetName)（\(row.depreciationMethod.label)）",
                    taxLine: .depreciationExpense,
                    value: row.currentYearAmount,
                    section: .fixedAssetSchedule
                ))
            }
        }

        // 付表: 地代家賃内訳
        let rentAccountId = AccountingConstants.defaultAccountsById["acct-rent"]?.id ?? "acct-rent"
        let postedEntryIds = Set(
            journalEntries
                .filter { $0.isPosted }
                .map(\.id)
        )
        let rentLines = journalLines.filter { line in
            line.accountId == rentAccountId && postedEntryIds.contains(line.entryId)
        }
        let rentTotal = rentLines.reduce(0) { $0 + $1.debit } - rentLines.reduce(0) { $0 + $1.credit }
        if rentTotal > 0 {
            fields.append(EtaxField(
                id: "shushi_rent_breakdown",
                fieldLabel: "地代家賃合計",
                taxLine: .rentExpense,
                value: rentTotal,
                section: .deductions
            ))
        }

        return EtaxForm(
            fiscalYear: fiscalYear,
            formType: .whiteReturn,
            fields: fields,
            generatedAt: Date()
        )
    }
}
