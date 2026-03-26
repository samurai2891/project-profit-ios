import Foundation
import SwiftData

@MainActor
struct CanonicalTransactionDisplayBuilder {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func allDisplayItems() -> [CanonicalTransactionDisplayItem] {
        let projectsById = Dictionary(uniqueKeysWithValues: fetchProjects().map { ($0.id, $0) })
        let counterpartiesById = Dictionary(
            uniqueKeysWithValues: fetchCounterparties().map { ($0.counterpartyId, $0.displayName) }
        )
        let legacyTransactionsByJournalPairs: [(UUID, PPTransaction)] = fetchLegacyTransactions().compactMap { transaction in
            guard let journalEntryId = transaction.journalEntryId else {
                return nil
            }
            return (journalEntryId, transaction)
        }
        let legacyTransactionsByJournalId = Dictionary(uniqueKeysWithValues: legacyTransactionsByJournalPairs)
        let candidatesById = Dictionary(
            uniqueKeysWithValues: fetchPostingCandidates().map { ($0.id, $0) }
        )
        let canonicalAccountsById = Dictionary(
            uniqueKeysWithValues: fetchCanonicalAccounts().map { ($0.id, $0) }
        )

        return fetchJournalEntries()
            .filter { $0.approvedAt != nil && $0.entryType == .normal }
            .compactMap { journal in
                makeDisplayItem(
                    journal: journal,
                    candidate: journal.sourceCandidateId.flatMap { candidatesById[$0] },
                    legacyTransaction: legacyTransactionsByJournalId[journal.id],
                    canonicalAccountsById: canonicalAccountsById,
                    projectsById: projectsById,
                    counterpartiesById: counterpartiesById
                )
            }
            .sorted {
                if $0.date != $1.date {
                    return $0.date > $1.date
                }
                return $0.id.uuidString > $1.id.uuidString
            }
    }

    private func makeDisplayItem(
        journal: CanonicalJournalEntry,
        candidate: PostingCandidate?,
        legacyTransaction: PPTransaction?,
        canonicalAccountsById: [UUID: CanonicalAccount],
        projectsById: [UUID: PPProject],
        counterpartiesById: [UUID: String]
    ) -> CanonicalTransactionDisplayItem? {
        guard let type = resolveType(
            journal: journal,
            candidate: candidate,
            legacyTransaction: legacyTransaction,
            canonicalAccountsById: canonicalAccountsById
        ) else {
            return nil
        }

        let amount = resolveAmount(
            type: type,
            journal: journal,
            candidate: candidate,
            legacyTransaction: legacyTransaction,
            canonicalAccountsById: canonicalAccountsById
        )
        guard amount > 0 else {
            return nil
        }

        let allocations = resolveProjectAllocations(
            type: type,
            amount: amount,
            journal: journal,
            candidate: candidate,
            legacyTransaction: legacyTransaction,
            canonicalAccountsById: canonicalAccountsById,
            projectsById: projectsById
        )

        let primaryAllocation = allocations.count == 1 ? allocations.first : nil
        let categoryId = candidate?.legacySnapshot?.categoryId
            ?? legacyTransaction?.categoryId
            ?? ""
        let memo = resolveMemo(
            journal: journal,
            candidate: candidate,
            legacyTransaction: legacyTransaction
        )
        let lineItems = candidate?.legacySnapshot?.lineItems ?? legacyTransaction?.lineItems ?? []
        let receiptImagePath = candidate?.legacySnapshot?.receiptImagePath ?? legacyTransaction?.receiptImagePath
        let counterpartyId = candidate?.counterpartyId ?? legacyTransaction?.counterpartyId
        let counterpartyName = candidate?.legacySnapshot?.counterpartyName
            ?? legacyTransaction?.counterparty
            ?? counterpartyId.flatMap { counterpartiesById[$0] }
        let recurringId = candidate?.legacySnapshot?.recurringId ?? legacyTransaction?.recurringId

        return CanonicalTransactionDisplayItem(
            id: journal.id,
            journalId: journal.id,
            sourceCandidateId: journal.sourceCandidateId,
            sourceEvidenceId: journal.sourceEvidenceId,
            legacyTransactionId: legacyTransaction?.id,
            date: journal.journalDate,
            type: type,
            amount: amount,
            projectAmount: primaryAllocation?.amount,
            projectRatio: primaryAllocation?.ratio,
            projectAllocations: allocations,
            categoryId: categoryId,
            memo: memo,
            lineItems: lineItems,
            receiptImagePath: receiptImagePath,
            counterpartyId: counterpartyId,
            counterpartyName: counterpartyName,
            recurringId: recurringId,
            isCanonicalOnly: legacyTransaction == nil,
            canOpenLegacyTransactionDetail: legacyTransaction != nil
        )
    }

    private func resolveType(
        journal: CanonicalJournalEntry,
        candidate: PostingCandidate?,
        legacyTransaction: PPTransaction?,
        canonicalAccountsById: [UUID: CanonicalAccount]
    ) -> TransactionType? {
        if let type = candidate?.legacySnapshot?.type {
            return type
        }
        if let type = legacyTransaction?.type {
            return type
        }

        let hasRevenueCredit = journal.lines.contains { line in
            guard line.creditAmount > 0,
                  let account = canonicalAccountsById[line.accountId]
            else {
                return false
            }
            return account.accountType == .revenue
        }
        if hasRevenueCredit {
            return .income
        }

        let hasExpenseDebit = journal.lines.contains { line in
            guard line.debitAmount > 0,
                  let account = canonicalAccountsById[line.accountId]
            else {
                return false
            }
            return account.accountType == .expense
        }
        if hasExpenseDebit {
            return .expense
        }

        return .transfer
    }

    private func resolveAmount(
        type: TransactionType,
        journal: CanonicalJournalEntry,
        candidate: PostingCandidate?,
        legacyTransaction: PPTransaction?,
        canonicalAccountsById: [UUID: CanonicalAccount]
    ) -> Int {
        let candidateAmount = amountFromCandidate(type: type, candidate: candidate)
        if candidateAmount > 0 {
            return candidateAmount
        }

        if let legacyAmount = legacyTransaction?.amount, legacyAmount > 0 {
            return legacyAmount
        }

        switch type {
        case .income:
            return journal.lines.reduce(0) { partialResult, line in
                guard line.creditAmount > 0,
                      let account = canonicalAccountsById[line.accountId],
                      account.accountType == .revenue
                else {
                    return partialResult
                }
                return partialResult + decimalInt(line.creditAmount)
            }
        case .expense:
            return journal.lines.reduce(0) { partialResult, line in
                guard line.debitAmount > 0,
                      let account = canonicalAccountsById[line.accountId],
                      account.accountType == .expense
                else {
                    return partialResult
                }
                return partialResult + decimalInt(line.debitAmount)
            }
        case .transfer:
            return max(decimalInt(journal.totalDebit), decimalInt(journal.totalCredit))
        }
    }

    private func resolveProjectAllocations(
        type: TransactionType,
        amount: Int,
        journal: CanonicalJournalEntry,
        candidate: PostingCandidate?,
        legacyTransaction: PPTransaction?,
        canonicalAccountsById: [UUID: CanonicalAccount],
        projectsById: [UUID: PPProject]
    ) -> [CanonicalTransactionProjectAllocation] {
        let candidateAllocations = allocationsFromCandidate(
            type: type,
            amount: amount,
            candidate: candidate,
            projectsById: projectsById
        )
        if !candidateAllocations.isEmpty {
            return candidateAllocations
        }

        if let legacyTransaction {
            let legacyAllocations = legacyTransaction.allocations.map { allocation in
                CanonicalTransactionProjectAllocation(
                    projectId: allocation.projectId,
                    projectName: projectsById[allocation.projectId]?.name,
                    amount: allocation.amount,
                    ratio: allocation.ratio
                )
            }
            if !legacyAllocations.isEmpty {
                return legacyAllocations
            }
        }

        let journalAllocations = allocationsFromJournal(
            type: type,
            amount: amount,
            journal: journal,
            canonicalAccountsById: canonicalAccountsById,
            projectsById: projectsById
        )
        return journalAllocations
    }

    private func amountFromCandidate(type: TransactionType, candidate: PostingCandidate?) -> Int {
        guard let candidate else {
            return 0
        }

        let lines: [PostingCandidateLine]
        switch type {
        case .income:
            lines = candidate.proposedLines.filter { $0.creditAccountId != nil }
        case .expense:
            lines = candidate.proposedLines.filter { $0.debitAccountId != nil }
        case .transfer:
            lines = candidate.proposedLines
        }

        return lines.reduce(0) { $0 + decimalInt($1.amount) }
    }

    private func allocationsFromCandidate(
        type: TransactionType,
        amount: Int,
        candidate: PostingCandidate?,
        projectsById: [UUID: PPProject]
    ) -> [CanonicalTransactionProjectAllocation] {
        guard let candidate else {
            return []
        }

        let relevantLines: [PostingCandidateLine]
        switch type {
        case .income:
            relevantLines = candidate.proposedLines.filter { $0.creditAccountId != nil }
        case .expense:
            relevantLines = candidate.proposedLines.filter { $0.debitAccountId != nil }
        case .transfer:
            relevantLines = candidate.proposedLines
        }

        let grouped = Dictionary(grouping: relevantLines.compactMap { line -> (UUID, Int)? in
            guard let projectId = line.projectAllocationId else {
                return nil
            }
            return (projectId, decimalInt(line.amount))
        }, by: \.0)

        return grouped.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { projectId in
            let projectAmount = grouped[projectId]?.reduce(0) { $0 + $1.1 } ?? 0
            guard projectAmount > 0 else {
                return nil
            }
            return CanonicalTransactionProjectAllocation(
                projectId: projectId,
                projectName: projectsById[projectId]?.name,
                amount: projectAmount,
                ratio: derivedRatio(projectAmount: projectAmount, totalAmount: amount)
            )
        }
    }

    private func allocationsFromJournal(
        type: TransactionType,
        amount: Int,
        journal: CanonicalJournalEntry,
        canonicalAccountsById: [UUID: CanonicalAccount],
        projectsById: [UUID: PPProject]
    ) -> [CanonicalTransactionProjectAllocation] {
        let grouped = Dictionary(grouping: journal.lines.compactMap { line -> (UUID, Int)? in
            guard let projectId = line.projectAllocationId else {
                return nil
            }

            switch type {
            case .income:
                guard line.creditAmount > 0,
                      let account = canonicalAccountsById[line.accountId],
                      account.accountType == .revenue
                else {
                    return nil
                }
                return (projectId, decimalInt(line.creditAmount))
            case .expense:
                guard line.debitAmount > 0,
                      let account = canonicalAccountsById[line.accountId],
                      account.accountType == .expense
                else {
                    return nil
                }
                return (projectId, decimalInt(line.debitAmount))
            case .transfer:
                let lineAmount = max(decimalInt(line.debitAmount), decimalInt(line.creditAmount))
                guard lineAmount > 0 else {
                    return nil
                }
                return (projectId, lineAmount)
            }
        }, by: \.0)

        return grouped.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { projectId in
            let projectAmount = grouped[projectId]?.reduce(0) { $0 + $1.1 } ?? 0
            guard projectAmount > 0 else {
                return nil
            }
            return CanonicalTransactionProjectAllocation(
                projectId: projectId,
                projectName: projectsById[projectId]?.name,
                amount: projectAmount,
                ratio: derivedRatio(projectAmount: projectAmount, totalAmount: amount)
            )
        }
    }

    private func resolveMemo(
        journal: CanonicalJournalEntry,
        candidate: PostingCandidate?,
        legacyTransaction: PPTransaction?
    ) -> String {
        let candidateMemo = candidate?.memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let candidateMemo, !candidateMemo.isEmpty {
            return candidateMemo
        }

        let legacyMemo = legacyTransaction?.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        if let legacyMemo, !legacyMemo.isEmpty {
            return legacyMemo
        }

        return journal.description
    }

    private func derivedRatio(projectAmount: Int, totalAmount: Int) -> Int? {
        guard totalAmount > 0 else {
            return nil
        }
        return Int((Double(projectAmount) / Double(totalAmount) * 100.0).rounded())
    }

    private func decimalInt(_ decimal: Decimal) -> Int {
        NSDecimalNumber(decimal: decimal).intValue
    }

    private func fetchProjects() -> [PPProject] {
        let descriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchLegacyTransactions() -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.deletedAt == nil }
    }

    private func fetchPostingCandidates() -> [PostingCandidate] {
        let descriptor = FetchDescriptor<PostingCandidateEntity>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return ((try? modelContext.fetch(descriptor)) ?? []).map(PostingCandidateEntityMapper.toDomain)
    }

    private func fetchCounterparties() -> [CounterpartyEntity] {
        let descriptor = FetchDescriptor<CounterpartyEntity>(sortBy: [SortDescriptor(\.displayName)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchCanonicalAccounts() -> [CanonicalAccount] {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(sortBy: [SortDescriptor(\.displayOrder)])
        return ((try? modelContext.fetch(descriptor)) ?? []).map(CanonicalAccountEntityMapper.toDomain)
    }

    private func fetchJournalEntries() -> [CanonicalJournalEntry] {
        let descriptor = FetchDescriptor<JournalEntryEntity>(sortBy: [SortDescriptor(\.journalDate, order: .reverse)])
        return ((try? modelContext.fetch(descriptor)) ?? []).map(CanonicalJournalEntryEntityMapper.toDomain)
    }
}
