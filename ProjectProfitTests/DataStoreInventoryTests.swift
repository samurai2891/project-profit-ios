import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DataStoreInventoryTests: XCTestCase {
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

    // MARK: - CRUD

    func testAddInventoryRecord() {
        let record = dataStore.addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000,
            memo: "在庫"
        )

        XCTAssertNotNil(record)
        XCTAssertEqual(dataStore.inventoryRecords.count, 1)
        XCTAssertEqual(dataStore.inventoryRecords[0].fiscalYear, 2025)
    }

    func testUpdateInventoryRecord() {
        guard let record = dataStore.addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        ) else {
            XCTFail("棚卸追加に失敗")
            return
        }

        let updatedResult = dataStore.updateInventoryRecord(
            id: record.id,
            openingInventory: 120_000,
            closingInventory: 60_000,
            memo: "更新後"
        )
        XCTAssertTrue(updatedResult)

        let updated = dataStore.getInventoryRecord(fiscalYear: 2025)
        XCTAssertEqual(updated?.openingInventory, 120_000)
        XCTAssertEqual(updated?.closingInventory, 60_000)
        XCTAssertEqual(updated?.memo, "更新後")
    }

    func testDeleteInventoryRecord() {
        guard let record = dataStore.addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        ) else {
            XCTFail("棚卸追加に失敗")
            return
        }

        let deleted = dataStore.deleteInventoryRecord(id: record.id)
        XCTAssertTrue(deleted)
        XCTAssertTrue(dataStore.inventoryRecords.isEmpty)
    }

    // MARK: - Year Lock Guard

    func testAddInventoryRecord_BlockedWhenYearLocked() {
        setupProfileAndLockYear(2025)

        let record = dataStore.addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        )

        XCTAssertNil(record)
        XCTAssertTrue(dataStore.inventoryRecords.isEmpty)
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    func testUpdateInventoryRecord_BlockedWhenYearLocked() {
        guard let record = dataStore.addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000,
            memo: "初期"
        ) else {
            XCTFail("棚卸追加に失敗")
            return
        }
        setupProfileAndLockYear(2025)

        let updatedResult = dataStore.updateInventoryRecord(
            id: record.id,
            openingInventory: 300_000,
            memo: "更新後"
        )
        XCTAssertFalse(updatedResult)

        let updated = dataStore.getInventoryRecord(fiscalYear: 2025)
        XCTAssertEqual(updated?.openingInventory, 100_000)
        XCTAssertEqual(updated?.memo, "初期")
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    func testDeleteInventoryRecord_BlockedWhenYearLocked() {
        guard let record = dataStore.addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        ) else {
            XCTFail("棚卸追加に失敗")
            return
        }
        setupProfileAndLockYear(2025)

        let deleted = dataStore.deleteInventoryRecord(id: record.id)
        XCTAssertFalse(deleted)

        XCTAssertEqual(dataStore.inventoryRecords.count, 1)
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    // MARK: - Helpers

    private func setupProfileAndLockYear(_ year: Int) {
        if dataStore.accountingProfile == nil {
            let profile = PPAccountingProfile(
                fiscalYear: year,
                bookkeepingMode: .doubleEntry
            )
            dataStore.modelContext.insert(profile)
            dataStore.save()
            dataStore.accountingProfile = profile
        }
        dataStore.lockFiscalYear(year)
    }
}
