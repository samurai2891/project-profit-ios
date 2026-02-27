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
        XCTAssertEqual(revenueFields[0].value.numberValue, 5_000_000)
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

    func testPopulateWithInsuranceExpenseItem() {
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
                    amount: 95_000,
                    deductibleAmount: 95_000
                )
            ]
        )
        let form = EtaxFieldPopulator.populate(
            fiscalYear: 2025,
            profitLoss: pl,
            balanceSheet: nil,
            accounts: dataStore.accounts
        )

        let insuranceField = form.fields.first { $0.id == "expense_insurance" }
        XCTAssertNotNil(insuranceField)
        XCTAssertEqual(insuranceField?.taxLine, .insuranceExpense)
        XCTAssertEqual(insuranceField?.value.numberValue, 95_000)
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

        XCTAssertEqual(totalRevenueField?.value.numberValue, 3_000_000)
        XCTAssertEqual(totalExpensesField?.value.numberValue, 500_000)
        XCTAssertEqual(netIncomeField?.value.numberValue, 2_500_000)
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
        XCTAssertEqual(
            revenueField?.fieldLabel,
            TaxYearDefinitionLoader.fieldLabel(for: .salesRevenue, formType: .blueReturn, fiscalYear: 2025)
        )
    }

    func testPopulateDeclarantInfoLoadsFromSecureStore() {
        let profileId = UUID().uuidString
        defer { _ = ProfileSecureStore.delete(profileId: profileId) }

        let profile = PPAccountingProfile(
            id: profileId,
            fiscalYear: 2025,
            businessName: "暗号化屋号",
            ownerName: "山田太郎"
        )
        let birthDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 1990, month: 1, day: 2))
        let payload = ProfileSensitivePayload.fromLegacyProfile(
            ownerNameKana: "ヤマダタロウ",
            postalCode: "1000001",
            address: "東京都千代田区1-1",
            phoneNumber: "0312345678",
            dateOfBirth: birthDate,
            businessCategory: "ソフトウェア開発",
            myNumberFlag: true,
            includeSensitiveInExport: true
        )
        XCTAssertTrue(ProfileSecureStore.save(payload, profileId: profileId))

        let fields = EtaxFieldPopulator.populateDeclarantInfo(profile: profile)
        let values = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.value.exportText) })

        XCTAssertEqual(values["declarant_name"], "山田太郎")
        XCTAssertEqual(values["declarant_business_name"], "暗号化屋号")
        XCTAssertEqual(values["declarant_name_kana"], "ヤマダタロウ")
        XCTAssertEqual(values["declarant_postal_code"], "1000001")
        XCTAssertEqual(values["declarant_address"], "東京都千代田区1-1")
        XCTAssertEqual(values["declarant_phone"], "0312345678")
        XCTAssertEqual(values["declarant_business_category"], "ソフトウェア開発")
        XCTAssertEqual(values["declarant_birth_date"], "1990-01-02")
        XCTAssertEqual(values["declarant_my_number_flag"], "1")
    }

    func testPopulateDeclarantInfoSkipsSensitiveFieldsWhenConsentDisabled() {
        let profileId = UUID().uuidString
        defer { _ = ProfileSecureStore.delete(profileId: profileId) }

        let profile = PPAccountingProfile(
            id: profileId,
            fiscalYear: 2025,
            businessName: "屋号",
            ownerName: "佐藤花子"
        )
        let payload = ProfileSensitivePayload.fromLegacyProfile(
            ownerNameKana: "サトウハナコ",
            postalCode: "1000001",
            address: "東京都千代田区1-1",
            phoneNumber: "0312345678",
            dateOfBirth: Date(),
            businessCategory: "デザイン",
            myNumberFlag: true,
            includeSensitiveInExport: false
        )
        XCTAssertTrue(ProfileSecureStore.save(payload, profileId: profileId))

        let fields = EtaxFieldPopulator.populateDeclarantInfo(profile: profile)
        let ids = Set(fields.map(\.id))

        XCTAssertTrue(ids.contains("declarant_name"))
        XCTAssertTrue(ids.contains("declarant_business_name"))
        XCTAssertFalse(ids.contains("declarant_name_kana"))
        XCTAssertFalse(ids.contains("declarant_postal_code"))
        XCTAssertFalse(ids.contains("declarant_address"))
        XCTAssertFalse(ids.contains("declarant_phone"))
        XCTAssertFalse(ids.contains("declarant_business_category"))
        XCTAssertFalse(ids.contains("declarant_birth_date"))
        XCTAssertFalse(ids.contains("declarant_my_number_flag"))
    }

    func testPopulateDeclarantInfoDoesNotUseLegacyPlainFieldsWhenSecurePayloadMissing() {
        let profileId = UUID().uuidString
        defer { _ = ProfileSecureStore.delete(profileId: profileId) }

        let profile = PPAccountingProfile(
            id: profileId,
            fiscalYear: 2025,
            businessName: "屋号",
            ownerName: "田中太郎",
            ownerNameKana: "タナカタロウ",
            postalCode: "1000001",
            address: "東京都千代田区1-1",
            phoneNumber: "0312345678",
            businessCategory: "ソフトウェア開発",
            myNumberFlag: true
        )

        let fields = EtaxFieldPopulator.populateDeclarantInfo(profile: profile)
        let ids = Set(fields.map(\.id))

        XCTAssertTrue(ids.contains("declarant_name"))
        XCTAssertTrue(ids.contains("declarant_business_name"))
        XCTAssertFalse(ids.contains("declarant_name_kana"))
        XCTAssertFalse(ids.contains("declarant_postal_code"))
        XCTAssertFalse(ids.contains("declarant_address"))
        XCTAssertFalse(ids.contains("declarant_phone"))
        XCTAssertFalse(ids.contains("declarant_business_category"))
        XCTAssertFalse(ids.contains("declarant_birth_date"))
        XCTAssertFalse(ids.contains("declarant_my_number_flag"))
    }

    func testProfileSecureStoreSaveFailsForEmptyProfileId() {
        let payload = ProfileSensitivePayload.fromLegacyProfile(
            ownerNameKana: "テスト",
            postalCode: "1000001",
            address: "東京都千代田区1-1",
            phoneNumber: "0312345678",
            dateOfBirth: nil,
            businessCategory: "テスト業",
            myNumberFlag: nil,
            includeSensitiveInExport: true
        )

        XCTAssertFalse(ProfileSecureStore.save(payload, profileId: ""))
    }
}
