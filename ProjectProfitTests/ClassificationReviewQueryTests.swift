import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ClassificationReviewQueryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var businessId: UUID!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        businessId = dataStore.businessProfile?.id
    }

    override func tearDown() {
        businessId = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testSnapshotReturnsCandidateEvidenceAndSuggestedCategory() async throws {
        let legacyAccount = PPAccount(
            id: "acct-cloud-communication",
            code: "612",
            name: "クラウド通信費",
            accountType: .expense,
            subtype: .communicationExpense,
            displayOrder: 999
        )
        let category = PPCategory(
            id: "cat-cloud-communication",
            name: "クラウド通信費",
            type: .expense,
            icon: "wifi",
            linkedAccountId: legacyAccount.id
        )
        context.insert(legacyAccount)
        context.insert(category)
        context.insert(PPUserRule(keyword: "aws", taxLine: .communicationExpense, priority: 300))
        try context.save()

        let evidence = EvidenceDocument(
            businessId: businessId,
            taxYear: 2026,
            sourceType: .camera,
            legalDocumentType: .receipt,
            storageCategory: .paperScan,
            issueDate: date(2026, 3, 7),
            originalFilename: "aws.jpg",
            mimeType: "image/jpeg",
            fileHash: "aws-review-hash",
            originalFilePath: "aws.jpg",
            ocrText: "AWS 月額利用料",
            searchTokens: ["aws", "review"],
            structuredFields: EvidenceStructuredFields(counterpartyName: "AWS")
        )
        let candidate = PostingCandidate(
            evidenceId: evidence.id,
            businessId: businessId,
            taxYear: 2026,
            candidateDate: date(2026, 3, 7),
            status: .needsReview,
            source: .ocr,
            memo: "AWS 月額利用料",
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
                counterpartyName: "AWS"
            )
        )

        try await EvidenceCatalogUseCase(modelContext: context).save(evidence)
        try await PostingWorkflowUseCase(modelContext: context).saveCandidate(candidate)

        let snapshot = ClassificationQueryUseCase(modelContext: context).snapshot()
        let result = try XCTUnwrap(snapshot.results.first(where: { $0.candidate.id == candidate.id }))

        XCTAssertEqual(result.evidence?.id, evidence.id)
        XCTAssertEqual(result.result.source, .userRule)
        XCTAssertEqual(result.result.taxLine, .communicationExpense)
        XCTAssertEqual(result.suggestedCategoryId, category.id)
    }

    func testViewModelCorrectionLearnsFromCandidateAndClearsReviewItem() async throws {
        let evidence = EvidenceDocument(
            businessId: businessId,
            taxYear: 2026,
            sourceType: .camera,
            legalDocumentType: .receipt,
            storageCategory: .paperScan,
            issueDate: date(2026, 3, 8),
            originalFilename: "sakura.jpg",
            mimeType: "image/jpeg",
            fileHash: "sakura-review-hash",
            originalFilePath: "sakura.jpg",
            structuredFields: EvidenceStructuredFields(counterpartyName: "さくらインターネット")
        )
        let candidate = PostingCandidate(
            evidenceId: evidence.id,
            businessId: businessId,
            taxYear: 2026,
            candidateDate: date(2026, 3, 8),
            status: .needsReview,
            source: .ocr,
            memo: "   ",
            legacySnapshot: PostingCandidateLegacySnapshot(
                type: .expense,
                categoryId: "cat-nonexistent",
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

        try await EvidenceCatalogUseCase(modelContext: context).save(evidence)
        try await PostingWorkflowUseCase(modelContext: context).saveCandidate(candidate)

        let viewModel = ClassificationViewModel(modelContext: context)
        XCTAssertEqual(viewModel.unclassifiedResults.count, 1)

        viewModel.correctClassification(candidateId: candidate.id, newTaxLine: .communicationExpense)

        XCTAssertTrue(viewModel.userRules.contains(where: {
            $0.keyword == "さくらインターネット" && $0.taxLine == .communicationExpense
        }))
        XCTAssertTrue(viewModel.unclassifiedResults.isEmpty)
        XCTAssertTrue(viewModel.results.contains(where: {
            $0.candidate.id == candidate.id && $0.result.source == .userRule
        }))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
