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

    private func makeCandidate(
        memo: String,
        categoryId: String = "cat-tools",
        type: TransactionType = .expense
    ) -> PostingCandidate {
        PostingCandidate(
            businessId: UUID(),
            taxYear: 2026,
            candidateDate: Date(),
            status: .needsReview,
            source: .ocr,
            memo: memo,
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

    private func makeEvidence(counterpartyName: String? = nil, ocrText: String? = nil) -> EvidenceDocument {
        EvidenceDocument(
            businessId: UUID(),
            taxYear: 2026,
            sourceType: .camera,
            legalDocumentType: .receipt,
            storageCategory: .paperScan,
            originalFilename: "receipt.jpg",
            mimeType: "image/jpeg",
            fileHash: UUID().uuidString,
            originalFilePath: "receipt.jpg",
            ocrText: ocrText,
            searchTokens: ["aws", "jr"],
            structuredFields: EvidenceStructuredFields(counterpartyName: counterpartyName)
        )
    }

    // MARK: - Dictionary Rules

    func testDictionaryMatchAWS() {
        let candidate = makeCandidate(memo: "AWS月額利用料")
        let result = ClassificationEngine.classify(
            candidate: candidate,
            evidence: nil,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .communicationExpense)
        XCTAssertEqual(result.source, .dictionary)
    }

    func testDictionaryMatchTravel() {
        let candidate = makeCandidate(memo: "JR東京-大阪")
        let result = ClassificationEngine.classify(
            candidate: candidate,
            evidence: nil,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .travelExpense)
    }

    func testDictionaryMatchRent() {
        let candidate = makeCandidate(memo: "12月分家賃")
        let result = ClassificationEngine.classify(
            candidate: candidate,
            evidence: nil,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .rentExpense)
    }

    // MARK: - User Rule Priority

    func testUserRuleOverridesDictionary() {
        let candidate = makeCandidate(memo: "AWS会食費用")
        let userRule = PPUserRule(keyword: "AWS", taxLine: .suppliesExpense, priority: 100)

        let result = ClassificationEngine.classify(
            candidate: candidate,
            evidence: nil,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: [userRule]
        )
        XCTAssertEqual(result.taxLine, .suppliesExpense)
        XCTAssertEqual(result.source, .userRule)
        XCTAssertEqual(result.confidence, 1.0)
    }

    func testInactiveUserRuleIsIgnored() {
        let candidate = makeCandidate(memo: "AWS")
        let userRule = PPUserRule(keyword: "AWS", taxLine: .suppliesExpense, priority: 100, isActive: false)

        let result = ClassificationEngine.classify(
            candidate: candidate,
            evidence: nil,
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
        let candidate = makeCandidate(memo: "未知の取引", categoryId: "cat-hosting")
        let result = ClassificationEngine.classify(
            candidate: candidate,
            evidence: nil,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.source, .categoryMapping)
        XCTAssertEqual(result.taxLine, .communicationExpense)
    }

    // MARK: - Fallback

    func testFallbackToMisc() {
        let candidate = makeCandidate(memo: "完全に未知の取引内容", categoryId: "cat-nonexistent")
        let result = ClassificationEngine.classify(
            candidate: candidate,
            evidence: nil,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .miscExpense)
        XCTAssertEqual(result.source, .fallback)
    }

    func testFallbackIncomeToSales() {
        let candidate = makeCandidate(memo: "不明な収入", categoryId: "cat-nonexistent", type: .income)
        let result = ClassificationEngine.classify(
            candidate: candidate,
            evidence: nil,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .salesRevenue)
    }

    // MARK: - Batch Classification

    func testBatchClassificationForCandidates() {
        let candidates = [
            makeCandidate(memo: "AWS"),
            makeCandidate(memo: "JR"),
            makeCandidate(memo: "不明"),
        ]
        let results = ClassificationEngine.classifyBatch(
            candidates: candidates,
            evidencesById: [:],
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].result.taxLine, .communicationExpense)
        XCTAssertEqual(results[1].result.taxLine, .travelExpense)
    }

    func testClassifyUsesEvidenceTextWhenCandidateMemoMissing() {
        let candidate = makeCandidate(memo: "   ")
        let evidence = makeEvidence(counterpartyName: "さくらインターネット", ocrText: "さくらインターネット 利用料")

        let result = ClassificationEngine.classify(
            candidate: candidate,
            evidence: evidence,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: [PPUserRule(keyword: "さくら", taxLine: .communicationExpense, priority: 300)]
        )

        XCTAssertEqual(result.source, .userRule)
        XCTAssertEqual(result.taxLine, .communicationExpense)
    }

    // MARK: - Case Insensitivity

    func testCompatibilityAdapterRetainsTransactionEntryPoint() {
        let tx = PPTransaction(type: .expense, amount: 1000, date: Date(), categoryId: "cat-tools", memo: "aws monthly fee")
        let result = ClassificationEngineCompatibilityAdapter.classify(
            transaction: tx,
            categories: dataStore.categories,
            accounts: dataStore.accounts,
            userRules: []
        )
        XCTAssertEqual(result.taxLine, .communicationExpense)
    }
}
