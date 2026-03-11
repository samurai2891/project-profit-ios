import Foundation

struct DocumentAddInput: Sendable, Equatable {
    let transactionId: UUID?
    let documentType: LegalDocumentType
    let originalFileName: String
    let fileData: Data
    let mimeType: String?
    let issueDate: Date
    let note: String
}

@MainActor
struct DocumentWorkflowUseCase {
    private let dataStore: DataStore
    private let documentRepository: any DocumentRepository

    init(
        dataStore: DataStore,
        documentRepository: (any DocumentRepository)? = nil
    ) {
        self.dataStore = dataStore
        self.documentRepository = documentRepository ?? SwiftDataDocumentRepository(modelContext: dataStore.modelContext)
    }

    func listDocuments(transactionId: UUID? = nil) -> [PPDocumentRecord] {
        do {
            return try documentRepository.listDocuments(transactionId: transactionId)
        } catch {
            AppLogger.dataStore.error("Failed to fetch document records: \(error.localizedDescription)")
            return []
        }
    }

    func document(id: UUID) -> PPDocumentRecord? {
        do {
            return try documentRepository.document(id: id)
        } catch {
            AppLogger.dataStore.error("Failed to fetch document record: \(error.localizedDescription)")
            return nil
        }
    }

    func listComplianceLogs(limit: Int = 200) -> [PPComplianceLog] {
        do {
            return try documentRepository.listComplianceLogs(limit: limit)
        } catch {
            AppLogger.dataStore.error("Failed to fetch compliance logs: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    func addDocument(input: DocumentAddInput) -> Result<PPDocumentRecord, AppError> {
        if let transactionId = input.transactionId, dataStore.getTransaction(id: transactionId) == nil {
            return .failure(.transactionNotFound(id: transactionId))
        }

        do {
            let storedFileName = try ReceiptImageStore.saveDocumentData(
                input.fileData,
                originalFileName: input.originalFileName
            )
            let record = PPDocumentRecord(
                transactionId: input.transactionId,
                documentType: input.documentType,
                storedFileName: storedFileName,
                originalFileName: input.originalFileName,
                mimeType: input.mimeType,
                fileSize: input.fileData.count,
                contentHash: ReceiptImageStore.sha256Hex(data: input.fileData),
                issueDate: input.issueDate,
                note: input.note
            )
            documentRepository.insertDocument(record)
            if dataStore.save() {
                appendComplianceLog(
                    eventType: .documentAdded,
                    message: "書類登録: \(record.documentType.label) (\(record.originalFileName))",
                    documentId: record.id,
                    transactionId: record.transactionId
                )
                return .success(record)
            }
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
            return .failure(dataStore.lastError ?? .invalidInput(message: "書類の保存に失敗しました"))
        } catch {
            AppLogger.dataStore.error("Failed to save document file: \(error.localizedDescription)")
            return .failure(.invalidInput(message: "書類ファイルの保存に失敗しました"))
        }
    }

    func requestDeletion(id: UUID) -> DocumentDeleteAttempt {
        guard let record = document(id: id) else {
            return .failed(message: "書類が見つかりません")
        }

        if let warning = record.retentionWarningMessage() {
            appendComplianceLog(
                eventType: .retentionWarningShown,
                message: warning,
                documentId: record.id,
                transactionId: record.transactionId
            )
            return .warningRequired(message: warning)
        }

        return performDeletion(record: record, reason: nil)
    }

    func confirmDeletion(id: UUID, reason: String) -> DocumentDeleteAttempt {
        guard let record = document(id: id) else {
            return .failed(message: "書類が見つかりません")
        }
        return performDeletion(record: record, reason: reason)
    }

    private func performDeletion(record: PPDocumentRecord, reason: String?) -> DocumentDeleteAttempt {
        let fileName = record.storedFileName
        let requiresWarning = record.retentionWarningMessage() != nil
        let documentType = record.documentType
        let originalFileName = record.originalFileName
        let transactionId = record.transactionId
        let documentId = record.id

        documentRepository.deleteDocument(record)
        guard dataStore.save() else {
            return .failed(
                message: (dataStore.lastError ?? .invalidInput(message: "書類削除に失敗しました")).localizedDescription
            )
        }

        ReceiptImageStore.deleteDocumentFile(fileName: fileName)

        if requiresWarning {
            let cleanedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            appendComplianceLog(
                eventType: .retentionWarningConfirmedDeletion,
                message: "保存期間内削除を実行: \(documentType.label) / 理由: \(cleanedReason.isEmpty ? "未入力" : cleanedReason)",
                documentId: documentId,
                transactionId: transactionId
            )
        } else {
            appendComplianceLog(
                eventType: .documentDeleted,
                message: "書類削除: \(documentType.label) (\(originalFileName))",
                documentId: documentId,
                transactionId: transactionId
            )
        }

        return .deleted
    }

    func addComplianceLog(
        eventType: ComplianceEventType,
        message: String,
        documentId: UUID?,
        transactionId: UUID?
    ) {
        appendComplianceLog(
            eventType: eventType,
            message: message,
            documentId: documentId,
            transactionId: transactionId
        )
    }

    private func appendComplianceLog(
        eventType: ComplianceEventType,
        message: String,
        documentId: UUID?,
        transactionId: UUID?
    ) {
        let log = PPComplianceLog(
            eventType: eventType,
            message: message,
            documentId: documentId,
            transactionId: transactionId
        )
        documentRepository.insertComplianceLog(log)
        _ = dataStore.save()
    }
}
