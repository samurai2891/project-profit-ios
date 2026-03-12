import Foundation
import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class CanonicalFlowE2ETests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var tempDirectory: URL!
    private var previousFiscalYearStartMonth: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousFiscalYearStartMonth = UserDefaults.standard.object(forKey: FiscalYearSettings.userDefaultsKey)
        UserDefaults.standard.set(FiscalYearSettings.defaultStartMonth, forKey: FiscalYearSettings.userDefaultsKey)
        container = try TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "CanonicalFlowE2ETests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        ReceiptImageStore.setBaseDirectoryOverride(tempDirectory)
    }

    override func tearDownWithError() throws {
        ReceiptImageStore.setBaseDirectoryOverride(nil)
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        if let previousFiscalYearStartMonth {
            UserDefaults.standard.set(previousFiscalYearStartMonth, forKey: FiscalYearSettings.userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        }
        previousFiscalYearStartMonth = nil
        tempDirectory = nil
        dataStore = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testEvidenceApprovalFlowFeedsCanonicalJournalTrialBalanceAndEtaxPreview() async throws {
        let fiscalYear = 2025
        let taxYearProfile = try await ensureTaxYearProfile(for: fiscalYear)
        let flow = try await makeApprovedReceiptFlow(fiscalYear: fiscalYear, amount: 110_000, counterpartyName: "株式会社承認テスト")

        let projected = dataStore.projectedCanonicalJournals(fiscalYear: fiscalYear)
        XCTAssertFalse(projected.entries.isEmpty)
        XCTAssertTrue(projected.entries.contains(where: { $0.id == flow.journal.id }))

        let trialBalance = AccountingReportService.generateTrialBalance(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines,
            startMonth: FiscalYearSettings.startMonth
        )
        XCTAssertTrue(trialBalance.isBalanced)
        XCTAssertGreaterThan(trialBalance.debitTotal, 0)

        let worksheet = ConsumptionTaxReportService.generateWorksheet(
            fiscalYear: fiscalYear,
            taxYearProfile: taxYearProfile,
            journalEntries: try await PostingWorkflowUseCase(modelContext: context).journals(
                businessId: flow.businessId,
                taxYear: fiscalYear
            ),
            accounts: try await ChartOfAccountsUseCase(modelContext: context).accounts(businessId: flow.businessId),
            counterparties: try await CounterpartyMasterUseCase(modelContext: context).loadCounterparties(businessId: flow.businessId),
            pack: try? await BundledTaxYearPackProvider(bundle: .main).pack(for: fiscalYear),
            startMonth: FiscalYearSettings.startMonth
        )
        XCTAssertEqual(worksheet.lines.count, 1)
        XCTAssertEqual(worksheet.rawInputTaxTotal, 10_000)

        XCTAssertTrue(mutations(dataStore).transitionFiscalYearState(.softClose, for: fiscalYear))
        XCTAssertTrue(mutations(dataStore).transitionFiscalYearState(.taxClose, for: fiscalYear))

        let taxIssues = try TaxYearStateUseCase(modelContext: context).filingPreflightIssues(
            businessId: flow.businessId,
            taxYear: fiscalYear
        )
        XCTAssertTrue(taxIssues.filter { $0.severity == .error }.isEmpty)

        let exportPreflight = try FilingPreflightUseCase(modelContext: context).preflightReport(
            businessId: flow.businessId,
            taxYear: fiscalYear,
            context: .export
        )
        XCTAssertFalse(exportPreflight.isBlocking)

        let viewModel = makeEtaxExportViewModel()
        viewModel.fiscalYear = fiscalYear
        viewModel.generatePreview()

        XCTAssertNotNil(viewModel.exportedForm)
        XCTAssertTrue(viewModel.validationErrors.isEmpty)

        viewModel.exportCsv()
        guard case .success(let url)? = viewModel.exportResult else {
            return XCTFail("e-Tax CSV export should succeed after preflight passes")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    private func makeEtaxExportViewModel() -> EtaxExportViewModel {
        let contextQueryUseCase = EtaxExportContextQueryUseCase(modelContext: context)
        return EtaxExportViewModel(
            modelContext: context,
            contextProvider: { fiscalYear in
                EtaxExportContext(
                    businessId: self.dataStore.businessProfile?.id,
                    fallbackTaxYearProfile: self.dataStore.currentTaxYearProfile?.taxYear == fiscalYear
                        ? self.dataStore.currentTaxYearProfile
                        : contextQueryUseCase.context(fiscalYear: fiscalYear).fallbackTaxYearProfile
                )
            },
            formBuilder: { filingStyle, fiscalYear in
                try FormEngine.build(
                    filingStyle: filingStyle,
                    dataStore: self.dataStore,
                    fiscalYear: fiscalYear
                )
            },
            exporter: { format, form in
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

    func testBackupRestoreRoundTripRestoresSearchableCanonicalArtifacts() async throws {
        let flow = try await makeApprovedReceiptFlow(fiscalYear: 2025, amount: 55_000, counterpartyName: "株式会社バックアップ")
        let evidenceUseCase = EvidenceCatalogUseCase(modelContext: context)
        let journalSearchUseCase = JournalSearchUseCase(modelContext: context)

        let evidenceBefore = try await evidenceUseCase.search(
            EvidenceSearchCriteria(
                businessId: flow.businessId,
                fileHash: flow.fileHash
            )
        )
        let journalsBefore = try await journalSearchUseCase.search(
            criteria: JournalSearchCriteria(
                businessId: flow.businessId,
                fileHash: flow.fileHash
            )
        )
        XCTAssertEqual(evidenceBefore.map(\.id), [flow.evidence.id])
        XCTAssertEqual(journalsBefore, [flow.journal.id])

        let backup = try BackupService(modelContext: context).export(scope: .full)
        let restoreService = RestoreService(modelContext: context)
        let dryRun = try restoreService.dryRun(snapshotURL: backup.archiveURL)
        XCTAssertTrue(dryRun.canApply)

        let noiseFlow = try await makeApprovedReceiptFlow(fiscalYear: 2025, amount: 66_000, counterpartyName: "株式会社ノイズ")
        let evidenceWithNoise = try await evidenceUseCase.search(EvidenceSearchCriteria(businessId: flow.businessId))
        XCTAssertEqual(evidenceWithNoise.count, 2)

        let applyResult = try restoreService.apply(snapshotURL: backup.archiveURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: applyResult.rollbackArchiveURL.path))

        let evidenceAfter = try await evidenceUseCase.search(
            EvidenceSearchCriteria(
                businessId: flow.businessId,
                fileHash: flow.fileHash
            )
        )
        let journalsAfter = try await journalSearchUseCase.search(
            criteria: JournalSearchCriteria(
                businessId: flow.businessId,
                fileHash: flow.fileHash
            )
        )
        let noiseEvidenceAfter = try await evidenceUseCase.search(
            EvidenceSearchCriteria(
                businessId: flow.businessId,
                fileHash: noiseFlow.fileHash
            )
        )
        let noiseJournalsAfter = try await journalSearchUseCase.search(
            criteria: JournalSearchCriteria(
                businessId: flow.businessId,
                fileHash: noiseFlow.fileHash
            )
        )

        XCTAssertEqual(evidenceAfter.map(\.id), [flow.evidence.id])
        XCTAssertEqual(journalsAfter, [flow.journal.id])
        XCTAssertTrue(noiseEvidenceAfter.isEmpty)
        XCTAssertTrue(noiseJournalsAfter.isEmpty)
        XCTAssertTrue(ReceiptImageStore.documentFileExists(fileName: flow.evidence.originalFilePath))
    }

    func testMigrationRehearsalOnGoldenFixtureHasNoOrphans() async throws {
        let scenario = try await GoldenFixtureLoader.makeScenario(testCase: self)
        let report = try MigrationReportRunner(modelContext: scenario.context).dryRun()

        XCTAssertTrue(report.orphanRecords.isEmpty)
        XCTAssertTrue(report.warnings.isEmpty)
        XCTAssertTrue(report.deltas.contains(where: { $0.modelName == "Profile" && $0.executeSupported }))
    }

    private func makeApprovedReceiptFlow(
        fiscalYear: Int,
        amount: Int,
        counterpartyName: String
    ) async throws -> ApprovedReceiptFlow {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let request = ReceiptEvidenceIntakeRequest(
            receiptData: ReceiptData(
                totalAmount: amount,
                taxAmount: amount / 11,
                subtotalAmount: amount - (amount / 11),
                date: "\(fiscalYear)-04-10",
                storeName: counterpartyName,
                registrationNumber: nil,
                estimatedCategory: "tools",
                itemSummary: "監査証憑"
            ),
            ocrText: "\(counterpartyName)\n合計 \(amount)円",
            sourceType: .camera,
            fileData: Data("receipt-\(counterpartyName)".utf8),
            originalFileName: "\(counterpartyName).jpg",
            mimeType: "image/jpeg",
            reviewedAmount: amount,
            reviewedDate: makeDate(year: fiscalYear, month: 4, day: 10),
            transactionType: .expense,
            categoryId: "cat-tools",
            memo: "[レシート] \(counterpartyName)",
            lineItems: [LineItem(name: "監査証憑", quantity: 1, unitPrice: amount)],
            linkedProjectIds: [],
            paymentAccountId: AccountingConstants.cashAccountId,
            transferToAccountId: nil,
            taxDeductibleRate: 100,
            taxCodeId: TaxCode.standard10.rawValue,
            isTaxIncluded: false,
            taxAmount: amount / 11,
            registrationNumber: nil,
            counterpartyId: nil,
            counterpartyName: counterpartyName
        )

        let intakeResult = try await ReceiptEvidenceIntakeUseCase(modelContext: context).intake(request)
        let journal = try await PostingWorkflowUseCase(modelContext: context).approveCandidate(
            candidateId: intakeResult.candidate.id,
            description: "承認済み証憑"
        )
        dataStore.loadData()

        return ApprovedReceiptFlow(
            businessId: businessId,
            evidence: intakeResult.evidence,
            journal: journal,
            fileHash: intakeResult.evidence.fileHash
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date!
    }

    private func ensureTaxYearProfile(for fiscalYear: Int) async throws -> TaxYearProfile {
        let useCase = ProfileSettingsUseCase(modelContext: context)
        let state = try await useCase.load(
            defaultTaxYear: fiscalYear,
            sensitivePayload: dataStore.profileSensitivePayload
        )
        dataStore.loadData()
        return state.taxYearProfile
    }
}

private struct ApprovedReceiptFlow {
    let businessId: UUID
    let evidence: EvidenceDocument
    let journal: CanonicalJournalEntry
    let fileHash: String
}
