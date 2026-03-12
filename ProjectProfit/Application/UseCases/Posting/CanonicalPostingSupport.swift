import CryptoKit
import Foundation
import SwiftData

struct CanonicalPostingSeed: Sendable {
    let id: UUID
    let type: TransactionType
    let amount: Int
    let date: Date
    let categoryId: String
    let memo: String
    let recurringId: UUID?
    let paymentAccountId: String?
    let transferToAccountId: String?
    let taxDeductibleRate: Int?
    let taxAmount: Int?
    let taxCodeId: String?
    let taxRate: Int?
    let isTaxIncluded: Bool?
    let taxCategory: TaxCategory?
    let receiptImagePath: String?
    let lineItems: [ReceiptLineItem]
    let counterpartyId: UUID?
    let counterpartyName: String?
    let source: CandidateSource
    let createdAt: Date
    let updatedAt: Date
    let journalEntryId: UUID?

    init(
        id: UUID,
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        recurringId: UUID?,
        paymentAccountId: String?,
        transferToAccountId: String?,
        taxDeductibleRate: Int?,
        taxAmount: Int?,
        taxCodeId: String?,
        taxRate: Int? = nil,
        isTaxIncluded: Bool?,
        taxCategory: TaxCategory? = nil,
        receiptImagePath: String?,
        lineItems: [ReceiptLineItem],
        counterpartyId: UUID?,
        counterpartyName: String?,
        source: CandidateSource,
        createdAt: Date,
        updatedAt: Date,
        journalEntryId: UUID?
    ) {
        let resolvedTaxCode = TaxCode.resolve(id: taxCodeId)
            ?? TaxCode.resolve(legacyCategory: taxCategory, taxRate: taxRate)

        self.id = id
        self.type = type
        self.amount = amount
        self.date = date
        self.categoryId = categoryId
        self.memo = memo
        self.recurringId = recurringId
        self.paymentAccountId = paymentAccountId
        self.transferToAccountId = transferToAccountId
        self.taxDeductibleRate = taxDeductibleRate
        self.taxAmount = taxAmount
        self.taxCodeId = resolvedTaxCode?.rawValue
        self.taxRate = resolvedTaxCode?.taxRatePercent
        self.isTaxIncluded = isTaxIncluded
        self.taxCategory = resolvedTaxCode?.legacyCategory
        self.receiptImagePath = receiptImagePath
        self.lineItems = lineItems
        self.counterpartyId = counterpartyId
        self.counterpartyName = counterpartyName
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.journalEntryId = journalEntryId
    }
}

@MainActor
struct CanonicalPostingSupport {
    private let modelContext: ModelContext
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let postingWorkflowUseCase: PostingWorkflowUseCase

    init(
        modelContext: ModelContext,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        postingWorkflowUseCase: PostingWorkflowUseCase? = nil
    ) {
        self.modelContext = modelContext
        self.transactionFormQueryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        self.postingWorkflowUseCase = postingWorkflowUseCase ?? PostingWorkflowUseCase(modelContext: modelContext)
    }

    private var postingEngine: CanonicalPostingEngine {
        CanonicalPostingEngine(modelContext: modelContext)
    }

    func snapshot() throws -> TransactionFormSnapshot {
        try transactionFormQueryUseCase.snapshot()
    }

    func buildApprovedPosting(
        seed: CanonicalPostingSeed,
        snapshot: TransactionFormSnapshot
    ) throws -> CanonicalTransactionPostingBridge.Posting {
        let taxYear = fiscalYear(for: seed.date, startMonth: FiscalYearSettings.startMonth)
        guard WorkflowPersistenceSupport.canPostNormalEntry(modelContext: modelContext, year: taxYear) else {
            throw AppError.yearLocked(year: taxYear)
        }
        guard let businessId = snapshot.businessId else {
            throw AppError.invalidInput(message: "事業者プロフィールが未設定のため承認待ち候補を作成できません")
        }

        let explicitTaxCodeId = seed.taxCodeId
        let resolvedCounterparty = try resolveCounterpartyReference(
            explicitId: seed.counterpartyId,
            rawName: seed.counterpartyName,
            defaultTaxCodeId: explicitTaxCodeId,
            businessId: businessId
        )
        let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)
        let transactionSnapshot = CanonicalTransactionPostingBridge.TransactionSnapshot(
            id: seed.id,
            type: seed.type,
            amount: seed.amount,
            date: seed.date,
            categoryId: safeCategoryId(for: seed.type, categoryId: seed.categoryId),
            memo: seed.memo,
            recurringId: seed.recurringId,
            paymentAccountId: seed.paymentAccountId,
            transferToAccountId: seed.transferToAccountId,
            taxDeductibleRate: seed.taxDeductibleRate,
            taxAmount: seed.taxAmount,
            taxCodeId: explicitTaxCodeId,
            taxRate: seed.taxRate,
            isTaxIncluded: seed.isTaxIncluded,
            taxCategory: seed.taxCategory,
            receiptImagePath: seed.receiptImagePath,
            lineItems: seed.lineItems,
            counterpartyName: resolvedCounterparty.displayName,
            createdAt: seed.createdAt,
            updatedAt: seed.updatedAt,
            journalEntryId: seed.journalEntryId
        )

        guard let posting = bridge.buildApprovedPosting(
            for: transactionSnapshot,
            businessId: businessId,
            counterpartyId: resolvedCounterparty.id,
            source: seed.source,
            categories: snapshot.activeCategories,
            legacyAccounts: snapshot.accounts
        ) else {
            throw AppError.invalidInput(message: "承認待ち候補の勘定科目または税区分を解決できません")
        }

        return posting
    }

    func saveDraftCandidate(
        posting: CanonicalTransactionPostingBridge.Posting,
        allocations: [(projectId: UUID, ratio: Int)]
    ) async throws -> PostingCandidate {
        let candidate = candidateWithProjectAllocations(
            posting.candidate.updated(status: .draft),
            allocations: allocations
        )
        try await postingWorkflowUseCase.saveCandidate(candidate)
        return candidate
    }

    func syncApprovedCandidate(
        posting: CanonicalTransactionPostingBridge.Posting,
        allocations: [(projectId: UUID, ratio: Int)],
        actor: String = "user"
    ) async throws -> CanonicalJournalEntry {
        let candidate = candidateWithProjectAllocations(
            posting.candidate,
            allocations: allocations
        )
        return try await syncApprovedCandidate(
            posting: posting,
            candidate: candidate,
            actor: actor
        )
    }

    func syncApprovedCandidate(
        posting: CanonicalTransactionPostingBridge.Posting,
        allocationAmounts: [Allocation],
        actor: String = "user"
    ) async throws -> CanonicalJournalEntry {
        let candidate = candidateWithProjectAllocations(
            posting.candidate,
            allocationAmounts: allocationAmounts
        )
        return try await syncApprovedCandidate(
            posting: posting,
            candidate: candidate,
            actor: actor
        )
    }

    func persistApprovedPosting(
        posting: CanonicalTransactionPostingBridge.Posting,
        allocations: [(projectId: UUID, ratio: Int)],
        actor: String = "system",
        saveChanges: Bool = false
    ) throws -> CanonicalJournalEntry {
        let candidate = candidateWithProjectAllocations(
            posting.candidate,
            allocations: allocations
        )
        return try persistApprovedPosting(
            posting: posting,
            candidate: candidate,
            actor: actor,
            saveChanges: saveChanges
        )
    }

    func persistApprovedPosting(
        posting: CanonicalTransactionPostingBridge.Posting,
        allocationAmounts: [Allocation],
        actor: String = "system",
        saveChanges: Bool = false
    ) throws -> CanonicalJournalEntry {
        let candidate = candidateWithProjectAllocations(
            posting.candidate,
            allocationAmounts: allocationAmounts
        )
        return try persistApprovedPosting(
            posting: posting,
            candidate: candidate,
            actor: actor,
            saveChanges: saveChanges
        )
    }

    func candidateWithProjectAllocations(
        _ candidate: PostingCandidate,
        allocations: [(projectId: UUID, ratio: Int)]
    ) -> PostingCandidate {
        guard !allocations.isEmpty else {
            return candidate
        }

        let normalizedAllocations = allocations.filter { $0.ratio > 0 }
        guard !normalizedAllocations.isEmpty else {
            return candidate
        }

        let expandedLines = candidate.proposedLines.flatMap { line -> [PostingCandidateLine] in
            if normalizedAllocations.count == 1, let allocation = normalizedAllocations.first {
                return [line.updated(projectAllocationId: .some(allocation.projectId))]
            }

            let lineAmount = NSDecimalNumber(decimal: line.amount).intValue
            let splitAllocations = calculateRatioAllocations(amount: lineAmount, allocations: normalizedAllocations)
            return splitAllocations.compactMap { allocation in
                guard allocation.amount > 0 else {
                    return nil
                }
                return PostingCandidateLine(
                    debitAccountId: line.debitAccountId,
                    creditAccountId: line.creditAccountId,
                    amount: Decimal(allocation.amount),
                    taxCodeId: line.taxCodeId,
                    legalReportLineId: line.legalReportLineId,
                    projectAllocationId: allocation.projectId,
                    memo: line.memo,
                    evidenceLineReferenceId: line.evidenceLineReferenceId,
                    withholdingTaxCodeId: line.withholdingTaxCodeId,
                    withholdingTaxAmount: line.withholdingTaxAmount
                )
            }
        }

        guard !expandedLines.isEmpty else {
            return candidate
        }
        return candidate.updated(proposedLines: expandedLines)
    }

    func candidateWithProjectAllocations(
        _ candidate: PostingCandidate,
        allocationAmounts: [Allocation]
    ) -> PostingCandidate {
        let normalizedAllocations = allocationAmounts.filter { $0.amount > 0 }
        guard !normalizedAllocations.isEmpty else {
            return candidate
        }

        let expandedLines = candidate.proposedLines.flatMap { line -> [PostingCandidateLine] in
            if normalizedAllocations.count == 1, let allocation = normalizedAllocations.first {
                return [line.updated(projectAllocationId: .some(allocation.projectId))]
            }

            let lineAmount = NSDecimalNumber(decimal: line.amount).intValue
            let totalAllocationAmount = normalizedAllocations.reduce(0) { partialResult, allocation in
                partialResult + allocation.amount
            }
            guard lineAmount > 0, totalAllocationAmount > 0 else {
                return []
            }

            var distributedSoFar = 0
            return normalizedAllocations.enumerated().compactMap { index, allocation in
                let splitAmount: Int
                if index == normalizedAllocations.count - 1 {
                    splitAmount = lineAmount - distributedSoFar
                } else {
                    splitAmount = lineAmount * allocation.amount / totalAllocationAmount
                    distributedSoFar += splitAmount
                }

                guard splitAmount > 0 else {
                    return nil
                }

                return PostingCandidateLine(
                    debitAccountId: line.debitAccountId,
                    creditAccountId: line.creditAccountId,
                    amount: Decimal(splitAmount),
                    taxCodeId: line.taxCodeId,
                    legalReportLineId: line.legalReportLineId,
                    projectAllocationId: allocation.projectId,
                    memo: line.memo,
                    evidenceLineReferenceId: line.evidenceLineReferenceId,
                    withholdingTaxCodeId: line.withholdingTaxCodeId,
                    withholdingTaxAmount: line.withholdingTaxAmount
                )
            }
        }

        guard !expandedLines.isEmpty else {
            return candidate
        }
        return candidate.updated(proposedLines: expandedLines)
    }

    func resolveCounterpartyReference(
        explicitId: UUID?,
        rawName: String?,
        defaultTaxCodeId: String? = nil,
        businessId: UUID?
    ) throws -> (id: UUID?, displayName: String?) {
        if let explicitId,
           let existing = try canonicalCounterparty(id: explicitId) {
            if defaultTaxCodeId != nil, existing.defaultTaxCodeId != defaultTaxCodeId {
                upsertCanonicalCounterparty(existing.updated(defaultTaxCodeId: .some(defaultTaxCodeId)))
            }
            return (existing.id, existing.displayName)
        }

        guard let businessId,
              let displayName = normalizedOptionalString(rawName) else {
            return (nil, normalizedOptionalString(rawName))
        }

        let counterparties = try fetchCanonicalCounterparties(businessId: businessId)
        if let exactMatch = counterparties.first(where: {
            $0.displayName.compare(
                displayName,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) == .orderedSame
        }) {
            if defaultTaxCodeId != nil, exactMatch.defaultTaxCodeId != defaultTaxCodeId {
                upsertCanonicalCounterparty(exactMatch.updated(defaultTaxCodeId: .some(defaultTaxCodeId)))
            }
            return (exactMatch.id, exactMatch.displayName)
        }

        let counterparty = Counterparty(
            id: stableCounterpartyId(businessId: businessId, displayName: displayName),
            businessId: businessId,
            displayName: displayName,
            defaultTaxCodeId: defaultTaxCodeId,
            createdAt: Date(),
            updatedAt: Date()
        )
        upsertCanonicalCounterparty(counterparty)
        return (counterparty.id, counterparty.displayName)
    }

    private func syncApprovedCandidate(
        posting: CanonicalTransactionPostingBridge.Posting,
        candidate: PostingCandidate,
        actor: String
    ) async throws -> CanonicalJournalEntry {
        try await postingEngine.persistApprovedCandidateAsync(
            candidate,
            journalId: posting.journalId,
            entryType: posting.entryType,
            description: posting.description,
            approvedAt: posting.approvedAt,
            actor: actor
        )
    }

    private func persistApprovedPosting(
        posting: CanonicalTransactionPostingBridge.Posting,
        candidate: PostingCandidate,
        actor: String,
        saveChanges: Bool
    ) throws -> CanonicalJournalEntry {
        try postingEngine.persistApprovedCandidateSync(
            candidate,
            journalId: posting.journalId,
            entryType: posting.entryType,
            description: posting.description,
            approvedAt: posting.approvedAt,
            actor: actor,
            saveChanges: saveChanges
        )
    }

    private func canonicalCounterparty(id: UUID) throws -> Counterparty? {
        let descriptor = FetchDescriptor<CounterpartyEntity>(
            predicate: #Predicate { $0.counterpartyId == id }
        )
        return try modelContext.fetch(descriptor).first.map(CounterpartyEntityMapper.toDomain)
    }

    private func fetchCanonicalCounterparties(businessId: UUID) throws -> [Counterparty] {
        let descriptor = FetchDescriptor<CounterpartyEntity>(
            predicate: #Predicate { $0.businessId == businessId },
            sortBy: [SortDescriptor(\.displayName)]
        )
        return try modelContext.fetch(descriptor).map(CounterpartyEntityMapper.toDomain)
    }

    private func upsertCanonicalCounterparty(_ counterparty: Counterparty) {
        let descriptor = FetchDescriptor<CounterpartyEntity>(
            predicate: #Predicate { $0.counterpartyId == counterparty.id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            CounterpartyEntityMapper.update(existing, from: counterparty)
        } else {
            modelContext.insert(CounterpartyEntityMapper.toEntity(counterparty))
        }
    }

    private func safeCategoryId(for type: TransactionType, categoryId: String) -> String {
        switch type {
        case .transfer:
            categoryId
        case .income, .expense:
            categoryId.isEmpty ? Self.defaultCategoryId(for: type) : categoryId
        }
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func stableCounterpartyId(businessId: UUID, displayName: String) -> UUID {
        let normalizedName = displayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let seed = "\(businessId.uuidString.lowercased())|\(normalizedName)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    private static func defaultCategoryId(for type: TransactionType) -> String {
        switch type {
        case .expense, .transfer:
            "cat-other-expense"
        case .income:
            "cat-other-income"
        }
    }
}

extension TransactionFormSnapshot {
    func replacing(projects: [PPProject]) -> TransactionFormSnapshot {
        TransactionFormSnapshot(
            businessId: businessId,
            accounts: accounts,
            activeCategories: activeCategories,
            projects: projects,
            counterparties: counterparties,
            defaultPaymentAccountId: defaultPaymentAccountId,
            isLegacyTransactionEditingEnabled: isLegacyTransactionEditingEnabled,
            legacyTransactionMutationDisabledMessage: legacyTransactionMutationDisabledMessage
        )
    }
}
