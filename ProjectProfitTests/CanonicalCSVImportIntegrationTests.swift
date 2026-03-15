import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class CanonicalCSVImportIntegrationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: PostingIntakeUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = PostingIntakeUseCase(modelContext: context)
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testLedgerCashBookImportWritesCanonicalEvidenceAndNeedsReviewCandidate() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let evidenceRepository = SwiftDataEvidenceRepository(modelContext: context)
        let taxYear = fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        let beforeCandidates = try await workflow.pendingCandidates(businessId: businessId)
        let beforeEvidence = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: taxYear)
        let csv = """
        帳簿名,現金出納帳
        事業年度,2026
        月,日,摘要,勘定科目,入金,出金
        1,10,売上入金,売上高,5000,
        """

        let result = await useCase.importTransactions(
            request: CSVImportRequest(
                csvString: csv,
                originalFileName: "canonical-ledger-cash.csv",
                fileData: Data(csv.utf8),
                mimeType: "text/csv",
                channel: .ledgerBook(ledgerType: .cashBook, metadataJSON: nil)
            )
        )

        let pending = try await workflow.pendingCandidates(businessId: businessId)
        let evidence = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: taxYear)

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.evidenceCount, 1)
        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.assetCount, 0)
        XCTAssertEqual(pending.count, beforeCandidates.count + 1)
        XCTAssertEqual(evidence.count, beforeEvidence.count + 1)
        XCTAssertTrue(pending.contains { $0.memo == "売上入金" && $0.status == .needsReview && $0.source == .importFile })
    }

    func testLedgerFixedAssetImportWritesCanonicalEvidenceAndAsset() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let evidenceRepository = SwiftDataEvidenceRepository(modelContext: context)
        let beforeEvidence = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: 2026)
        let beforeAssets = try context.fetch(FetchDescriptor<PPFixedAsset>())
        let csv = """
        勘定科目,資産コード,資産名,資産の種類,状態,取得日,取得価額,償却方法,耐用年数,償却率,償却月数,期首帳簿価額,事業専用割合,摘要
        建物,FA-1,MacBook Pro,工具器具備品,使用中,2026-01-15,240000,定額法,4,0.25,12,240000,100,導入
        """

        let result = await useCase.importTransactions(
            request: CSVImportRequest(
                csvString: csv,
                originalFileName: "canonical-ledger-fixed-asset.csv",
                fileData: Data(csv.utf8),
                mimeType: "text/csv",
                channel: .ledgerBook(ledgerType: .fixedAssetDepreciation, metadataJSON: nil)
            )
        )

        let evidence = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: 2026)
        let assets = try context.fetch(FetchDescriptor<PPFixedAsset>())

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.evidenceCount, 1)
        XCTAssertEqual(result.candidateCount, 0)
        XCTAssertEqual(result.assetCount, 1)
        XCTAssertEqual(evidence.count, beforeEvidence.count + 1)
        XCTAssertEqual(assets.count, beforeAssets.count + 1)
        XCTAssertTrue(assets.contains { $0.name == "MacBook Pro" && $0.acquisitionCost == 240000 })
    }
}
