import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class InventoryViewModelTests: XCTestCase {
    var container: ModelContainer!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self,
            PPRecurringTransaction.self, PPAccount.self, PPJournalEntry.self,
            PPJournalLine.self, PPAccountingProfile.self, PPUserRule.self,
            PPFixedAsset.self, PPInventoryRecord.self,
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

    func testSaveCreateFailureOnLockedYearKeepsInput() {
        let viewModel = InventoryViewModel(dataStore: dataStore)
        viewModel.fiscalYear = 2025
        viewModel.loadForYear()
        XCTAssertNil(viewModel.existingRecord)

        viewModel.openingInventoryText = "100000"
        viewModel.purchasesText = "500000"
        viewModel.closingInventoryText = "80000"
        viewModel.memo = "入力中"

        setupProfileAndLockYear(2025)
        viewModel.save()

        XCTAssertEqual(viewModel.openingInventoryText, "100000")
        XCTAssertEqual(viewModel.purchasesText, "500000")
        XCTAssertEqual(viewModel.closingInventoryText, "80000")
        XCTAssertEqual(viewModel.memo, "入力中")
        XCTAssertNil(dataStore.getInventoryRecord(fiscalYear: 2025))
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    func testSaveUpdateFailureOnLockedYearKeepsInput() {
        _ = dataStore.addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000,
            memo: "保存済み"
        )

        let viewModel = InventoryViewModel(dataStore: dataStore)
        viewModel.fiscalYear = 2025
        viewModel.loadForYear()
        XCTAssertNotNil(viewModel.existingRecord)

        viewModel.openingInventoryText = "999999"
        viewModel.memo = "編集中"

        setupProfileAndLockYear(2025)
        viewModel.save()

        XCTAssertEqual(viewModel.openingInventoryText, "999999")
        XCTAssertEqual(viewModel.memo, "編集中")
        let stored = dataStore.getInventoryRecord(fiscalYear: 2025)
        XCTAssertEqual(stored?.openingInventory, 100_000)
        XCTAssertEqual(stored?.memo, "保存済み")
        if case .yearLocked(let year) = dataStore.lastError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    func testSaveSuccessReloadsFromPersistedData() {
        _ = dataStore.addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        )

        let viewModel = InventoryViewModel(dataStore: dataStore)
        viewModel.fiscalYear = 2025
        viewModel.loadForYear()
        XCTAssertNotNil(viewModel.existingRecord)

        // updateInventoryRecordは負値を0に丸める。保存成功時のみ再読込する契約を検証する。
        viewModel.openingInventoryText = "-10"
        viewModel.save()

        XCTAssertEqual(dataStore.getInventoryRecord(fiscalYear: 2025)?.openingInventory, 0)
        XCTAssertEqual(viewModel.openingInventoryText, "", "保存成功時は再読込され、0は空文字表示になる")
    }

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
