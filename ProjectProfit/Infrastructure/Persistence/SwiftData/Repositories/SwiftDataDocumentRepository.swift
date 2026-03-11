import Foundation
import SwiftData

@MainActor
final class SwiftDataDocumentRepository: DocumentRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func listDocuments(transactionId: UUID?) throws -> [PPDocumentRecord] {
        let descriptor = FetchDescriptor<PPDocumentRecord>(
            sortBy: [SortDescriptor(\.issueDate, order: .reverse)]
        )
        let records = try modelContext.fetch(descriptor)
        if let transactionId {
            return records.filter { $0.transactionId == transactionId }
        }
        return records
    }

    func document(id: UUID) throws -> PPDocumentRecord? {
        let predicate = #Predicate<PPDocumentRecord> { $0.id == id }
        let descriptor = FetchDescriptor<PPDocumentRecord>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    func listComplianceLogs(limit: Int) throws -> [PPComplianceLog] {
        let descriptor = FetchDescriptor<PPComplianceLog>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return Array(try modelContext.fetch(descriptor).prefix(max(1, limit)))
    }

    func insertDocument(_ record: PPDocumentRecord) {
        modelContext.insert(record)
    }

    func deleteDocument(_ record: PPDocumentRecord) {
        modelContext.delete(record)
    }

    func insertComplianceLog(_ log: PPComplianceLog) {
        modelContext.insert(log)
    }
}
