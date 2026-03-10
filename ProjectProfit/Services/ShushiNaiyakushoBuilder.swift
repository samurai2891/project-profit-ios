import Foundation

/// 白色申告 収支内訳書ビルダー
/// 白色申告の場合、青色と異なりフィールド構成がシンプル
@MainActor
enum ShushiNaiyakushoBuilder {
    /// 白色申告向けに canonical projection から抽出した最小入力
    struct WhiteReturnProjection: Sendable {
        let postedRentTotal: Int

        static let empty = WhiteReturnProjection(postedRentTotal: 0)
    }

    /// 白色申告 収支内訳書用のEtaxFormを生成（canonical profile ベース）
    static func build(
        fiscalYear: Int,
        profitLoss: ProfitLossReport,
        accounts: [PPAccount],
        businessProfile: BusinessProfile? = nil,
        taxYearProfile: TaxYearProfile? = nil,
        sensitivePayload: ProfileSensitivePayload? = nil,
        fixedAssets: [PPFixedAsset] = [],
        projection: WhiteReturnProjection = .empty
    ) -> EtaxForm {
        let fields = buildFields(
            fiscalYear: fiscalYear,
            profitLoss: profitLoss,
            accounts: accounts,
            fixedAssets: fixedAssets,
            projection: projection
        )

        var allFields = fields
        if let businessProfile {
            allFields.append(contentsOf: EtaxFieldPopulator.populateDeclarantInfo(
                businessProfile: businessProfile,
                sensitivePayload: sensitivePayload
            ))
        }

        return EtaxForm(
            fiscalYear: fiscalYear,
            formType: .whiteReturn,
            fields: allFields,
            generatedAt: Date()
        )
    }

    // MARK: - Private

    /// 共通のフィールド生成ロジック（申告者情報を除く）
    private static func buildFields(
        fiscalYear: Int,
        profitLoss: ProfitLossReport,
        accounts: [PPAccount],
        fixedAssets: [PPFixedAsset],
        projection: WhiteReturnProjection
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
                fieldLabel: TaxYearDefinitionLoader.fieldLabel(
                    for: taxLine,
                    formType: .whiteReturn,
                    fiscalYear: fiscalYear
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
        if projection.postedRentTotal > 0 {
            fields.append(EtaxField(
                id: "shushi_rent_breakdown",
                fieldLabel: "地代家賃合計",
                taxLine: .rentExpense,
                value: projection.postedRentTotal,
                section: .deductions
            ))
        }

        return fields
    }
}
