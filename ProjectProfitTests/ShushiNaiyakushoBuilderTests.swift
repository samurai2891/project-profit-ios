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
        let form = ShushiNaiyakushoBuilder.build(profitLoss: pl, input: makeBuildInput(fiscalYear: 2025))
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
        let form = ShushiNaiyakushoBuilder.build(profitLoss: pl, input: makeBuildInput(fiscalYear: 2025))

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
        let form = ShushiNaiyakushoBuilder.build(profitLoss: pl, input: makeBuildInput(fiscalYear: 2025))

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
        let form = ShushiNaiyakushoBuilder.build(profitLoss: pl, input: makeBuildInput(fiscalYear: 2025))

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
        let form = ShushiNaiyakushoBuilder.build(profitLoss: pl, input: makeBuildInput(fiscalYear: 2025))

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
        let form = ShushiNaiyakushoBuilder.build(profitLoss: pl, input: makeBuildInput(fiscalYear: 2025))

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
        let rentEntryId = UUID()
        let projectedEntries = [
            PPJournalEntry(
                id: rentEntryId,
                sourceKey: "canonical:\(rentEntryId.uuidString)",
                date: Date(),
                entryType: .auto,
                memo: "",
                isPosted: true
            )
        ]
        let projectedLines = [
            PPJournalLine(
                entryId: rentEntryId,
                accountId: rentAccountId(),
                debit: 240_000,
                credit: 0
            )
        ]

        let form = ShushiNaiyakushoBuilder.build(
            profitLoss: pl,
            input: makeBuildInput(
                fiscalYear: 2025,
                projectedEntries: projectedEntries,
                projectedLines: projectedLines
            )
        )

        let rentField = form.fields.first { $0.id == "shushi_rent_breakdown" }
        XCTAssertNotNil(rentField)
        XCTAssertEqual(rentField?.taxLine, .rentExpense)
        XCTAssertEqual(rentField?.value.numberValue, 240_000)
    }

    func testBuildExcludesUnpostedOrNonRentLinesFromRentBreakdown() {
        let pl = ProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: []
        )
        let postedRentEntryId = UUID()
        let unpostedRentEntryId = UUID()
        let postedNonRentEntryId = UUID()
        let projectedEntries = [
            PPJournalEntry(
                id: postedRentEntryId,
                sourceKey: "canonical:\(postedRentEntryId.uuidString)",
                date: Date(),
                entryType: .auto,
                memo: "",
                isPosted: true
            ),
            PPJournalEntry(
                id: unpostedRentEntryId,
                sourceKey: "canonical:\(unpostedRentEntryId.uuidString)",
                date: Date(),
                entryType: .auto,
                memo: "",
                isPosted: false
            ),
            PPJournalEntry(
                id: postedNonRentEntryId,
                sourceKey: "canonical:\(postedNonRentEntryId.uuidString)",
                date: Date(),
                entryType: .auto,
                memo: "",
                isPosted: true
            ),
        ]
        let projectedLines = [
            PPJournalLine(
                entryId: postedRentEntryId,
                accountId: rentAccountId(),
                debit: 120_000,
                credit: 0
            ),
            PPJournalLine(
                entryId: unpostedRentEntryId,
                accountId: rentAccountId(),
                debit: 90_000,
                credit: 0
            ),
            PPJournalLine(
                entryId: postedNonRentEntryId,
                accountId: nonRentAccountId(),
                debit: 70_000,
                credit: 0
            ),
        ]

        let form = ShushiNaiyakushoBuilder.build(
            profitLoss: pl,
            input: makeBuildInput(
                fiscalYear: 2025,
                projectedEntries: projectedEntries,
                projectedLines: projectedLines
            )
        )

        let rentField = form.fields.first { $0.id == "shushi_rent_breakdown" }
        XCTAssertEqual(rentField?.value.numberValue, 120_000)
    }

    private func makeBuildInput(
        fiscalYear: Int,
        projectedEntries: [PPJournalEntry] = [],
        projectedLines: [PPJournalLine] = []
    ) -> FormEngine.BuildInput {
        FormEngine.BuildInput(
            fiscalYear: fiscalYear,
            startMonth: FiscalYearSettings.startMonth,
            accounts: dataStore.accounts,
            categories: dataStore.categories,
            fixedAssets: dataStore.fixedAssets,
            inventoryRecord: nil,
            businessProfile: nil,
            taxYearProfile: nil,
            sensitivePayload: nil,
            projectedEntries: projectedEntries,
            projectedLines: projectedLines,
            canonicalJournals: [],
            postingCandidatesById: [:]
        )
    }

    private func rentAccountId() -> String {
        dataStore.accounts.first { $0.subtype == .rentExpense }?.id
            ?? (AccountingConstants.defaultAccountsById["acct-rent"]?.id ?? "acct-rent")
    }

    private func nonRentAccountId() -> String {
        dataStore.accounts.first { $0.subtype == .communicationExpense }?.id ?? "acct-communication"
    }
}
