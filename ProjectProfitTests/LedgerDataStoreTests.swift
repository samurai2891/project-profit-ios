import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class LedgerDataStoreTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var store: LedgerDataStore!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext
        store = LedgerDataStore(modelContext: context, accessMode: .readWrite)
    }

    override func tearDown() {
        store = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Book CRUD

    func testCreateBook() {
        let book = store.createBook(
            ledgerType: .cashBook,
            title: "現金出納帳 2025"
        )!

        XCTAssertEqual(book.title, "現金出納帳 2025")
        XCTAssertEqual(book.ledgerTypeRaw, "cash_book")
        XCTAssertEqual(store.books.count, 1)
    }

    func testCreateMultipleBooks() {
        store.createBook(ledgerType: .cashBook, title: "現金出納帳")
        store.createBook(ledgerType: .bankAccountBook, title: "預金出納帳")
        store.createBook(ledgerType: .journal, title: "仕訳帳")

        XCTAssertEqual(store.books.count, 3)
    }

    func testUpdateBookTitle() {
        let book = store.createBook(ledgerType: .cashBook, title: "旧名称")!

        store.updateBookTitle(book.id, title: "新名称")

        XCTAssertEqual(store.book(for: book.id)?.title, "新名称")
    }

    func testDeleteBook() {
        let book = store.createBook(ledgerType: .cashBook, title: "削除対象")!

        store.deleteBook(book.id)

        XCTAssertEqual(store.books.count, 0)
        XCTAssertNil(store.book(for: book.id))
    }

    func testDeleteBookCascadesEntries() {
        let book = store.createBook(ledgerType: .cashBook, title: "テスト")!
        let entry = CashBookEntry(
            month: 1, day: 15, description: "売上", account: "売上高",
            income: 10000
        )
        store.addEntry(to: book.id, entry: entry)

        XCTAssertEqual(store.fetchRawEntries(for: book.id).count, 1)

        store.deleteBook(book.id)

        XCTAssertEqual(store.fetchRawEntries(for: book.id).count, 0)
    }

    func testBooksFilterByType() {
        store.createBook(ledgerType: .cashBook, title: "現金1")
        store.createBook(ledgerType: .cashBook, title: "現金2")
        store.createBook(ledgerType: .journal, title: "仕訳帳")

        let cashBooks = store.books(ofType: .cashBook)
        XCTAssertEqual(cashBooks.count, 2)

        let journals = store.books(ofType: .journal)
        XCTAssertEqual(journals.count, 1)
    }

    // MARK: - Entry CRUD

    func testAddCashBookEntry() {
        let book = store.createBook(ledgerType: .cashBook, title: "テスト")!
        let entry = CashBookEntry(
            month: 3, day: 1, description: "事務用品", account: "消耗品費",
            expense: 5000
        )

        let sdEntry = store.addEntry(to: book.id, entry: entry)

        XCTAssertNotNil(sdEntry)
        XCTAssertEqual(store.fetchRawEntries(for: book.id).count, 1)
    }

    func testDecodeCashBookEntryRoundTrip() {
        let book = store.createBook(ledgerType: .cashBook, title: "テスト")!
        let original = CashBookEntry(
            month: 4, day: 10, description: "売上入金", account: "売上高",
            income: 50000
        )
        store.addEntry(to: book.id, entry: original)

        let decoded = store.cashBookEntries(for: book.id)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].month, 4)
        XCTAssertEqual(decoded[0].day, 10)
        XCTAssertEqual(decoded[0].description, "売上入金")
        XCTAssertEqual(decoded[0].account, "売上高")
        XCTAssertEqual(decoded[0].income, 50000)
        XCTAssertNil(decoded[0].expense)
    }

    func testDeleteEntry() {
        let book = store.createBook(ledgerType: .cashBook, title: "テスト")!
        let entry = CashBookEntry(
            month: 1, day: 1, description: "テスト", account: "テスト",
            income: 1000
        )
        let sdEntry = store.addEntry(to: book.id, entry: entry)!

        store.deleteEntry(sdEntry.id, bookId: book.id)

        XCTAssertEqual(store.fetchRawEntries(for: book.id).count, 0)
    }

    // MARK: - Balance Calculations

    func testCashBookBalance() {
        let metadataJSON = LedgerBridge.encodeCashBookMetadata(
            CashBookMetadata(carryForward: 100000)
        )
        let book = store.createBook(
            ledgerType: .cashBook, title: "テスト",
            metadataJSON: metadataJSON
        )!

        // エントリ1: 入金 50000
        store.addEntry(to: book.id, entry: CashBookEntry(
            month: 1, day: 5, description: "売上", account: "売上高",
            income: 50000
        ))
        // エントリ2: 出金 30000
        store.addEntry(to: book.id, entry: CashBookEntry(
            month: 1, day: 10, description: "仕入", account: "仕入高",
            expense: 30000
        ))

        let balances = store.cashBookBalances(for: book.id)
        XCTAssertEqual(balances.count, 2)
        // 残高 = 100000 + 50000 - 0 = 150000
        XCTAssertEqual(balances[0].balance, 150000)
        // 残高 = 150000 + 0 - 30000 = 120000
        XCTAssertEqual(balances[1].balance, 120000)
    }

    func testBankAccountBookBalance() {
        let metadataJSON = LedgerBridge.encodeBankAccountBookMetadata(
            BankAccountBookMetadata(
                bankName: "テスト銀行", branchName: "本店",
                accountType: "普通", carryForward: 500000
            )
        )
        let book = store.createBook(
            ledgerType: .bankAccountBook, title: "テスト",
            metadataJSON: metadataJSON
        )!

        store.addEntry(to: book.id, entry: BankAccountBookEntry(
            month: 2, day: 1, description: "振込", account: "売掛金",
            deposit: 200000
        ))
        store.addEntry(to: book.id, entry: BankAccountBookEntry(
            month: 2, day: 5, description: "引落", account: "買掛金",
            withdrawal: 80000
        ))

        let balances = store.bankAccountBookBalances(for: book.id)
        XCTAssertEqual(balances[0].balance, 700000)  // 500000 + 200000
        XCTAssertEqual(balances[1].balance, 620000)  // 700000 - 80000
    }

    func testAccountsReceivableBalance() {
        let metadataJSON = LedgerBridge.encodeAccountsReceivableMetadata(
            AccountsReceivableMetadata(clientName: "テスト社", carryForward: 100000)
        )
        let book = store.createBook(
            ledgerType: .accountsReceivable, title: "テスト",
            metadataJSON: metadataJSON
        )!

        store.addEntry(to: book.id, entry: AccountsReceivableEntry(
            month: 3, day: 1, counterAccount: "売上高", description: "商品売上",
            salesAmount: 80000
        ))
        store.addEntry(to: book.id, entry: AccountsReceivableEntry(
            month: 3, day: 15, counterAccount: "預金", description: "回収",
            receivedAmount: 50000
        ))

        let balances = store.accountsReceivableBalances(for: book.id)
        // 残高 = 100000 + 80000 - 0 = 180000
        XCTAssertEqual(balances[0].balance, 180000)
        // 残高 = 180000 + 0 - 50000 = 130000
        XCTAssertEqual(balances[1].balance, 130000)
    }

    func testAccountsPayableBalance() {
        let metadataJSON = LedgerBridge.encodeAccountsPayableMetadata(
            AccountsPayableMetadata(supplierName: "仕入先", carryForward: 200000)
        )
        let book = store.createBook(
            ledgerType: .accountsPayable, title: "テスト",
            metadataJSON: metadataJSON
        )!

        store.addEntry(to: book.id, entry: AccountsPayableEntry(
            month: 4, day: 1, counterAccount: "仕入高", description: "商品仕入",
            purchaseAmount: 150000
        ))
        store.addEntry(to: book.id, entry: AccountsPayableEntry(
            month: 4, day: 20, counterAccount: "預金", description: "支払",
            paymentAmount: 100000
        ))

        let balances = store.accountsPayableBalances(for: book.id)
        // 残高 = 200000 + 150000 - 0 = 350000
        XCTAssertEqual(balances[0].balance, 350000)
        // 残高 = 350000 + 0 - 100000 = 250000
        XCTAssertEqual(balances[1].balance, 250000)
    }

    func testExpenseBookRunningTotal() {
        let metadataJSON = LedgerBridge.encodeExpenseBookMetadata(
            ExpenseBookMetadata(accountName: "消耗品費")
        )
        let book = store.createBook(
            ledgerType: .expenseBook, title: "テスト",
            metadataJSON: metadataJSON
        )!

        store.addEntry(to: book.id, entry: ExpenseBookEntry(
            month: 5, day: 1, counterAccount: "現金", description: "コピー用紙",
            amount: 3000
        ))
        store.addEntry(to: book.id, entry: ExpenseBookEntry(
            month: 5, day: 10, counterAccount: "現金", description: "インク",
            amount: 5000
        ))

        let totals = store.expenseBookRunningTotals(for: book.id)
        XCTAssertEqual(totals[0].balance, 3000)
        XCTAssertEqual(totals[1].balance, 8000)  // 3000 + 5000
    }

    func testGeneralLedgerBalance_AssetAccount() {
        let metadataJSON = LedgerBridge.encodeGeneralLedgerMetadata(
            GeneralLedgerMetadata(
                accountName: "現金", accountAttribute: .asset,
                carryForward: 100000
            )
        )
        let book = store.createBook(
            ledgerType: .generalLedger, title: "テスト",
            metadataJSON: metadataJSON
        )!

        // 借方増加（資産）
        store.addEntry(to: book.id, entry: GeneralLedgerEntry(
            month: 6, day: 1, counterAccount: "売上高", description: "現金売上",
            debit: 30000
        ))
        // 貸方減少（資産）
        store.addEntry(to: book.id, entry: GeneralLedgerEntry(
            month: 6, day: 5, counterAccount: "仕入高", description: "現金仕入",
            credit: 10000
        ))

        let balances = store.generalLedgerBalances(for: book.id)
        // 資産: 残高 = 100000 + 30000 - 0 = 130000
        XCTAssertEqual(balances[0].balance, 130000)
        // 資産: 残高 = 130000 + 0 - 10000 = 120000
        XCTAssertEqual(balances[1].balance, 120000)
    }

    func testGeneralLedgerBalance_LiabilityAccount() {
        let metadataJSON = LedgerBridge.encodeGeneralLedgerMetadata(
            GeneralLedgerMetadata(
                accountName: "買掛金", accountAttribute: .liability,
                carryForward: 200000
            )
        )
        let book = store.createBook(
            ledgerType: .generalLedger, title: "テスト",
            metadataJSON: metadataJSON
        )!

        // 貸方増加（負債）
        store.addEntry(to: book.id, entry: GeneralLedgerEntry(
            month: 7, day: 1, counterAccount: "仕入高", description: "仕入",
            credit: 50000
        ))
        // 借方減少（負債）
        store.addEntry(to: book.id, entry: GeneralLedgerEntry(
            month: 7, day: 15, counterAccount: "預金", description: "支払",
            debit: 80000
        ))

        let balances = store.generalLedgerBalances(for: book.id)
        // 負債: 残高 = 200000 - 0 + 50000 = 250000
        XCTAssertEqual(balances[0].balance, 250000)
        // 負債: 残高 = 250000 - 80000 + 0 = 170000
        XCTAssertEqual(balances[1].balance, 170000)
    }

    // MARK: - CSV Export

    func testCSVExportCashBook() {
        let metadataJSON = LedgerBridge.encodeCashBookMetadata(
            CashBookMetadata(carryForward: 100000)
        )
        let book = store.createBook(
            ledgerType: .cashBook, title: "テスト",
            metadataJSON: metadataJSON
        )!

        store.addEntry(to: book.id, entry: CashBookEntry(
            month: 1, day: 5, description: "売上", account: "売上高",
            income: 50000
        ))

        let csv = store.exportCSV(for: book.id)
        XCTAssertNotNil(csv)
        XCTAssertTrue(csv!.hasPrefix("\u{FEFF}"), "UTF-8 BOM付き")
        XCTAssertTrue(csv!.contains("月,日,摘要,勘定科目,入金,出金,残高"))
        XCTAssertTrue(csv!.contains("前期より繰越"))
        XCTAssertTrue(csv!.contains("売上"))
    }

    func testCSVExportInvoice() {
        let metadataJSON = LedgerBridge.encodeCashBookMetadata(
            CashBookMetadata(carryForward: 0)
        )
        let book = store.createBook(
            ledgerType: .cashBookInvoice, title: "テスト",
            metadataJSON: metadataJSON,
            includeInvoice: true
        )!

        store.addEntry(to: book.id, entry: CashBookEntry(
            month: 1, day: 1, description: "テスト", account: "売上高",
            income: 10000,
            reducedTax: true,
            invoiceType: .applicable
        ))

        let csv = store.exportCSV(for: book.id)
        XCTAssertNotNil(csv)
        XCTAssertTrue(csv!.contains("軽減税率"))
        XCTAssertTrue(csv!.contains("インボイス"))
        XCTAssertTrue(csv!.contains("〇"))
    }

    // MARK: - Final Balance

    func testFinalBalance() {
        let metadataJSON = LedgerBridge.encodeCashBookMetadata(
            CashBookMetadata(carryForward: 50000)
        )
        let book = store.createBook(
            ledgerType: .cashBook, title: "テスト",
            metadataJSON: metadataJSON
        )!

        store.addEntry(to: book.id, entry: CashBookEntry(
            month: 1, day: 1, description: "入金", account: "売上高",
            income: 20000
        ))
        store.addEntry(to: book.id, entry: CashBookEntry(
            month: 1, day: 2, description: "出金", account: "消耗品費",
            expense: 5000
        ))

        XCTAssertEqual(store.finalBalance(for: book.id), 65000)  // 50000 + 20000 - 5000
    }

    func testFinalBalanceEmpty() {
        let book = store.createBook(ledgerType: .journal, title: "テスト")!
        XCTAssertNil(store.finalBalance(for: book.id))
    }

    func testReadOnlyStoreRejectsBookCreation() {
        let readOnlyStore = LedgerDataStore(modelContext: context, accessMode: .readOnly)

        let created = readOnlyStore.createBook(ledgerType: .cashBook, title: "読み取り専用")

        XCTAssertNil(created)
        XCTAssertEqual(readOnlyStore.books.count, 0)
        XCTAssertEqual(readOnlyStore.lastError?.errorDescription, "旧台帳は読み取り専用です")
    }

    func testReadOnlyStoreRejectsEntryMutation() {
        let writableStore = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        let book = writableStore.createBook(ledgerType: .cashBook, title: "テスト")!
        let readOnlyStore = LedgerDataStore(modelContext: context, accessMode: .readOnly)
        let entry = CashBookEntry(
            month: 1,
            day: 1,
            description: "売上",
            account: "売上高",
            income: 1000
        )

        let inserted = readOnlyStore.addEntry(to: book.id, entry: entry)
        readOnlyStore.deleteBook(book.id)

        XCTAssertNil(inserted)
        XCTAssertNotNil(readOnlyStore.book(for: book.id))
        XCTAssertEqual(readOnlyStore.fetchRawEntries(for: book.id).count, 0)
        XCTAssertEqual(readOnlyStore.lastError?.errorDescription, "旧台帳は読み取り専用です")
    }
}
