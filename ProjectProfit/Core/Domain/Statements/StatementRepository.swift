import Foundation

protocol StatementRepository: Sendable {
    func findImport(_ id: UUID) async throws -> StatementImportRecord?
    func findImports(businessId: UUID, statementKind: StatementKind?, paymentAccountId: String?) async throws -> [StatementImportRecord]
    func saveImport(_ record: StatementImportRecord) async throws
    func deleteImport(_ id: UUID) async throws

    func findLine(_ id: UUID) async throws -> StatementLineRecord?
    func findLines(
        businessId: UUID,
        statementKind: StatementKind?,
        paymentAccountId: String?,
        matchState: StatementMatchState?,
        startDate: Date?,
        endDate: Date?
    ) async throws -> [StatementLineRecord]
    func findLines(importId: UUID) async throws -> [StatementLineRecord]
    func saveLine(_ record: StatementLineRecord) async throws
    func saveLines(_ records: [StatementLineRecord]) async throws
    func deleteLines(importId: UUID) async throws
}
