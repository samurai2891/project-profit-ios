import Foundation

enum DocumentDeleteAttempt {
    case deleted
    case adminOverrideRequired(message: String)
    case restored
    case failed(message: String)
}

@MainActor
protocol DocumentRepository {
    func allDocuments() throws -> [PPDocumentRecord]
    func listDocuments(transactionId: UUID?) throws -> [PPDocumentRecord]
    func document(id: UUID) throws -> PPDocumentRecord?
    func listComplianceLogs(limit: Int) throws -> [PPComplianceLog]
    func transactionExists(id: UUID) throws -> Bool
    func listProjects() throws -> [PPProject]
    func currentBusinessId() throws -> UUID?
    func insertDocument(_ record: PPDocumentRecord)
    func deleteDocument(_ record: PPDocumentRecord)
    func insertComplianceLog(_ log: PPComplianceLog)
    func saveChanges() throws
}
