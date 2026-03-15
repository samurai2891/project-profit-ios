import SwiftData
import Foundation

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

    func confirmDocumentDeletion(id: UUID, reason: String) -> DocumentDeleteAttempt {
        documentWorkflowUseCase.confirmDeletion(id: id, reason: reason)
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

    func purgeDocumentRecords(for transactionId: UUID) -> [String] {
        let records = listDocumentRecords(transactionId: transactionId)
        let fileNames = records.map(\.storedFileName)
        for record in records {
            modelContext.delete(record)
        }
        return fileNames
    }
}
