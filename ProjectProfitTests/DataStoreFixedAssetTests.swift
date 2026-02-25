import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DataStoreFixedAssetTests: XCTestCase {
    var container: ModelContainer!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self,
            PPRecurringTransaction.self, PPAccount.self, PPJournalEntry.self,
            PPJournalLine.self, PPAccountingProfile.self, PPUserRule.self,
            PPFixedAsset.self,
            configurations: config
        )
        dataStore = ProjectProfit.DataStore(modelContext: container.mainContext)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        container = nil
        super.tearDown()
    }

    // MARK: - CRUD Tests

    func testAddFixedAsset() {
        let asset = dataStore.addFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: date(2025, 4, 1),
            acquisitionCost: 300_000,
            usefulLifeYears: 4
        )

        XCTAssertEqual(asset.name, "MacBook Pro")
        XCTAssertEqual(asset.acquisitionCost, 300_000)
        XCTAssertEqual(dataStore.fixedAssets.count, 1)
    }

    func testUpdateFixedAsset() {
        let asset = dataStore.addFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: date(2025, 4, 1),
            acquisitionCost: 300_000,
            usefulLifeYears: 4
        )

        dataStore.updateFixedAsset(
            id: asset.id,
            name: "MacBook Pro M4",
            acquisitionCost: 350_000
        )

        let updated = dataStore.getFixedAsset(id: asset.id)
        XCTAssertEqual(updated?.name, "MacBook Pro M4")
        XCTAssertEqual(updated?.acquisitionCost, 350_000)
        XCTAssertEqual(updated?.usefulLifeYears, 4, "更新していないフィールドは保持される")
    }

    func testDeleteFixedAsset_CascadeJournalEntries() {
        let asset = dataStore.addFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4
        )

        // 減価償却仕訳を計上
        dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)
        let sourceKey = PPFixedAsset.depreciationSourceKey(assetId: asset.id, year: 2025)
        XCTAssertTrue(dataStore.journalEntries.contains { $0.sourceKey == sourceKey })

        // 削除 → 仕訳も削除
        dataStore.deleteFixedAsset(id: asset.id)
        XCTAssertTrue(dataStore.fixedAssets.isEmpty)
        XCTAssertFalse(dataStore.journalEntries.contains { $0.sourceKey == sourceKey })
    }

    func testPostDepreciation_CreatesEntry() {
        let asset = dataStore.addFixedAsset(
            name: "デスク",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 5
        )

        let entry = dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)

        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.isPosted)

        let lines = dataStore.getJournalLines(for: entry!.id)
        XCTAssertEqual(lines.count, 2)
    }

    func testPostDepreciation_YearLocked() {
        // 年度ロック
        let profile = PPAccountingProfile(
            fiscalYear: 2025,
            bookkeepingMode: .doubleEntry
        )
        dataStore.modelContext.insert(profile)
        dataStore.save()
        dataStore.accountingProfile = profile
        dataStore.lockFiscalYear(2025)

        let asset = dataStore.addFixedAsset(
            name: "チェア",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 100_000,
            usefulLifeYears: 5
        )

        let entry = dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)
        XCTAssertNil(entry, "ロック済み年度では計上不可")
    }

    func testPostAllDepreciations() {
        dataStore.addFixedAsset(
            name: "PC", acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 500_000, usefulLifeYears: 4
        )
        dataStore.addFixedAsset(
            name: "モニター", acquisitionDate: date(2025, 3, 1),
            acquisitionCost: 200_000, usefulLifeYears: 5
        )

        let count = dataStore.postAllDepreciations(fiscalYear: 2025)
        XCTAssertEqual(count, 2)
    }

    func testPreviewSchedule() {
        let asset = dataStore.addFixedAsset(
            name: "PC",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4
        )

        let schedule = dataStore.previewDepreciationSchedule(asset: asset)
        // 定額法 249,999/年 × 4年 = 999,996、残り3を5年目に → 5エントリ
        XCTAssertEqual(schedule.count, 5, "4年+端数1年のスケジュール")
        XCTAssertEqual(schedule.last?.bookValueAfter, 1, "最終残存1円")
    }

    func testSeedMissingDefaultAccounts() {
        // 新規アカウント（減価償却累計額）がシードされることを確認
        let hasAccumulated = dataStore.accounts.contains { $0.id == "acct-accumulated-depreciation" }
        XCTAssertTrue(hasAccumulated, "減価償却累計額アカウントがシードされるべき")
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
