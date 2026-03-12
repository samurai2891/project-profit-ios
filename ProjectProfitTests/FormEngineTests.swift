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
                input: makeBuildInput(fiscalYear: 2025)
            )
        ) { error in
            XCTAssertTrue(error is CashBasisReturnBuilder.BuildError)
            XCTAssertTrue(error.localizedDescription.contains("取引データ"))
        }
    }

    func testCashBasisBuilderGeneratesFieldsForCanonicalJournals() {
        let incomeCategory = ensureCategory(id: "cat-income", name: "売上", type: .income, icon: "yen")
        let expenseCategory = ensureCategory(id: "cat-expense", name: "通信費", type: .expense, icon: "phone")

        let incomeCandidateId = UUID()
        let expenseCandidateId = UUID()

        let form = try? CashBasisReturnBuilder.build(
            input: makeBuildInput(
                fiscalYear: 2025,
                canonicalJournals: [
                    makeCanonicalJournal(
                        id: UUID(),
                        candidateId: incomeCandidateId,
                        date: makeDate(year: 2025, month: 3, day: 15)
                    ),
                    makeCanonicalJournal(
                        id: UUID(),
                        candidateId: expenseCandidateId,
                        date: makeDate(year: 2025, month: 6, day: 1)
                    ),
                ],
                postingCandidatesById: [
                    incomeCandidateId: makePostingCandidate(
                        id: incomeCandidateId,
                        taxYear: 2025,
                        type: .income,
                        categoryId: incomeCategory.id,
                        amount: 500_000
                    ),
                    expenseCandidateId: makePostingCandidate(
                        id: expenseCandidateId,
                        taxYear: 2025,
                        type: .expense,
                        categoryId: expenseCategory.id,
                        amount: 100_000
                    ),
                ]
            )
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
        let incomeCategory = ensureCategory(id: "cat-income", name: "売上", type: .income, icon: "yen")
        let incomeCandidateId = UUID()

        let businessProfile = BusinessProfile(
            id: UUID(),
            ownerName: "山田太郎",
            businessName: "テスト屋号"
        )

        let form = try? CashBasisReturnBuilder.build(
            input: makeBuildInput(
                fiscalYear: 2025,
                businessProfile: businessProfile,
                canonicalJournals: [
                    makeCanonicalJournal(
                        id: UUID(),
                        candidateId: incomeCandidateId,
                        date: makeDate(year: 2025, month: 6, day: 1)
                    )
                ],
                postingCandidatesById: [
                    incomeCandidateId: makePostingCandidate(
                        id: incomeCandidateId,
                        taxYear: 2025,
                        type: .income,
                        categoryId: incomeCategory.id,
                        amount: 100_000
                    )
                ]
            )
        )

        XCTAssertNotNil(form)
        let nameField = form?.fields.first { $0.id == "declarant_name" }
        XCTAssertNotNil(nameField)
        XCTAssertEqual(nameField?.value.exportText, "山田太郎")
    }

    func testCashBasisBuilderOmitsDeclarantInfoWhenProfileNil() {
        let incomeCategory = ensureCategory(id: "cat-income", name: "売上", type: .income, icon: "yen")
        let incomeCandidateId = UUID()

        let form = try? CashBasisReturnBuilder.build(
            input: makeBuildInput(
                fiscalYear: 2025,
                canonicalJournals: [
                    makeCanonicalJournal(
                        id: UUID(),
                        candidateId: incomeCandidateId,
                        date: makeDate(year: 2025, month: 6, day: 1)
                    )
                ],
                postingCandidatesById: [
                    incomeCandidateId: makePostingCandidate(
                        id: incomeCandidateId,
                        taxYear: 2025,
                        type: .income,
                        categoryId: incomeCategory.id,
                        amount: 100_000
                    )
                ]
            )
        )

        XCTAssertNotNil(form)
        let declarantFields = form?.fields.filter { $0.section == EtaxSection.declarantInfo } ?? []
        XCTAssertTrue(declarantFields.isEmpty)
    }

    func testCashBasisBuilderGroupsExpensesByCategory() {
        let expenseCategory1 = ensureCategory(id: "cat-expense1", name: "通信費", type: .expense, icon: "phone")
        let expenseCategory2 = ensureCategory(id: "cat-expense-travel", name: "旅費交通費", type: .expense, icon: "car")
        let incomeCategory = ensureCategory(id: "cat-income", name: "売上", type: .income, icon: "yen")

        let incomeCandidateId = UUID()
        let expenseCandidateId1 = UUID()
        let expenseCandidateId2 = UUID()
        let expenseCandidateId3 = UUID()

        let form = try? CashBasisReturnBuilder.build(
            input: makeBuildInput(
                fiscalYear: 2025,
                canonicalJournals: [
                    makeCanonicalJournal(
                        id: UUID(),
                        candidateId: incomeCandidateId,
                        date: makeDate(year: 2025, month: 1, day: 15)
                    ),
                    makeCanonicalJournal(
                        id: UUID(),
                        candidateId: expenseCandidateId1,
                        date: makeDate(year: 2025, month: 2, day: 1)
                    ),
                    makeCanonicalJournal(
                        id: UUID(),
                        candidateId: expenseCandidateId2,
                        date: makeDate(year: 2025, month: 3, day: 1)
                    ),
                    makeCanonicalJournal(
                        id: UUID(),
                        candidateId: expenseCandidateId3,
                        date: makeDate(year: 2025, month: 4, day: 1)
                    ),
                ],
                postingCandidatesById: [
                    incomeCandidateId: makePostingCandidate(
                        id: incomeCandidateId,
                        taxYear: 2025,
                        type: .income,
                        categoryId: incomeCategory.id,
                        amount: 1_000_000
                    ),
                    expenseCandidateId1: makePostingCandidate(
                        id: expenseCandidateId1,
                        taxYear: 2025,
                        type: .expense,
                        categoryId: expenseCategory1.id,
                        amount: 50_000
                    ),
                    expenseCandidateId2: makePostingCandidate(
                        id: expenseCandidateId2,
                        taxYear: 2025,
                        type: .expense,
                        categoryId: expenseCategory1.id,
                        amount: 30_000
                    ),
                    expenseCandidateId3: makePostingCandidate(
                        id: expenseCandidateId3,
                        taxYear: 2025,
                        type: .expense,
                        categoryId: expenseCategory2.id,
                        amount: 200_000
                    ),
                ]
            )
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

    func testCashBasisBuilderSkipsTransferJournals() {
        let transferCandidateId = UUID()

        let form = try? CashBasisReturnBuilder.build(
            input: makeBuildInput(
                fiscalYear: 2025,
                canonicalJournals: [
                    makeCanonicalJournal(
                        id: UUID(),
                        candidateId: transferCandidateId,
                        date: makeDate(year: 2025, month: 7, day: 1)
                    )
                ],
                postingCandidatesById: [
                    transferCandidateId: makePostingCandidate(
                        id: transferCandidateId,
                        taxYear: 2025,
                        type: .transfer,
                        categoryId: "",
                        amount: 100_000
                    )
                ]
            )
        )

        XCTAssertNil(form)
    }

    func testFormEngineBuildBlueCashBasisUsesCanonicalArtifacts() throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let taxYear = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            filingStyle: .blueCashBasis,
            bookkeepingBasis: .cashBasis,
            yearLockState: .taxClose,
            taxPackVersion: "2025-v1"
        )
        let incomeCategory = ensureCategory(id: "cat-income", name: "売上", type: .income, icon: "yen")
        let expenseCategory = ensureCategory(id: "cat-expense", name: "通信費", type: .expense, icon: "phone")

        let incomeCandidateId = UUID()
        let expenseCandidateId = UUID()
        context.insert(TaxYearProfileEntityMapper.toEntity(taxYear))
        context.insert(PostingCandidateEntityMapper.toEntity(
            makePostingCandidate(
                id: incomeCandidateId,
                businessId: businessId,
                taxYear: 2025,
                type: .income,
                categoryId: incomeCategory.id,
                amount: 500_000
            )
        ))
        context.insert(PostingCandidateEntityMapper.toEntity(
            makePostingCandidate(
                id: expenseCandidateId,
                businessId: businessId,
                taxYear: 2025,
                type: .expense,
                categoryId: expenseCategory.id,
                amount: 120_000
            )
        ))
        context.insert(CanonicalJournalEntryEntityMapper.toEntity(
            makeCanonicalJournal(
                id: UUID(),
                businessId: businessId,
                candidateId: incomeCandidateId,
                date: makeDate(year: 2025, month: 5, day: 10)
            )
        ))
        context.insert(CanonicalJournalEntryEntityMapper.toEntity(
            makeCanonicalJournal(
                id: UUID(),
                businessId: businessId,
                candidateId: expenseCandidateId,
                date: makeDate(year: 2025, month: 5, day: 12)
            )
        ))
        try context.save()
        dataStore.loadData()

        let form = try FormEngine.build(
            filingStyle: .blueCashBasis,
            dataStore: dataStore,
            fiscalYear: 2025
        )

        XCTAssertEqual(form.formType, .blueCashBasis)
        XCTAssertEqual(form.fields.first { $0.id == "cash_basis_revenue" }?.value.numberValue, 500_000)
        XCTAssertEqual(form.fields.first { $0.id == "cash_basis_expense_total" }?.value.numberValue, 120_000)
        XCTAssertEqual(form.fields.first { $0.id == "cash_basis_income" }?.value.numberValue, 380_000)
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func ensureCategory(
        id: String,
        name: String,
        type: CategoryType,
        icon: String
    ) -> PPCategory {
        if let existing = dataStore.categories.first(where: { $0.id == id }) {
            return existing
        }

        let category = PPCategory(id: id, name: name, type: type, icon: icon)
        context.insert(category)
        try! context.save()
        dataStore.loadData()
        return dataStore.categories.first(where: { $0.id == id }) ?? category
    }

    private func makeBuildInput(
        fiscalYear: Int,
        businessProfile: BusinessProfile? = nil,
        canonicalJournals: [CanonicalJournalEntry] = [],
        postingCandidatesById: [UUID: PostingCandidate] = [:]
    ) -> FormEngine.BuildInput {
        FormEngine.BuildInput(
            fiscalYear: fiscalYear,
            startMonth: FiscalYearSettings.startMonth,
            accounts: dataStore.accounts,
            categories: dataStore.categories,
            fixedAssets: dataStore.fixedAssets,
            inventoryRecord: nil,
            businessProfile: businessProfile,
            taxYearProfile: nil,
            sensitivePayload: nil,
            projectedEntries: [],
            projectedLines: [],
            canonicalJournals: canonicalJournals,
            postingCandidatesById: postingCandidatesById
        )
    }

    private func makePostingCandidate(
        id: UUID,
        businessId: UUID? = nil,
        taxYear: Int,
        type: TransactionType,
        categoryId: String,
        amount: Int
    ) -> PostingCandidate {
        let line = switch type {
        case .income:
            PostingCandidateLine(
                debitAccountId: UUID(),
                creditAccountId: UUID(),
                amount: Decimal(amount)
            )
        case .expense:
            PostingCandidateLine(
                debitAccountId: UUID(),
                creditAccountId: UUID(),
                amount: Decimal(amount)
            )
        case .transfer:
            PostingCandidateLine(
                debitAccountId: UUID(),
                creditAccountId: UUID(),
                amount: Decimal(amount)
            )
        }

        return PostingCandidate(
            id: id,
            businessId: businessId ?? UUID(),
            taxYear: taxYear,
            candidateDate: makeDate(year: taxYear, month: 1, day: 1),
            proposedLines: [line],
            status: .approved,
            memo: "test",
            legacySnapshot: PostingCandidateLegacySnapshot(
                type: type,
                categoryId: categoryId,
                recurringId: nil,
                paymentAccountId: nil,
                transferToAccountId: nil,
                taxDeductibleRate: nil,
                taxAmount: nil,
                taxCodeId: nil,
                taxRate: nil,
                isTaxIncluded: nil,
                taxCategory: nil,
                receiptImagePath: nil,
                lineItems: [],
                counterpartyName: nil
            )
        )
    }

    private func makeCanonicalJournal(
        id: UUID,
        businessId: UUID? = nil,
        candidateId: UUID,
        date: Date
    ) -> CanonicalJournalEntry {
        CanonicalJournalEntry(
            id: id,
            businessId: businessId ?? UUID(),
            taxYear: 2025,
            journalDate: date,
            voucherNo: "1",
            sourceCandidateId: candidateId,
            lines: [
                JournalLine(journalId: id, accountId: UUID(), debitAmount: 1, sortOrder: 0),
                JournalLine(journalId: id, accountId: UUID(), creditAmount: 1, sortOrder: 1),
            ],
            approvedAt: date
        )
    }

    private func seedTaxYearProfile(_ profile: TaxYearProfile) {
        context.insert(TaxYearProfileEntityMapper.toEntity(profile))
        try! context.save()
    }
}
