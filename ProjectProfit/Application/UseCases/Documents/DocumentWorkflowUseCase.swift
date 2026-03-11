import Foundation
import SwiftData

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
    private let documentRepository: any DocumentRepository
    private let evidenceCatalogUseCase: EvidenceCatalogUseCase
    private let searchIndexRebuilder: SearchIndexRebuilder

    init(
        modelContext: ModelContext,
        documentRepository: (any DocumentRepository)? = nil,
        evidenceCatalogUseCase: EvidenceCatalogUseCase? = nil,
        searchIndexRebuilder: SearchIndexRebuilder? = nil
    ) {
        self.documentRepository = documentRepository ?? SwiftDataDocumentRepository(modelContext: modelContext)
        self.evidenceCatalogUseCase = evidenceCatalogUseCase ?? EvidenceCatalogUseCase(modelContext: modelContext)
        self.searchIndexRebuilder = searchIndexRebuilder ?? SearchIndexRebuilder(modelContext: modelContext)
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

    func availableProjects() -> [PPProject] {
        do {
            return try documentRepository.listProjects()
        } catch {
            AppLogger.dataStore.error("Failed to fetch projects for document ledger: \(error.localizedDescription)")
            return []
        }
    }

    func matchingStoredFileNames(form: EvidenceSearchFormState) async throws -> Set<String>? {
        guard form.hasActiveFilters else {
            return nil
        }
        guard let businessId = try documentRepository.currentBusinessId() else {
            return nil
        }

        let evidences = try await evidenceCatalogUseCase.search(form.makeCriteria(businessId: businessId))
        return Set(evidences.map(\.originalFilePath))
    }

    func rebuildEvidenceIndex() async throws {
        let businessId = try documentRepository.currentBusinessId()
        try searchIndexRebuilder.rebuildEvidenceIndex(businessId: businessId)
    }

    @discardableResult
    func addDocument(input: DocumentAddInput) -> Result<PPDocumentRecord, AppError> {
        do {
            if let transactionId = input.transactionId, try documentRepository.transactionExists(id: transactionId) == false {
                return .failure(.transactionNotFound(id: transactionId))
            }
        } catch let error as AppError {
            AppLogger.dataStore.error("Failed to validate transaction for document: \(error.localizedDescription)")
            return .failure(error)
        } catch {
            AppLogger.dataStore.error("Failed to validate transaction for document: \(error.localizedDescription)")
            return .failure(.dataLoadFailed(underlying: error))
        }

        var storedFileName: String?

        do {
            storedFileName = try ReceiptImageStore.saveDocumentData(
                input.fileData,
                originalFileName: input.originalFileName
            )
            let record = PPDocumentRecord(
                transactionId: input.transactionId,
                documentType: input.documentType,
                storedFileName: storedFileName ?? "",
                originalFileName: input.originalFileName,
                mimeType: input.mimeType,
                fileSize: input.fileData.count,
                contentHash: ReceiptImageStore.sha256Hex(data: input.fileData),
                issueDate: input.issueDate,
                note: input.note
            )
            documentRepository.insertDocument(record)
            try documentRepository.saveChanges()
            appendComplianceLog(
                eventType: .documentAdded,
                message: "書類登録: \(record.documentType.label) (\(record.originalFileName))",
                documentId: record.id,
                transactionId: record.transactionId
            )
            return .success(record)
        } catch let error as AppError {
            AppLogger.dataStore.error("Failed to save document: \(error.localizedDescription)")
            return cleanupFailedSave(storedFileName: storedFileName, error: error)
        } catch {
            AppLogger.dataStore.error("Failed to save document: \(error.localizedDescription)")
            return cleanupFailedSave(storedFileName: storedFileName, error: .saveFailed(underlying: error))
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
        do {
            try documentRepository.saveChanges()
        } catch {
            return .failed(
                message: ((error as? AppError) ?? .invalidInput(message: "書類削除に失敗しました")).localizedDescription
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
        do {
            try documentRepository.saveChanges()
        } catch {
            AppLogger.dataStore.error("Failed to save compliance log: \(error.localizedDescription)")
        }
    }

    private func cleanupFailedSave(storedFileName: String?, error: AppError) -> Result<PPDocumentRecord, AppError> {
        if let storedFileName {
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
        }
        return .failure(error)
    }
}
