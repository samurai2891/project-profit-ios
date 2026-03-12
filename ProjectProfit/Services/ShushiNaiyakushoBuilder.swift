import Foundation

/// 白色申告 収支内訳書ビルダー
/// 白色申告の場合、青色と異なりフィールド構成がシンプル
@MainActor
enum ShushiNaiyakushoBuilder {
    /// 白色申告 収支内訳書用のEtaxFormを生成（canonical profile ベース）
    static func build(
        profitLoss: ProfitLossReport,
        input: FormEngine.BuildInput
    ) -> EtaxForm {
        let fields = buildFields(
            profitLoss: profitLoss,
            input: input
        )

        var allFields = fields
        if let businessProfile = input.businessProfile {
            allFields.append(contentsOf: EtaxFieldPopulator.populateDeclarantInfo(
                businessProfile: businessProfile,
                sensitivePayload: input.sensitivePayload
            ))
        }

        return EtaxForm(
            fiscalYear: input.fiscalYear,
            formType: .whiteReturn,
            fields: allFields,
            generatedAt: Date()
        )
    }

    // MARK: - Private

    /// 共通のフィールド生成ロジック（申告者情報を除く）
    private static func buildFields(
        profitLoss: ProfitLossReport,
        input: FormEngine.BuildInput
    ) -> [EtaxField] {
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
            if let account = input.accounts.first(where: { $0.id == item.id }),
               let subtype = account.subtype,
               let taxLine = TaxLine.allCases.first(where: { $0.accountSubtype == subtype })
            {
                expenseByTaxLine[taxLine, default: 0] += item.amount
            }
        }
        for (taxLine, amount) in expenseByTaxLine.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            fields.append(EtaxField(
                id: "shushi_expense_\(taxLine.rawValue)",
                fieldLabel: TaxYearDefinitionLoader.fieldLabel(
                    for: taxLine,
                    formType: .whiteReturn,
                    fiscalYear: input.fiscalYear
                ),
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
        if !input.fixedAssets.isEmpty {
            let scheduleRows = DepreciationScheduleBuilder.build(
                assets: input.fixedAssets,
                fiscalYear: input.fiscalYear
            )
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
        let postedRentTotal = postedRentTotal(input: input)
        if postedRentTotal > 0 {
            fields.append(EtaxField(
                id: "shushi_rent_breakdown",
                fieldLabel: "地代家賃合計",
                taxLine: .rentExpense,
                value: postedRentTotal,
                section: .deductions
            ))
        }

        return fields
    }

    private static func postedRentTotal(input: FormEngine.BuildInput) -> Int {
        let rentAccountIds = Set(
            input.accounts
                .filter { $0.subtype == .rentExpense }
                .map(\.id)
        )
        let resolvedRentAccountIds = rentAccountIds.isEmpty
            ? [AccountingConstants.defaultAccountsById["acct-rent"]?.id ?? "acct-rent"]
            : Array(rentAccountIds)
        let postedEntryIds = Set(input.projectedEntries.lazy.filter(\.isPosted).map(\.id))

        return input.projectedLines.reduce(into: 0) { partialResult, line in
            guard resolvedRentAccountIds.contains(line.accountId),
                  postedEntryIds.contains(line.entryId)
            else {
                return
            }
            partialResult += line.debit - line.credit
        }
    }
}
