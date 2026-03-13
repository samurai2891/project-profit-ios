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
        let canonicalAccountsById = Dictionary(uniqueKeysWithValues: input.canonicalAccounts.map { ($0.id, $0) })

        // 収入 — 売上のみ（白色は簡易）
        let totalRevenue = decimalInt(canonicalProfitLoss.totalRevenue)
        fields.append(EtaxField(
            id: "shushi_revenue_total",
            fieldLabel: "収入金額",
            taxLine: .salesRevenue,
            value: totalRevenue,
            section: .revenue
        ))

        // 経費 — e-Tax 12区分でマッピング（同じTaxLineは合算）
        var expenseByTaxLine: [TaxLine: Int] = [:]
        for item in canonicalProfitLoss.expenseItems {
            if let taxLine = taxLine(
                for: item.id,
                canonicalAccountsById: canonicalAccountsById,
                legacyAccountsById: input.legacyAccountsById
            )
            {
                expenseByTaxLine[taxLine, default: 0] += decimalInt(item.amount)
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
        let totalExpenses = decimalInt(canonicalProfitLoss.totalExpenses)
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
        let rentAccountIds = Set<UUID>(
            input.canonicalAccounts.compactMap { account in
                guard let legacyAccountId = account.legacyAccountId,
                      input.legacyAccountsById[legacyAccountId]?.subtype == .rentExpense
                else {
                    return nil
                }
                return account.id
            }
        )

        return input.canonicalJournals.reduce(into: 0) { partialResult, journal in
            guard journal.approvedAt != nil else {
                return
            }
            for line in journal.lines where rentAccountIds.contains(line.accountId) {
                partialResult += decimalInt(line.debitAmount - line.creditAmount)
            }
        }
    }

    private static func taxLine(
        for accountId: UUID,
        canonicalAccountsById: [UUID: CanonicalAccount],
        legacyAccountsById: [String: PPAccount]
    ) -> TaxLine? {
        guard let canonicalAccount = canonicalAccountsById[accountId],
              let legacyAccountId = canonicalAccount.legacyAccountId,
              let subtype = legacyAccountsById[legacyAccountId]?.subtype
        else {
            return nil
        }

        return TaxLine.allCases.first { $0.accountSubtype == subtype }
    }

    private static func decimalInt(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).intValue
    }
}
