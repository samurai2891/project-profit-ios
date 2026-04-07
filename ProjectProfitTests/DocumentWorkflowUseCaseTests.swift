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
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = DocumentWorkflowUseCase(modelContext: context)
        storedFileNames = []
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DocumentWorkflowUseCaseTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        ReceiptImageStore.setBaseDirectoryOverride(tempDirectory)
    }

    override func tearDownWithError() throws {
        for fileName in storedFileNames {
            ReceiptImageStore.deleteDocumentFile(fileName: fileName)
            ReceiptImageStore.deleteQuarantinedDocumentFile(fileName: fileName)
        }
        for record in useCase?.quarantinedDocuments() ?? [] {
            if let quarantineFileName = record.quarantineFileName {
                ReceiptImageStore.deleteQuarantinedDocumentFile(fileName: quarantineFileName)
            }
        }
        ReceiptImageStore.setBaseDirectoryOverride(nil)
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        storedFileNames = []
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testAddDocumentSuccessCreatesRecordAndComplianceLog() {
        let project = mutations(dataStore).addProject(name: "Doc Workflow", description: "test")
        let transaction = mutations(dataStore).addTransaction(
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

    func testRequestDeletionRequiresAdminOverrideWithinRetention() {
        let record = try! XCTUnwrap(makeDocumentRecord())

        let attempt = useCase.requestDeletion(id: record.id)

        switch attempt {
        case .adminOverrideRequired(let message):
            XCTAssertTrue(message.contains("保存期間"))
            let storedRecord = try! XCTUnwrap(useCase.document(id: record.id))
            XCTAssertNotNil(storedRecord.deletionRequestedAt)
            XCTAssertEqual(useCase.listComplianceLogs(limit: 10).first?.eventType, .adminOverrideRequested)
        default:
            XCTFail("Expected adminOverrideRequired")
        }
    }

    func testConfirmDeletionFailsWithoutPriorRequestWithinRetention() {
        let record = try! XCTUnwrap(makeDocumentRecord())

        let attempt = useCase.confirmDeletion(
            id: record.id,
            reason: "workflow-test",
            approvedBy: "監査担当"
        )

        if case .failed(let message) = attempt {
            XCTAssertTrue(message.contains("削除申請"))
        } else {
            XCTFail("Expected failed")
        }
    }

    func testConfirmDeletionRejectsEmptyApprovedByWithinRetention() {
        let record = try! XCTUnwrap(makeDocumentRecord())
        _ = useCase.requestDeletion(id: record.id)

        let attempt = useCase.confirmDeletion(id: record.id, reason: "workflow-test", approvedBy: " ")

        if case .failed(let message) = attempt {
            XCTAssertTrue(message.contains("承認者名"))
        } else {
            XCTFail("Expected failed")
        }
    }

    func testConfirmDeletionQuarantinesRecordAndLogsAdminOverride() {
        let record = try! XCTUnwrap(makeDocumentRecord())
        _ = useCase.requestDeletion(id: record.id)

        let attempt = useCase.confirmDeletion(
            id: record.id,
            reason: "workflow-test",
            approvedBy: "監査担当"
        )

        if case .deleted = attempt {
            XCTAssertFalse(ReceiptImageStore.documentFileExists(fileName: record.storedFileName))
            let storedRecord = try! XCTUnwrap(useCase.document(id: record.id))
            XCTAssertEqual(storedRecord.deletionStatus, .quarantined)
            XCTAssertNil(storedRecord.deletionRequestedAt)
            XCTAssertEqual(storedRecord.deletionReason, "workflow-test")
            XCTAssertNotNil(storedRecord.overrideApprovedAt)
            XCTAssertEqual(storedRecord.overrideApprovedBy, "監査担当")
            XCTAssertNotNil(storedRecord.quarantineFileName)
            XCTAssertEqual(useCase.listDocuments(transactionId: record.transactionId).count, 0)
            XCTAssertEqual(useCase.quarantinedDocuments(transactionId: record.transactionId).count, 1)
            XCTAssertEqual(useCase.listComplianceLogs(limit: 10).first?.eventType, .documentQuarantined)
        } else {
            XCTFail("Expected deleted")
        }
    }

    func testDeleteAfterRetentionMovesRecordToQuarantineAndLogsDocumentDeleted() {
        let issueDate = Calendar.current.date(byAdding: .year, value: -8, to: Date())!
        let record = try! XCTUnwrap(makeDocumentRecord(issueDate: issueDate, documentType: .receipt))

        let firstAttempt = useCase.requestDeletion(id: record.id)

        if case .deleted = firstAttempt {
            let storedRecord = try! XCTUnwrap(useCase.document(id: record.id))
            XCTAssertEqual(storedRecord.deletionStatus, .quarantined)
            XCTAssertEqual(useCase.listComplianceLogs(limit: 10).first?.eventType, .documentDeleted)
        } else {
            XCTFail("Expected deleted without warning")
        }
    }

    func testRestoreDeletedDocumentReturnsRecordToActiveList() {
        let record = try! XCTUnwrap(makeDocumentRecord())
        _ = useCase.requestDeletion(id: record.id)
        _ = useCase.confirmDeletion(id: record.id, reason: "restore-test", approvedBy: "監査担当")

        let attempt = useCase.restoreDeletedDocument(id: record.id)

        if case .restored = attempt {
            let restoredRecord = try! XCTUnwrap(useCase.document(id: record.id))
            XCTAssertEqual(restoredRecord.deletionStatus, .active)
            XCTAssertNil(restoredRecord.deletionRequestedAt)
            XCTAssertNil(restoredRecord.quarantineFileName)
            XCTAssertTrue(ReceiptImageStore.documentFileExists(fileName: restoredRecord.storedFileName))
            XCTAssertEqual(useCase.listDocuments(transactionId: record.transactionId).count, 1)
            XCTAssertEqual(useCase.listComplianceLogs(limit: 10).first?.eventType, .documentRestored)
        } else {
            XCTFail("Expected restored")
        }
    }

    func testConfirmDeletionRestoresFileWhenRepositorySaveFails() throws {
        let record = try XCTUnwrap(makeDocumentRecord())
        _ = useCase.requestDeletion(id: record.id)

        let failingRepository = MockDocumentRepository(
            records: [record],
            complianceLogs: [],
            shouldFailSave: true
        )
        let failingUseCase = DocumentWorkflowUseCase(
            modelContext: context,
            documentRepository: failingRepository
        )

        let attempt = failingUseCase.confirmDeletion(
            id: record.id,
            reason: "workflow-test",
            approvedBy: "監査担当"
        )

        if case .failed = attempt {
            XCTAssertTrue(ReceiptImageStore.documentFileExists(fileName: record.storedFileName))
        } else {
            XCTFail("Expected failed")
        }
    }

    func testRestoreDeletedDocumentReQuarantinesFileWhenRepositorySaveFails() throws {
        let record = try XCTUnwrap(makeDocumentRecord())
        _ = useCase.requestDeletion(id: record.id)
        _ = useCase.confirmDeletion(id: record.id, reason: "restore-test", approvedBy: "監査担当")

        let quarantinedRecord = try XCTUnwrap(useCase.document(id: record.id))
        let failingRepository = MockDocumentRepository(
            records: [quarantinedRecord],
            complianceLogs: [],
            shouldFailSave: true
        )
        let failingUseCase = DocumentWorkflowUseCase(
            modelContext: context,
            documentRepository: failingRepository
        )

        let attempt = failingUseCase.restoreDeletedDocument(id: record.id)

        if case .failed = attempt {
            XCTAssertFalse(ReceiptImageStore.documentFileExists(fileName: record.storedFileName))
        } else {
            XCTFail("Expected failed")
        }
    }

    func testAvailableProjectsReturnsProjectsForFilterSheet() {
        let first = mutations(dataStore).addProject(name: "First", description: "one")
        let second = mutations(dataStore).addProject(name: "Second", description: "two")

        let projects = useCase.availableProjects()

        XCTAssertEqual(projects.map(\.id), [second.id, first.id])
    }

    func testMatchingStoredFileNamesReturnsNilWithoutActiveFilters() async throws {
        var form = EvidenceSearchFormState()

        let results = try await useCase.matchingStoredFileNames(form: form)

        XCTAssertNil(results)
    }

    func testMatchingStoredFileNamesReturnsResultsWhenBusinessProfileExistsAndFiltersActive() async throws {
        let project = mutations(dataStore).addProject(name: "Evidence Project", description: "doc")
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
        let project = mutations(dataStore).addProject(name: "Rebuild Project", description: "doc")
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
        let project = mutations(dataStore).addProject(name: "Delete Doc", description: "test")
        let transaction = mutations(dataStore).addTransaction(
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

@MainActor
private final class MockDocumentRepository: DocumentRepository {
    private(set) var records: [PPDocumentRecord]
    private(set) var complianceLogs: [PPComplianceLog]
    private let shouldFailSave: Bool

    init(records: [PPDocumentRecord], complianceLogs: [PPComplianceLog], shouldFailSave: Bool) {
        self.records = records
        self.complianceLogs = complianceLogs
        self.shouldFailSave = shouldFailSave
    }

    func allDocuments() throws -> [PPDocumentRecord] { records }
    func listDocuments(transactionId: UUID?) throws -> [PPDocumentRecord] {
        records.filter { record in
            record.deletionStatus == .active && (transactionId == nil || record.transactionId == transactionId)
        }
    }
    func document(id: UUID) throws -> PPDocumentRecord? { records.first { $0.id == id } }
    func listComplianceLogs(limit: Int) throws -> [PPComplianceLog] { Array(complianceLogs.prefix(limit)) }
    func transactionExists(id: UUID) throws -> Bool { true }
    func listProjects() throws -> [PPProject] { [] }
    func currentBusinessId() throws -> UUID? { nil }
    func insertDocument(_ record: PPDocumentRecord) { records.append(record) }
    func deleteDocument(_ record: PPDocumentRecord) { records.removeAll { $0.id == record.id } }
    func insertComplianceLog(_ log: PPComplianceLog) { complianceLogs.insert(log, at: 0) }
    func saveChanges() throws {
        if shouldFailSave {
            throw AppError.saveFailed(underlying: NSError(domain: "MockDocumentRepository", code: 1))
        }
    }
}
