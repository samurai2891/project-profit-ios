import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ClosingEntryTests: XCTestCase {
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
            PPJournalLine.self, PPAccountingProfile.self, PPUserRule.self,
            PPFixedAsset.self,
            configurations: config
        )
        context = container.mainContext
        engine = AccountingEngine(modelContext: context)

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

    // MARK: - Closing Entry Tests

    func testClosingEntry_Basic() {
        // 収益100万、費用60万 → 純利益40万が元入金へ
        createPostedEntry(accountId: "acct-sales", debit: 0, credit: 1_000_000, year: 2025)
        createPostedEntry(accountId: "acct-rent", debit: 600_000, credit: 0, year: 2025)

        let entries = fetchAllEntries()
        let lines = fetchAllLines()

        let result = engine.generateClosingBalanceEntry(
            for: 2025, accounts: accounts, journalEntries: entries, journalLines: lines
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isPosted)
        XCTAssertEqual(result!.entryType, .closing)

        let closingLines = fetchLines(for: result!.id)
        // 収益1行(借方) + 費用1行(貸方) + 元入金1行(貸方) = 3行
        XCTAssertEqual(closingLines.count, 3)

        // 収益を閉じる: 借方1,000,000
        let revenueLine = closingLines.first { $0.accountId == "acct-sales" }
        XCTAssertEqual(revenueLine?.debit, 1_000_000)
        XCTAssertEqual(revenueLine?.credit, 0)

        // 費用を閉じる: 貸方600,000
        let expenseLine = closingLines.first { $0.accountId == "acct-rent" }
        XCTAssertEqual(expenseLine?.debit, 0)
        XCTAssertEqual(expenseLine?.credit, 600_000)

        // 元入金: 貸方400,000 (純利益)
        let capitalLine = closingLines.first { $0.accountId == "acct-owner-capital" }
        XCTAssertEqual(capitalLine?.debit, 0)
        XCTAssertEqual(capitalLine?.credit, 400_000)
    }

    func testClosingEntry_NetLoss() {
        // 収益30万、費用50万 → 純損失20万が元入金借方へ
        createPostedEntry(accountId: "acct-sales", debit: 0, credit: 300_000, year: 2025)
        createPostedEntry(accountId: "acct-rent", debit: 500_000, credit: 0, year: 2025)

        let entries = fetchAllEntries()
        let lines = fetchAllLines()

        let result = engine.generateClosingBalanceEntry(
            for: 2025, accounts: accounts, journalEntries: entries, journalLines: lines
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isPosted)

        let closingLines = fetchLines(for: result!.id)
        let capitalLine = closingLines.first { $0.accountId == "acct-owner-capital" }
        XCTAssertEqual(capitalLine?.debit, 200_000)  // 純損失 → 借方
        XCTAssertEqual(capitalLine?.credit, 0)
    }

    func testClosingEntry_Idempotent() {
        createPostedEntry(accountId: "acct-sales", debit: 0, credit: 100_000, year: 2025)

        let entries1 = fetchAllEntries()
        let lines1 = fetchAllLines()
        let first = engine.generateClosingBalanceEntry(
            for: 2025, accounts: accounts, journalEntries: entries1, journalLines: lines1
        )

        let entries2 = fetchAllEntries()
        let lines2 = fetchAllLines()
        let second = engine.generateClosingBalanceEntry(
            for: 2025, accounts: accounts, journalEntries: entries2, journalLines: lines2
        )

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first!.id, second!.id, "同一年度の二重生成は既存を返す")
    }

    func testClosingEntry_Delete() {
        createPostedEntry(accountId: "acct-sales", debit: 0, credit: 100_000, year: 2025)

        let entries = fetchAllEntries()
        let lines = fetchAllLines()
        let entry = engine.generateClosingBalanceEntry(
            for: 2025, accounts: accounts, journalEntries: entries, journalLines: lines
        )
        XCTAssertNotNil(entry)

        engine.deleteClosingBalanceEntry(for: 2025)
        try! context.save()

        let remainingEntries = fetchAllEntries()
        let closingEntries = remainingEntries.filter { $0.entryType == .closing }
        XCTAssertTrue(closingEntries.isEmpty)

        let remainingLines = fetchLines(for: entry!.id)
        XCTAssertTrue(remainingLines.isEmpty)
    }

    func testClosingEntry_Regenerate() {
        createPostedEntry(accountId: "acct-sales", debit: 0, credit: 100_000, year: 2025)

        let entries1 = fetchAllEntries()
        let lines1 = fetchAllLines()
        let first = engine.generateClosingBalanceEntry(
            for: 2025, accounts: accounts, journalEntries: entries1, journalLines: lines1
        )
        let firstId = first!.id

        engine.deleteClosingBalanceEntry(for: 2025)
        try! context.save()

        let entries2 = fetchAllEntries()
        let lines2 = fetchAllLines()
        let second = engine.generateClosingBalanceEntry(
            for: 2025, accounts: accounts, journalEntries: entries2, journalLines: lines2
        )

        XCTAssertNotNil(second)
        XCTAssertNotEqual(firstId, second!.id, "再生成は新しいIDで作成される")
    }

    func testClosingEntry_NoRevenueOrExpense() {
        // 残高0 → nil を返す
        let entries = fetchAllEntries()
        let lines = fetchAllLines()

        let result = engine.generateClosingBalanceEntry(
            for: 2025, accounts: accounts, journalEntries: entries, journalLines: lines
        )
        XCTAssertNil(result)
    }

    func testReports_ExcludeClosingEntries() {
        // まず収益・費用を記録
        createPostedEntry(accountId: "acct-sales", debit: 0, credit: 500_000, year: 2025)
        createPostedEntry(accountId: "acct-rent", debit: 200_000, credit: 0, year: 2025)

        // 決算仕訳を生成
        let entries1 = fetchAllEntries()
        let lines1 = fetchAllLines()
        engine.generateClosingBalanceEntry(
            for: 2025, accounts: accounts, journalEntries: entries1, journalLines: lines1
        )
        try! context.save()

        // P&Lが決算仕訳を除外していることを確認
        let entries2 = fetchAllEntries()
        let lines2 = fetchAllLines()
        let pl = AccountingReportService.generateProfitLoss(
            fiscalYear: 2025, accounts: accounts, journalEntries: entries2, journalLines: lines2
        )

        XCTAssertEqual(pl.totalRevenue, 500_000, "P&Lは決算仕訳を除外すべき")
        XCTAssertEqual(pl.totalExpenses, 200_000, "P&Lは決算仕訳を除外すべき")
        XCTAssertEqual(pl.netIncome, 300_000)
    }

    func testOpeningEntry_UsesPreClosingBalance() {
        // 収入取引: 借方=cash 500,000, 貸方=sales 500,000
        createBalancedEntry(
            debitAccountId: "acct-cash", creditAccountId: "acct-sales",
            amount: 500_000, year: 2025
        )
        // 経費取引: 借方=rent 200,000, 貸方=cash 200,000
        createBalancedEntry(
            debitAccountId: "acct-rent", creditAccountId: "acct-cash",
            amount: 200_000, year: 2025
        )

        // 決算仕訳を生成
        let entries1 = fetchAllEntries()
        let lines1 = fetchAllLines()
        engine.generateClosingBalanceEntry(
            for: 2025, accounts: accounts, journalEntries: entries1, journalLines: lines1
        )
        try! context.save()

        // 期首残高仕訳を生成
        let entries2 = fetchAllEntries()
        let lines2 = fetchAllLines()
        let opening = engine.generateOpeningBalanceEntry(
            for: 2026, accounts: accounts, journalEntries: entries2, journalLines: lines2
        )

        XCTAssertNotNil(opening)

        // 期首残高にB/S科目（cash）のみが含まれ、P&L科目は含まれないことを確認
        // cash残高: 500,000(debit) - 200,000(credit) = 300,000
        let openingLines = fetchLines(for: opening!.id)
        let cashLine = openingLines.first { $0.accountId == "acct-cash" }
        XCTAssertNotNil(cashLine, "期首残高にcash残高が含まれるべき")
        XCTAssertEqual(cashLine?.debit, 300_000)

        // 収益・費用科目は期首残高に含まれない（generateOpeningBalanceEntryのbsAccountsフィルタ）
        let salesLine = openingLines.first { $0.accountId == "acct-sales" }
        XCTAssertNil(salesLine, "P&L科目は期首残高に含まれない")
    }

    // MARK: - Helpers

    private func createBalancedEntry(debitAccountId: String, creditAccountId: String, amount: Int, year: Int) {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: year, month: 6, day: 15))!

        let entry = PPJournalEntry(
            sourceKey: "test:\(UUID().uuidString)",
            date: date,
            entryType: .auto,
            memo: "テスト",
            isPosted: true
        )
        context.insert(entry)

        let line1 = PPJournalLine(entryId: entry.id, accountId: debitAccountId, debit: amount, credit: 0, displayOrder: 0)
        let line2 = PPJournalLine(entryId: entry.id, accountId: creditAccountId, debit: 0, credit: amount, displayOrder: 1)
        context.insert(line1)
        context.insert(line2)

        try! context.save()
    }

    private func createPostedEntry(accountId: String, debit: Int, credit: Int, year: Int) {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: year, month: 6, day: 15))!

        let entry = PPJournalEntry(
            sourceKey: "test:\(UUID().uuidString)",
            date: date,
            entryType: .auto,
            memo: "テスト",
            isPosted: true
        )
        context.insert(entry)

        // 相手科目行を追加して借方=貸方を保証
        if debit > 0 {
            // 借方=accountId, 貸方=cash
            let line1 = PPJournalLine(entryId: entry.id, accountId: accountId, debit: debit, credit: 0, displayOrder: 0)
            let line2 = PPJournalLine(entryId: entry.id, accountId: "acct-cash", debit: 0, credit: debit, displayOrder: 1)
            context.insert(line1)
            context.insert(line2)
        } else {
            // 借方=cash, 貸方=accountId
            let line1 = PPJournalLine(entryId: entry.id, accountId: "acct-cash", debit: credit, credit: 0, displayOrder: 0)
            let line2 = PPJournalLine(entryId: entry.id, accountId: accountId, debit: 0, credit: credit, displayOrder: 1)
            context.insert(line1)
            context.insert(line2)
        }

        try! context.save()
    }

    private func fetchAllEntries() -> [PPJournalEntry] {
        let descriptor = FetchDescriptor<PPJournalEntry>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchAllLines() -> [PPJournalLine] {
        let descriptor = FetchDescriptor<PPJournalLine>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchLines(for entryId: UUID) -> [PPJournalLine] {
        let descriptor = FetchDescriptor<PPJournalLine>(
            predicate: #Predicate<PPJournalLine> { $0.entryId == entryId },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
