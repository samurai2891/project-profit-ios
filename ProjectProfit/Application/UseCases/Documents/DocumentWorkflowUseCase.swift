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

    func quarantinedDocuments(transactionId: UUID? = nil) -> [PPDocumentRecord] {
        do {
            return try documentRepository.allDocuments()
                .filter { $0.deletionStatus == .quarantined }
                .filter { transactionId == nil || $0.transactionId == transactionId }
        } catch {
            AppLogger.dataStore.error("Failed to fetch quarantined document records: \(error.localizedDescription)")
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
        guard record.deletionStatus == .active else {
            return .failed(message: "この書類はすでに隔離保管中です")
        }

        if let warning = record.retentionWarningMessage() {
            record.deletionRequestedAt = Date()
            record.updatedAt = Date()
            do {
                try documentRepository.saveChanges()
            } catch {
                return .failed(message: "削除申請の記録に失敗しました")
            }
            appendComplianceLog(
                eventType: .adminOverrideRequested,
                message: warning,
                documentId: record.id,
                transactionId: record.transactionId
            )
            return .adminOverrideRequired(message: warning)
        }

        return performDeletion(record: record, reason: nil)
    }

    func confirmDeletion(
        id: UUID,
        reason: String,
        approvedBy: String
    ) -> DocumentDeleteAttempt {
        guard let record = document(id: id) else {
            return .failed(message: "書類が見つかりません")
        }
        guard record.deletionStatus == .active else {
            return .failed(message: "この書類はすでに隔離保管中です")
        }
        let cleanedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedReason.isEmpty else {
            return .failed(message: "管理者解除理由を入力してください")
        }
        let cleanedApprovedBy = approvedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedApprovedBy.isEmpty else {
            return .failed(message: "承認者名を入力してください")
        }
        if record.retentionWarningMessage() != nil, record.hasPendingDeletionRequest == false {
            return .failed(message: "削除申請を行ってから管理者解除を実行してください")
        }
        return performDeletion(record: record, reason: cleanedReason, approvedBy: cleanedApprovedBy)
    }

    func restoreDeletedDocument(id: UUID) -> DocumentDeleteAttempt {
        guard let record = document(id: id) else {
            return .failed(message: "書類が見つかりません")
        }
        guard record.deletionStatus == .quarantined,
              let quarantineFileName = record.quarantineFileName else {
            return .failed(message: "復元対象の隔離書類がありません")
        }

        do {
            try ReceiptImageStore.restoreQuarantinedDocumentFile(
                quarantineFileName: quarantineFileName,
                targetFileName: record.storedFileName
            )
            record.deletionStatus = .active
            record.deletionRequestedAt = nil
            record.deletionReason = nil
            record.overrideApprovedAt = nil
            record.overrideApprovedBy = nil
            record.quarantinedAt = nil
            record.quarantineFileName = nil
            record.updatedAt = Date()
            try documentRepository.saveChanges()
            appendComplianceLog(
                eventType: .documentRestored,
                message: "隔離保管から復元: \(record.documentType.label) (\(record.originalFileName))",
                documentId: record.id,
                transactionId: record.transactionId
            )
            return .restored
        } catch {
            if ReceiptImageStore.documentFileExists(fileName: record.storedFileName) {
                _ = try? ReceiptImageStore.quarantineDocumentFile(fileName: record.storedFileName)
            }
            return .failed(message: "書類の復元に失敗しました")
        }
    }

    private func performDeletion(
        record: PPDocumentRecord,
        reason: String?,
        approvedBy: String? = nil
    ) -> DocumentDeleteAttempt {
        let requiresWarning = record.retentionWarningMessage() != nil
        let documentType = record.documentType
        let originalFileName = record.originalFileName
        let transactionId = record.transactionId
        let documentId = record.id

        do {
            let quarantineFileName = try ReceiptImageStore.quarantineDocumentFile(fileName: record.storedFileName)
            record.deletionStatus = .quarantined
            record.deletionRequestedAt = nil
            record.deletionReason = reason
            record.overrideApprovedAt = requiresWarning ? Date() : nil
            record.overrideApprovedBy = requiresWarning ? approvedBy : nil
            record.quarantinedAt = Date()
            record.quarantineFileName = quarantineFileName
            record.updatedAt = Date()
            try documentRepository.saveChanges()
        } catch {
            if let quarantineFileName = record.quarantineFileName {
                try? ReceiptImageStore.restoreQuarantinedDocumentFile(
                    quarantineFileName: quarantineFileName,
                    targetFileName: record.storedFileName
                )
                record.quarantineFileName = nil
            }
            return .failed(
                message: ((error as? AppError) ?? .invalidInput(message: "書類削除に失敗しました")).localizedDescription
            )
        }

        if requiresWarning {
            appendComplianceLog(
                eventType: .adminOverrideApproved,
                message: "保存期間内の管理者解除を承認: \(documentType.label) / 理由: \(reason ?? "未入力")",
                documentId: documentId,
                transactionId: transactionId
            )
            appendComplianceLog(
                eventType: .documentQuarantined,
                message: "保存期間内の書類を隔離保管へ移動: \(documentType.label) (\(originalFileName))",
                documentId: documentId,
                transactionId: transactionId
            )
        } else {
            appendComplianceLog(
                eventType: .documentDeleted,
                message: "保存期間経過後の書類を隔離保管へ移動: \(documentType.label) (\(originalFileName))",
                documentId: documentId,
                transactionId: transactionId
            )
        }

        return .deleted
    }

    @discardableResult
    func quarantineForMaintenance(
        id: UUID,
        trigger: String
    ) -> DocumentDeleteAttempt {
        guard let record = document(id: id) else {
            return .failed(message: "書類が見つかりません")
        }
        guard record.deletionStatus == .active else {
            return .deleted
        }

        let message = "\(trigger)により書類を隔離保管へ移動: \(record.documentType.label) (\(record.originalFileName))"
        return quarantineWithoutApproval(record: record, reason: trigger, logMessage: message)
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

    private func quarantineWithoutApproval(
        record: PPDocumentRecord,
        reason: String,
        logMessage: String
    ) -> DocumentDeleteAttempt {
        do {
            let quarantineFileName = try ReceiptImageStore.quarantineDocumentFile(fileName: record.storedFileName)
            record.deletionStatus = .quarantined
            record.deletionRequestedAt = nil
            record.deletionReason = reason
            record.overrideApprovedAt = nil
            record.overrideApprovedBy = nil
            record.quarantinedAt = Date()
            record.quarantineFileName = quarantineFileName
            record.updatedAt = Date()
            try documentRepository.saveChanges()
        } catch {
            if let quarantineFileName = record.quarantineFileName {
                try? ReceiptImageStore.restoreQuarantinedDocumentFile(
                    quarantineFileName: quarantineFileName,
                    targetFileName: record.storedFileName
                )
                record.quarantineFileName = nil
            }
            return .failed(message: "書類の隔離保管に失敗しました")
        }

        appendComplianceLog(
            eventType: .documentQuarantined,
            message: logMessage,
            documentId: record.id,
            transactionId: record.transactionId
        )
        return .deleted
    }

    private func cleanupFailedSave(storedFileName: String?, error: AppError) -> Result<PPDocumentRecord, AppError> {
        if let storedFileName {
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
        }
        return .failure(error)
    }
}
