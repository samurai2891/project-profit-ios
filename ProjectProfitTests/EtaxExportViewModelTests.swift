import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class EtaxExportViewModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self,
            PPAccount.self, PPJournalEntry.self, PPJournalLine.self, PPAccountingProfile.self,
            PPUserRule.self, PPFixedAsset.self,
            configurations: config
        )
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testGeneratePreviewUnsupportedYearSetsValidationError() {
        let viewModel = EtaxExportViewModel(dataStore: dataStore)
        viewModel.fiscalYear = 1900

        viewModel.generatePreview()

        XCTAssertNil(viewModel.exportedForm)
        XCTAssertFalse(viewModel.validationErrors.isEmpty)
        XCTAssertTrue(
            viewModel.validationErrors.contains(where: { error in
                error.description.contains("未対応")
            })
        )
    }

    func testExportXtxFailsWhenFiscalYearChangedAfterPreview() {
        let viewModel = EtaxExportViewModel(dataStore: dataStore)
        viewModel.fiscalYear = 2025
        viewModel.generatePreview()
        XCTAssertNotNil(viewModel.exportedForm)

        viewModel.fiscalYear = 2024
        viewModel.exportXtx()

        guard case .failure(let message)? = viewModel.exportResult else {
            return XCTFail("年度変更後はfailureが返るべき")
        }
        XCTAssertTrue(message.contains("再生成"))
    }
}
