import Foundation

/// 白色申告 収支内訳書ビルダー
/// 白色申告の場合、青色と異なりフィールド構成がシンプル
@MainActor
enum ShushiNaiyakushoBuilder {
    /// 白色申告 収支内訳書用のEtaxFormを生成（canonical profile ベース）
    static func build(
        canonicalProfitLoss: CanonicalProfitLossReport,
        input: FormEngine.BuildInput
    ) -> EtaxForm {
        let fields = buildFields(
            canonicalProfitLoss: canonicalProfitLoss,
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
        canonicalProfitLoss: CanonicalProfitLossReport,
        input: FormEngine.BuildInput
    ) -> [EtaxField] {
        var fields: [EtaxField] = []

        let totalRevenue = decimalInt(canonicalProfitLoss.totalRevenue)
        let homeConsumption = 0
        let otherRevenue = 0

        fields.append(EtaxField(
            id: "shushi_revenue_sales",
            fieldLabel: "売上（収入）金額",
            taxLine: .salesRevenue,
            value: totalRevenue,
            section: .revenue
        ))
        fields.append(EtaxField(
            id: "shushi_revenue_total",
            fieldLabel: "計",
            taxLine: .salesRevenue,
            value: totalRevenue + homeConsumption + otherRevenue,
            section: .revenue
        ))
        fields.append(EtaxField(
            id: "shushi_revenue_home_consumption",
            fieldLabel: "家事消費",
            taxLine: nil,
            value: homeConsumption,
            section: .revenue
        ))
        fields.append(EtaxField(
            id: "shushi_revenue_other",
            fieldLabel: "その他の収入",
            taxLine: nil,
            value: otherRevenue,
            section: .revenue
        ))

        fields.append(EtaxField(
            id: "shushi_inventory_opening",
            fieldLabel: "期首商品（製品）棚卸高",
            taxLine: nil,
            value: 0,
            section: .inventory
        ))
        fields.append(EtaxField(
            id: "shushi_inventory_purchases",
            fieldLabel: "仕入金額（製品製造原価）",
            taxLine: nil,
            value: 0,
            section: .inventory
        ))
        fields.append(EtaxField(
            id: "shushi_inventory_subtotal",
            fieldLabel: "小計",
            taxLine: nil,
            value: 0,
            section: .inventory
        ))
        fields.append(EtaxField(
            id: "shushi_inventory_closing",
            fieldLabel: "期末商品（製品）棚卸高",
            taxLine: nil,
            value: 0,
            section: .inventory
        ))
        fields.append(EtaxField(
            id: "shushi_inventory_cogs",
            fieldLabel: "差引原価",
            taxLine: nil,
            value: 0,
            section: .inventory
        ))
        fields.append(EtaxField(
            id: "shushi_income_gross",
            fieldLabel: "差引金額",
            taxLine: nil,
            value: totalRevenue,
            section: .income
        ))

        // 経費 — e-Tax 区分でマッピング（同じTaxLineは合算）
        var expenseByTaxLine: [TaxLine: Int] = [:]
        for item in canonicalProfitLoss.expenseItems {
            if let taxLine = taxLine(for: item.id, canonicalAccountsById: input.canonicalAccountsById) {
                expenseByTaxLine[taxLine, default: 0] += decimalInt(item.amount)
            }
        }
        var expenseByFieldId: [String: Int] = [:]
        for (taxLine, amount) in expenseByTaxLine.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let fieldId = "shushi_expense_\(taxLine.rawValue)"
            expenseByFieldId[fieldId] = amount
            fields.append(EtaxField(
                id: fieldId,
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

        let totalExpenses = decimalInt(canonicalProfitLoss.totalExpenses)
        let directExpenseKeys: Set<String> = [
            "shushi_expense_salary",
            "shushi_expense_outsourcing",
            "shushi_expense_depreciation",
            "shushi_expense_bad_debt",
            "shushi_expense_rent",
            "shushi_expense_interest"
        ]
        let otherExpenseSubtotal = expenseByFieldId.reduce(into: 0) { partialResult, entry in
            guard !directExpenseKeys.contains(entry.key) else {
                return
            }
            partialResult += entry.value
        }

        fields.append(EtaxField(
            id: "shushi_expense_other_subtotal",
            fieldLabel: "小計",
            taxLine: nil,
            value: otherExpenseSubtotal,
            section: .expenses
        ))
        fields.append(EtaxField(
            id: "shushi_expense_total",
            fieldLabel: "経費合計",
            taxLine: nil,
            value: totalExpenses,
            section: .expenses
        ))

        fields.append(EtaxField(
            id: "shushi_income_before_employee_deduction",
            fieldLabel: "専従者控除前の所得金額",
            taxLine: nil,
            value: totalRevenue - totalExpenses,
            section: .income
        ))
        fields.append(EtaxField(
            id: "shushi_employee_deduction",
            fieldLabel: "専従者控除",
            taxLine: nil,
            value: 0,
            section: .income
        ))
        fields.append(EtaxField(
            id: "shushi_income_net",
            fieldLabel: "所得金額",
            taxLine: nil,
            value: totalRevenue - totalExpenses,
            section: .income
        ))

        if !input.fixedAssets.isEmpty {
            let scheduleRows = DepreciationScheduleBuilder.build(
                assets: input.fixedAssets,
                fiscalYear: input.fiscalYear
            )
            var ordinaryTotal = 0
            var expenseTotal = 0
            for (index, row) in scheduleRows.prefix(6).enumerated() {
                let rowNumber = index + 1
                let amount = row.currentYearAmount
                ordinaryTotal += amount
                expenseTotal += amount
                let assetName = row.assetName
                let method = row.depreciationMethod.label

                fields.append(EtaxField(
                    id: "shushi_depreciation_detail_\(rowNumber)_name",
                    fieldLabel: "減価償却資産の名称等",
                    taxLine: nil,
                    value: assetName,
                    section: .fixedAssetSchedule
                ))
                fields.append(EtaxField(
                    id: "shushi_depreciation_detail_\(rowNumber)_acquired_year_month",
                    fieldLabel: "取得年月",
                    taxLine: nil,
                    value: "",
                    section: .fixedAssetSchedule
                ))
                fields.append(EtaxField(
                    id: "shushi_depreciation_detail_\(rowNumber)_acquisition_cost",
                    fieldLabel: "取得価額",
                    taxLine: nil,
                    value: 0,
                    section: .fixedAssetSchedule
                ))
                fields.append(EtaxField(
                    id: "shushi_depreciation_detail_\(rowNumber)_method",
                    fieldLabel: "償却方法",
                    taxLine: nil,
                    value: method,
                    section: .fixedAssetSchedule
                ))
                fields.append(EtaxField(
                    id: "shushi_depreciation_detail_\(rowNumber)_useful_life",
                    fieldLabel: "耐用年数",
                    taxLine: nil,
                    value: 0,
                    section: .fixedAssetSchedule
                ))
                fields.append(EtaxField(
                    id: "shushi_depreciation_detail_\(rowNumber)_period_months",
                    fieldLabel: "本年中の償却期間",
                    taxLine: nil,
                    value: 12,
                    section: .fixedAssetSchedule
                ))
                fields.append(EtaxField(
                    id: "shushi_depreciation_detail_\(rowNumber)_ordinary_amount",
                    fieldLabel: "本年分の普通償却費",
                    taxLine: .depreciationExpense,
                    value: amount,
                    section: .fixedAssetSchedule
                ))
                fields.append(EtaxField(
                    id: "shushi_depreciation_detail_\(rowNumber)_necessary_expense_amount",
                    fieldLabel: "本年分の必要経費算入額",
                    taxLine: .depreciationExpense,
                    value: amount,
                    section: .fixedAssetSchedule
                ))
                fields.append(EtaxField(
                    id: "shushi_depreciation_detail_\(rowNumber)_remaining_balance",
                    fieldLabel: "未償却残高",
                    taxLine: nil,
                    value: 0,
                    section: .fixedAssetSchedule
                ))
            }

            fields.append(EtaxField(
                id: "shushi_depreciation_next_total_label",
                fieldLabel: "減価償却費の計算（次葉合計）",
                taxLine: nil,
                value: "",
                section: .fixedAssetSchedule
            ))
            fields.append(EtaxField(
                id: "shushi_depreciation_total_ordinary",
                fieldLabel: "本年分の普通償却費",
                taxLine: nil,
                value: ordinaryTotal,
                section: .fixedAssetSchedule
            ))
            fields.append(EtaxField(
                id: "shushi_depreciation_total_special",
                fieldLabel: "特別償却費",
                taxLine: nil,
                value: 0,
                section: .fixedAssetSchedule
            ))
            fields.append(EtaxField(
                id: "shushi_depreciation_total_amount",
                fieldLabel: "本年分の償却費合計",
                taxLine: nil,
                value: ordinaryTotal,
                section: .fixedAssetSchedule
            ))
            fields.append(EtaxField(
                id: "shushi_depreciation_total_necessary_expense",
                fieldLabel: "本年分の必要経費算入額",
                taxLine: nil,
                value: expenseTotal,
                section: .fixedAssetSchedule
            ))
            fields.append(EtaxField(
                id: "shushi_depreciation_total_remaining_balance",
                fieldLabel: "未償却残高",
                taxLine: nil,
                value: 0,
                section: .fixedAssetSchedule
            ))
        } else {
            fields.append(EtaxField(
                id: "shushi_depreciation_total_ordinary",
                fieldLabel: "本年分の普通償却費",
                taxLine: nil,
                value: 0,
                section: .fixedAssetSchedule
            ))
            fields.append(EtaxField(
                id: "shushi_depreciation_total_special",
                fieldLabel: "特別償却費",
                taxLine: nil,
                value: 0,
                section: .fixedAssetSchedule
            ))
            fields.append(EtaxField(
                id: "shushi_depreciation_total_amount",
                fieldLabel: "本年分の償却費合計",
                taxLine: nil,
                value: 0,
                section: .fixedAssetSchedule
            ))
            fields.append(EtaxField(
                id: "shushi_depreciation_total_necessary_expense",
                fieldLabel: "本年分の必要経費算入額",
                taxLine: nil,
                value: 0,
                section: .fixedAssetSchedule
            ))
            fields.append(EtaxField(
                id: "shushi_depreciation_total_remaining_balance",
                fieldLabel: "未償却残高",
                taxLine: nil,
                value: 0,
                section: .fixedAssetSchedule
            ))
        }

        fields.append(EtaxField(
            id: "shushi_sales_detail_other_total",
            fieldLabel: "上記以外の売上先の計",
            taxLine: nil,
            value: 0,
            section: .revenue
        ))
        fields.append(EtaxField(
            id: "shushi_sales_detail_reduced_tax_total",
            fieldLabel: "右記(1)のうち軽減税率対象",
            taxLine: nil,
            value: 0,
            section: .revenue
        ))
        fields.append(EtaxField(
            id: "shushi_sales_detail_total",
            fieldLabel: "計",
            taxLine: nil,
            value: 0,
            section: .revenue
        ))
        fields.append(EtaxField(
            id: "shushi_purchase_detail_other_total",
            fieldLabel: "上記以外の仕入先の計",
            taxLine: nil,
            value: 0,
            section: .expenses
        ))
        fields.append(EtaxField(
            id: "shushi_purchase_detail_reduced_tax_total",
            fieldLabel: "右記(6)のうち軽減税率対象",
            taxLine: nil,
            value: 0,
            section: .expenses
        ))
        fields.append(EtaxField(
            id: "shushi_purchase_detail_total",
            fieldLabel: "計",
            taxLine: nil,
            value: 0,
            section: .expenses
        ))

        return fields
    }

    private static func taxLine(
        for accountId: UUID,
        canonicalAccountsById: [UUID: CanonicalAccount]
    ) -> TaxLine? {
        guard let canonicalAccount = canonicalAccountsById[accountId] else { return nil }
        return TaxLine(legalReportLineId: canonicalAccount.defaultLegalReportLineId)
    }

    private static func decimalInt(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).intValue
    }
}
