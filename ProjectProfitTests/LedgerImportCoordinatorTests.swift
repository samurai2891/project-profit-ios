import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class LedgerImportCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testPreparePreviewStripsBOMAndParsesRows() {
        let coordinator = LedgerImportCoordinator(
            modelContext: context,
            ledgerType: .cashBook,
            metadataJSON: nil
        )
        let rows = coordinator.preparePreview(
            content: "\u{FEFF}月,日,摘要,勘定科目,入金,出金\n1,10,売上入金,売上高,5000,"
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first, ["月", "日", "摘要", "勘定科目", "入金", "出金"])
        XCTAssertEqual(rows.last, ["1", "10", "売上入金", "売上高", "5000", ""])
    }

    func testImportFileCreatesNeedsReviewCandidateForLedgerBookChannel() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let evidenceRepository = SwiftDataEvidenceRepository(modelContext: context)
        let beforePending = try await workflow.pendingCandidates(businessId: businessId)
        let beforeEvidence = try await evidenceRepository.findByBusinessAndYear(
            businessId: businessId,
            taxYear: fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        )

        let coordinator = LedgerImportCoordinator(
            modelContext: context,
            ledgerType: .cashBook,
            metadataJSON: nil
        )
        let csv = """
        月,日,摘要,勘定科目,入金,出金
        1,10,売上入金,売上高,5000,
        """

        let result = try await coordinator.importFile(
            fileData: Data(csv.utf8),
            originalFileName: "ledger-cashbook.csv"
        )

        let pending = try await workflow.pendingCandidates(businessId: businessId)
        let currentTaxYearEvidence = try await evidenceRepository.findByBusinessAndYear(
            businessId: businessId,
            taxYear: fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.evidenceCount, 1)
        XCTAssertEqual(pending.count, beforePending.count + 1)
        XCTAssertEqual(currentTaxYearEvidence.count, beforeEvidence.count + 1)
        XCTAssertTrue(pending.contains(where: { $0.memo == "売上入金" && $0.source == .importFile }))
    }
}
