import SwiftData
import UIKit
import XCTest
@testable import ProjectProfit

@MainActor
final class StatementImportUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: StatementImportUseCase!
    private var repository: SwiftDataStatementRepository!
    private var evidenceRepository: SwiftDataEvidenceRepository!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = StatementImportUseCase(modelContext: context)
        repository = SwiftDataStatementRepository(modelContext: context)
        evidenceRepository = SwiftDataEvidenceRepository(modelContext: context)
    }

    override func tearDown() {
        evidenceRepository = nil
        repository = nil
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testPreviewParsesCommonCSVJapaneseAndEnglishHeaders() async throws {
        let request = StatementImportRequest(
            fileData: Data("""
            date,description,amount,direction,counterparty,reference,memo
            2026-01-10,Client Deposit,120000,inflow,ACME,REF-1,入金確認
            """.utf8),
            originalFileName: "statement.csv",
            mimeType: "text/csv",
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            statementPeriodYear: 2026
        )

        let preview = try await useCase.preview(request: request)

        XCTAssertEqual(preview.fileSource, .csv)
        XCTAssertEqual(preview.parsedLineCount, 1)
        XCTAssertTrue(preview.lineErrors.isEmpty)
        XCTAssertEqual(preview.sampleLines.first?.contains("Client Deposit"), true)
    }

    func testImportStatementCreatesEvidenceImportAndLinesWhenDirectionIsOmitted() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let approvalQueue = ApprovalQueueQueryUseCase(modelContext: context)
        let chart = SwiftDataChartOfAccountsRepository(modelContext: context)
        let request = StatementImportRequest(
            fileData: Data("""
            日付,摘要,金額,取引先,参照番号,メモ
            2026/01/10,振込入金,120000,株式会社テスト,REF-001,1月分
            2026/01/12,カード決済,-5500,カフェ,REF-002,会食
            """.utf8),
            originalFileName: "bank-statement.csv",
            mimeType: "text/csv",
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            statementPeriodYear: 2026
        )

        let result = try await useCase.importStatement(request: request)
        let imports = try await repository.findImports(
            businessId: businessId,
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId
        )
        let lines = try await repository.findLines(importId: result.importRecord.id)
        let evidences = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: 2026)
        let candidates = try await workflow.candidates(evidenceId: result.evidenceId)
        let pendingItems = try await approvalQueue.pendingItems()
        let bankAccount = try await chart.findByLegacyId(
            businessId: businessId,
            legacyAccountId: AccountingConstants.bankAccountId
        )
        let suspenseAccount = try await chart.findByLegacyId(
            businessId: businessId,
            legacyAccountId: AccountingConstants.suspenseAccountId
        )
        let bankAccountId = try XCTUnwrap(bankAccount?.id)
        let suspenseAccountId = try XCTUnwrap(suspenseAccount?.id)

        XCTAssertEqual(result.lineCount, 2)
        XCTAssertTrue(result.lineErrors.isEmpty)
        XCTAssertEqual(imports.count, 1)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].direction, .inflow)
        XCTAssertEqual(lines[1].direction, .outflow)
        XCTAssertEqual(lines[1].amount, Decimal(5500))
        XCTAssertTrue(evidences.contains {
            $0.id == result.evidenceId
                && $0.legalDocumentType == .statement
                && $0.sourceType == .importedCSV
        })
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.allSatisfy { $0.status == .needsReview })
        XCTAssertTrue(candidates.allSatisfy { $0.source == .importFile })
        XCTAssertEqual(
            Set(candidates.compactMap(\.proposedLines.first?.evidenceLineReferenceId)),
            Set(lines.map(\.id))
        )
        let inflowCandidate = try XCTUnwrap(candidates.first { $0.memo == "1月分" })
        XCTAssertEqual(inflowCandidate.proposedLines.first?.debitAccountId, bankAccountId)
        XCTAssertEqual(inflowCandidate.proposedLines.first?.creditAccountId, suspenseAccountId)
        let outflowCandidate = try XCTUnwrap(candidates.first { $0.memo == "会食" })
        XCTAssertEqual(outflowCandidate.proposedLines.first?.debitAccountId, suspenseAccountId)
        XCTAssertEqual(outflowCandidate.proposedLines.first?.creditAccountId, bankAccountId)
        XCTAssertTrue(lines.allSatisfy { $0.suggestedCandidateId != nil })
        XCTAssertTrue(
            pendingItems.contains { item in
                if case let .candidate(candidate) = item {
                    return candidates.contains(where: { $0.id == candidate.id })
                }
                return false
            }
        )
    }

    func testImportStatementUsesCalendarTaxYearWhenFiscalStartMonthChanges() async throws {
        let key = FiscalYearSettings.userDefaultsKey
        let previousStartMonth = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(4, forKey: key)
        defer {
            if let previousStartMonth {
                UserDefaults.standard.set(previousStartMonth, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let request = StatementImportRequest(
            fileData: Data("""
            日付,摘要,金額,取引先,参照番号,メモ
            2026/03/10,振込入金,120000,株式会社テスト,REF-301,3月分
            2026/03/12,カード決済,-5500,カフェ,REF-302,会食
            """.utf8),
            originalFileName: "calendar-tax-year.csv",
            mimeType: "text/csv",
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            statementPeriodYear: 2026
        )

        let result = try await useCase.importStatement(request: request)
        let evidences = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: 2026)
        let importedEvidence = try XCTUnwrap(evidences.first { $0.id == result.evidenceId })
        let candidates = try await PostingWorkflowUseCase(modelContext: context).candidates(evidenceId: result.evidenceId)

        XCTAssertEqual(importedEvidence.taxYear, 2026)
        XCTAssertEqual(Set(candidates.map(\.taxYear)), [2026])
    }

    func testImportStatementUsesRequestYearForPDFMonthDayRows() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let pdfData = makeTextPDF(pages: [
            "01/10 ClientDeposit 120000",
            "01/12 CoffeeShop -5500"
        ])
        let request = StatementImportRequest(
            fileData: pdfData,
            originalFileName: "bank-statement.pdf",
            mimeType: "application/pdf",
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            statementPeriodYear: 2024
        )

        let result = try await useCase.importStatement(request: request)
        let lines = try await repository.findLines(importId: result.importRecord.id)
        let evidences = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: 2024)
        let importedEvidence = try XCTUnwrap(evidences.first { $0.id == result.evidenceId })
        let candidates = try await PostingWorkflowUseCase(modelContext: context).candidates(evidenceId: result.evidenceId)
        let years = Set(lines.map { Calendar.current.component(.year, from: $0.date) })

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(years, [2024])
        XCTAssertEqual(importedEvidence.taxYear, 2024)
        XCTAssertEqual(Set(candidates.map(\.taxYear)), [2024])
    }

    func testImportStatementRollsBackArtifactsWhenSuggestionRefreshFails() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let baseRepository = SwiftDataStatementRepository(modelContext: context)
        let failingRepository = FailingSaveLinesStatementRepository(base: baseRepository)
        let failingMatchService = StatementMatchService(
            modelContext: context,
            statementRepository: failingRepository
        )
        let failingUseCase = StatementImportUseCase(
            modelContext: context,
            statementRepository: baseRepository,
            matchService: failingMatchService
        )
        let request = StatementImportRequest(
            fileData: Data("""
            日付,摘要,金額,取引先,参照番号,メモ
            2026/02/10,振込入金,120000,株式会社テスト,REF-101,2月分
            2026/02/12,カード決済,-5500,カフェ,REF-102,会食
            """.utf8),
            originalFileName: "rollback-statement.csv",
            mimeType: "text/csv",
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            statementPeriodYear: 2026
        )
        let fileHash = ReceiptImageStore.sha256Hex(data: request.fileData)
        let importsBefore = try await repository.findImports(
            businessId: businessId,
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId
        ).count
        let linesBefore = try await repository.findLines(
            businessId: businessId,
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            matchState: nil,
            startDate: nil,
            endDate: nil
        ).count
        let candidatesBefore = try await workflow.pendingCandidates(businessId: businessId).count
        let filesBefore = documentFileNames()

        do {
            _ = try await failingUseCase.importStatement(request: request)
            XCTFail("import は失敗するべき")
        } catch FailingSaveLinesStatementRepository.TestError.saveLinesFailure {
            // expected
        } catch {
            XCTFail("想定外エラー: \(error)")
        }

        let importsAfter = try await repository.findImports(
            businessId: businessId,
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId
        ).count
        let linesAfter = try await repository.findLines(
            businessId: businessId,
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId,
            matchState: nil,
            startDate: nil,
            endDate: nil
        ).count
        let candidatesAfter = try await workflow.pendingCandidates(businessId: businessId).count
        let filesAfter = documentFileNames()

        XCTAssertEqual(importsAfter, importsBefore)
        XCTAssertEqual(linesAfter, linesBefore)
        XCTAssertEqual(candidatesAfter, candidatesBefore)
        XCTAssertEqual(filesAfter, filesBefore)
        XCTAssertNil(try existingEvidenceId(businessId: businessId, fileHash: fileHash))
    }

    private func makeTextPDF(pages: [String]) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 28, weight: .regular),
                    .foregroundColor: UIColor.black,
                ]
                page.draw(in: CGRect(x: 40, y: 120, width: 500, height: 60), withAttributes: attrs)
            }
        }
    }

    private func documentFileNames() -> Set<String> {
        let path = ReceiptImageStore.documentDirectoryURL.path
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return Set(names)
    }

    private func existingEvidenceId(businessId: UUID, fileHash: String) throws -> UUID? {
        let descriptor = FetchDescriptor<EvidenceRecordEntity>(
            predicate: #Predicate {
                $0.businessId == businessId &&
                    $0.fileHash == fileHash &&
                    $0.deletedAt == nil
            }
        )
        return try context.fetch(descriptor).first?.evidenceId
    }
}

@MainActor
private final class FailingSaveLinesStatementRepository: StatementRepository {
    enum TestError: Error {
        case saveLinesFailure
    }

    private let base: any StatementRepository

    init(base: any StatementRepository) {
        self.base = base
    }

    func findImport(_ id: UUID) async throws -> StatementImportRecord? {
        try await base.findImport(id)
    }

    func findImports(
        businessId: UUID,
        statementKind: StatementKind?,
        paymentAccountId: String?
    ) async throws -> [StatementImportRecord] {
        try await base.findImports(
            businessId: businessId,
            statementKind: statementKind,
            paymentAccountId: paymentAccountId
        )
    }

    func saveImport(_ record: StatementImportRecord) async throws {
        try await base.saveImport(record)
    }

    func deleteImport(_ id: UUID) async throws {
        try await base.deleteImport(id)
    }

    func findLine(_ id: UUID) async throws -> StatementLineRecord? {
        try await base.findLine(id)
    }

    func findLines(
        businessId: UUID,
        statementKind: StatementKind?,
        paymentAccountId: String?,
        matchState: StatementMatchState?,
        startDate: Date?,
        endDate: Date?
    ) async throws -> [StatementLineRecord] {
        try await base.findLines(
            businessId: businessId,
            statementKind: statementKind,
            paymentAccountId: paymentAccountId,
            matchState: matchState,
            startDate: startDate,
            endDate: endDate
        )
    }

    func findLines(importId: UUID) async throws -> [StatementLineRecord] {
        try await base.findLines(importId: importId)
    }

    func saveLine(_ record: StatementLineRecord) async throws {
        try await base.saveLine(record)
    }

    func saveLines(_ records: [StatementLineRecord]) async throws {
        throw TestError.saveLinesFailure
    }

    func deleteLines(importId: UUID) async throws {
        try await base.deleteLines(importId: importId)
    }
}
