import Foundation

enum DocumentDeleteAttempt {
    case deleted
    case warningRequired(message: String)
    case failed(message: String)
}

@MainActor
protocol DocumentRepository {
    func listDocuments(transactionId: UUID?) throws -> [PPDocumentRecord]
    func document(id: UUID) throws -> PPDocumentRecord?
    func listComplianceLogs(limit: Int) throws -> [PPComplianceLog]
    func insertDocument(_ record: PPDocumentRecord)
    func deleteDocument(_ record: PPDocumentRecord)
    func insertComplianceLog(_ log: PPComplianceLog)
}
