import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class AccountingBootstrapTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - needsBootstrap Tests

    func testNeedsBootstrap_WhenNoProfile() {
        let service = AccountingBootstrapService(modelContext: context)
        XCTAssertTrue(service.needsBootstrap())
    }

    func testNeedsBootstrap_WhenProfileExists() {
        context.insert(BusinessProfileEntity(businessId: UUID()))
        try! context.save()

        let service = AccountingBootstrapService(modelContext: context)
        XCTAssertFalse(service.needsBootstrap())
    }

    // MARK: - Step 1: Profile Creation

    func testStep1_CreatesCanonicalProfile() {
        let (categories, transactions) = seedTestData()
        let service = AccountingBootstrapService(modelContext: context)

        _ = service.execute(categories: categories, transactions: transactions)

        let businessProfiles = try! context.fetch(FetchDescriptor<BusinessProfileEntity>())
        let taxYearProfiles = try! context.fetch(FetchDescriptor<TaxYearProfileEntity>())
        XCTAssertEqual(businessProfiles.count, 1)
        XCTAssertEqual(businessProfiles[0].defaultPaymentAccountId, "acct-cash")
        XCTAssertEqual(taxYearProfiles.count, 1)
    }

    // MARK: - Step 2: Default Accounts

    func testStep2_SeedsDefaultAccounts() {
        let (categories, transactions) = seedTestData()
        let service = AccountingBootstrapService(modelContext: context)

        let result = service.execute(categories: categories, transactions: transactions)

        XCTAssertEqual(result.accountsCreated, AccountingConstants.defaultAccounts.count)

        let descriptor = FetchDescriptor<PPAccount>()
        let accounts = try! context.fetch(descriptor)
        XCTAssertEqual(accounts.count, AccountingConstants.defaultAccounts.count)
    }

    func testStep2_IdempotentOnSecondRun() {
        let (categories, transactions) = seedTestData()
        let service = AccountingBootstrapService(modelContext: context)

        _ = service.execute(categories: categories, transactions: transactions)
        let businessDescriptor = FetchDescriptor<BusinessProfileEntity>()
        if let profile = try? context.fetch(businessDescriptor).first {
            context.delete(profile)
            try! context.save()
        }

        let result2 = service.execute(categories: categories, transactions: transactions)

        // 勘定科目は重複作成されない
        XCTAssertEqual(result2.accountsCreated, 0, "2回目はアカウント作成されない")
    }

    // MARK: - Step 3: Category Linking

    func testStep3_LinksCategoriesFromMapping() {
        let (categories, transactions) = seedTestData()
        let service = AccountingBootstrapService(modelContext: context)

        let result = service.execute(categories: categories, transactions: transactions)

        XCTAssertGreaterThan(result.categoriesLinked, 0)

        // cat-hosting → acct-communication
        let hosting = categories.first { $0.id == "cat-hosting" }
        XCTAssertEqual(hosting?.linkedAccountId, "acct-communication")

        // cat-sales → acct-sales
        let sales = categories.first { $0.id == "cat-sales" }
        XCTAssertEqual(sales?.linkedAccountId, "acct-sales")
    }

    func testStep3_DoesNotOverwriteExistingLink() {
        let (categories, transactions) = seedTestData()

        // 事前にリンクを設定
        let hosting = categories.first { $0.id == "cat-hosting" }!
        hosting.linkedAccountId = "acct-misc"
        try! context.save()

        let service = AccountingBootstrapService(modelContext: context)
        _ = service.execute(categories: categories, transactions: transactions)

        // 既存のリンクは上書きされない
        XCTAssertEqual(hosting.linkedAccountId, "acct-misc")
    }

    // MARK: - Step 4: Transaction Field Backfill

    func testStep4_BackfillsTransactionFields() {
        let (categories, _) = seedTestData()
        let tx = PPTransaction(
            type: .expense, amount: 10_000, date: Date(),
            categoryId: "cat-tools", memo: "テスト", allocations: []
        )
        tx.paymentAccountId = nil
        tx.taxDeductibleRate = nil
        tx.bookkeepingMode = nil
        context.insert(tx)
        try! context.save()

        let service = AccountingBootstrapService(modelContext: context)
        let result = service.execute(categories: categories, transactions: [tx])

        XCTAssertEqual(result.transactionsBackfilled, 1)
        XCTAssertEqual(tx.paymentAccountId, "acct-cash")
        XCTAssertEqual(tx.taxDeductibleRate, 100)
        XCTAssertEqual(tx.bookkeepingMode, .auto)
    }

    // MARK: - Step 5: Unmapped Categories to Suspense

    func testStep5_LinksUnmappedToSuspense() {
        let (categories, transactions) = seedTestData()

        // ユーザー作成カテゴリを追加
        let userCategory = PPCategory(id: "cat-custom-xyz", name: "ユーザーカテゴリ", type: .expense, icon: "star", isDefault: false)
        context.insert(userCategory)
        try! context.save()

        var allCategories = categories
        allCategories.append(userCategory)

        let service = AccountingBootstrapService(modelContext: context)
        _ = service.execute(categories: allCategories, transactions: transactions)

        XCTAssertEqual(userCategory.linkedAccountId, "acct-suspense")
    }

    // MARK: - Step 7: Journal Entry Generation

    func testStep7_GeneratesCanonicalJournalEntries() {
        let (categories, _) = seedTestData()
        let tx1 = PPTransaction(
            type: .income, amount: 100_000, date: Date(),
            categoryId: "cat-sales", memo: "売上", allocations: []
        )
        let tx2 = PPTransaction(
            type: .expense, amount: 30_000, date: Date(),
            categoryId: "cat-tools", memo: "ツール", allocations: []
        )
        context.insert(tx1)
        context.insert(tx2)
        try! context.save()

        let service = AccountingBootstrapService(modelContext: context)
        let result = service.execute(categories: categories, transactions: [tx1, tx2])

        XCTAssertEqual(result.journalEntriesGenerated, 2)
        XCTAssertNotNil(tx1.journalEntryId)
        XCTAssertNotNil(tx2.journalEntryId)
        XCTAssertEqual(try! context.fetch(FetchDescriptor<JournalEntryEntity>()).count, 2)
        XCTAssertEqual(try! context.fetch(FetchDescriptor<PostingCandidateEntity>()).count, 2)
    }

    func testStep7_SkipsAlreadyLinkedTransactions() {
        let (categories, _) = seedTestData()
        let tx = PPTransaction(
            type: .income, amount: 100_000, date: Date(),
            categoryId: "cat-sales", memo: "売上", allocations: []
        )
        tx.journalEntryId = UUID() // 既にリンク済み
        context.insert(tx)
        try! context.save()

        let service = AccountingBootstrapService(modelContext: context)
        let result = service.execute(categories: categories, transactions: [tx])

        XCTAssertEqual(result.journalEntriesGenerated, 0)
    }

    // MARK: - Full Bootstrap Integration

    func testFullBootstrap_AllStepsExecute() {
        let (categories, _) = seedTestData()

        let tx = PPTransaction(
            type: .expense, amount: 50_000, date: Date(),
            categoryId: "cat-hosting", memo: "サーバー代", allocations: []
        )
        context.insert(tx)
        try! context.save()

        let service = AccountingBootstrapService(modelContext: context)
        let result = service.execute(categories: categories, transactions: [tx])

        XCTAssertEqual(result.accountsCreated, AccountingConstants.defaultAccounts.count)
        XCTAssertGreaterThan(result.categoriesLinked, 0)
        XCTAssertEqual(result.transactionsBackfilled, 1)
        XCTAssertEqual(result.journalEntriesGenerated, 1)

        // 仕訳の借方/貸方が一致しているか
        XCTAssertTrue(result.integrityIssues.isEmpty, "整合性チェックに問題なし")
    }

    // MARK: - Helpers

    private func seedTestData() -> (categories: [PPCategory], transactions: [PPTransaction]) {
        var categories: [PPCategory] = []
        for cat in DEFAULT_CATEGORIES {
            let category = PPCategory(
                id: cat.id, name: cat.name, type: cat.type, icon: cat.icon, isDefault: true
            )
            context.insert(category)
            categories.append(category)
        }
        try! context.save()
        return (categories, [])
    }
}
