import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DocumentWorkflowUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: DocumentWorkflowUseCase!
    private var storedFileNames: [String] = []

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = DocumentWorkflowUseCase(modelContext: context)
        storedFileNames = []
    }

    override func tearDown() {
        for fileName in storedFileNames {
            ReceiptImageStore.deleteDocumentFile(fileName: fileName)
        }
        storedFileNames = []
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testAddDocumentSuccessCreatesRecordAndComplianceLog() {
        let project = dataStore.addProject(name: "Doc Workflow", description: "test")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 2_400,
            date: Date(),
            categoryId: "cat-other-expense",
            memo: "doc",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let result = useCase.addDocument(
            input: DocumentAddInput(
                transactionId: transaction.id,
                documentType: .invoice,
                originalFileName: "invoice.pdf",
                fileData: Data("invoice-data".utf8),
                mimeType: "application/pdf",
                issueDate: Date(),
                note: "workflow"
            )
        )

        guard case .success(let record) = result else {
            XCTFail("Expected success")
            return
        }

        storedFileNames.append(record.storedFileName)
        XCTAssertEqual(useCase.listDocuments(transactionId: transaction.id).count, 1)
        XCTAssertTrue(ReceiptImageStore.documentFileExists(fileName: record.storedFileName))
        XCTAssertEqual(useCase.listComplianceLogs(limit: 10).first?.eventType, .documentAdded)
    }

    func testAddDocumentFailsForUnknownTransaction() {
        let result = useCase.addDocument(
            input: DocumentAddInput(
                transactionId: UUID(),
                documentType: .receipt,
                originalFileName: "receipt.jpg",
                fileData: Data("receipt-data".utf8),
                mimeType: "image/jpeg",
                issueDate: Date(),
                note: ""
            )
        )

        guard case .failure(let error) = result else {
            XCTFail("Expected failure")
            return
        }

        if case .transactionNotFound = error {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected transactionNotFound")
        }
    }

    func testRequestDeletionReturnsWarningWithinRetention() {
        let record = try! XCTUnwrap(makeDocumentRecord())

        let attempt = useCase.requestDeletion(id: record.id)

        switch attempt {
        case .warningRequired(let message):
            XCTAssertTrue(message.contains("保存期間"))
            XCTAssertEqual(useCase.listComplianceLogs(limit: 10).first?.eventType, .retentionWarningShown)
        default:
            XCTFail("Expected warningRequired")
        }
    }

    func testConfirmDeletionRemovesRecordFileAndLogsConfirmedDeletion() {
        let record = try! XCTUnwrap(makeDocumentRecord())

        let attempt = useCase.confirmDeletion(id: record.id, reason: "workflow-test")

        if case .deleted = attempt {
            XCTAssertNil(useCase.document(id: record.id))
            XCTAssertFalse(ReceiptImageStore.documentFileExists(fileName: record.storedFileName))
            XCTAssertEqual(useCase.listComplianceLogs(limit: 10).first?.eventType, .retentionWarningConfirmedDeletion)
            storedFileNames.removeAll { $0 == record.storedFileName }
        } else {
            XCTFail("Expected deleted")
        }
    }

    func testDeleteAfterRetentionLogsDocumentDeleted() {
        let issueDate = Calendar.current.date(byAdding: .year, value: -8, to: Date())!
        let record = try! XCTUnwrap(makeDocumentRecord(issueDate: issueDate, documentType: .receipt))

        let firstAttempt = useCase.requestDeletion(id: record.id)

        if case .deleted = firstAttempt {
            XCTAssertNil(useCase.document(id: record.id))
            XCTAssertEqual(useCase.listComplianceLogs(limit: 10).first?.eventType, .documentDeleted)
            storedFileNames.removeAll { $0 == record.storedFileName }
        } else {
            XCTFail("Expected deleted without warning")
        }
    }

    func testAvailableProjectsReturnsProjectsForFilterSheet() {
        let first = dataStore.addProject(name: "First", description: "one")
        let second = dataStore.addProject(name: "Second", description: "two")

        let projects = useCase.availableProjects()

        XCTAssertEqual(projects.map(\.id), [second.id, first.id])
    }

    func testMatchingStoredFileNamesReturnsNilWithoutActiveFilters() async throws {
        var form = EvidenceSearchFormState()

        let results = try await useCase.matchingStoredFileNames(form: form)

        XCTAssertNil(results)
    }

    func testMatchingStoredFileNamesReturnsResultsWhenBusinessProfileExistsAndFiltersActive() async throws {
        let project = dataStore.addProject(name: "Evidence Project", description: "doc")
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let evidence = makeEvidence(
            businessId: businessId,
            fileHash: "DOC-HASH-001",
            projectId: project.id,
            counterpartyName: "Acme Corp",
            registrationNumber: "T1234567890123",
            totalAmount: 2_400
        )
        try await EvidenceCatalogUseCase(modelContext: context).save(evidence)

        var form = EvidenceSearchFormState()
        form.textQuery = "Acme"

        let results = try await useCase.matchingStoredFileNames(form: form)

        XCTAssertEqual(results, Set([evidence.originalFilePath]))
    }

    func testRebuildEvidenceIndexKeepsSearchResultsAvailable() async throws {
        let project = dataStore.addProject(name: "Rebuild Project", description: "doc")
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let evidence = makeEvidence(
            businessId: businessId,
            fileHash: "DOC-HASH-REBUILD",
            projectId: project.id,
            counterpartyName: "Ledger Co",
            registrationNumber: "T9999999999999",
            totalAmount: 1_100
        )
        try await EvidenceCatalogUseCase(modelContext: context).save(evidence)

        try await useCase.rebuildEvidenceIndex()

        var form = EvidenceSearchFormState()
        form.counterpartyText = "Ledger"
        let results = try await useCase.matchingStoredFileNames(form: form)
        XCTAssertEqual(results, Set([evidence.originalFilePath]))
    }

    private func makeDocumentRecord(
        issueDate: Date = Date(),
        documentType: LegalDocumentType = .invoice
    ) -> PPDocumentRecord? {
        let project = dataStore.addProject(name: "Delete Doc", description: "test")
        let transaction = dataStore.addTransaction(
            type: .expense,
            amount: 1_000,
            date: issueDate,
            categoryId: "cat-other-expense",
            memo: "delete",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let result = useCase.addDocument(
            input: DocumentAddInput(
                transactionId: transaction.id,
                documentType: documentType,
                originalFileName: "delete.pdf",
                fileData: Data("delete-data".utf8),
                mimeType: "application/pdf",
                issueDate: issueDate,
                note: ""
            )
        )

        guard case .success(let record) = result else {
            return nil
        }
        storedFileNames.append(record.storedFileName)
        return record
    }

    private func makeEvidence(
        businessId: UUID,
        fileHash: String,
        projectId: UUID,
        counterpartyName: String,
        registrationNumber: String,
        totalAmount: Decimal
    ) -> EvidenceDocument {
        EvidenceDocument(
            businessId: businessId,
            taxYear: 2025,
            sourceType: .camera,
            legalDocumentType: .invoice,
            storageCategory: .electronicTransaction,
            receivedAt: Date(timeIntervalSince1970: 1_741_392_000),
            issueDate: Date(timeIntervalSince1970: 1_741_392_000),
            originalFilename: "\(counterpartyName).pdf",
            mimeType: "application/pdf",
            fileHash: fileHash,
            originalFilePath: "\(fileHash).pdf",
            ocrText: "\(counterpartyName) \(totalAmount)",
            extractionVersion: "ocr-v1",
            searchTokens: [counterpartyName, fileHash],
            structuredFields: EvidenceStructuredFields(
                counterpartyName: counterpartyName,
                registrationNumber: registrationNumber,
                transactionDate: Date(timeIntervalSince1970: 1_741_392_000),
                totalAmount: totalAmount,
                confidence: 0.93
            ),
            linkedProjectIds: [projectId],
            complianceStatus: .pendingReview
        )
    }
}
