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
        container = try! TestModelContainer.create()
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

    func testInitUsesSupportedFiscalYear() {
        let viewModel = makeViewModel()
        let supportedYears = TaxYearDefinitionLoader.supportedYears(formType: .blueReturn)
        XCTAssertTrue(supportedYears.contains(viewModel.fiscalYear))
    }

    func testGeneratePreviewUnsupportedYearSetsValidationError() {
        let viewModel = makeViewModel()
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
        let businessId = try! XCTUnwrap(dataStore.businessProfile?.id)
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )

        let viewModel = makeViewModel()
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
        let viewModel = makeViewModel()
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
        let viewModel = makeViewModel()
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
        let businessId = try! XCTUnwrap(dataStore.businessProfile?.id)
        let viewModel = makeViewModel()
        viewModel.formType = .blueReturn
        viewModel.fiscalYear = 2025

        let key = FiscalYearSettings.userDefaultsKey
        let previousStartMonth = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(4, forKey: key)
        defer { UserDefaults.standard.set(previousStartMonth, forKey: key) }

        seedCanonicalJournal(
            businessId: businessId,
            date: makeDate(year: 2025, month: 3, day: 31),
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 100_000
        )
        seedCanonicalJournal(
            businessId: businessId,
            date: makeDate(year: 2025, month: 4, day: 1),
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 200_000
        )
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )

        viewModel.generatePreview()

        guard let form = viewModel.exportedForm else {
            return XCTFail("プレビューが生成されるべき")
        }
        let revenueField = form.fields.first { $0.id == "revenue_sales_revenue" }
        XCTAssertEqual(revenueField?.value.numberValue, 200_000)
    }

    func testGeneratePreviewUsesCanonicalProfileInsteadOfLegacyProfile() {
        let businessId = try! XCTUnwrap(dataStore.businessProfile?.id)
        seedBusinessProfile(BusinessProfile(
            id: businessId,
            ownerName: "Canonical Owner",
            businessName: "Canonical商店"
        ))
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                filingStyle: .blueGeneral,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )

        let viewModel = makeViewModel()
        viewModel.formType = .blueReturn
        viewModel.fiscalYear = 2025

        viewModel.generatePreview()

        let nameField = viewModel.exportedForm?.fields.first { $0.id == "declarant_name" }
        let businessField = viewModel.exportedForm?.fields.first { $0.id == "declarant_business_name" }
        XCTAssertEqual(nameField?.value.exportText, "Canonical Owner")
        XCTAssertEqual(businessField?.value.exportText, "Canonical商店")
    }

    func testGeneratePreviewBuildsCashBasisFormWhenBlueCashBasisSelected() {
        var capturedStyle: FilingStyle?
        let snapshot = makeSnapshot(fiscalYear: 2025)
        let expectedForm = EtaxForm(
            fiscalYear: 2025,
            formType: .blueCashBasis,
            fields: [
                EtaxField(
                    id: "cash_basis_revenue",
                    fieldLabel: "ア 収入金額",
                    taxLine: nil,
                    value: 300_000,
                    section: .revenue
                ),
                EtaxField(
                    id: "cash_basis_expense_total",
                    fieldLabel: "経費合計",
                    taxLine: nil,
                    value: 80_000,
                    section: .expenses
                ),
            ],
            generatedAt: Date()
        )

        let viewModel = EtaxExportViewModel(
            modelContext: context,
            contextProvider: { _ in
                EtaxExportContext(
                    businessId: nil,
                    fallbackTaxYearProfile: nil
                )
            },
            snapshotProvider: { _ in snapshot },
            formBuilder: { filingStyle, _ in
                capturedStyle = filingStyle
                return expectedForm
            },
            exporter: { _, _ in
                URL(fileURLWithPath: "/tmp/mock-export.xtx")
            }
        )
        viewModel.formType = .blueCashBasis
        viewModel.fiscalYear = 2025

        viewModel.generatePreview()

        XCTAssertEqual(capturedStyle, .blueCashBasis)
        XCTAssertEqual(viewModel.exportedForm?.formType, .blueCashBasis)
        XCTAssertEqual(
            viewModel.exportedForm?.fields.first { $0.id == "cash_basis_revenue" }?.value.numberValue,
            300_000
        )
        XCTAssertEqual(
            viewModel.exportedForm?.fields.first { $0.id == "cash_basis_expense_total" }?.value.numberValue,
            80_000
        )
    }

    func testExportRebuildsPreviewWhenDataRevisionChanges() {
        let businessId = try! XCTUnwrap(dataStore.businessProfile?.id)
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )

        var buildCount = 0
        var exportedRevenue: Int?
        let snapshotProvider = { [unowned self] (fiscalYear: Int) in
            self.makeSnapshot(fiscalYear: fiscalYear)
        }
        let viewModel = EtaxExportViewModel(
            modelContext: context,
            contextProvider: { [unowned self] fiscalYear in
                EtaxExportContextQueryUseCase(modelContext: self.context).context(fiscalYear: fiscalYear)
            },
            snapshotProvider: snapshotProvider,
            formBuilder: { filingStyle, snapshot in
                buildCount += 1
                return try FormEngine.build(
                    filingStyle: filingStyle,
                    input: FormEngine.BuildInput(snapshot: snapshot)
                )
            },
            exporter: { _, form in
                exportedRevenue = form.fields.first { $0.id == "revenue_sales_revenue" }?.value.numberValue
                return URL(fileURLWithPath: "/tmp/mock-export.csv")
            }
        )
        viewModel.formType = .blueReturn
        viewModel.fiscalYear = 2025

        seedCanonicalJournal(
            businessId: businessId,
            date: makeDate(year: 2025, month: 4, day: 1),
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 100_000
        )

        viewModel.generatePreview()
        XCTAssertEqual(buildCount, 1)
        XCTAssertEqual(
            viewModel.exportedForm?.fields.first { $0.id == "revenue_sales_revenue" }?.value.numberValue,
            100_000
        )

        seedCanonicalJournal(
            businessId: businessId,
            date: makeDate(year: 2025, month: 4, day: 2),
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 40_000
        )

        viewModel.exportCsv()

        XCTAssertEqual(buildCount, 2)
        XCTAssertEqual(exportedRevenue, 140_000)
        XCTAssertEqual(
            viewModel.exportedForm?.fields.first { $0.id == "revenue_sales_revenue" }?.value.numberValue,
            140_000
        )
        guard case .success? = viewModel.exportResult else {
            return XCTFail("revision change should rebuild and export latest form")
        }
    }

    func testExportFailsWhenCurrentDataPreflightBecomesInvalidAfterPreview() {
        let businessId = try! XCTUnwrap(dataStore.businessProfile?.id)
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                filingStyle: .blueGeneral,
                vatStatus: .exempt,
                vatMethod: .general,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )

        let viewModel = makeViewModel()
        viewModel.formType = .blueReturn
        viewModel.fiscalYear = 2025

        viewModel.generatePreview()
        XCTAssertNotNil(viewModel.exportedForm)
        XCTAssertTrue(viewModel.validationErrors.isEmpty)

        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                filingStyle: .blueGeneral,
                vatStatus: .taxable,
                vatMethod: .simplified,
                simplifiedBusinessCategory: nil,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v2"
            )
        )

        viewModel.exportXtx()

        guard case .failure(let message)? = viewModel.exportResult else {
            return XCTFail("current preflight failure should block export")
        }
        XCTAssertTrue(message.contains("業種区分"))
    }

    func testWhitePreviewAndExportUseSameFieldSet() {
        let businessId = try! XCTUnwrap(dataStore.businessProfile?.id)
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                filingStyle: .white,
                bookkeepingBasis: .singleEntry,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )
        seedCanonicalJournal(
            businessId: businessId,
            date: makeDate(year: 2025, month: 4, day: 5),
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 88_000
        )

        var exportedFieldIDs: [String] = []
        let viewModel = makeViewModel(
            exporter: { _, form in
                exportedFieldIDs = form.fields.map(\.id)
                return URL(fileURLWithPath: "/tmp/mock-white-parity.csv")
            }
        )
        viewModel.formType = .whiteReturn
        viewModel.fiscalYear = 2025

        viewModel.generatePreview()
        let previewFieldIDs = viewModel.exportedForm?.fields.map(\.id)

        viewModel.exportCsv()

        guard case .success? = viewModel.exportResult else {
            return XCTFail("white export should succeed for field parity")
        }
        XCTAssertEqual(previewFieldIDs, exportedFieldIDs)
    }

    func testExportableFormDropsPreviewOnlyBalanceSheetFieldsBeforeValidation() {
        let rawForm = EtaxForm(
            fiscalYear: 2025,
            formType: .blueReturn,
            fields: [
                EtaxField(
                    id: "revenue_sales_revenue",
                    fieldLabel: "売上（収入）金額",
                    taxLine: .salesRevenue,
                    value: 100_000,
                    section: .revenue
                ),
                EtaxField(
                    id: "bs_asset_acct-cash",
                    fieldLabel: "現金",
                    taxLine: nil,
                    value: 100_000,
                    section: .balanceSheet
                ),
                EtaxField(
                    id: "bs_total_assets",
                    fieldLabel: "資産合計",
                    taxLine: nil,
                    value: 100_000,
                    section: .balanceSheet
                ),
            ],
            generatedAt: Date()
        )

        let exportableForm = EtaxExportViewModel.exportableForm(from: rawForm)
        let errors = EtaxCharacterValidator.validateForm(exportableForm)

        XCTAssertTrue(rawForm.fields.contains(where: { $0.id == "bs_asset_acct-cash" }))
        XCTAssertFalse(exportableForm.fields.contains(where: { $0.id == "bs_asset_acct-cash" }))
        XCTAssertTrue(exportableForm.fields.contains(where: { $0.id == "revenue_sales_revenue" }))
        XCTAssertTrue(exportableForm.fields.contains(where: { $0.id == "bs_total_assets" }))
        XCTAssertFalse(
            errors.contains(where: {
                $0.description.contains("未定義のinternalKeyです")
            })
        )
    }

    func testExportCsvSucceedsWithPreviewOnlyBalanceSheetFieldsPresent() {
        let businessId = try! XCTUnwrap(dataStore.businessProfile?.id)
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )

        let viewModel = makeViewModel()
        viewModel.formType = .blueReturn
        viewModel.fiscalYear = 2025
        viewModel.exportedForm = EtaxForm(
            fiscalYear: 2025,
            formType: .blueReturn,
            fields: [
                EtaxField(
                    id: "revenue_sales_revenue",
                    fieldLabel: "売上（収入）金額",
                    taxLine: .salesRevenue,
                    value: 120_000,
                    section: .revenue
                ),
                EtaxField(
                    id: "bs_asset_acct-cash",
                    fieldLabel: "現金",
                    taxLine: nil,
                    value: 120_000,
                    section: .balanceSheet
                ),
                EtaxField(
                    id: "bs_total_assets",
                    fieldLabel: "資産合計",
                    taxLine: nil,
                    value: 120_000,
                    section: .balanceSheet
                ),
            ],
            generatedAt: Date()
        )

        viewModel.exportCsv()

        guard case .success(let url)? = viewModel.exportResult else {
            return XCTFail("preview-only balance sheet fields should not block CSV export")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testGeneratePreviewBlocksWhenCanonicalTaxProfileHasValidationErrors() {
        let businessId = try! XCTUnwrap(dataStore.businessProfile?.id)
        seedBusinessProfile(BusinessProfile(
            id: businessId,
            ownerName: "Canonical Owner",
            businessName: "Canonical商店"
        ))
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                filingStyle: .blueGeneral,
                vatStatus: .taxable,
                vatMethod: .simplified,
                simplifiedBusinessCategory: nil,
                taxPackVersion: "2025-v1"
            )
        )

        let viewModel = makeViewModel()
        viewModel.formType = .blueReturn
        viewModel.fiscalYear = 2025

        viewModel.generatePreview()

        XCTAssertNil(viewModel.exportedForm)
        XCTAssertTrue(
            viewModel.validationErrors.contains(where: {
                $0.description.contains("業種区分")
            })
        )
    }

    func testExportXtxFailsWhenCanonicalTaxProfilePreflightFails() {
        let businessId = try! XCTUnwrap(dataStore.businessProfile?.id)
        seedBusinessProfile(BusinessProfile(
            id: businessId,
            ownerName: "Canonical Owner",
            businessName: "Canonical商店"
        ))
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                filingStyle: .blueGeneral,
                vatStatus: .taxable,
                vatMethod: .simplified,
                simplifiedBusinessCategory: nil,
                taxPackVersion: "2025-v1"
            )
        )

        let viewModel = makeViewModel()
        viewModel.formType = .blueReturn
        viewModel.fiscalYear = 2025
        viewModel.exportedForm = EtaxForm(
            fiscalYear: 2025,
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
            return XCTFail("preflight failure should return failure")
        }
        XCTAssertTrue(message.contains("業種区分"))
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeViewModel(
        exporter customExporter: (@MainActor (ExportCoordinator.ExportFormat, EtaxForm) throws -> URL)? = nil
    ) -> EtaxExportViewModel {
        let contextQueryUseCase = EtaxExportContextQueryUseCase(modelContext: context)
        let formBuildQueryUseCase = EtaxFormBuildQueryUseCase(modelContext: context)
        return EtaxExportViewModel(
            modelContext: context,
            contextProvider: { fiscalYear in
                contextQueryUseCase.context(fiscalYear: fiscalYear)
            },
            snapshotProvider: { fiscalYear in
                formBuildQueryUseCase.snapshot(fiscalYear: fiscalYear)
            },
            formBuilder: { filingStyle, snapshot in
                try FormEngine.build(
                    filingStyle: filingStyle,
                    input: FormEngine.BuildInput(
                        snapshot: snapshot
                    )
                )
            },
            exporter: customExporter ?? { format, form in
                try ExportCoordinator.export(
                    target: .etax,
                    format: format,
                    fiscalYear: form.fiscalYear,
                    modelContext: self.context,
                    skipPreflightValidation: true,
                    etaxOptions: .init(form: EtaxExportViewModel.exportableForm(from: form))
                )
            }
        )
    }

    private func makeSnapshot(fiscalYear: Int) -> EtaxFormBuildSnapshot {
        EtaxFormBuildQueryUseCase(modelContext: context).snapshot(fiscalYear: fiscalYear)
    }

    private func seedTaxYearProfile(_ profile: TaxYearProfile) {
        let existing = try! context.fetch(FetchDescriptor<TaxYearProfileEntity>())
        existing
            .filter { $0.businessId == profile.businessId && $0.taxYear == profile.taxYear }
            .forEach(context.delete)
        context.insert(TaxYearProfileEntityMapper.toEntity(profile))
        try! context.save()
    }

    private func seedBusinessProfile(_ profile: BusinessProfile) {
        let existing = try! context.fetch(FetchDescriptor<BusinessProfileEntity>())
        existing.forEach(context.delete)
        context.insert(BusinessProfileEntityMapper.toEntity(profile))
        try! context.save()
    }

    private func seedCanonicalJournal(
        businessId: UUID,
        date: Date,
        debitLegacyAccountId: String,
        creditLegacyAccountId: String,
        amount: Int
    ) {
        let journalId = UUID()
        let debitAccountId = try! XCTUnwrap(dataStore.canonicalAccountId(for: debitLegacyAccountId))
        let creditAccountId = try! XCTUnwrap(dataStore.canonicalAccountId(for: creditLegacyAccountId))
        context.insert(CanonicalJournalEntryEntityMapper.toEntity(
            CanonicalJournalEntry(
                id: journalId,
                businessId: businessId,
                taxYear: 2025,
                journalDate: date,
                voucherNo: "1",
                lines: [
                    JournalLine(journalId: journalId, accountId: debitAccountId, debitAmount: Decimal(amount), sortOrder: 0),
                    JournalLine(journalId: journalId, accountId: creditAccountId, creditAmount: Decimal(amount), sortOrder: 1),
                ],
                approvedAt: date
            )
        ))
        try! context.save()
    }
}
