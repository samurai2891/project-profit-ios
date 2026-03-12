import SwiftData
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
            paymentAccountId: AccountingConstants.bankAccountId
        )

        let preview = try await useCase.preview(request: request)

        XCTAssertEqual(preview.fileSource, .csv)
        XCTAssertEqual(preview.parsedLineCount, 1)
        XCTAssertTrue(preview.lineErrors.isEmpty)
        XCTAssertEqual(preview.sampleLines.first?.contains("Client Deposit"), true)
    }

    func testImportStatementCreatesEvidenceImportAndLinesWhenDirectionIsOmitted() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let request = StatementImportRequest(
            fileData: Data("""
            日付,摘要,金額,取引先,参照番号,メモ
            2026/01/10,振込入金,120000,株式会社テスト,REF-001,1月分
            2026/01/12,カード決済,-5500,カフェ,REF-002,会食
            """.utf8),
            originalFileName: "bank-statement.csv",
            mimeType: "text/csv",
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId
        )

        let result = try await useCase.importStatement(request: request)
        let imports = try await repository.findImports(
            businessId: businessId,
            statementKind: .bank,
            paymentAccountId: AccountingConstants.bankAccountId
        )
        let lines = try await repository.findLines(importId: result.importRecord.id)
        let evidences = try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: 2026)

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
    }
}
