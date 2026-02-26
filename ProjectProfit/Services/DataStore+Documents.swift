import SwiftData
import Foundation

enum DocumentDeleteAttempt {
    case deleted
    case warningRequired(message: String)
    case failed(message: String)
}

extension DataStore {
    // MARK: - Document CRUD

    func listDocumentRecords(transactionId: UUID? = nil) -> [PPDocumentRecord] {
        do {
            let descriptor = FetchDescriptor<PPDocumentRecord>(
                sortBy: [SortDescriptor(\.issueDate, order: .reverse)]
            )
            let records = try modelContext.fetch(descriptor)
            if let transactionId {
                return records.filter { $0.transactionId == transactionId }
            }
            return records
        } catch {
            AppLogger.dataStore.error("Failed to fetch document records: \(error.localizedDescription)")
            return []
        }
    }

    func getDocumentRecord(id: UUID) -> PPDocumentRecord? {
        listDocumentRecords().first { $0.id == id }
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
        if let transactionId, getTransaction(id: transactionId) == nil {
            return .failure(.transactionNotFound(id: transactionId))
        }

        do {
            let storedFileName = try ReceiptImageStore.saveDocumentData(fileData, originalFileName: originalFileName)
            let record = PPDocumentRecord(
                transactionId: transactionId,
                documentType: documentType,
                storedFileName: storedFileName,
                originalFileName: originalFileName,
                mimeType: mimeType,
                fileSize: fileData.count,
                contentHash: ReceiptImageStore.sha256Hex(data: fileData),
                issueDate: issueDate,
                note: note
            )
            modelContext.insert(record)
            if save() {
                addComplianceLog(
                    eventType: .documentAdded,
                    message: "書類登録: \(record.documentType.label) (\(record.originalFileName))",
                    documentId: record.id,
                    transactionId: record.transactionId
                )
                return .success(record)
            }
            ReceiptImageStore.deleteDocumentFile(fileName: storedFileName)
            return .failure(lastError ?? .invalidInput(message: "書類の保存に失敗しました"))
        } catch {
            AppLogger.dataStore.error("Failed to save document file: \(error.localizedDescription)")
            return .failure(.invalidInput(message: "書類ファイルの保存に失敗しました"))
        }
    }

    func requestDocumentDeletion(id: UUID) -> DocumentDeleteAttempt {
        guard let record = getDocumentRecord(id: id) else {
            return .failed(message: "書類が見つかりません")
        }

        if let warning = record.retentionWarningMessage() {
            addComplianceLog(
                eventType: .retentionWarningShown,
                message: warning,
                documentId: record.id,
                transactionId: record.transactionId
            )
            return .warningRequired(message: warning)
        }

        return performDocumentDeletion(record: record, reason: nil)
    }

    func confirmDocumentDeletion(id: UUID, reason: String) -> DocumentDeleteAttempt {
        guard let record = getDocumentRecord(id: id) else {
            return .failed(message: "書類が見つかりません")
        }
        return performDocumentDeletion(record: record, reason: reason)
    }

    private func performDocumentDeletion(record: PPDocumentRecord, reason: String?) -> DocumentDeleteAttempt {
        let fileName = record.storedFileName
        let requiresWarning = record.retentionWarningMessage() != nil

        modelContext.delete(record)
        guard save() else {
            return .failed(message: (lastError ?? .invalidInput(message: "書類削除に失敗しました")).localizedDescription)
        }

        ReceiptImageStore.deleteDocumentFile(fileName: fileName)

        if requiresWarning {
            let cleanedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = "保存期間内削除を実行: \(record.documentType.label) / 理由: \(cleanedReason.isEmpty ? "未入力" : cleanedReason)"
            addComplianceLog(
                eventType: .retentionWarningConfirmedDeletion,
                message: message,
                documentId: record.id,
                transactionId: record.transactionId
            )
        } else {
            addComplianceLog(
                eventType: .documentDeleted,
                message: "書類削除: \(record.documentType.label) (\(record.originalFileName))",
                documentId: record.id,
                transactionId: record.transactionId
            )
        }

        return .deleted
    }

    // MARK: - Compliance Logs

    func listComplianceLogs(limit: Int = 200) -> [PPComplianceLog] {
        do {
            let descriptor = FetchDescriptor<PPComplianceLog>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return Array(try modelContext.fetch(descriptor).prefix(max(1, limit)))
        } catch {
            AppLogger.dataStore.error("Failed to fetch compliance logs: \(error.localizedDescription)")
            return []
        }
    }

    func addComplianceLog(
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
        modelContext.insert(log)
        _ = save()
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
