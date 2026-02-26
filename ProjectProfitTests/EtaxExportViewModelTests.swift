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

    func testExportXtxUnsupportedYearReturnsFailure() {
        let viewModel = EtaxExportViewModel(dataStore: dataStore)
        viewModel.fiscalYear = 1900
        viewModel.exportedForm = EtaxForm(
            fiscalYear: 1900,
            formType: .blueReturn,
            fields: [
                EtaxField(
                    id: "revenue_sales_revenue",
                    fieldLabel: "売上（収入）金額",
                    taxLine: .salesRevenue,
                    value: 1000,
                    section: .revenue
                )
            ],
            generatedAt: Date()
        )

        viewModel.exportXtx()

        guard case .failure(let message)? = viewModel.exportResult else {
            return XCTFail("未対応年分のXTX出力はfailureが返るべき")
        }
        XCTAssertTrue(message.contains("未対応"))
    }

    func testExportCsvUnsupportedYearReturnsFailure() {
        let viewModel = EtaxExportViewModel(dataStore: dataStore)
        viewModel.fiscalYear = 1900
        viewModel.exportedForm = EtaxForm(
            fiscalYear: 1900,
            formType: .blueReturn,
            fields: [
                EtaxField(
                    id: "revenue_sales_revenue",
                    fieldLabel: "売上（収入）金額",
                    taxLine: .salesRevenue,
                    value: 1000,
                    section: .revenue
                )
            ],
            generatedAt: Date()
        )

        viewModel.exportCsv()

        guard case .failure(let message)? = viewModel.exportResult else {
            return XCTFail("未対応年分のCSV出力はfailureが返るべき")
        }
        XCTAssertTrue(message.contains("未対応"))
    }

    func testGeneratePreviewRespectsFiscalStartMonthBoundary() {
        let viewModel = EtaxExportViewModel(dataStore: dataStore)
        viewModel.formType = .blueReturn
        viewModel.fiscalYear = 2025

        let key = FiscalYearSettings.userDefaultsKey
        let previousStartMonth = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(4, forKey: key)
        defer { UserDefaults.standard.set(previousStartMonth, forKey: key) }

        let entryBefore = PPJournalEntry(
            sourceKey: "manual:before",
            date: makeDate(year: 2025, month: 3, day: 31),
            entryType: .manual,
            memo: "before",
            isPosted: true
        )
        let entryInRange = PPJournalEntry(
            sourceKey: "manual:in-range",
            date: makeDate(year: 2025, month: 4, day: 1),
            entryType: .manual,
            memo: "in-range",
            isPosted: true
        )

        dataStore.journalEntries = [entryBefore, entryInRange]
        dataStore.journalLines = [
            PPJournalLine(entryId: entryBefore.id, accountId: AccountingConstants.salesAccountId, debit: 0, credit: 100_000),
            PPJournalLine(entryId: entryInRange.id, accountId: AccountingConstants.salesAccountId, debit: 0, credit: 200_000),
        ]

        viewModel.generatePreview()

        guard let form = viewModel.exportedForm else {
            return XCTFail("プレビューが生成されるべき")
        }
        let revenueField = form.fields.first { $0.id == "revenue_sales_revenue" }
        XCTAssertEqual(revenueField?.value.numberValue, 200_000)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
