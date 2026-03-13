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
        let pl = CanonicalProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: []
        )
        let form = ShushiNaiyakushoBuilder.build(canonicalProfitLoss: pl, input: makeBuildInput(fiscalYear: 2025))
        XCTAssertEqual(form.formType, .whiteReturn)
        XCTAssertEqual(form.fiscalYear, 2025)
    }

    func testBuildIncludesRevenueTotal() {
        let salesAccount = dataStore.accounts.first { $0.subtype == .salesRevenue }!

        let pl = CanonicalProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [
                CanonicalProfitLossItem(
                    id: canonicalAccountId(for: salesAccount.id),
                    code: salesAccount.code,
                    name: salesAccount.name,
                    amount: Decimal(3_000_000)
                )
            ],
            expenseItems: []
        )
        let form = ShushiNaiyakushoBuilder.build(canonicalProfitLoss: pl, input: makeBuildInput(fiscalYear: 2025))

        let revenueField = form.fields.first { $0.id == "shushi_revenue_total" }
        XCTAssertNotNil(revenueField)
        XCTAssertEqual(revenueField?.value.numberValue, 3_000_000)
    }

    func testBuildExpenseMappedByTaxLine() {
        let commAccount = dataStore.accounts.first { $0.subtype == .communicationExpense }!

        let pl = CanonicalProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: [
                CanonicalProfitLossItem(
                    id: canonicalAccountId(for: commAccount.id),
                    code: commAccount.code,
                    name: commAccount.name,
                    amount: Decimal(120_000)
                )
            ]
        )
        let form = ShushiNaiyakushoBuilder.build(canonicalProfitLoss: pl, input: makeBuildInput(fiscalYear: 2025))

        let commField = form.fields.first { $0.taxLine == .communicationExpense }
        XCTAssertNotNil(commField)
        XCTAssertEqual(commField?.value.numberValue, 120_000)
    }

    func testBuildNetIncome() {
        let salesAccount = dataStore.accounts.first { $0.subtype == .salesRevenue }!
        let commAccount = dataStore.accounts.first { $0.subtype == .communicationExpense }!

        let pl = CanonicalProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [
                CanonicalProfitLossItem(
                    id: canonicalAccountId(for: salesAccount.id),
                    code: salesAccount.code,
                    name: salesAccount.name,
                    amount: Decimal(2_000_000)
                )
            ],
            expenseItems: [
                CanonicalProfitLossItem(
                    id: canonicalAccountId(for: commAccount.id),
                    code: commAccount.code,
                    name: commAccount.name,
                    amount: Decimal(300_000)
                )
            ]
        )
        let form = ShushiNaiyakushoBuilder.build(canonicalProfitLoss: pl, input: makeBuildInput(fiscalYear: 2025))

        let netIncomeField = form.fields.first { $0.id == "shushi_income_net" }
        XCTAssertNotNil(netIncomeField)
        XCTAssertEqual(netIncomeField?.value.numberValue, 1_700_000)
    }

    func testBuildExpenseTotalField() {
        let commAccount = dataStore.accounts.first { $0.subtype == .communicationExpense }!
        let travelAccount = dataStore.accounts.first { $0.subtype == .travelExpense }!

        let pl = CanonicalProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: [
                CanonicalProfitLossItem(
                    id: canonicalAccountId(for: commAccount.id),
                    code: commAccount.code,
                    name: commAccount.name,
                    amount: Decimal(100_000)
                ),
                CanonicalProfitLossItem(
                    id: canonicalAccountId(for: travelAccount.id),
                    code: travelAccount.code,
                    name: travelAccount.name,
                    amount: Decimal(50_000)
                )
            ]
        )
        let form = ShushiNaiyakushoBuilder.build(canonicalProfitLoss: pl, input: makeBuildInput(fiscalYear: 2025))

        let totalField = form.fields.first { $0.id == "shushi_expense_total" }
        XCTAssertNotNil(totalField)
        XCTAssertEqual(totalField?.value.numberValue, 150_000)
    }

    func testBuildIncludesInsuranceExpenseField() {
        let insuranceAccount = dataStore.accounts.first { $0.subtype == .insuranceExpense }!

        let pl = CanonicalProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: [
                CanonicalProfitLossItem(
                    id: canonicalAccountId(for: insuranceAccount.id),
                    code: insuranceAccount.code,
                    name: insuranceAccount.name,
                    amount: Decimal(90_000)
                )
            ]
        )
        let form = ShushiNaiyakushoBuilder.build(canonicalProfitLoss: pl, input: makeBuildInput(fiscalYear: 2025))

        let insuranceField = form.fields.first { $0.id == "shushi_expense_insurance" }
        XCTAssertNotNil(insuranceField)
        XCTAssertEqual(insuranceField?.taxLine, .insuranceExpense)
        XCTAssertEqual(insuranceField?.value.numberValue, 90_000)
    }

    func testBuildIncludesRentBreakdownFromCanonicalProjection() {
        let pl = CanonicalProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: []
        )
        let rentEntryId = UUID()
        let form = ShushiNaiyakushoBuilder.build(
            canonicalProfitLoss: pl,
            input: makeBuildInput(
                fiscalYear: 2025,
                canonicalJournals: [
                    CanonicalJournalEntry(
                        id: rentEntryId,
                        businessId: try! XCTUnwrap(dataStore.businessProfile?.id),
                        taxYear: 2025,
                        journalDate: Date(),
                        voucherNo: "1",
                        lines: [
                            JournalLine(
                                journalId: rentEntryId,
                                accountId: canonicalAccountId(for: rentAccountId()),
                                debitAmount: Decimal(240_000),
                                sortOrder: 0
                            )
                        ],
                        approvedAt: Date()
                    )
                ]
            )
        )

        let rentField = form.fields.first { $0.id == "shushi_rent_breakdown" }
        XCTAssertNotNil(rentField)
        XCTAssertEqual(rentField?.taxLine, .rentExpense)
        XCTAssertEqual(rentField?.value.numberValue, 240_000)
    }

    func testBuildExcludesUnpostedOrNonRentLinesFromRentBreakdown() {
        let pl = CanonicalProfitLossReport(
            fiscalYear: 2025,
            generatedAt: Date(),
            revenueItems: [],
            expenseItems: []
        )
        let postedRentEntryId = UUID()
        let unpostedRentEntryId = UUID()
        let postedNonRentEntryId = UUID()
        let form = ShushiNaiyakushoBuilder.build(
            canonicalProfitLoss: pl,
            input: makeBuildInput(
                fiscalYear: 2025,
                canonicalJournals: [
                    makeCanonicalJournal(
                        id: postedRentEntryId,
                        accountId: canonicalAccountId(for: rentAccountId()),
                        debitAmount: Decimal(120_000),
                        approvedAt: Date()
                    ),
                    makeCanonicalJournal(
                        id: unpostedRentEntryId,
                        accountId: canonicalAccountId(for: rentAccountId()),
                        debitAmount: Decimal(90_000),
                        approvedAt: nil
                    ),
                    makeCanonicalJournal(
                        id: postedNonRentEntryId,
                        accountId: canonicalAccountId(for: nonRentAccountId()),
                        debitAmount: Decimal(70_000),
                        approvedAt: Date()
                    ),
                ]
            )
        )

        let rentField = form.fields.first { $0.id == "shushi_rent_breakdown" }
        XCTAssertEqual(rentField?.value.numberValue, 120_000)
    }

    private func makeBuildInput(
        fiscalYear: Int,
        canonicalProfitLoss: CanonicalProfitLossReport? = nil,
        canonicalJournals: [CanonicalJournalEntry] = []
    ) -> FormEngine.BuildInput {
        FormEngine.BuildInput(
            fiscalYear: fiscalYear,
            startMonth: FiscalYearSettings.startMonth,
            canonicalAccounts: dataStore.canonicalAccounts(),
            legacyAccountsById: Dictionary(uniqueKeysWithValues: dataStore.accounts.map { ($0.id, $0) }),
            categoryNamesById: Dictionary(uniqueKeysWithValues: dataStore.categories.map { ($0.id, $0.name) }),
            fixedAssets: dataStore.fixedAssets,
            inventoryRecord: nil,
            businessProfile: nil,
            taxYearProfile: nil,
            sensitivePayload: nil,
            canonicalProfitLoss: canonicalProfitLoss ?? CanonicalProfitLossReport(
                fiscalYear: fiscalYear,
                generatedAt: Date(),
                revenueItems: [],
                expenseItems: []
            ),
            canonicalBalanceSheet: CanonicalBalanceSheetReport(
                fiscalYear: fiscalYear,
                generatedAt: Date(),
                assetItems: [],
                liabilityItems: [],
                equityItems: []
            ),
            canonicalJournals: canonicalJournals,
            postingCandidatesById: [:]
        )
    }

    private func canonicalAccountId(for legacyAccountId: String) -> UUID {
        try! XCTUnwrap(dataStore.canonicalAccountId(for: legacyAccountId))
    }

    private func rentAccountId() -> String {
        dataStore.accounts.first { $0.subtype == .rentExpense }?.id
            ?? (AccountingConstants.defaultAccountsById["acct-rent"]?.id ?? "acct-rent")
    }

    private func nonRentAccountId() -> String {
        dataStore.accounts.first { $0.subtype == .communicationExpense }?.id ?? "acct-communication"
    }

    private func makeCanonicalJournal(
        id: UUID,
        accountId: UUID,
        debitAmount: Decimal,
        approvedAt: Date?
    ) -> CanonicalJournalEntry {
        CanonicalJournalEntry(
            id: id,
            businessId: try! XCTUnwrap(dataStore.businessProfile?.id),
            taxYear: 2025,
            journalDate: Date(),
            voucherNo: "1",
            lines: [
                JournalLine(journalId: id, accountId: accountId, debitAmount: debitAmount, sortOrder: 0)
            ],
            approvedAt: approvedAt
        )
    }
}
