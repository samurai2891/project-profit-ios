import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DataStoreFixedAssetTests: XCTestCase {
    var container: ModelContainer!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
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
        guard let asset = dataStore.addFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: date(2025, 4, 1),
            acquisitionCost: 300_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        XCTAssertEqual(asset.name, "MacBook Pro")
        XCTAssertEqual(asset.acquisitionCost, 300_000)
        XCTAssertEqual(dataStore.fixedAssets.count, 1)
    }

    func testUpdateFixedAsset() {
        guard let asset = dataStore.addFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: date(2025, 4, 1),
            acquisitionCost: 300_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let updatedResult = dataStore.updateFixedAsset(
            id: asset.id,
            name: "MacBook Pro M4",
            acquisitionCost: 350_000
        )
        XCTAssertTrue(updatedResult)

        let updated = dataStore.getFixedAsset(id: asset.id)
        XCTAssertEqual(updated?.name, "MacBook Pro M4")
        XCTAssertEqual(updated?.acquisitionCost, 350_000)
        XCTAssertEqual(updated?.usefulLifeYears, 4, "更新していないフィールドは保持される")
    }

    func testDeleteFixedAsset_CascadeJournalEntries() {
        guard let asset = dataStore.addFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        // 減価償却仕訳を計上
        dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)
        let sourceKey = PPFixedAsset.depreciationSourceKey(assetId: asset.id, year: 2025)
        XCTAssertTrue(dataStore.journalEntries.contains { $0.sourceKey == sourceKey })

        // 削除 → 仕訳も削除
        let deleted = dataStore.deleteFixedAsset(id: asset.id)
        XCTAssertTrue(deleted)
        XCTAssertTrue(dataStore.fixedAssets.isEmpty)
        XCTAssertFalse(dataStore.journalEntries.contains { $0.sourceKey == sourceKey })
    }

    func testPostDepreciation_CreatesEntry() {
        guard let asset = dataStore.addFixedAsset(
            name: "デスク",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 5
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let entry = dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)

        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.isPosted)

        let lines = dataStore.getJournalLines(for: entry!.id)
        XCTAssertEqual(lines.count, 2)
    }

    func testPostDepreciation_YearLocked() {
        guard let asset = dataStore.addFixedAsset(
            name: "チェア",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 100_000,
            usefulLifeYears: 5
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }
        setupProfileAndLockYear(2025)

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
        guard let asset = dataStore.addFixedAsset(
            name: "PC",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let schedule = dataStore.previewDepreciationSchedule(asset: asset)
        // 定額法 249,999/年 × 4年 = 999,996、残り3を5年目に → 5エントリ
        XCTAssertEqual(schedule.count, 5, "4年+端数1年のスケジュール")
        XCTAssertEqual(schedule.last?.bookValueAfter, 1, "最終残存1円")
    }

    func testAddFixedAsset_BlockedWhenFiscalYearLocked() {
        setupProfileAndLockYear(2025)

        let asset = dataStore.addFixedAsset(
            name: "Locked Asset",
            acquisitionDate: date(2025, 4, 1),
            acquisitionCost: 120_000,
            usefulLifeYears: 4
        )

        XCTAssertNil(asset, "ロック年度では固定資産追加を拒否する")
        XCTAssertTrue(dataStore.fixedAssets.isEmpty)
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    func testUpdateFixedAsset_BlockedWhenFiscalYearLocked() {
        guard let asset = dataStore.addFixedAsset(
            name: "更新対象",
            acquisitionDate: date(2025, 4, 1),
            acquisitionCost: 300_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }
        setupProfileAndLockYear(2025)

        let updatedResult = dataStore.updateFixedAsset(
            id: asset.id,
            name: "更新後",
            acquisitionCost: 500_000
        )
        XCTAssertFalse(updatedResult)

        let updated = dataStore.getFixedAsset(id: asset.id)
        XCTAssertEqual(updated?.name, "更新対象")
        XCTAssertEqual(updated?.acquisitionCost, 300_000)
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    func testDeleteFixedAsset_BlockedWhenFiscalYearLocked() {
        guard let asset = dataStore.addFixedAsset(
            name: "削除対象",
            acquisitionDate: date(2025, 4, 1),
            acquisitionCost: 200_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }
        setupProfileAndLockYear(2025)

        let deleted = dataStore.deleteFixedAsset(id: asset.id)
        XCTAssertFalse(deleted)

        XCTAssertEqual(dataStore.fixedAssets.count, 1, "ロック年度では削除を拒否する")
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
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

    private func setupProfileAndLockYear(_ year: Int) {
        if dataStore.businessProfile == nil {
            // Insert legacy profile so migration auto-creates canonical profiles
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
