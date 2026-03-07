import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class FormEngineTests: XCTestCase {
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

    // MARK: - FormEngine.formType mapping

    func testFormTypeForBlueGeneral() {
        XCTAssertEqual(FormEngine.formType(for: .blueGeneral), .blueReturn)
    }

    func testFormTypeForBlueCashBasis() {
        XCTAssertEqual(FormEngine.formType(for: .blueCashBasis), .blueCashBasis)
    }

    func testFormTypeForWhite() {
        XCTAssertEqual(FormEngine.formType(for: .white), .whiteReturn)
    }

    // MARK: - FormEngine.build

    func testBuildBlueGeneralProducesBlueReturnForm() {
        let businessId = dataStore.businessProfile?.id ?? UUID()
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )

        let form = try? FormEngine.build(
            filingStyle: .blueGeneral,
            dataStore: dataStore,
            fiscalYear: 2025
        )

        XCTAssertNotNil(form)
        XCTAssertEqual(form?.formType, .blueReturn)
        XCTAssertEqual(form?.fiscalYear, 2025)
    }

    func testBuildWhiteProducesWhiteReturnForm() {
        let businessId = dataStore.businessProfile?.id ?? UUID()
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )

        let form = try? FormEngine.build(
            filingStyle: .white,
            dataStore: dataStore,
            fiscalYear: 2025
        )

        XCTAssertNotNil(form)
        XCTAssertEqual(form?.formType, .whiteReturn)
    }

    func testBuildUnsupportedTaxYearThrows() {
        XCTAssertThrowsError(
            try FormEngine.build(
                filingStyle: .blueGeneral,
                dataStore: dataStore,
                fiscalYear: 1900
            )
        ) { error in
            XCTAssertTrue(error is FormEngine.FormEngineError)
            XCTAssertTrue(error.localizedDescription.contains("未対応"))
        }
    }

    // MARK: - EtaxFormType.blueCashBasis

    func testBlueCashBasisFormTypeProperties() {
        XCTAssertEqual(EtaxFormType.blueCashBasis.rawValue, "青色申告決算書（現金主義）")
        XCTAssertEqual(EtaxFormType.blueCashBasis.definitionFormKey, "blue_cash_basis")
    }

    // MARK: - CashBasisReturnBuilder

    func testCashBasisExpenseFieldLabels() {
        XCTAssertEqual(CashBasisReturnBuilder.expenseFieldLabel(index: 1), "イ")
        XCTAssertEqual(CashBasisReturnBuilder.expenseFieldLabel(index: 2), "ウ")
        XCTAssertEqual(CashBasisReturnBuilder.expenseFieldLabel(index: 14), "ソ")
        XCTAssertEqual(CashBasisReturnBuilder.expenseFieldLabel(index: 0), "他")
        XCTAssertEqual(CashBasisReturnBuilder.expenseFieldLabel(index: 15), "他")
    }

    func testCashBasisBuilderThrowsWhenNoTransactions() {
        XCTAssertThrowsError(
            try CashBasisReturnBuilder.build(
                fiscalYear: 2025,
                dataStore: dataStore
            )
        ) { error in
            XCTAssertTrue(error is CashBasisReturnBuilder.BuildError)
            XCTAssertTrue(error.localizedDescription.contains("取引データ"))
        }
    }

    func testCashBasisBuilderGeneratesFieldsForTransactions() {
        let incomeCategory = dataStore.categories.first { $0.type == .income }
            ?? PPCategory(id: "cat-income", name: "売上", type: .income, icon: "yen")
        let expenseCategory = dataStore.categories.first { $0.type == .expense }
            ?? PPCategory(id: "cat-expense", name: "通信費", type: .expense, icon: "phone")

        if dataStore.categories.isEmpty {
            context.insert(incomeCategory)
            context.insert(expenseCategory)
            try! context.save()
            dataStore.loadData()
        }

        // 2025年度の取引を追加
        let incomeTx = PPTransaction(
            type: .income,
            amount: 500_000,
            date: makeDate(year: 2025, month: 3, day: 15),
            categoryId: incomeCategory.id,
            memo: "売上"
        )
        let expenseTx = PPTransaction(
            type: .expense,
            amount: 100_000,
            date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: expenseCategory.id,
            memo: "通信費"
        )
        context.insert(incomeTx)
        context.insert(expenseTx)
        try! context.save()
        dataStore.loadData()

        let form = try? CashBasisReturnBuilder.build(
            fiscalYear: 2025,
            dataStore: dataStore
        )

        XCTAssertNotNil(form)
        XCTAssertEqual(form?.formType, .blueCashBasis)
        XCTAssertEqual(form?.fiscalYear, 2025)

        // 収入金額フィールドの検証
        let revenueField = form?.fields.first { $0.id == "cash_basis_revenue" }
        XCTAssertNotNil(revenueField)
        XCTAssertEqual(revenueField?.value.numberValue, 500_000)

        // 経費合計フィールドの検証
        let expenseTotalField = form?.fields.first { $0.id == "cash_basis_expense_total" }
        XCTAssertNotNil(expenseTotalField)
        XCTAssertEqual(expenseTotalField?.value.numberValue, 100_000)

        // 所得金額フィールドの検証
        let incomeField = form?.fields.first { $0.id == "cash_basis_income" }
        XCTAssertNotNil(incomeField)
        XCTAssertEqual(incomeField?.value.numberValue, 400_000)
    }

    func testCashBasisBuilderIncludesDeclarantInfoWhenProfilePresent() {
        let incomeCategory = dataStore.categories.first { $0.type == .income }
            ?? PPCategory(id: "cat-income", name: "売上", type: .income, icon: "yen")

        if dataStore.categories.isEmpty {
            context.insert(incomeCategory)
            try! context.save()
            dataStore.loadData()
        }

        let tx = PPTransaction(
            type: .income,
            amount: 100_000,
            date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: incomeCategory.id,
            memo: "売上"
        )
        context.insert(tx)
        try! context.save()
        dataStore.loadData()

        let businessProfile = BusinessProfile(
            id: UUID(),
            ownerName: "山田太郎",
            businessName: "テスト屋号"
        )

        let form = try? CashBasisReturnBuilder.build(
            fiscalYear: 2025,
            dataStore: dataStore,
            businessProfile: businessProfile
        )

        XCTAssertNotNil(form)
        let nameField = form?.fields.first { $0.id == "declarant_name" }
        XCTAssertNotNil(nameField)
        XCTAssertEqual(nameField?.value.exportText, "山田太郎")
    }

    func testCashBasisBuilderOmitsDeclarantInfoWhenProfileNil() {
        let incomeCategory = dataStore.categories.first { $0.type == .income }
            ?? PPCategory(id: "cat-income", name: "売上", type: .income, icon: "yen")

        if dataStore.categories.isEmpty {
            context.insert(incomeCategory)
            try! context.save()
            dataStore.loadData()
        }

        let tx = PPTransaction(
            type: .income,
            amount: 100_000,
            date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: incomeCategory.id,
            memo: "売上"
        )
        context.insert(tx)
        try! context.save()
        dataStore.loadData()

        let form = try? CashBasisReturnBuilder.build(
            fiscalYear: 2025,
            dataStore: dataStore
        )

        XCTAssertNotNil(form)
        let declarantFields = form?.fields.filter { $0.section == EtaxSection.declarantInfo } ?? []
        XCTAssertTrue(declarantFields.isEmpty)
    }

    func testCashBasisBuilderGroupsExpensesByCategory() {
        let expenseCategory1 = dataStore.categories.first { $0.type == .expense }
            ?? PPCategory(id: "cat-expense1", name: "通信費", type: .expense, icon: "phone")
        let expenseCategory2Id = "cat-expense-travel"
        let expenseCategory2 = PPCategory(
            id: expenseCategory2Id, name: "旅費交通費", type: .expense, icon: "car"
        )
        let incomeCategory = dataStore.categories.first { $0.type == .income }
            ?? PPCategory(id: "cat-income", name: "売上", type: .income, icon: "yen")

        // カテゴリをコンテキストに追加
        if dataStore.categories.isEmpty {
            context.insert(incomeCategory)
            context.insert(expenseCategory1)
        }
        context.insert(expenseCategory2)
        try! context.save()
        dataStore.loadData()

        // 収入取引（フィルタ用）
        let incomeTx = PPTransaction(
            type: .income, amount: 1_000_000,
            date: makeDate(year: 2025, month: 1, day: 15),
            categoryId: incomeCategory.id, memo: "売上"
        )
        // 2つのカテゴリの経費取引
        let expense1 = PPTransaction(
            type: .expense, amount: 50_000,
            date: makeDate(year: 2025, month: 2, day: 1),
            categoryId: expenseCategory1.id, memo: "通信費"
        )
        let expense2 = PPTransaction(
            type: .expense, amount: 30_000,
            date: makeDate(year: 2025, month: 3, day: 1),
            categoryId: expenseCategory1.id, memo: "通信費2"
        )
        let expense3 = PPTransaction(
            type: .expense, amount: 200_000,
            date: makeDate(year: 2025, month: 4, day: 1),
            categoryId: expenseCategory2Id, memo: "出張"
        )
        context.insert(incomeTx)
        context.insert(expense1)
        context.insert(expense2)
        context.insert(expense3)
        try! context.save()
        dataStore.loadData()

        let form = try? CashBasisReturnBuilder.build(
            fiscalYear: 2025,
            dataStore: dataStore
        )

        XCTAssertNotNil(form)

        // 経費はカテゴリ別にグループ化され、金額降順でソートされる
        let expenseFields = form?.fields.filter { field in
            field.section == EtaxSection.expenses && field.id != "cash_basis_expense_total"
        } ?? []
        XCTAssertEqual(expenseFields.count, 2)

        // 最大金額のカテゴリが最初（旅費交通費 200,000）
        XCTAssertEqual(expenseFields.first?.value.numberValue, 200_000)
        // 次が通信費（50,000 + 30,000 = 80,000）
        XCTAssertEqual(expenseFields.last?.value.numberValue, 80_000)

        // 経費合計
        let totalField = form?.fields.first { $0.id == "cash_basis_expense_total" }
        XCTAssertEqual(totalField?.value.numberValue, 280_000)
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func seedTaxYearProfile(_ profile: TaxYearProfile) {
        context.insert(TaxYearProfileEntityMapper.toEntity(profile))
        try! context.save()
    }
}
