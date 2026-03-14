import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class PostingIntakeUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: PostingIntakeUseCase!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = PostingIntakeUseCase(modelContext: context)
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    private func makeCSVRequest(
        _ csv: String,
        fileName: String = "import.csv"
    ) -> CSVImportRequest {
        CSVImportRequest(
            csvString: csv,
            originalFileName: fileName,
            fileData: Data(csv.utf8),
            mimeType: "text/csv",
            channel: .settingsTransactionCSV
        )
    }

    private func makeLedgerCSVRequest(
        _ csv: String,
        ledgerType: LedgerType = .cashBook,
        metadataJSON: String? = nil,
        fileName: String = "ledger-import.csv"
    ) -> CSVImportRequest {
        CSVImportRequest(
            csvString: csv,
            originalFileName: fileName,
            fileData: Data(csv.utf8),
            mimeType: "text/csv",
            channel: .ledgerBook(ledgerType: ledgerType, metadataJSON: metadataJSON)
        )
    }

    func testSaveManualCandidateCreatesDraftWithoutLegacyTransaction() async throws {
        FeatureFlags.useCanonicalPosting = true
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let beforeTransactions = dataStore.transactions.count
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let fiscalYear = fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        let beforeJournals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)

        let candidate = try await useCase.saveManualCandidate(
            input: ManualPostingCandidateInput(
                type: .expense,
                amount: 12_000,
                date: Date(),
                categoryId: "cat-tools",
                memo: "manual candidate",
                allocations: [(projectId: project.id, ratio: 100)],
                paymentAccountId: "acct-cash",
                transferToAccountId: nil,
                taxDeductibleRate: 100,
                taxAmount: 1_200,
                taxCodeId: TaxCode.standard10.rawValue,
                isTaxIncluded: false,
                counterpartyId: nil,
                counterparty: nil,
                isWithholdingEnabled: false,
                withholdingTaxCodeId: nil,
                withholdingTaxAmount: nil,
                candidateSource: .manual
            )
        )

        let pendingCandidates = try await workflow.pendingCandidates(businessId: businessId)
        let journals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)

        XCTAssertEqual(candidate.status, .draft)
        XCTAssertEqual(candidate.source, .manual)
        XCTAssertEqual(candidate.legacySnapshot?.categoryId, "cat-tools")
        XCTAssertEqual(candidate.legacySnapshot?.taxCodeId, TaxCode.standard10.rawValue)
        XCTAssertEqual(candidate.legacySnapshot?.taxRate, 10)
        XCTAssertEqual(candidate.legacySnapshot?.taxCategory, .standardRate)
        XCTAssertEqual(dataStore.transactions.count, beforeTransactions)
        XCTAssertEqual(journals.count, beforeJournals.count)
        XCTAssertTrue(pendingCandidates.contains(where: { $0.id == candidate.id }))
    }

    func testSaveManualCandidateFailsForYearLockedDate() async {
        FeatureFlags.useCanonicalPosting = true
        let lockedYear = Calendar.current.component(.year, from: Date())
        mutations(dataStore).lockFiscalYear(lockedYear)
        let project = mutations(dataStore).addProject(name: "Locked PJ", description: "")

        do {
            _ = try await useCase.saveManualCandidate(
                input: ManualPostingCandidateInput(
                    type: .expense,
                    amount: 5_000,
                    date: Date(),
                    categoryId: "cat-tools",
                    memo: "locked candidate",
                    allocations: [(projectId: project.id, ratio: 100)],
                    paymentAccountId: "acct-cash",
                    transferToAccountId: nil,
                    taxDeductibleRate: nil,
                    taxAmount: nil,
                    taxCodeId: nil,
                    isTaxIncluded: nil,
                    counterpartyId: nil,
                    counterparty: nil,
                    isWithholdingEnabled: false,
                    withholdingTaxCodeId: nil,
                    withholdingTaxAmount: nil,
                    candidateSource: .manual
                )
            )
            XCTFail("year locked save should fail")
        } catch let error as AppError {
            guard case let .yearLocked(year) = error else {
                return XCTFail("expected yearLocked error, got \(error)")
            }
            XCTAssertEqual(year, lockedYear)
        } catch {
            XCTFail("unexpected error: \(error.localizedDescription)")
        }
    }

    func testSaveManualCandidateBuildsThreeLinesWhenWithholdingEnabled() async throws {
        FeatureFlags.useCanonicalPosting = true
        let project = mutations(dataStore).addProject(name: "Withholding PJ", description: "")

        let candidate = try await useCase.saveManualCandidate(
            input: ManualPostingCandidateInput(
                type: .expense,
                amount: 100_000,
                date: Date(),
                categoryId: "cat-tools",
                memo: "withholding candidate",
                allocations: [(projectId: project.id, ratio: 100)],
                paymentAccountId: AccountingConstants.cashAccountId,
                transferToAccountId: nil,
                taxDeductibleRate: nil,
                taxAmount: nil,
                taxCodeId: nil,
                isTaxIncluded: nil,
                counterpartyId: nil,
                counterparty: "税理士法人テスト",
                isWithholdingEnabled: true,
                withholdingTaxCodeId: WithholdingTaxCode.professionalFee.rawValue,
                withholdingTaxAmount: nil,
                candidateSource: .manual
            )
        )

        let debitTotal = candidate.proposedLines
            .filter { $0.debitAccountId != nil }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let creditTotal = candidate.proposedLines
            .filter { $0.creditAccountId != nil }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let annotatedLine = try XCTUnwrap(candidate.proposedLines.first { $0.withholdingTaxAmount != nil })
        let expectedWithholding = WithholdingTaxCalculator.calculate(
            grossAmount: Decimal(100_000),
            code: .professionalFee
        ).withholdingAmount

        XCTAssertEqual(candidate.proposedLines.count, 3)
        XCTAssertEqual(debitTotal, creditTotal)
        XCTAssertEqual(annotatedLine.withholdingTaxCodeId, WithholdingTaxCode.professionalFee.rawValue)
        XCTAssertEqual(annotatedLine.withholdingTaxAmount, expectedWithholding)
        XCTAssertEqual(annotatedLine.withholdingTaxBaseAmount, Decimal(100_000))
        XCTAssertTrue(candidate.proposedLines.contains {
            $0.creditAccountId != nil && $0.amount == expectedWithholding
        })
    }

    func testImportTransactionsCreatesNeedsReviewCandidateAndEvidenceWithoutLegacyMirrorTransaction() async throws {
        FeatureFlags.useCanonicalPosting = true
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let beforeTransactions = dataStore.transactions.count
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let beforeJournals = try await workflow.journals(businessId: businessId, taxYear: 2026)
        let beforePending = try await workflow.pendingCandidates(businessId: businessId)
        let evidenceRepository = SwiftDataEvidenceRepository(modelContext: context)
        let beforeEvidence = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: 2026)
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ,支払口座,税率,税込区分,税区分
        2026-01-10,経費,5500,ツール,ImportProject(100%),CSV取り込み,acct-cash,10,税込,課税（10%）
        """

        let result = await useCase.importTransactions(request: makeCSVRequest(csv))
        dataStore.refreshProjects()
        dataStore.refreshTransactions()
        let journals = try await workflow.journals(businessId: businessId, taxYear: 2026)
        let pending = try await workflow.pendingCandidates(businessId: businessId)
        let evidence = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: 2026)
        let project = try XCTUnwrap(dataStore.projects.first { $0.name == "ImportProject" })
        let imported = try XCTUnwrap(pending.first { $0.memo == "CSV取り込み" })

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.evidenceCount, 1)
        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.assetCount, 0)
        XCTAssertEqual(dataStore.transactions.count, beforeTransactions)
        XCTAssertEqual(journals.count, beforeJournals.count)
        XCTAssertEqual(pending.count, beforePending.count + 1)
        XCTAssertEqual(evidence.count, beforeEvidence.count + 1)
        XCTAssertEqual(imported.status, .needsReview)
        XCTAssertEqual(imported.source, .importFile)
        XCTAssertNotNil(imported.evidenceId)
        XCTAssertTrue(imported.proposedLines.contains(where: { $0.projectAllocationId == project.id }))
    }

    func testImportTransactionsReportsInvalidAllocationRatio() async {
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ
        2026-01-10,経費,5500,ツール,ImportProjectA(60%);ImportProjectB(30%),CSV取り込み
        """

        let result = await useCase.importTransactions(request: makeCSVRequest(csv))

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertEqual(result.errors.first, "行2: 配分比率が不正です（合計: 90%）")
        XCTAssertEqual(result.evidenceCount, 1)
    }

    func testImportTransactionsUsesCounterpartyPayeeInfoForWithholdingCandidate() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "CSV税理士",
            payeeInfo: PayeeInfo(isWithholdingSubject: true, withholdingCategory: .professionalFee)
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)

        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ,支払口座,取引先
        2026-01-10,経費,100000,ツール,ImportProject(100%),CSV源泉,acct-cash,CSV税理士
        """

        let result = await useCase.importTransactions(request: makeCSVRequest(csv, fileName: "withholding-import.csv"))
        let pending = try await PostingWorkflowUseCase(modelContext: context).pendingCandidates(businessId: businessId)
        let imported = try XCTUnwrap(pending.first { $0.memo == "CSV源泉" })
        let annotatedLine = try XCTUnwrap(imported.proposedLines.first { $0.withholdingTaxAmount != nil })

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(annotatedLine.withholdingTaxCodeId, WithholdingTaxCode.professionalFee.rawValue)
        XCTAssertEqual(
            annotatedLine.withholdingTaxAmount,
            WithholdingTaxCalculator.calculate(
                grossAmount: Decimal(100_000),
                code: .professionalFee
            ).withholdingAmount
        )
    }

    func testImportTransactionsReportsUnknownCategory() async {
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ
        2026-01-10,経費,5500,存在しないカテゴリ,ImportProject(100%),CSV取り込み
        """

        let result = await useCase.importTransactions(request: makeCSVRequest(csv))

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertEqual(result.errors.first, "行2: カテゴリが見つかりません: 存在しないカテゴリ")
        XCTAssertEqual(result.lineErrors.first?.line, 2)
    }

    func testImportTransactionsRejectsDuplicateFileHash() async {
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ
        2026-01-10,経費,5500,ツール,ImportProject(100%),CSV取り込み
        """

        _ = await useCase.importTransactions(request: makeCSVRequest(csv, fileName: "duplicate.csv"))
        let result = await useCase.importTransactions(request: makeCSVRequest(csv, fileName: "duplicate.csv"))

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertTrue(result.errors.first?.contains("同一の CSV ファイル") == true)
    }

    func testImportTransactionsCreatesNeedsReviewCandidateForLedgerBookChannel() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let evidenceRepository = SwiftDataEvidenceRepository(modelContext: context)
        let taxYear = fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        let beforePending = try await workflow.pendingCandidates(businessId: businessId)
        let beforeEvidence = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: taxYear)
        let csv = """
        月,日,摘要,勘定科目,入金,出金
        1,10,売上入金,売上高,5000,
        """

        let result = await useCase.importTransactions(
            request: makeLedgerCSVRequest(csv)
        )

        let pending = try await workflow.pendingCandidates(businessId: businessId)
        let evidence = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: taxYear)

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(result.evidenceCount, 1)
        XCTAssertEqual(pending.count, beforePending.count + 1)
        XCTAssertEqual(evidence.count, beforeEvidence.count + 1)
        XCTAssertTrue(pending.contains { $0.memo == "売上入金" && $0.status == .needsReview && $0.source == .importFile })
    }
}
