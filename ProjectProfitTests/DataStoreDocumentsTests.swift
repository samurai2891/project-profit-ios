import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DataStoreDocumentsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "DataStoreDocumentsTests-\(UUID().uuidString)",
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
        dataStore = nil
        context = nil
        container = nil
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testPurgeDocumentRecordsQuarantinesActiveRecordsInsteadOfDeletingThem() throws {
        let transaction = makeTransaction(named: "purge-active")
        let result = dataStore.addDocumentRecord(
            transactionId: transaction.id,
            documentType: .invoice,
            originalFileName: "purge-active.pdf",
            fileData: Data("purge-active".utf8),
            mimeType: "application/pdf",
            issueDate: Date()
        )

        guard case .success(let record) = result else {
            XCTFail("Expected document to be created")
            return
        }

        let result = dataStore.purgeDocumentRecords(for: transaction.id)

        XCTAssertEqual(result.processedCount, 1)
        XCTAssertTrue(result.isSuccess)
        let storedRecord = try XCTUnwrap(dataStore.getDocumentRecord(id: record.id))
        XCTAssertEqual(storedRecord.deletionStatus, .quarantined)
        XCTAssertEqual(storedRecord.deletionReason, "取引関連データの内部整理")
        XCTAssertFalse(ReceiptImageStore.documentFileExists(fileName: record.storedFileName))
        XCTAssertNotNil(ReceiptImageStore.quarantinedDocumentFileURL(fileName: try XCTUnwrap(storedRecord.quarantineFileName)))
    }

    func testPurgeDocumentRecordsKeepsAlreadyQuarantinedRecords() throws {
        let transaction = makeTransaction(named: "purge-quarantined")
        let result = dataStore.addDocumentRecord(
            transactionId: transaction.id,
            documentType: .invoice,
            originalFileName: "purge-quarantined.pdf",
            fileData: Data("purge-quarantined".utf8),
            mimeType: "application/pdf",
            issueDate: Date()
        )

        guard case .success(let record) = result else {
            XCTFail("Expected document to be created")
            return
        }

        _ = dataStore.requestDocumentDeletion(id: record.id)
        _ = dataStore.confirmDocumentDeletion(id: record.id, reason: "事前隔離", approvedBy: "管理者C")
        let quarantinedRecord = try XCTUnwrap(dataStore.getDocumentRecord(id: record.id))
        let quarantineFileName = try XCTUnwrap(quarantinedRecord.quarantineFileName)

        let result = dataStore.purgeDocumentRecords(for: transaction.id)

        XCTAssertEqual(result.processedCount, 1)
        XCTAssertTrue(result.isSuccess)
        let storedRecord = try XCTUnwrap(dataStore.getDocumentRecord(id: record.id))
        XCTAssertEqual(storedRecord.deletionStatus, .quarantined)
        XCTAssertEqual(storedRecord.quarantineFileName, quarantineFileName)
        XCTAssertNotNil(ReceiptImageStore.quarantinedDocumentFileURL(fileName: quarantineFileName))
    }

    func testPurgeDocumentRecordsReturnsFailureWhenDocumentFileIsMissing() throws {
        let transaction = makeTransaction(named: "purge-missing")
        let result = dataStore.addDocumentRecord(
            transactionId: transaction.id,
            documentType: .invoice,
            originalFileName: "purge-missing.pdf",
            fileData: Data("purge-missing".utf8),
            mimeType: "application/pdf",
            issueDate: Date()
        )

        guard case .success(let record) = result else {
            XCTFail("Expected document to be created")
            return
        }

        ReceiptImageStore.deleteDocumentFile(fileName: record.storedFileName)

        let purgeResult = dataStore.purgeDocumentRecords(for: transaction.id)

        XCTAssertFalse(purgeResult.isSuccess)
        XCTAssertEqual(purgeResult.failedDocumentIds, [record.id])
        let storedRecord = try XCTUnwrap(dataStore.getDocumentRecord(id: record.id))
        XCTAssertEqual(storedRecord.deletionStatus, .active)
    }

    private func makeTransaction(named name: String) -> PPTransaction {
        let project = mutations(dataStore).addProject(name: name, description: "doc")
        return mutations(dataStore).addTransaction(
            type: .expense,
            amount: 500,
            date: Date(),
            categoryId: "cat-other-expense",
            memo: name,
            allocations: [(projectId: project.id, ratio: 100)]
        )
    }
}
