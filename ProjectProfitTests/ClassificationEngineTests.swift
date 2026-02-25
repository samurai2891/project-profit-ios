import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class ClassificationEngineTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self,
            PPAccount.self, PPJournalEntry.self, PPJournalLine.self, PPAccountingProfile.self,
            PPUserRule.self,
            PPFixedAsset.self,
            configurations: config
        )
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

    private func makeTx(memo: String, categoryId: String = "cat-tools", type: TransactionType = .expense) -> PPTransaction {
        PPTransaction(type: type, amount: 1000, date: Date(), categoryId: categoryId, memo: memo)
    }

    // MARK: - Dictionary Rules

    func testDictionaryMatchAWS() {
        let tx = makeTx(memo: "AWS月額利用料")
        let result = ClassificationEngine.classify(
            transaction: tx,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .communicationExpense)
        XCTAssertEqual(result.source, .dictionary)
    }

    func testDictionaryMatchTravel() {
        let tx = makeTx(memo: "JR東京-大阪")
        let result = ClassificationEngine.classify(
            transaction: tx,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .travelExpense)
    }

    func testDictionaryMatchRent() {
        let tx = makeTx(memo: "12月分家賃")
        let result = ClassificationEngine.classify(
            transaction: tx,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .rentExpense)
    }

    // MARK: - User Rule Priority

    func testUserRuleOverridesDictionary() {
        let tx = makeTx(memo: "AWS会食費用")  // AWS would match communication, 会食 would match entertainment
        let userRule = PPUserRule(keyword: "AWS", taxLine: .suppliesExpense, priority: 100)

        let result = ClassificationEngine.classify(
            transaction: tx,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: [userRule]
        )
        XCTAssertEqual(result.taxLine, .suppliesExpense)
        XCTAssertEqual(result.source, .userRule)
        XCTAssertEqual(result.confidence, 1.0)
    }

    func testInactiveUserRuleIsIgnored() {
        let tx = makeTx(memo: "AWS")
        let userRule = PPUserRule(keyword: "AWS", taxLine: .suppliesExpense, priority: 100, isActive: false)

        let result = ClassificationEngine.classify(
            transaction: tx,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: [userRule]
        )
        // ユーザールール無効なので辞書マッチにフォールバック
        XCTAssertEqual(result.taxLine, .communicationExpense)
        XCTAssertEqual(result.source, .dictionary)
    }

    // MARK: - Category Mapping Fallback

    func testCategoryMappingFallback() {
        // カテゴリ紐付けがある場合のフォールバック
        let tx = makeTx(memo: "未知の取引", categoryId: "cat-hosting")
        let result = ClassificationEngine.classify(
            transaction: tx,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        // cat-hosting はブートストラップで acct-communication にリンクされている
        XCTAssertEqual(result.source, .categoryMapping)
        XCTAssertEqual(result.taxLine, .communicationExpense)
    }

    // MARK: - Fallback

    func testFallbackToMisc() {
        let tx = makeTx(memo: "完全に未知の取引内容", categoryId: "cat-nonexistent")
        let result = ClassificationEngine.classify(
            transaction: tx,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .miscExpense)
        XCTAssertEqual(result.source, .fallback)
    }

    func testFallbackIncomeToSales() {
        let tx = makeTx(memo: "不明な収入", categoryId: "cat-nonexistent", type: .income)
        let result = ClassificationEngine.classify(
            transaction: tx,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .salesRevenue)
    }

    // MARK: - Batch Classification

    func testBatchClassification() {
        let txs = [
            makeTx(memo: "AWS"),
            makeTx(memo: "JR"),
            makeTx(memo: "不明"),
        ]
        let results = ClassificationEngine.classifyBatch(
            transactions: txs,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].result.taxLine, .communicationExpense)
        XCTAssertEqual(results[1].result.taxLine, .travelExpense)
    }

    // MARK: - Case Insensitivity

    func testCaseInsensitiveMatch() {
        let tx = makeTx(memo: "aws monthly fee")
        let result = ClassificationEngine.classify(
            transaction: tx,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .communicationExpense)
    }
}
