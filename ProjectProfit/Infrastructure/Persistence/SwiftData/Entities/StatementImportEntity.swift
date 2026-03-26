import Foundation
import SwiftData

@Model
final class StatementImportEntity {
    @Attribute(.unique) var importId: UUID
    var businessId: UUID
    var evidenceId: UUID
    var statementKindRaw: String
    var paymentAccountId: String
    var fileSourceRaw: String
    var importedAt: Date
    var originalFileName: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StatementLineEntity.statementImport)
    var lines: [StatementLineEntity]

    init(
        importId: UUID = UUID(),
        businessId: UUID = UUID(),
        evidenceId: UUID = UUID(),
        statementKindRaw: String = StatementKind.bank.rawValue,
        paymentAccountId: String = "",
        fileSourceRaw: String = StatementFileSource.csv.rawValue,
        importedAt: Date = Date(),
        originalFileName: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lines: [StatementLineEntity] = []
    ) {
        self.importId = importId
        self.businessId = businessId
        self.evidenceId = evidenceId
        self.statementKindRaw = statementKindRaw
        self.paymentAccountId = paymentAccountId
        self.fileSourceRaw = fileSourceRaw
        self.importedAt = importedAt
        self.originalFileName = originalFileName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lines = lines
    }
}
