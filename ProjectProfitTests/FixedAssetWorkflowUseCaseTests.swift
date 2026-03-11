import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class FixedAssetWorkflowUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: FixedAssetWorkflowUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        dataStore = ProjectProfit.DataStore(modelContext: container.mainContext)
        dataStore.loadData()
        useCase = FixedAssetWorkflowUseCase(
            modelContext: container.mainContext,
            reloadFixedAssets: { self.dataStore.refreshFixedAssets() },
            reloadJournalState: {
                self.dataStore.refreshJournalEntries()
                self.dataStore.refreshJournalLines()
            },
            setError: { self.dataStore.lastError = $0 }
        )
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        container = nil
        super.tearDown()
    }

    func testCreateAssetInsertsRecord() {
        let asset = useCase.createAsset(input: makeInput())

        XCTAssertEqual(asset?.name, "MacBook Pro")
        XCTAssertEqual(dataStore.fixedAssets.count, 1)
    }

    func testSaveAssetUpdatesExistingRecord() {
        let asset = try! XCTUnwrap(useCase.createAsset(input: makeInput()))

        let updated = useCase.saveAsset(
            existingAssetId: asset.id,
            input: makeInput(name: "MacBook Pro M4", acquisitionCost: 350_000)
        )

        XCTAssertTrue(updated)
        XCTAssertEqual(dataStore.getFixedAsset(id: asset.id)?.name, "MacBook Pro M4")
        XCTAssertEqual(dataStore.getFixedAsset(id: asset.id)?.acquisitionCost, 350_000)
    }

    func testDisposeAssetUpdatesStatusAndDisposalDate() {
        let asset = try! XCTUnwrap(useCase.createAsset(input: makeInput()))
        let disposalDate = date(2025, 12, 31)

        let disposed = useCase.disposeAsset(id: asset.id, disposalDate: disposalDate)

        XCTAssertTrue(disposed)
        XCTAssertEqual(dataStore.getFixedAsset(id: asset.id)?.assetStatus, .disposed)
        XCTAssertEqual(dataStore.getFixedAsset(id: asset.id)?.disposalDate, disposalDate)
    }

    func testDeleteAssetCascadesDepreciationEntries() {
        let asset = try! XCTUnwrap(useCase.createAsset(input: makeInput(acquisitionDate: date(2025, 1, 1), acquisitionCost: 1_000_000)))
        _ = useCase.postDepreciation(assetId: asset.id, fiscalYear: 2025)

        let deleted = useCase.deleteAsset(id: asset.id)

        let sourceKey = PPFixedAsset.depreciationSourceKey(assetId: asset.id, year: 2025)
        XCTAssertTrue(deleted)
        XCTAssertNil(dataStore.getFixedAsset(id: asset.id))
        XCTAssertFalse(dataStore.journalEntries.contains { $0.sourceKey == sourceKey })
    }

    func testPostDepreciationCreatesEntry() {
        let asset = try! XCTUnwrap(useCase.createAsset(input: makeInput(acquisitionDate: date(2025, 1, 1), acquisitionCost: 500_000, usefulLifeYears: 5)))

        let entry = useCase.postDepreciation(assetId: asset.id, fiscalYear: 2025)

        XCTAssertNotNil(entry)
        XCTAssertEqual(dataStore.getJournalLines(for: try! XCTUnwrap(entry?.id)).count, 2)
    }

    func testPostAllDepreciationsReturnsPostedCount() {
        _ = useCase.createAsset(input: makeInput(name: "PC", acquisitionDate: date(2025, 1, 1), acquisitionCost: 500_000))
        _ = useCase.createAsset(input: makeInput(name: "Monitor", acquisitionDate: date(2025, 3, 1), acquisitionCost: 200_000, usefulLifeYears: 5))

        let count = useCase.postAllDepreciations(fiscalYear: 2025)

        XCTAssertEqual(count, 2)
    }

    func testCreateAssetBlockedWhenFiscalYearLocked() {
        setupProfileAndLockYear(2025)

        let asset = useCase.createAsset(input: makeInput())

        XCTAssertNil(asset)
        XCTAssertTrue(dataStore.fixedAssets.isEmpty)
    }

    private func makeInput(
        name: String = "MacBook Pro",
        acquisitionDate: Date? = nil,
        acquisitionCost: Int = 300_000,
        usefulLifeYears: Int = 4
    ) -> FixedAssetUpsertInput {
        FixedAssetUpsertInput(
            name: name,
            acquisitionDate: acquisitionDate ?? date(2025, 4, 1),
            acquisitionCost: acquisitionCost,
            usefulLifeYears: usefulLifeYears,
            depreciationMethod: .straightLine,
            salvageValue: 1,
            businessUsePercent: 100,
            memo: nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func setupProfileAndLockYear(_ year: Int) {
        if dataStore.businessProfile == nil {
            let profile = PPAccountingProfile(
                fiscalYear: year,
                bookkeepingMode: .doubleEntry
            )
            dataStore.modelContext.insert(profile)
            dataStore.save()
            dataStore.loadData()
        }
        dataStore.lockFiscalYear(year)
    }
}
