import XCTest
import SwiftData
import UIKit
@testable import ProjectProfit

@MainActor
final class DocumentAndSubLedgerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!

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

    func testLegalDocumentTypeRetentionPolicyDefaults() {
        XCTAssertEqual(LegalDocumentType.receipt.retentionCategory, .cashBankDocuments)
        XCTAssertEqual(LegalDocumentType.receipt.retentionCategory.retentionYears, 7)
        XCTAssertEqual(LegalDocumentType.invoice.retentionCategory, .otherBusinessDocuments)
        XCTAssertEqual(LegalDocumentType.invoice.retentionCategory.retentionYears, 5)
    }

    func testDocumentDeletionFlow_requiresWarningBeforeDeletion() {
        let project = mutations(dataStore).addProject(name: "書類テスト", description: "doc")
        let tx = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1200,
            date: Date(),
            categoryId: "cat-other-expense",
            memo: "書類付き",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let addResult = dataStore.addDocumentRecord(
            transactionId: tx.id,
            documentType: .invoice,
            originalFileName: "invoice.pdf",
            fileData: Data("invoice-data".utf8),
            mimeType: "application/pdf",
            issueDate: Date()
        )

        guard case .success(let record) = addResult else {
            XCTFail("Document should be added")
            return
        }

        let firstAttempt = dataStore.requestDocumentDeletion(id: record.id)
        switch firstAttempt {
        case .warningRequired(let message):
            XCTAssertTrue(message.contains("保存期間"))
        default:
            XCTFail("Expected warningRequired")
        }

        let confirmed = dataStore.confirmDocumentDeletion(id: record.id, reason: "単体テスト")
        if case .deleted = confirmed {
            XCTAssertEqual(dataStore.documentCount(for: tx.id), 0)
        } else {
            XCTFail("Expected deleted")
        }
    }

    func testSubLedger_cashBookExtractsCashLines() {
        let _ = mutations(dataStore).addManualJournalEntry(
            date: Date(),
            memo: "現金売上",
            lines: [
                (accountId: AccountingConstants.cashAccountId, debit: 3000, credit: 0, memo: "入金"),
                (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 3000, memo: "売上")
            ]
        )

        let entries = dataStore.getSubLedgerEntries(type: .cashBook)
        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.allSatisfy { $0.accountId == AccountingConstants.cashAccountId })
    }

    func testLegacyReceiptImageBackfill_migratesToDocumentRecordAndClearsPath() throws {
        let legacyImageFile = try ReceiptImageStore.saveImage(createTestImage())
        let project = mutations(dataStore).addProject(name: "移行テスト", description: "legacy")
        let tx = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 980,
            date: Date(timeIntervalSince1970: 1_735_689_600),
            categoryId: "cat-other-expense",
            memo: "旧領収書",
            allocations: [(projectId: project.id, ratio: 100)],
            receiptImagePath: legacyImageFile,
            reloadStoreAfterMutation: false
        )

        let reloadedStore = ProjectProfit.DataStore(modelContext: context)
        reloadedStore.loadData()

        guard let migratedTx = reloadedStore.getTransaction(id: tx.id) else {
            XCTFail("Transaction should exist")
            return
        }
        XCTAssertNil(migratedTx.receiptImagePath)

        let records = reloadedStore.listDocumentRecords(transactionId: tx.id)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.documentType, .receipt)
        XCTAssertEqual(records.first?.originalFileName, legacyImageFile)
        XCTAssertFalse(ReceiptImageStore.imageExists(fileName: legacyImageFile))

        if let storedFileName = records.first?.storedFileName {
            XCTAssertTrue(ReceiptImageStore.documentFileExists(fileName: storedFileName))
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
        }
    }

    func testLegacyReceiptImageBackfill_isIdempotentWhenDocumentAlreadyExists() throws {
        let legacyImageFile = try ReceiptImageStore.saveImage(createTestImage())
        let project = mutations(dataStore).addProject(name: "移行重複テスト", description: "legacy")
        let tx = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1200,
            date: Date(),
            categoryId: "cat-other-expense",
            memo: "既存書類あり",
            allocations: [(projectId: project.id, ratio: 100)],
            receiptImagePath: legacyImageFile,
            reloadStoreAfterMutation: false
        )

        let existingDocumentResult = dataStore.addDocumentRecord(
            transactionId: tx.id,
            documentType: .receipt,
            originalFileName: legacyImageFile,
            fileData: Data("already-backed-up".utf8),
            mimeType: "image/jpeg",
            issueDate: tx.date
        )

        guard case .success(let existingRecord) = existingDocumentResult else {
            XCTFail("Existing document should be inserted")
            return
        }

        let reloadedStore = ProjectProfit.DataStore(modelContext: context)
        reloadedStore.loadData()

        guard let migratedTx = reloadedStore.getTransaction(id: tx.id) else {
            XCTFail("Transaction should exist")
            return
        }
        XCTAssertNil(migratedTx.receiptImagePath)

        let records = reloadedStore.listDocumentRecords(transactionId: tx.id)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, existingRecord.id)
        XCTAssertFalse(ReceiptImageStore.imageExists(fileName: legacyImageFile))

        ReceiptImageStore.deleteDocumentFile(fileName: existingRecord.storedFileName)
    }

    private func createTestImage() -> UIImage {
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
