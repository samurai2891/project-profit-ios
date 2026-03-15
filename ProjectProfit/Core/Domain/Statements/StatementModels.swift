import Foundation

enum StatementKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case bank
    case card

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bank:
            return "銀行"
        case .card:
            return "カード"
        }
    }
}

enum StatementFileSource: String, Codable, Sendable, CaseIterable {
    case csv
    case pdf
}

enum StatementDirection: String, Codable, Sendable, CaseIterable {
    case inflow
    case outflow

    var displayName: String {
        switch self {
        case .inflow:
            return "入金"
        case .outflow:
            return "出金"
        }
    }
}

enum StatementMatchState: String, Codable, Sendable, CaseIterable, Identifiable {
    case unmatched
    case candidateMatched
    case journalMatched

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unmatched:
            return "未照合"
        case .candidateMatched:
            return "候補一致"
        case .journalMatched:
            return "確定一致"
        }
    }
}

struct StatementImportRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let evidenceId: UUID
    let statementKind: StatementKind
    let paymentAccountId: String
    let fileSource: StatementFileSource
    let importedAt: Date
    let originalFileName: String
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        businessId: UUID,
        evidenceId: UUID,
        statementKind: StatementKind,
        paymentAccountId: String,
        fileSource: StatementFileSource,
        importedAt: Date = Date(),
        originalFileName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.evidenceId = evidenceId
        self.statementKind = statementKind
        self.paymentAccountId = paymentAccountId
        self.fileSource = fileSource
        self.importedAt = importedAt
        self.originalFileName = originalFileName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct StatementLineRecord: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let importId: UUID
    let businessId: UUID
    let statementKind: StatementKind
    let paymentAccountId: String
    let date: Date
    let description: String
    let amount: Decimal
    let direction: StatementDirection
    let counterparty: String?
    let reference: String?
    let memo: String?
    let matchState: StatementMatchState
    let matchedCandidateId: UUID?
    let matchedJournalId: UUID?
    let suggestedCandidateId: UUID?
    let suggestedJournalId: UUID?
    let matchedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        importId: UUID,
        businessId: UUID,
        statementKind: StatementKind,
        paymentAccountId: String,
        date: Date,
        description: String,
        amount: Decimal,
        direction: StatementDirection,
        counterparty: String? = nil,
        reference: String? = nil,
        memo: String? = nil,
        matchState: StatementMatchState = .unmatched,
        matchedCandidateId: UUID? = nil,
        matchedJournalId: UUID? = nil,
        suggestedCandidateId: UUID? = nil,
        suggestedJournalId: UUID? = nil,
        matchedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.importId = importId
        self.businessId = businessId
        self.statementKind = statementKind
        self.paymentAccountId = paymentAccountId
        self.date = date
        self.description = description
        self.amount = amount
        self.direction = direction
        self.counterparty = counterparty
        self.reference = reference
        self.memo = memo
        self.matchState = matchState
        self.matchedCandidateId = matchedCandidateId
        self.matchedJournalId = matchedJournalId
        self.suggestedCandidateId = suggestedCandidateId
        self.suggestedJournalId = suggestedJournalId
        self.matchedAt = matchedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func updated(
        matchState: StatementMatchState? = nil,
        matchedCandidateId: UUID?? = nil,
        matchedJournalId: UUID?? = nil,
        suggestedCandidateId: UUID?? = nil,
        suggestedJournalId: UUID?? = nil,
        matchedAt: Date?? = nil
    ) -> StatementLineRecord {
        StatementLineRecord(
            id: id,
            importId: importId,
            businessId: businessId,
            statementKind: statementKind,
            paymentAccountId: paymentAccountId,
            date: date,
            description: description,
            amount: amount,
            direction: direction,
            counterparty: counterparty,
            reference: reference,
            memo: memo,
            matchState: matchState ?? self.matchState,
            matchedCandidateId: matchedCandidateId ?? self.matchedCandidateId,
            matchedJournalId: matchedJournalId ?? self.matchedJournalId,
            suggestedCandidateId: suggestedCandidateId ?? self.suggestedCandidateId,
            suggestedJournalId: suggestedJournalId ?? self.suggestedJournalId,
            matchedAt: matchedAt ?? self.matchedAt,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

struct StatementLineDraft: Sendable, Equatable {
    let date: Date
    let description: String
    let amount: Decimal
    let direction: StatementDirection
    let counterparty: String?
    let reference: String?
    let memo: String?
}

struct StatementImportRequest: Sendable, Equatable {
    let fileData: Data
    let originalFileName: String
    let mimeType: String
    let statementKind: StatementKind
    let paymentAccountId: String
}

struct StatementImportPreview: Equatable {
    let fileSource: StatementFileSource
    let parsedLineCount: Int
    let sampleLines: [String]
    let lineErrors: [CSVImportLineError]
}

struct StatementImportResult: Equatable {
    let importRecord: StatementImportRecord
    let evidenceId: UUID
    let lineCount: Int
    let lineErrors: [CSVImportLineError]

    var errorCount: Int { lineErrors.count }
}

struct StatementReconciliationFilter: Sendable, Equatable {
    var statementKind: StatementKind?
    var paymentAccountId: String?
    var matchState: StatementMatchState?
    var startDate: Date?
    var endDate: Date?
}

struct StatementMatchSuggestion: Sendable, Equatable {
    let candidateId: UUID?
    let journalId: UUID?
}

struct StatementReconciliationSnapshot: Equatable {
    let imports: [StatementImportRecord]
    let lines: [StatementLineRecord]
    let availablePaymentAccounts: [PPAccount]
    let unmatchedCount: Int
}

struct StatementLinePrefill: Sendable, Equatable {
    let type: TransactionType
    let amount: Int
    let date: Date
    let memo: String
    let counterparty: String
    let paymentAccountId: String

    init?(line: StatementLineRecord) {
        let amountNumber = NSDecimalNumber(decimal: line.amount)
        let amount = amountNumber.intValue
        guard amount > 0 else {
            return nil
        }

        self.type = line.direction == .inflow ? .income : .expense
        self.amount = amount
        self.date = line.date
        self.memo = line.memo ?? line.description
        self.counterparty = line.counterparty ?? ""
        self.paymentAccountId = line.paymentAccountId
    }
}
