import Foundation
import SwiftData

@MainActor
struct StatementMatchService {
    private let modelContext: ModelContext
    private let statementRepository: any StatementRepository
    private let postingWorkflowUseCase: PostingWorkflowUseCase
    private let chartOfAccountsRepository: any ChartOfAccountsRepository
    private let counterpartyUseCase: CounterpartyMasterUseCase

    init(
        modelContext: ModelContext,
        statementRepository: (any StatementRepository)? = nil,
        postingWorkflowUseCase: PostingWorkflowUseCase? = nil,
        chartOfAccountsRepository: (any ChartOfAccountsRepository)? = nil,
        counterpartyUseCase: CounterpartyMasterUseCase? = nil
    ) {
        self.modelContext = modelContext
        self.statementRepository = statementRepository ?? SwiftDataStatementRepository(modelContext: modelContext)
        self.postingWorkflowUseCase = postingWorkflowUseCase ?? PostingWorkflowUseCase(modelContext: modelContext)
        self.chartOfAccountsRepository = chartOfAccountsRepository ?? SwiftDataChartOfAccountsRepository(modelContext: modelContext)
        self.counterpartyUseCase = counterpartyUseCase ?? CounterpartyMasterUseCase(modelContext: modelContext)
    }

    func refreshSuggestions(for lines: [StatementLineRecord]) async throws -> [StatementLineRecord] {
        var updatedLines: [StatementLineRecord] = []
        for line in lines {
            updatedLines.append(try await refreshSuggestions(for: line))
        }
        try await statementRepository.saveLines(updatedLines)
        return updatedLines
    }

    func refreshSuggestions(for line: StatementLineRecord) async throws -> StatementLineRecord {
        let candidates = try await candidateOptions(for: line)
        let journals = try await journalOptions(for: line)
        return line.updated(
            suggestedCandidateId: .some(candidates.first?.id),
            suggestedJournalId: .some(journals.first?.id)
        )
    }

    func candidateOptions(for line: StatementLineRecord) async throws -> [PostingCandidate] {
        guard let accountId = try await canonicalPaymentAccountId(for: line) else {
            return []
        }
        let candidates = try await postingWorkflowUseCase.pendingCandidates(businessId: line.businessId)
        let counterparties = try await counterpartiesById(businessId: line.businessId)
        return candidates
            .filter { candidate in
                abs(daysBetween(candidate.candidateDate, line.date)) <= 7
                    && candidate.proposedLines.contains(where: { matches(candidateLine: $0, accountId: accountId, line: line) })
            }
            .sorted { lhs, rhs in
                compare(
                    lhsDate: lhs.candidateDate,
                    rhsDate: rhs.candidateDate,
                    lhsText: candidateSearchText(lhs, counterparties: counterparties),
                    rhsText: candidateSearchText(rhs, counterparties: counterparties),
                    line: line,
                    lhsUpdatedAt: lhs.updatedAt,
                    rhsUpdatedAt: rhs.updatedAt
                )
            }
    }

    func journalOptions(for line: StatementLineRecord) async throws -> [CanonicalJournalEntry] {
        guard let accountId = try await canonicalPaymentAccountId(for: line) else {
            return []
        }

        let years = Set([
            fiscalYear(for: line.date, startMonth: FiscalYearSettings.startMonth),
            fiscalYear(for: Calendar.current.date(byAdding: .day, value: -7, to: line.date) ?? line.date, startMonth: FiscalYearSettings.startMonth),
            fiscalYear(for: Calendar.current.date(byAdding: .day, value: 7, to: line.date) ?? line.date, startMonth: FiscalYearSettings.startMonth),
        ])
        var journals: [CanonicalJournalEntry] = []
        for year in years {
            journals += try await postingWorkflowUseCase.journals(businessId: line.businessId, taxYear: year)
        }
        let uniqueJournals = Dictionary(uniqueKeysWithValues: journals.map { ($0.id, $0) }).values
        return uniqueJournals
            .filter { journal in
                abs(daysBetween(journal.journalDate, line.date)) <= 7
                    && journal.lines.contains(where: { matches(journalLine: $0, accountId: accountId, line: line) })
            }
            .sorted { lhs, rhs in
                compare(
                    lhsDate: lhs.journalDate,
                    rhsDate: rhs.journalDate,
                    lhsText: lhs.description,
                    rhsText: rhs.description,
                    line: line,
                    lhsUpdatedAt: lhs.updatedAt,
                    rhsUpdatedAt: rhs.updatedAt
                )
            }
    }

    func matchCandidate(lineId: UUID, candidateId: UUID) async throws -> StatementLineRecord {
        guard let line = try await statementRepository.findLine(lineId) else {
            throw CanonicalRepositoryError.recordNotFound("StatementLine", lineId)
        }
        let updated = line.updated(
            matchState: .candidateMatched,
            matchedCandidateId: .some(candidateId),
            matchedJournalId: .some(nil),
            matchedAt: .some(Date())
        )
        try await statementRepository.saveLine(updated)
        return updated
    }

    func linkCreatedCandidate(lineId: UUID, candidateId: UUID) async throws -> StatementLineRecord {
        try await matchCandidate(lineId: lineId, candidateId: candidateId)
    }

    func matchJournal(lineId: UUID, journalId: UUID) async throws -> StatementLineRecord {
        guard let line = try await statementRepository.findLine(lineId) else {
            throw CanonicalRepositoryError.recordNotFound("StatementLine", lineId)
        }
        let updated = line.updated(
            matchState: .journalMatched,
            matchedCandidateId: .some(nil),
            matchedJournalId: .some(journalId),
            matchedAt: .some(Date())
        )
        try await statementRepository.saveLine(updated)
        return updated
    }

    func clearMatch(lineId: UUID) async throws -> StatementLineRecord {
        guard let line = try await statementRepository.findLine(lineId) else {
            throw CanonicalRepositoryError.recordNotFound("StatementLine", lineId)
        }
        let refreshed = try await refreshSuggestions(for: line.updated(
            matchState: .unmatched,
            matchedCandidateId: .some(nil),
            matchedJournalId: .some(nil),
            matchedAt: .some(nil)
        ))
        try await statementRepository.saveLine(refreshed)
        return refreshed
    }

    func promoteCandidateMatches(businessId: UUID) async throws {
        let lines = try await statementRepository.findLines(
            businessId: businessId,
            statementKind: nil,
            paymentAccountId: nil,
            matchState: .candidateMatched,
            startDate: nil,
            endDate: nil
        )
        guard !lines.isEmpty else { return }

        let years = Set(lines.map { fiscalYear(for: $0.date, startMonth: FiscalYearSettings.startMonth) })
        var journals: [CanonicalJournalEntry] = []
        for year in years {
            journals += try await postingWorkflowUseCase.journals(businessId: businessId, taxYear: year)
        }
        let journalByCandidateId: [UUID: CanonicalJournalEntry] = Dictionary(uniqueKeysWithValues: journals.compactMap { journal in
            guard let sourceCandidateId = journal.sourceCandidateId else { return nil }
            return (sourceCandidateId, journal)
        })

        let updatedLines = lines.compactMap { line -> StatementLineRecord? in
            guard let matchedCandidateId = line.matchedCandidateId,
                  let journal = journalByCandidateId[matchedCandidateId] else {
                return nil
            }
            return line.updated(
                matchState: .journalMatched,
                matchedJournalId: .some(journal.id),
                matchedAt: .some(Date())
            )
        }
        try await statementRepository.saveLines(updatedLines)
    }

    private func canonicalPaymentAccountId(for line: StatementLineRecord) async throws -> UUID? {
        let account = try await chartOfAccountsRepository.findByLegacyId(
            businessId: line.businessId,
            legacyAccountId: line.paymentAccountId
        )
        return account?.id
    }

    private func matches(candidateLine: PostingCandidateLine, accountId: UUID, line: StatementLineRecord) -> Bool {
        let amount = NSDecimalNumber(decimal: candidateLine.amount).decimalValue
        guard amount == line.amount else { return false }
        switch line.direction {
        case .inflow:
            return candidateLine.debitAccountId == accountId
        case .outflow:
            return candidateLine.creditAccountId == accountId
        }
    }

    private func matches(journalLine: JournalLine, accountId: UUID, line: StatementLineRecord) -> Bool {
        guard journalLine.accountId == accountId else { return false }
        let amount = line.amount
        switch line.direction {
        case .inflow:
            return journalLine.debitAmount == amount
        case .outflow:
            return journalLine.creditAmount == amount
        }
    }

    private func candidateSearchText(
        _ candidate: PostingCandidate,
        counterparties: [UUID: Counterparty]
    ) -> String {
        let counterparty = candidate.counterpartyId.flatMap { counterparties[$0]?.displayName } ?? ""
        return [candidate.memo, counterparty].compactMap { $0 }.joined(separator: " ")
    }

    private func counterpartiesById(businessId: UUID) async throws -> [UUID: Counterparty] {
        let counterparties = try await counterpartyUseCase.loadCounterparties(businessId: businessId)
        return Dictionary(uniqueKeysWithValues: counterparties.map { ($0.id, $0) })
    }

    private func compare(
        lhsDate: Date,
        rhsDate: Date,
        lhsText: String,
        rhsText: String,
        line: StatementLineRecord,
        lhsUpdatedAt: Date,
        rhsUpdatedAt: Date
    ) -> Bool {
        let lhsDayDelta = abs(daysBetween(lhsDate, line.date))
        let rhsDayDelta = abs(daysBetween(rhsDate, line.date))
        if lhsDayDelta != rhsDayDelta {
            return lhsDayDelta < rhsDayDelta
        }

        let lhsOverlap = tokenOverlapScore(line: line, candidateText: lhsText)
        let rhsOverlap = tokenOverlapScore(line: line, candidateText: rhsText)
        if lhsOverlap != rhsOverlap {
            return lhsOverlap > rhsOverlap
        }

        return lhsUpdatedAt > rhsUpdatedAt
    }

    private func tokenOverlapScore(line: StatementLineRecord, candidateText: String) -> Int {
        let source = Set(tokens(from: [line.description, line.counterparty, line.reference, line.memo].compactMap { $0 }.joined(separator: " ")))
        let target = Set(tokens(from: candidateText))
        return source.intersection(target).count
    }

    private func tokens(from text: String) -> [String] {
        let normalized = SearchIndexNormalizer.normalizeText(text)
        guard !normalized.isEmpty else { return [] }
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let splitTokens = normalized
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        if splitTokens.isEmpty {
            return [normalized]
        }
        return splitTokens + [normalized]
    }

    private func daysBetween(_ lhs: Date, _ rhs: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lhs), to: Calendar.current.startOfDay(for: rhs)).day ?? 0
    }
}
