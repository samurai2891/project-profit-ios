import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class ClassificationLearningServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - learnFromCorrection

    func testLearnFromCorrection_createsNewRule() {
        let tx = PPTransaction(type: .expense, amount: 5000, date: Date(), categoryId: "cat-tools", memo: "AWS月額利用料")

        let rule = ClassificationLearningService.learnFromCorrection(
            transaction: tx,
            correctedTaxLine: .communicationExpense,
            existingRules: [],
            modelContext: context
        )

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.keyword, "AWS月額利用料")
        XCTAssertEqual(rule?.taxLine, .communicationExpense)
        XCTAssertEqual(rule?.priority, 100)
        XCTAssertTrue(rule?.isActive == true)
    }

    func testLearnFromCorrection_updatesExistingRule() {
        let existingRule = PPUserRule(keyword: "AWS月額利用料", taxLine: .suppliesExpense, priority: 100)
        context.insert(existingRule)

        let tx = PPTransaction(type: .expense, amount: 5000, date: Date(), categoryId: "cat-tools", memo: "AWS月額利用料")

        let rule = ClassificationLearningService.learnFromCorrection(
            transaction: tx,
            correctedTaxLine: .communicationExpense,
            existingRules: [existingRule],
            modelContext: context
        )

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.taxLine, .communicationExpense)
        XCTAssertEqual(rule?.keyword, "AWS月額利用料")
    }

    func testLearnFromCorrection_emptyMemoReturnsNil() {
        let tx = PPTransaction(type: .expense, amount: 5000, date: Date(), categoryId: "cat-tools", memo: "")

        let rule = ClassificationLearningService.learnFromCorrection(
            transaction: tx,
            correctedTaxLine: .communicationExpense,
            existingRules: [],
            modelContext: context
        )

        XCTAssertNil(rule)
    }

    func testLearnFromCorrection_prefixedMemoStripsPrefix() {
        let tx = PPTransaction(type: .expense, amount: 5000, date: Date(), categoryId: "cat-tools", memo: "[定期] サーバー代")

        let rule = ClassificationLearningService.learnFromCorrection(
            transaction: tx,
            correctedTaxLine: .communicationExpense,
            existingRules: [],
            modelContext: context
        )

        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.keyword, "サーバー代")
    }

    func testLearnFromApprovedCandidate_usesCounterpartyFallbackWhenMemoIsEmpty() {
        let candidate = PostingCandidate(
            businessId: UUID(),
            taxYear: 2026,
            candidateDate: Date(),
            proposedLines: [],
            status: .approved,
            source: .ocr,
            memo: nil,
            legacySnapshot: PostingCandidateLegacySnapshot(
                type: .expense,
                categoryId: "cat-tools",
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
                counterpartyName: "クラウドサービス"
            )
        )

        let rule = ClassificationLearningService.learnFromApprovedCandidate(
            candidate: candidate,
            resolvedTaxLine: .communicationExpense,
            existingRules: [],
            modelContext: context
        )

        XCTAssertEqual(rule?.keyword, "クラウドサービス")
        XCTAssertEqual(rule?.taxLine, .communicationExpense)
    }

    func testExtractKeywordFromCandidate_prefersEvidenceCounterpartyWhenCandidateTextMissing() {
        let candidate = PostingCandidate(
            businessId: UUID(),
            taxYear: 2026,
            candidateDate: Date(),
            proposedLines: [],
            status: .needsReview,
            source: .ocr,
            memo: "   ",
            legacySnapshot: nil
        )
        let evidence = EvidenceDocument(
            businessId: UUID(),
            taxYear: 2026,
            sourceType: .camera,
            legalDocumentType: .receipt,
            storageCategory: .paperScan,
            originalFilename: "receipt.jpg",
            mimeType: "image/jpeg",
            fileHash: "hash",
            originalFilePath: "receipt.jpg",
            structuredFields: EvidenceStructuredFields(counterpartyName: "さくらインターネット")
        )

        let keyword = ClassificationLearningService.extractKeyword(from: candidate, evidence: evidence)

        XCTAssertEqual(keyword, "さくらインターネット")
    }

    // MARK: - extractKeyword

    func testExtractKeyword_shortMemoUsedAsIs() {
        let keyword = ClassificationLearningService.extractKeyword(from: "AWS利用料")
        XCTAssertEqual(keyword, "AWS利用料")
    }

    func testExtractKeyword_longMemoUsesFirstToken() {
        let keyword = ClassificationLearningService.extractKeyword(from: "Amazon Web Services 月額利用料 12月分")
        XCTAssertEqual(keyword, "Amazon")
    }

    func testExtractKeyword_emptyMemoReturnsEmpty() {
        let keyword = ClassificationLearningService.extractKeyword(from: "")
        XCTAssertEqual(keyword, "")
    }
}
