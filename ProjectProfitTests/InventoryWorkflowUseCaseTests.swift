import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class InventoryWorkflowUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: InventoryWorkflowUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = InventoryWorkflowUseCase(
            modelContext: context,
            reloadInventoryRecords: { self.dataStore.refreshInventoryRecords() },
            setError: { self.dataStore.lastError = $0 }
        )
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testCreateInventoryRecordPersistsInput() {
        let record = useCase.createInventoryRecord(
            input: makeInput(
                fiscalYear: 2025,
                openingInventory: 100_000,
                purchases: 500_000,
                closingInventory: 80_000,
                memo: "在庫"
            )
        )

        XCTAssertEqual(record?.fiscalYear, 2025)
        XCTAssertEqual(record?.openingInventory, 100_000)
        XCTAssertEqual(record?.purchases, 500_000)
        XCTAssertEqual(record?.closingInventory, 80_000)
        XCTAssertEqual(record?.memo, "在庫")
        XCTAssertEqual(dataStore.getInventoryRecord(fiscalYear: 2025)?.memo, "在庫")
    }

    func testUpdateInventoryRecordPersistsEditableFields() {
        let record = try! XCTUnwrap(
            useCase.createInventoryRecord(
                input: makeInput(
                    fiscalYear: 2025,
                    openingInventory: 100_000,
                    purchases: 500_000,
                    closingInventory: 80_000
                )
            )
        )

        let saved = useCase.updateInventoryRecord(
            id: record.id,
            input: makeInput(
                fiscalYear: 2025,
                openingInventory: 0,
                purchases: 120_000,
                closingInventory: 60_000,
                memo: "更新後"
            )
        )

        XCTAssertTrue(saved)
        let updated = dataStore.getInventoryRecord(fiscalYear: 2025)
        XCTAssertEqual(updated?.openingInventory, 0)
        XCTAssertEqual(updated?.purchases, 120_000)
        XCTAssertEqual(updated?.closingInventory, 60_000)
        XCTAssertEqual(updated?.memo, "更新後")
    }

    func testCreateInventoryRecordFailsWhenYearLocked() {
        setupProfileAndLockYear(2025)

        let record = useCase.createInventoryRecord(
            input: makeInput(
                fiscalYear: 2025,
                openingInventory: 100_000,
                purchases: 500_000,
                closingInventory: 80_000
            )
        )

        XCTAssertNil(record)
        XCTAssertNil(dataStore.getInventoryRecord(fiscalYear: 2025))
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    func testUpdateInventoryRecordFailsWhenYearLocked() {
        let record = try! XCTUnwrap(
            useCase.createInventoryRecord(
                input: makeInput(
                    fiscalYear: 2025,
                    openingInventory: 100_000,
                    purchases: 500_000,
                    closingInventory: 80_000,
                    memo: "初期"
                )
            )
        )
        setupProfileAndLockYear(2025)

        let saved = useCase.updateInventoryRecord(
            id: record.id,
            input: makeInput(
                fiscalYear: 2025,
                openingInventory: 300_000,
                purchases: 500_000,
                closingInventory: 80_000,
                memo: "更新後"
            )
        )

        XCTAssertFalse(saved)
        let updated = dataStore.getInventoryRecord(fiscalYear: 2025)
        XCTAssertEqual(updated?.openingInventory, 100_000)
        XCTAssertEqual(updated?.memo, "初期")
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    private func makeInput(
        fiscalYear: Int,
        openingInventory: Int = 0,
        purchases: Int = 0,
        closingInventory: Int = 0,
        memo: String? = nil
    ) -> InventoryUpsertInput {
        InventoryUpsertInput(
            fiscalYear: fiscalYear,
            openingInventory: openingInventory,
            purchases: purchases,
            closingInventory: closingInventory,
            memo: memo
        )
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
        mutations(dataStore).lockFiscalYear(year)
    }
}
