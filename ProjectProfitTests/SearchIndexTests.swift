import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class SearchIndexTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

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

    func testEvidenceRepositorySearchesByIndexedFields() async throws {
        let repository = SwiftDataEvidenceRepository(modelContext: context)
        let businessId = UUID()
        let projectId = UUID()
        let matched = makeEvidence(
            businessId: businessId,
            fileHash: "ABC123HASH",
            projectId: projectId,
            counterpartyName: "青色商事",
            registrationNumber: "T1234567890123",
            totalAmount: Decimal(string: "12000")!
        )
        let other = makeEvidence(
            businessId: businessId,
            fileHash: "OTHER999",
            projectId: UUID(),
            counterpartyName: "白色ストア",
            registrationNumber: "T9999999999999",
            totalAmount: Decimal(string: "4500")!
        )

        try await repository.save(matched)
        try await repository.save(other)

        let byAmount = try await repository.search(
            criteria: EvidenceSearchCriteria(
                businessId: businessId,
                amountRange: Decimal(string: "11000")!...Decimal(string: "13000")!
            )
        )
        let byCounterparty = try await repository.search(
            criteria: EvidenceSearchCriteria(
                businessId: businessId,
                counterpartyText: "青色"
            )
        )
        let byRegistration = try await repository.search(
            criteria: EvidenceSearchCriteria(
                businessId: businessId,
                registrationNumber: "T1234567890123"
            )
        )
        let byProject = try await repository.search(
            criteria: EvidenceSearchCriteria(
                businessId: businessId,
                projectId: projectId
            )
        )
        let byFileHash = try await repository.search(
            criteria: EvidenceSearchCriteria(
                businessId: businessId,
                fileHash: "abc123hash"
            )
        )

        XCTAssertEqual(byAmount.map(\.id), [matched.id])
        XCTAssertEqual(byCounterparty.map(\.id), [matched.id])
        XCTAssertEqual(byRegistration.map(\.id), [matched.id])
        XCTAssertEqual(byProject.map(\.id), [matched.id])
        XCTAssertEqual(byFileHash.map(\.id), [matched.id])
    }

    func testEvidenceRepositoryAutoRebuildsMissingIndex() async throws {
        let repository = SwiftDataEvidenceRepository(modelContext: context)
        let businessId = UUID()
        let evidence = makeEvidence(
            businessId: businessId,
            fileHash: "HASH-REBUILD",
            projectId: UUID(),
            counterpartyName: "再索引商店",
            registrationNumber: "T2222222222222",
            totalAmount: Decimal(string: "3300")!
        )

        try await repository.save(evidence)

        let existingIndex = try context.fetch(FetchDescriptor<EvidenceSearchIndexEntity>())
        XCTAssertEqual(existingIndex.count, 1)
        existingIndex.forEach(context.delete)
        try context.save()

        let results = try await repository.search(
            criteria: EvidenceSearchCriteria(
                businessId: businessId,
                fileHash: "hash-rebuild"
            )
        )
        let rebuiltIndex = try context.fetch(FetchDescriptor<EvidenceSearchIndexEntity>())

        XCTAssertEqual(results.map(\.id), [evidence.id])
        XCTAssertEqual(rebuiltIndex.count, 1)
    }

    func testJournalSearchUseCaseSearchesEvidenceBackedJournalsAndRebuildsIndex() async throws {
        let businessId = UUID()
        let evidence = makeEvidence(
            businessId: businessId,
            fileHash: "JOURNAL-HASH",
            projectId: UUID(),
            counterpartyName: "検索取引先",
            registrationNumber: "T7777777777777",
            totalAmount: Decimal(string: "8800")!
        )
        try await EvidenceCatalogUseCase(modelContext: context).save(evidence)

        let workflow = PostingWorkflowUseCase(modelContext: context)
        let candidate = PostingCandidate(
            evidenceId: evidence.id,
            businessId: businessId,
            taxYear: 2025,
            candidateDate: Date(timeIntervalSince1970: 1_741_478_400),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: UUID(),
                    creditAccountId: UUID(),
                    amount: Decimal(string: "8800")!,
                    memo: "検索テスト"
                )
            ],
            status: .needsReview,
            source: .ocr,
            memo: "検索テスト"
        )

        try await workflow.saveCandidate(candidate)
        let approved = try await workflow.approveCandidate(candidateId: candidate.id)

        let indexes = try context.fetch(FetchDescriptor<JournalSearchIndexEntity>())
        indexes.forEach(context.delete)
        try context.save()

        let useCase = JournalSearchUseCase(modelContext: context)
        let byCounterparty = try await useCase.search(
            criteria: JournalSearchCriteria(
                businessId: businessId,
                counterpartyText: "検索取引先"
            )
        )
        let byRegistration = try await useCase.search(
            criteria: JournalSearchCriteria(
                businessId: businessId,
                registrationNumber: "T7777777777777"
            )
        )
        let byFileHash = try await useCase.search(
            criteria: JournalSearchCriteria(
                businessId: businessId,
                fileHash: "journal-hash"
            )
        )
        let rebuiltIndexes = try context.fetch(FetchDescriptor<JournalSearchIndexEntity>())

        XCTAssertEqual(byCounterparty, [approved.id])
        XCTAssertEqual(byRegistration, [approved.id])
        XCTAssertEqual(byFileHash, [approved.id])
        XCTAssertEqual(rebuiltIndexes.count, 1)
    }

    func testJournalSearchUseCaseExcludesCancelledEntriesWhenRequested() async throws {
        let businessId = UUID()
        let evidence = makeEvidence(
            businessId: businessId,
            fileHash: "CANCELLED-HASH",
            projectId: UUID(),
            counterpartyName: "取消取引先",
            registrationNumber: "T5555555555555",
            totalAmount: Decimal(string: "5000")!
        )
        try await EvidenceCatalogUseCase(modelContext: context).save(evidence)

        let workflow = PostingWorkflowUseCase(modelContext: context)
        let candidate = PostingCandidate(
            evidenceId: evidence.id,
            businessId: businessId,
            taxYear: 2025,
            candidateDate: Date(timeIntervalSince1970: 1_741_478_400),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: UUID(),
                    creditAccountId: UUID(),
                    amount: Decimal(string: "5000")!,
                    memo: "取消検索"
                )
            ],
            status: .needsReview,
            source: .ocr,
            memo: "取消検索"
        )

        try await workflow.saveCandidate(candidate)
        let approved = try await workflow.approveCandidate(candidateId: candidate.id)
        let reversal = try await workflow.cancelJournal(journalId: approved.id, reason: "取消")

        let useCase = JournalSearchUseCase(modelContext: context)
        let excludingCancelled = try await useCase.search(
            criteria: JournalSearchCriteria(
                businessId: businessId,
                counterpartyText: "取消取引先",
                includeCancelled: false
            )
        )
        let includingCancelled = try await useCase.search(
            criteria: JournalSearchCriteria(
                businessId: businessId,
                counterpartyText: "取消取引先",
                includeCancelled: true
            )
        )

        XCTAssertTrue(excludingCancelled.isEmpty)
        XCTAssertEqual(Set(includingCancelled), Set([approved.id, reversal.id]))
    }

    private func makeEvidence(
        businessId: UUID,
        fileHash: String,
        projectId: UUID,
        counterpartyName: String,
        registrationNumber: String,
        totalAmount: Decimal
    ) -> EvidenceDocument {
        EvidenceDocument(
            businessId: businessId,
            taxYear: 2025,
            sourceType: .camera,
            legalDocumentType: .invoice,
            storageCategory: .electronicTransaction,
            receivedAt: Date(timeIntervalSince1970: 1_741_392_000),
            issueDate: Date(timeIntervalSince1970: 1_741_392_000),
            originalFilename: "\(counterpartyName).pdf",
            mimeType: "application/pdf",
            fileHash: fileHash,
            originalFilePath: "\(fileHash).pdf",
            ocrText: "\(counterpartyName) \(totalAmount)",
            extractionVersion: "ocr-v1",
            searchTokens: [counterpartyName, fileHash],
            structuredFields: EvidenceStructuredFields(
                counterpartyName: counterpartyName,
                registrationNumber: registrationNumber,
                transactionDate: Date(timeIntervalSince1970: 1_741_392_000),
                totalAmount: totalAmount,
                confidence: 0.93
            ),
            linkedProjectIds: [projectId],
            complianceStatus: .pendingReview
        )
    }
}
