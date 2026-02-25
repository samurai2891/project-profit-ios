import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class EtaxFieldPopulatorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self,
            PPAccount.self, PPJournalEntry.self, PPJournalLine.self, PPAccountingProfile.self,
            PPUserRule.self,
            PPFixedAsset.self,
            configurations: config
        )
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

    // MARK: - Basic Population

    func testPopulateWithEmptyPL() {
        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: []
        )
        let form = EtaxFieldPopulator.populate(
            fiscalYear: 2025,
            profitLoss: pl,
            balanceSheet: nil,
            accounts: dataStore.accounts
        )
        XCTAssertEqual(form.fiscalYear, 2025)
        XCTAssertEqual(form.formType, .blueReturn)
        // Should have 3 income section fields (total revenue, total expenses, net income)
        let incomeFields = form.fields.filter { $0.section == .income }
        XCTAssertEqual(incomeFields.count, 3)
        // All values should be 0
        XCTAssertEqual(form.totalRevenue, 0)
        XCTAssertEqual(form.totalExpenses, 0)
        XCTAssertEqual(form.netIncome, 0)
    }

    func testPopulateWithRevenueItems() {
        // Find account with salesRevenue subtype
        let salesAccount = dataStore.accounts.first { $0.subtype == .salesRevenue }!

        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [
                ProfitLossItem(
                    id: salesAccount.id,
                    code: salesAccount.code,
                    name: salesAccount.name,
                    amount: 5_000_000,
                    deductibleAmount: 5_000_000
                )
            ],
            expenseItems: []
        )
        let form = EtaxFieldPopulator.populate(
            fiscalYear: 2025,
            profitLoss: pl,
            balanceSheet: nil,
            accounts: dataStore.accounts
        )

        let revenueFields = form.fields.filter { $0.section == .revenue }
        XCTAssertEqual(revenueFields.count, 1)
        XCTAssertEqual(revenueFields[0].value, 5_000_000)
        XCTAssertEqual(revenueFields[0].taxLine, .salesRevenue)
    }

    func testPopulateWithExpenseItems() {
        // Find accounts with communication and travel subtypes
        let commAccount = dataStore.accounts.first { $0.subtype == .communicationExpense }!
        let travelAccount = dataStore.accounts.first { $0.subtype == .travelExpense }!

        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: [
                ProfitLossItem(
                    id: commAccount.id,
                    code: commAccount.code,
                    name: commAccount.name,
                    amount: 120_000,
                    deductibleAmount: 120_000
                ),
                ProfitLossItem(
                    id: travelAccount.id,
                    code: travelAccount.code,
                    name: travelAccount.name,
                    amount: 80_000,
                    deductibleAmount: 80_000
                )
            ]
        )
        let form = EtaxFieldPopulator.populate(
            fiscalYear: 2025,
            profitLoss: pl,
            balanceSheet: nil,
            accounts: dataStore.accounts
        )

        let expenseFields = form.fields.filter { $0.section == .expenses }
        XCTAssertEqual(expenseFields.count, 2)
        XCTAssertEqual(form.totalExpenses, 200_000)
    }

    func testPopulateIncomeSectionTotals() {
        let salesAccount = dataStore.accounts.first { $0.subtype == .salesRevenue }!
        let commAccount = dataStore.accounts.first { $0.subtype == .communicationExpense }!

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
            expenseItems: [
                ProfitLossItem(
                    id: commAccount.id, code: commAccount.code,
                    name: commAccount.name, amount: 500_000,
                    deductibleAmount: 500_000
                )
            ]
        )
        let form = EtaxFieldPopulator.populate(
            fiscalYear: 2025,
            profitLoss: pl,
            balanceSheet: nil,
            accounts: dataStore.accounts
        )

        let incomeFields = form.fields.filter { $0.section == .income }
        let totalRevenueField = incomeFields.first { $0.id == "income_total_revenue" }
        let totalExpensesField = incomeFields.first { $0.id == "income_total_expenses" }
        let netIncomeField = incomeFields.first { $0.id == "income_net" }

        XCTAssertEqual(totalRevenueField?.value, 3_000_000)
        XCTAssertEqual(totalExpensesField?.value, 500_000)
        XCTAssertEqual(netIncomeField?.value, 2_500_000)
    }

    func testPopulateWhiteReturnFormType() {
        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: []
        )
        let form = EtaxFieldPopulator.populate(
            fiscalYear: 2025,
            profitLoss: pl,
            balanceSheet: nil,
            formType: .whiteReturn,
            accounts: dataStore.accounts
        )
        XCTAssertEqual(form.formType, .whiteReturn)
    }

    func testPopulateFieldLabelsMatchTaxLine() {
        let salesAccount = dataStore.accounts.first { $0.subtype == .salesRevenue }!

        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [
                ProfitLossItem(
                    id: salesAccount.id, code: salesAccount.code,
                    name: salesAccount.name, amount: 1_000_000,
                    deductibleAmount: 1_000_000
                )
            ],
            expenseItems: []
        )
        let form = EtaxFieldPopulator.populate(
            fiscalYear: 2025,
            profitLoss: pl,
            balanceSheet: nil,
            accounts: dataStore.accounts
        )

        let revenueField = form.fields.first { $0.section == .revenue }
        XCTAssertNotNil(revenueField)
        // Phase 10A: TaxYearDefinitionLoaderにより年度別ラベルが使用される
        XCTAssertEqual(revenueField?.fieldLabel, TaxYearDefinitionLoader.fieldLabel(for: .salesRevenue, fiscalYear: 2025))
    }
}
