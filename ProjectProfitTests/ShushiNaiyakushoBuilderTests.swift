import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class ShushiNaiyakushoBuilderTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Basic

    func testBuildWhiteReturnFormType() {
        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: []
        )
        let form = ShushiNaiyakushoBuilder.build(
            fiscalYear: 2025,
            profitLoss: pl,
            accounts: dataStore.accounts
        )
        XCTAssertEqual(form.formType, .whiteReturn)
        XCTAssertEqual(form.fiscalYear, 2025)
    }

    func testBuildIncludesRevenueTotal() {
        let salesAccount = dataStore.accounts.first { $0.subtype == .salesRevenue }!

        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [
                ProfitLossItem(
                    id: salesAccount.id, code: salesAccount.code,
                    name: salesAccount.name, amount: 3_000_000,
                    deductibleAmount: 3_000_000
                )
            ],
            expenseItems: []
        )
        let form = ShushiNaiyakushoBuilder.build(
            fiscalYear: 2025,
            profitLoss: pl,
            accounts: dataStore.accounts
        )

        let revenueField = form.fields.first { $0.id == "shushi_revenue_total" }
        XCTAssertNotNil(revenueField)
        XCTAssertEqual(revenueField?.value.numberValue, 3_000_000)
    }

    func testBuildExpenseMappedByTaxLine() {
        let commAccount = dataStore.accounts.first { $0.subtype == .communicationExpense }!

        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: [
                ProfitLossItem(
                    id: commAccount.id, code: commAccount.code,
                    name: commAccount.name, amount: 120_000,
                    deductibleAmount: 120_000
                )
            ]
        )
        let form = ShushiNaiyakushoBuilder.build(
            fiscalYear: 2025,
            profitLoss: pl,
            accounts: dataStore.accounts
        )

        let commField = form.fields.first { $0.taxLine == .communicationExpense }
        XCTAssertNotNil(commField)
        XCTAssertEqual(commField?.value.numberValue, 120_000)
    }

    func testBuildNetIncome() {
        let salesAccount = dataStore.accounts.first { $0.subtype == .salesRevenue }!
        let commAccount = dataStore.accounts.first { $0.subtype == .communicationExpense }!

        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [
                ProfitLossItem(
                    id: salesAccount.id, code: salesAccount.code,
                    name: salesAccount.name, amount: 2_000_000,
                    deductibleAmount: 2_000_000
                )
            ],
            expenseItems: [
                ProfitLossItem(
                    id: commAccount.id, code: commAccount.code,
                    name: commAccount.name, amount: 300_000,
                    deductibleAmount: 300_000
                )
            ]
        )
        let form = ShushiNaiyakushoBuilder.build(
            fiscalYear: 2025,
            profitLoss: pl,
            accounts: dataStore.accounts
        )

        let netIncomeField = form.fields.first { $0.id == "shushi_income_net" }
        XCTAssertNotNil(netIncomeField)
        XCTAssertEqual(netIncomeField?.value.numberValue, 1_700_000)
    }

    func testBuildExpenseTotalField() {
        let commAccount = dataStore.accounts.first { $0.subtype == .communicationExpense }!
        let travelAccount = dataStore.accounts.first { $0.subtype == .travelExpense }!

        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: [
                ProfitLossItem(
                    id: commAccount.id, code: commAccount.code,
                    name: commAccount.name, amount: 100_000,
                    deductibleAmount: 100_000
                ),
                ProfitLossItem(
                    id: travelAccount.id, code: travelAccount.code,
                    name: travelAccount.name, amount: 50_000,
                    deductibleAmount: 50_000
                )
            ]
        )
        let form = ShushiNaiyakushoBuilder.build(
            fiscalYear: 2025,
            profitLoss: pl,
            accounts: dataStore.accounts
        )

        let totalField = form.fields.first { $0.id == "shushi_expense_total" }
        XCTAssertNotNil(totalField)
        XCTAssertEqual(totalField?.value.numberValue, 150_000)
    }

    func testBuildIncludesInsuranceExpenseField() {
        let insuranceAccount = dataStore.accounts.first { $0.subtype == .insuranceExpense }!

        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: [
                ProfitLossItem(
                    id: insuranceAccount.id,
                    code: insuranceAccount.code,
                    name: insuranceAccount.name,
                    amount: 90_000,
                    deductibleAmount: 90_000
                )
            ]
        )
        let form = ShushiNaiyakushoBuilder.build(
            fiscalYear: 2025,
            profitLoss: pl,
            accounts: dataStore.accounts
        )

        let insuranceField = form.fields.first { $0.id == "shushi_expense_insurance" }
        XCTAssertNotNil(insuranceField)
        XCTAssertEqual(insuranceField?.taxLine, .insuranceExpense)
        XCTAssertEqual(insuranceField?.value.numberValue, 90_000)
    }

    func testBuildIncludesRentBreakdownFromCanonicalProjection() {
        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: []
        )
        let projection = ShushiNaiyakushoBuilder.WhiteReturnProjection(postedRentTotal: 240_000)

        let form = ShushiNaiyakushoBuilder.build(
            fiscalYear: 2025,
            profitLoss: pl,
            accounts: dataStore.accounts,
            projection: projection
        )

        let rentField = form.fields.first { $0.id == "shushi_rent_breakdown" }
        XCTAssertNotNil(rentField)
        XCTAssertEqual(rentField?.taxLine, .rentExpense)
        XCTAssertEqual(rentField?.value.numberValue, 240_000)
    }
}
