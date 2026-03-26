import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class LedgerDataStoreReadOnlyTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        FeatureFlags.useLegacyLedger = true
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        FeatureFlags.clearOverrides()
        super.tearDown()
    }

    // MARK: - Default Access Mode

    func testDefaultAccessModeIsReadOnly() {
        let store = LedgerDataStore(modelContext: context)
        XCTAssertTrue(store.isReadOnly, "デフォルトのアクセスモードはreadOnlyであるべき")
    }

    // MARK: - Read-Only Rejects Writes

    func testReadOnlyStoreRejectsCreate() {
        let store = LedgerDataStore(modelContext: context, accessMode: .readOnly)
        let book = store.createBook(ledgerType: .cashBook, title: "テスト")
        XCTAssertNil(book, "readOnlyモードでは帳簿を作成できないべき")
        XCTAssertNotNil(store.lastError)
    }

    func testReadOnlyStoreRejectsDelete() {
        // まずreadWriteで帳簿を作成
        let rwStore = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        guard let book = rwStore.createBook(ledgerType: .cashBook, title: "削除テスト") else {
            XCTFail("帳簿の作成に失敗")
            return
        }

        // readOnlyで削除を試みる
        let roStore = LedgerDataStore(modelContext: context, accessMode: .readOnly)
        roStore.deleteBook(book.id)

        // 帳簿はまだ存在するべき
        roStore.loadBooks()
        XCTAssertFalse(roStore.books.isEmpty, "readOnlyモードでは帳簿を削除できないべき")
    }

    func testReadOnlyStoreRejectsUpdateBookTitle() {
        let rwStore = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        guard let book = rwStore.createBook(ledgerType: .cashBook, title: "元の名前") else {
            XCTFail("帳簿の作成に失敗")
            return
        }

        let roStore = LedgerDataStore(modelContext: context, accessMode: .readOnly)
        roStore.updateBookTitle(book.id, title: "変更後の名前")

        roStore.loadBooks()
        XCTAssertEqual(roStore.book(for: book.id)?.title, "元の名前", "readOnlyモードではタイトルを変更できないべき")
    }

    func testReadOnlyStoreRejectsAddEntry() {
        let rwStore = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        guard let book = rwStore.createBook(ledgerType: .cashBook, title: "テスト") else {
            XCTFail("帳簿の作成に失敗")
            return
        }

        let roStore = LedgerDataStore(modelContext: context, accessMode: .readOnly)
        let entry = CashBookEntry(
            month: 1, day: 1, description: "売上", account: "売上高",
            income: 1000
        )
        let result = roStore.addEntry(to: book.id, entry: entry)

        XCTAssertNil(result, "readOnlyモードではエントリを追加できないべき")
        XCTAssertEqual(roStore.fetchRawEntries(for: book.id).count, 0)
    }

    // MARK: - Read-Write Allows Writes

    func testReadWriteStoreAllowsCreate() {
        let store = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        let book = store.createBook(ledgerType: .cashBook, title: "テスト")
        XCTAssertNotNil(book, "readWriteモードでは帳簿を作成できるべき")
    }

    func testReadWriteStoreAllowsAddEntry() {
        let store = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        guard let book = store.createBook(ledgerType: .cashBook, title: "テスト") else {
            XCTFail("帳簿の作成に失敗")
            return
        }

        let entry = CashBookEntry(
            month: 1, day: 1, description: "売上", account: "売上高",
            income: 1000
        )
        let result = store.addEntry(to: book.id, entry: entry)
        XCTAssertNotNil(result, "readWriteモードではエントリを追加できるべき")
    }

    // MARK: - Read-Only Still Allows Reads

    func testReadOnlyStoreCanReadBooks() {
        let rwStore = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        rwStore.createBook(ledgerType: .cashBook, title: "読み取りテスト")

        let roStore = LedgerDataStore(modelContext: context, accessMode: .readOnly)
        XCTAssertEqual(roStore.books.count, 1, "readOnlyモードでも帳簿を読み取れるべき")
        XCTAssertEqual(roStore.books.first?.title, "読み取りテスト")
    }

    func testReadOnlyStoreCanReadEntries() {
        let rwStore = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        guard let book = rwStore.createBook(ledgerType: .cashBook, title: "テスト") else {
            XCTFail("帳簿の作成に失敗")
            return
        }
        rwStore.addEntry(to: book.id, entry: CashBookEntry(
            month: 1, day: 1, description: "売上", account: "売上高",
            income: 1000
        ))

        let roStore = LedgerDataStore(modelContext: context, accessMode: .readOnly)
        let entries = roStore.fetchRawEntries(for: book.id)
        XCTAssertEqual(entries.count, 1, "readOnlyモードでもエントリを読み取れるべき")
    }

    // MARK: - Error Message

    func testReadOnlyErrorMessage() {
        let store = LedgerDataStore(modelContext: context, accessMode: .readOnly)
        _ = store.createBook(ledgerType: .cashBook, title: "テスト")

        XCTAssertEqual(
            store.lastError?.errorDescription,
            "旧台帳は読み取り専用です",
            "readOnlyモードでは正しいエラーメッセージを設定するべき"
        )
    }
}
