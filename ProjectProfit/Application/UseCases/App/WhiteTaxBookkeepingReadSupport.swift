import SwiftData

struct WhiteTaxBookkeepingRow: Identifiable, Equatable {
    let id: String
    let title: String
    let amount: Int
}

struct WhiteTaxBookkeepingSnapshot: Equatable {
    let fiscalYear: Int
    let totalRevenue: Int
    let totalExpenses: Int
    let netIncome: Int
    let revenueRows: [WhiteTaxBookkeepingRow]
    let inventoryRows: [WhiteTaxBookkeepingRow]
    let expenseRows: [WhiteTaxBookkeepingRow]

    var isEmpty: Bool {
        totalRevenue == 0
            && totalExpenses == 0
            && revenueRows.allSatisfy { $0.amount == 0 }
            && inventoryRows.allSatisfy { $0.amount == 0 }
            && expenseRows.allSatisfy { $0.amount == 0 }
    }
}

@MainActor
struct WhiteTaxBookkeepingQueryUseCase {
    private let buildSnapshotUseCase: EtaxFormBuildQueryUseCase

    init(modelContext: ModelContext) {
        self.buildSnapshotUseCase = EtaxFormBuildQueryUseCase(modelContext: modelContext)
    }

    func snapshot(taxYear: Int) -> WhiteTaxBookkeepingSnapshot {
        let buildSnapshot = buildSnapshotUseCase.snapshot(taxYear: taxYear)
        let form = ShushiNaiyakushoBuilder.build(
            canonicalProfitLoss: buildSnapshot.canonicalProfitLoss,
            input: FormEngine.BuildInput(snapshot: buildSnapshot)
        )

        return WhiteTaxBookkeepingSnapshot(
            fiscalYear: taxYear,
            totalRevenue: fieldAmount("shushi_revenue_total", in: form),
            totalExpenses: fieldAmount("shushi_expense_total", in: form),
            netIncome: fieldAmount("shushi_income_net", in: form),
            revenueRows: rows(
                ids: [
                    "shushi_revenue_sales",
                    "shushi_revenue_home_consumption",
                    "shushi_revenue_other",
                    "shushi_revenue_total",
                ],
                in: form
            ),
            inventoryRows: rows(
                ids: [
                    "shushi_inventory_opening",
                    "shushi_inventory_purchases",
                    "shushi_inventory_subtotal",
                    "shushi_inventory_closing",
                    "shushi_inventory_cogs",
                ],
                in: form
            ),
            expenseRows: form.fields
                .filter { $0.section == .expenses && $0.taxLine != nil }
                .compactMap { field in
                    guard let amount = field.value.numberValue, amount != 0 else {
                        return nil
                    }
                    return WhiteTaxBookkeepingRow(
                        id: field.id,
                        title: field.fieldLabel,
                        amount: amount
                    )
                }
        )
    }

    private func fieldAmount(_ id: String, in form: EtaxForm) -> Int {
        form.fields.first(where: { $0.id == id })?.value.numberValue ?? 0
    }

    private func rows(ids: [String], in form: EtaxForm) -> [WhiteTaxBookkeepingRow] {
        ids.compactMap { id in
            guard let field = form.fields.first(where: { $0.id == id }) else {
                return nil
            }
            return WhiteTaxBookkeepingRow(
                id: field.id,
                title: field.fieldLabel,
                amount: field.value.numberValue ?? 0
            )
        }
    }
}
