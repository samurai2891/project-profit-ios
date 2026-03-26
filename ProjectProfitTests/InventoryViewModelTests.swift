import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class InventoryViewModelTests: XCTestCase {
    private final class CaptureBox {
        var reloadCount = 0
        var capturedError: AppError?
    }

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

    func testSaveCreateFailureOnLockedYearKeepsInput() {
        let capture = CaptureBox()
        let viewModel = makeViewModel(capture: capture)
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
        XCTAssertEqual(capture.reloadCount, 0)
        if case .yearLocked(let year) = capture.capturedError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    func testSaveUpdateFailureOnLockedYearKeepsInput() {
        _ = mutations(dataStore).addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000,
            memo: "保存済み"
        )

        let capture = CaptureBox()
        let viewModel = makeViewModel(capture: capture)
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
        XCTAssertEqual(capture.reloadCount, 0)
        if case .yearLocked(let year) = capture.capturedError {
            XCTAssertEqual(year, 2025)
        } else {
            XCTFail("yearLockedエラーが設定されるべき")
        }
    }

    func testSaveSuccessReloadsFromPersistedData() {
        _ = mutations(dataStore).addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        )

        let capture = CaptureBox()
        let viewModel = makeViewModel(capture: capture)
        viewModel.fiscalYear = 2025
        viewModel.loadForYear()
        XCTAssertNotNil(viewModel.existingRecord)

        // updateInventoryRecordは負値を0に丸める。保存成功時のみ再読込する契約を検証する。
        viewModel.openingInventoryText = "-10"
        viewModel.save()

        XCTAssertEqual(dataStore.getInventoryRecord(fiscalYear: 2025)?.openingInventory, 0)
        XCTAssertEqual(viewModel.openingInventoryText, "", "保存成功時は再読込され、0は空文字表示になる")
        XCTAssertEqual(capture.reloadCount, 1)
        XCTAssertNil(capture.capturedError)
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
        mutations(dataStore).lockFiscalYear(year)
    }

    private func makeViewModel(capture: CaptureBox) -> InventoryViewModel {
        let workflowUseCase = InventoryWorkflowUseCase(
            modelContext: dataStore.modelContext,
            reloadInventoryRecords: {
                capture.reloadCount += 1
                self.dataStore.refreshInventoryRecords()
            },
            setError: {
                capture.capturedError = $0
            }
        )
        return InventoryViewModel(
            modelContext: dataStore.modelContext,
            workflowUseCase: workflowUseCase
        )
    }
}
