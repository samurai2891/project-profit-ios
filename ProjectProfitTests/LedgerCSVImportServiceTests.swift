import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class LedgerCSVImportServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var service: LedgerCSVImportService!
    private var snapshot: TransactionFormSnapshot!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        service = LedgerCSVImportService(modelContext: context)
        snapshot = try! TransactionFormQueryUseCase(modelContext: context).snapshot()
    }

    override func tearDown() {
        snapshot = nil
        service = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testPrepareImportDetectsHeaderAfterMetadataRows() async throws {
        let businessId = try XCTUnwrap(snapshot.businessId)
        let chart = SwiftDataChartOfAccountsRepository(modelContext: context)
        let cash = try await chart.findByLegacyId(
            businessId: businessId,
            legacyAccountId: AccountingConstants.cashAccountId
        )
        let sales = try await chart.findByLegacyId(
            businessId: businessId,
            legacyAccountId: AccountingConstants.salesAccountId
        )

        let csv = """
        帳簿名,現金出納帳
        事業年度,2026
        月,日,摘要,勘定科目,入金,出金
        1,10,売上入金,売上高,5000,
        """

        let result = try await service.prepareImport(
            content: csv,
            ledgerType: .cashBook,
            metadataJSON: nil,
            snapshot: snapshot
        )

        XCTAssertTrue(result.lineErrors.isEmpty)
        XCTAssertEqual(result.candidateDrafts.count, 1)
        XCTAssertEqual(result.fixedAssetDrafts.count, 0)
        XCTAssertEqual(result.candidateDrafts.first?.sourceLine, 4)
        XCTAssertEqual(result.candidateDrafts.first?.proposedLines.first?.debitAccountId, cash?.id)
        XCTAssertEqual(result.candidateDrafts.first?.proposedLines.first?.creditAccountId, sales?.id)
    }

    func testPrepareImportExplodesWhiteTaxRowIntoMultipleCandidates() async throws {
        let csv = """
        月,日,摘要,売上金額,雑収入等,旅費交通費
        2,5,白色帳簿,1000,300,200
        """
        let metadata = LedgerBridge.encodeWhiteTaxBookkeepingMetadata(
            WhiteTaxBookkeepingMetadata(fiscalYear: 2026)
        )

        let result = try await service.prepareImport(
            content: csv,
            ledgerType: .whiteTaxBookkeeping,
            metadataJSON: metadata,
            snapshot: snapshot
        )

        XCTAssertTrue(result.lineErrors.isEmpty)
        XCTAssertEqual(result.candidateDrafts.count, 3)
        XCTAssertEqual(result.fixedAssetDrafts.count, 0)
        XCTAssertEqual(result.suggestedTaxYear, 2026)
    }

    func testPrepareImportMapsTransportationExpenseToTravelAndSuspense() async throws {
        let businessId = try XCTUnwrap(snapshot.businessId)
        let chart = SwiftDataChartOfAccountsRepository(modelContext: context)
        let travel = try await chart.findByLegacyId(
            businessId: businessId,
            legacyAccountId: "acct-travel"
        )
        let suspense = try await chart.findByLegacyId(
            businessId: businessId,
            legacyAccountId: AccountingConstants.suspenseAccountId
        )
        let metadata = LedgerBridge.encodeTransportationExpenseMetadata(
            TransportationExpenseMetadata(year: 2026)
        )
        let csv = """
        日付,行先,目的（用件）,交通機関（手段）,区間（起点）,区間（終点）,片/往,金額
        2026-03-01,都内,打ち合わせ,電車,新宿,渋谷,往復,880
        """

        let result = try await service.prepareImport(
            content: csv,
            ledgerType: .transportationExpense,
            metadataJSON: metadata,
            snapshot: snapshot
        )

        let line = try XCTUnwrap(result.candidateDrafts.first?.proposedLines.first)
        XCTAssertTrue(result.lineErrors.isEmpty)
        XCTAssertEqual(result.candidateDrafts.count, 1)
        XCTAssertEqual(line.debitAccountId, travel?.id)
        XCTAssertEqual(line.creditAccountId, suspense?.id)
    }

    func testPrepareImportCreatesFixedAssetDraftFromDepreciationLedger() async throws {
        let csv = """
        勘定科目,資産コード,資産名,資産の種類,状態,取得日,取得価額,償却方法,耐用年数,償却率,償却月数,期首帳簿価額,事業専用割合,摘要
        建物,FA-1,MacBook Pro,工具器具備品,使用中,2026-01-15,240000,定額法,4,0.25,12,240000,100,導入
        """

        let result = try await service.prepareImport(
            content: csv,
            ledgerType: .fixedAssetDepreciation,
            metadataJSON: nil,
            snapshot: snapshot
        )

        let draft = try XCTUnwrap(result.fixedAssetDrafts.first)
        XCTAssertTrue(result.lineErrors.isEmpty)
        XCTAssertTrue(result.candidateDrafts.isEmpty)
        XCTAssertEqual(result.fixedAssetDrafts.count, 1)
        XCTAssertEqual(draft.input.name, "MacBook Pro")
        XCTAssertEqual(draft.input.acquisitionCost, 240000)
        XCTAssertEqual(draft.input.usefulLifeYears, 4)
        XCTAssertEqual(draft.input.depreciationMethod, .straightLine)
    }
}
