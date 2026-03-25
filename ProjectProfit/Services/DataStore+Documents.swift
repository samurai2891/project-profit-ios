import SwiftData
import Foundation

struct DocumentPurgeResult {
    let processedDocumentIds: [UUID]
    let failedDocumentIds: [UUID]

    var processedCount: Int {
        processedDocumentIds.count
    }

    var isSuccess: Bool {
        failedDocumentIds.isEmpty
    }
}

extension DataStore {
    private var documentWorkflowUseCase: DocumentWorkflowUseCase {
        DocumentWorkflowUseCase(modelContext: modelContext)
    }

    // MARK: - Document CRUD

    func listDocumentRecords(transactionId: UUID? = nil) -> [PPDocumentRecord] {
        documentWorkflowUseCase.listDocuments(transactionId: transactionId)
    }

    func getDocumentRecord(id: UUID) -> PPDocumentRecord? {
        documentWorkflowUseCase.document(id: id)
    }

    func documentCount(for transactionId: UUID) -> Int {
        listDocumentRecords(transactionId: transactionId).count
    }

    @discardableResult
    func addDocumentRecord(
        transactionId: UUID?,
        documentType: LegalDocumentType,
        originalFileName: String,
        fileData: Data,
        mimeType: String? = nil,
        issueDate: Date = Date(),
        note: String = ""
    ) -> Result<PPDocumentRecord, AppError> {
        documentWorkflowUseCase.addDocument(
            input: DocumentAddInput(
                transactionId: transactionId,
                documentType: documentType,
                originalFileName: originalFileName,
                fileData: fileData,
                mimeType: mimeType,
                issueDate: issueDate,
                note: note
            )
        )
    }

    func requestDocumentDeletion(id: UUID) -> DocumentDeleteAttempt {
        documentWorkflowUseCase.requestDeletion(id: id)
    }

    func confirmDocumentDeletion(id: UUID, reason: String, approvedBy: String) -> DocumentDeleteAttempt {
        documentWorkflowUseCase.confirmDeletion(id: id, reason: reason, approvedBy: approvedBy)
    }

    // MARK: - Compliance Logs

    func listComplianceLogs(limit: Int = 200) -> [PPComplianceLog] {
        documentWorkflowUseCase.listComplianceLogs(limit: limit)
    }

    func addComplianceLog(
        eventType: ComplianceEventType,
        message: String,
        documentId: UUID?,
        transactionId: UUID?
    ) {
        documentWorkflowUseCase.addComplianceLog(
            eventType: eventType,
            message: message,
            documentId: documentId,
            transactionId: transactionId
        )
    }

    @discardableResult
    func purgeDocumentRecords(for transactionId: UUID) -> DocumentPurgeResult {
        let records = listDocumentRecords(transactionId: transactionId)
            + documentWorkflowUseCase.quarantinedDocuments(transactionId: transactionId)
        var processedDocumentIds: [UUID] = []
        var failedDocumentIds: [UUID] = []
        for record in records {
            if record.deletionStatus == .active {
                let attempt = documentWorkflowUseCase.quarantineForMaintenance(
                    id: record.id,
                    trigger: "取引関連データの内部整理"
                )
                if case .deleted = attempt {
                    processedDocumentIds.append(record.id)
                } else {
                    failedDocumentIds.append(record.id)
                }
            } else {
                processedDocumentIds.append(record.id)
            }
        }
        return DocumentPurgeResult(
            processedDocumentIds: processedDocumentIds,
            failedDocumentIds: failedDocumentIds
        )
    }
}
