import Foundation
import SwiftData

@Model
final class StatementLineEntity {
    @Attribute(.unique) var lineId: UUID
    var importId: UUID
    var businessId: UUID
    var statementKindRaw: String
    var paymentAccountId: String
    var date: Date
    var entryDescription: String
    var amount: Decimal
    var directionRaw: String
    var counterparty: String?
    var reference: String?
    var memo: String?
    var matchStateRaw: String
    var matchedCandidateId: UUID?
    var matchedJournalId: UUID?
    var suggestedCandidateId: UUID?
    var suggestedJournalId: UUID?
    var matchedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    var statementImport: StatementImportEntity?

    init(
        lineId: UUID = UUID(),
        importId: UUID = UUID(),
        businessId: UUID = UUID(),
        statementKindRaw: String = StatementKind.bank.rawValue,
        paymentAccountId: String = "",
        date: Date = Date(),
        entryDescription: String = "",
        amount: Decimal = .zero,
        directionRaw: String = StatementDirection.outflow.rawValue,
        counterparty: String? = nil,
        reference: String? = nil,
        memo: String? = nil,
        matchStateRaw: String = StatementMatchState.unmatched.rawValue,
        matchedCandidateId: UUID? = nil,
        matchedJournalId: UUID? = nil,
        suggestedCandidateId: UUID? = nil,
        suggestedJournalId: UUID? = nil,
        matchedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        statementImport: StatementImportEntity? = nil
    ) {
        self.lineId = lineId
        self.importId = importId
        self.businessId = businessId
        self.statementKindRaw = statementKindRaw
        self.paymentAccountId = paymentAccountId
        self.date = date
        self.entryDescription = entryDescription
        self.amount = amount
        self.directionRaw = directionRaw
        self.counterparty = counterparty
        self.reference = reference
        self.memo = memo
        self.matchStateRaw = matchStateRaw
        self.matchedCandidateId = matchedCandidateId
        self.matchedJournalId = matchedJournalId
        self.suggestedCandidateId = suggestedCandidateId
        self.suggestedJournalId = suggestedJournalId
        self.matchedAt = matchedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.statementImport = statementImport
    }
}
