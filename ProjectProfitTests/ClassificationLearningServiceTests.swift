import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class ClassificationLearningServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

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
