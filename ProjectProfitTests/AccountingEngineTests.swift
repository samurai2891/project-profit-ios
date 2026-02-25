import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class AccountingEngineTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var engine: AccountingEngine!
    var accounts: [PPAccount]!
    var categories: [PPCategory]!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self,
            PPRecurringTransaction.self, PPAccount.self, PPJournalEntry.self,
            PPJournalLine.self, PPAccountingProfile.self,
            PPFixedAsset.self,
            configurations: config
        )
        context = container.mainContext
        engine = AccountingEngine(modelContext: context)

        // デフォルト勘定科目をシード
        for def in AccountingConstants.defaultAccounts {
            let account = PPAccount(
                id: def.id, code: def.code, name: def.name,
                accountType: def.accountType, normalBalance: def.normalBalance,
                subtype: def.subtype, isSystem: true, displayOrder: def.displayOrder
            )
            context.insert(account)
        }
        try! context.save()

        let descriptor = FetchDescriptor<PPAccount>(sortBy: [SortDescriptor(\.displayOrder)])
        accounts = try! context.fetch(descriptor)

        // カテゴリをシード
        for cat in DEFAULT_CATEGORIES {
            let category = PPCategory(
                id: cat.id, name: cat.name, type: cat.type, icon: cat.icon, isDefault: true
            )
            if let accountId = AccountingConstants.categoryToAccountMapping[cat.id] {
                category.linkedAccountId = accountId
            }
            context.insert(category)
        }
        try! context.save()

        let catDescriptor = FetchDescriptor<PPCategory>()
        categories = try! context.fetch(catDescriptor)
    }

    override func tearDown() {
        accounts = nil
        categories = nil
        engine = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Income Tests

    func testIncomeJournal_DebitCash_CreditSales() {
        let tx = createTransaction(type: .income, amount: 100_000, categoryId: "cat-sales")

        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)

        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.isPosted)
        XCTAssertEqual(entry!.entryType, .auto)

        let lines = fetchLines(for: entry!.id)
        XCTAssertEqual(lines.count, 2)

        let debitLine = lines.first { $0.debit > 0 }
        let creditLine = lines.first { $0.credit > 0 }

        XCTAssertEqual(debitLine?.accountId, "acct-cash")
        XCTAssertEqual(debitLine?.debit, 100_000)
        XCTAssertEqual(creditLine?.accountId, "acct-sales")
        XCTAssertEqual(creditLine?.credit, 100_000)
    }

    func testIncomeJournal_CustomPaymentAccount() {
        let tx = createTransaction(type: .income, amount: 50_000, categoryId: "cat-service")
        tx.paymentAccountId = "acct-bank"

        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)

        let lines = fetchLines(for: entry!.id)
        let debitLine = lines.first { $0.debit > 0 }
        XCTAssertEqual(debitLine?.accountId, "acct-bank")
    }

    // MARK: - Expense Tests (100%)

    func testExpenseJournal_FullDeductible() {
        let tx = createTransaction(type: .expense, amount: 50_000, categoryId: "cat-tools")
        tx.taxDeductibleRate = 100

        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)

        XCTAssertNotNil(entry)
        let lines = fetchLines(for: entry!.id)
        XCTAssertEqual(lines.count, 2)

        let debitLine = lines.first { $0.debit > 0 }
        let creditLine = lines.first { $0.credit > 0 }

        XCTAssertEqual(debitLine?.accountId, "acct-supplies") // cat-tools → acct-supplies
        XCTAssertEqual(debitLine?.debit, 50_000)
        XCTAssertEqual(creditLine?.accountId, "acct-cash")
        XCTAssertEqual(creditLine?.credit, 50_000)
    }

    // MARK: - Expense Tests (Partial Deductible)

    func testExpenseJournal_PartialDeductible_80Percent() {
        let tx = createTransaction(type: .expense, amount: 100_000, categoryId: "cat-communication")
        tx.taxDeductibleRate = 80

        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)

        XCTAssertNotNil(entry)
        let lines = fetchLines(for: entry!.id)
        XCTAssertEqual(lines.count, 3, "按分ありの経費は3行仕訳")

        let expenseLine = lines.first { $0.accountId == "acct-communication" }
        let drawingsLine = lines.first { $0.accountId == "acct-owner-drawings" }
        let creditLine = lines.first { $0.credit > 0 }

        XCTAssertEqual(expenseLine?.debit, 80_000)
        XCTAssertEqual(drawingsLine?.debit, 20_000)
        XCTAssertEqual(creditLine?.accountId, "acct-cash")
        XCTAssertEqual(creditLine?.credit, 100_000)
    }

    func testExpenseJournal_ZeroDeductible() {
        let tx = createTransaction(type: .expense, amount: 10_000, categoryId: "cat-food")
        tx.taxDeductibleRate = 0

        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)

        let lines = fetchLines(for: entry!.id)
        // deductibleAmount=0 なので経費行は省略され、事業主貸のみ
        XCTAssertEqual(lines.count, 2)

        let drawingsLine = lines.first { $0.accountId == "acct-owner-drawings" }
        XCTAssertEqual(drawingsLine?.debit, 10_000)
    }

    // MARK: - Transfer Tests

    func testTransferJournal_CashToBank() {
        let tx = createTransaction(type: .transfer, amount: 50_000, categoryId: "cat-other-expense")
        tx.paymentAccountId = "acct-cash"
        tx.transferToAccountId = "acct-bank"

        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)

        XCTAssertNotNil(entry)
        let lines = fetchLines(for: entry!.id)
        XCTAssertEqual(lines.count, 2)

        let debitLine = lines.first { $0.debit > 0 }
        let creditLine = lines.first { $0.credit > 0 }

        XCTAssertEqual(debitLine?.accountId, "acct-bank")
        XCTAssertEqual(debitLine?.debit, 50_000)
        XCTAssertEqual(creditLine?.accountId, "acct-cash")
        XCTAssertEqual(creditLine?.credit, 50_000)
    }

    func testTransferJournal_MissingToAccount_UsesSuspense() {
        let tx = createTransaction(type: .transfer, amount: 30_000, categoryId: "cat-other-expense")
        tx.paymentAccountId = "acct-cash"
        tx.transferToAccountId = nil

        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)

        let lines = fetchLines(for: entry!.id)
        let debitLine = lines.first { $0.debit > 0 }
        XCTAssertEqual(debitLine?.accountId, "acct-suspense")
    }

    // MARK: - Upsert (Update) Tests

    func testUpsertUpdatesExistingEntry() {
        let tx = createTransaction(type: .income, amount: 100_000, categoryId: "cat-sales")

        let entry1 = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)
        let entryId1 = entry1!.id

        // 金額変更して再upsert
        tx.amount = 200_000
        let entry2 = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)

        XCTAssertEqual(entry2!.id, entryId1, "upsertは既存エントリを更新する")

        let lines = fetchLines(for: entry2!.id)
        let debitLine = lines.first { $0.debit > 0 }
        XCTAssertEqual(debitLine?.debit, 200_000, "金額が更新されている")
    }

    // MARK: - Delete Tests

    func testDeleteJournalEntry() {
        let tx = createTransaction(type: .income, amount: 100_000, categoryId: "cat-sales")
        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)
        XCTAssertNotNil(entry)

        engine.deleteJournalEntry(for: tx.id)

        let sourceKey = PPJournalEntry.transactionSourceKey(tx.id)
        let descriptor = FetchDescriptor<PPJournalEntry>(
            predicate: #Predicate<PPJournalEntry> { $0.sourceKey == sourceKey }
        )
        let remaining = try? context.fetch(descriptor)
        XCTAssertTrue(remaining?.isEmpty ?? true)
    }

    // MARK: - Rebuild Tests

    func testRebuildAllJournalEntries() {
        let tx1 = createTransaction(type: .income, amount: 100_000, categoryId: "cat-sales")
        let tx2 = createTransaction(type: .expense, amount: 30_000, categoryId: "cat-tools")
        tx2.taxDeductibleRate = 100

        engine.upsertJournalEntry(for: tx1, categories: categories, accounts: accounts)
        engine.upsertJournalEntry(for: tx2, categories: categories, accounts: accounts)

        // 全仕訳を再構築
        engine.rebuildAllJournalEntries(transactions: [tx1, tx2], categories: categories, accounts: accounts)

        let entryDescriptor = FetchDescriptor<PPJournalEntry>()
        let entries = try! context.fetch(entryDescriptor)
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: - Validation Tests

    func testValidateBalancedEntry() {
        let tx = createTransaction(type: .income, amount: 100_000, categoryId: "cat-sales")
        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)!

        let issues = engine.validateJournalEntry(entry)
        XCTAssertTrue(issues.isEmpty, "正しい仕訳にバリデーション問題はない")
    }

    // MARK: - Debit/Credit Balance Integrity

    func testIncomeEntryIsBalanced() {
        let tx = createTransaction(type: .income, amount: 77_777, categoryId: "cat-sales")
        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)!
        let lines = fetchLines(for: entry.id)

        let totalDebit = lines.reduce(0) { $0 + $1.debit }
        let totalCredit = lines.reduce(0) { $0 + $1.credit }
        XCTAssertEqual(totalDebit, totalCredit, "借方合計 == 貸方合計")
    }

    func testExpenseWithPartialDeductibleIsBalanced() {
        let tx = createTransaction(type: .expense, amount: 33_333, categoryId: "cat-communication")
        tx.taxDeductibleRate = 60

        let entry = engine.upsertJournalEntry(for: tx, categories: categories, accounts: accounts)!
        let lines = fetchLines(for: entry.id)

        let totalDebit = lines.reduce(0) { $0 + $1.debit }
        let totalCredit = lines.reduce(0) { $0 + $1.credit }
        XCTAssertEqual(totalDebit, totalCredit, "按分ありでも借方合計 == 貸方合計")
        XCTAssertEqual(totalCredit, 33_333)
    }

    // MARK: - Unmapped Category Tests

    func testUnmappedCategoryFallsBackToMapping() {
        // linkedAccountId が nil でも categoryToAccountMapping で解決できる
        let category = PPCategory(id: "cat-tools", name: "ツール", type: .expense, icon: "wrench", isDefault: true)
        category.linkedAccountId = nil
        context.insert(category)
        try! context.save()

        let tx = createTransaction(type: .expense, amount: 10_000, categoryId: "cat-tools")
        tx.taxDeductibleRate = 100

        let categoriesWithUnlinked = (try? context.fetch(FetchDescriptor<PPCategory>())) ?? []
        let entry = engine.upsertJournalEntry(for: tx, categories: categoriesWithUnlinked, accounts: accounts)!

        let lines = fetchLines(for: entry.id)
        let debitLine = lines.first { $0.debit > 0 }
        XCTAssertEqual(debitLine?.accountId, "acct-supplies", "マッピング経由でacct-suppliesに解決される")
    }

    // MARK: - Helpers

    private func createTransaction(type: TransactionType, amount: Int, categoryId: String) -> PPTransaction {
        let tx = PPTransaction(
            type: type, amount: amount, date: Date(),
            categoryId: categoryId, memo: "テスト", allocations: []
        )
        context.insert(tx)
        try! context.save()
        return tx
    }

    private func fetchLines(for entryId: UUID) -> [PPJournalLine] {
        let descriptor = FetchDescriptor<PPJournalLine>(
            predicate: #Predicate<PPJournalLine> { $0.entryId == entryId },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
