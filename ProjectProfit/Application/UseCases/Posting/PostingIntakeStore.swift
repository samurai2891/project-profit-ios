import CryptoKit
import Foundation
import SwiftData

@MainActor
struct PostingIntakeStore {
    private let modelContext: ModelContext
    private let projectRepository: any ProjectRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase

    init(
        modelContext: ModelContext,
        projectRepository: (any ProjectRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil
    ) {
        self.modelContext = modelContext
        self.projectRepository = projectRepository ?? SwiftDataProjectRepository(modelContext: modelContext)
        self.transactionFormQueryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
    }

    func makeManualCandidate(
        input: ManualPostingCandidateInput,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async throws -> PostingCandidate {
        let snapshot = try transactionFormQueryUseCase.snapshot()
        let posting = try buildApprovedPosting(
            type: input.type,
            amount: input.amount,
            date: input.date,
            categoryId: input.categoryId,
            memo: input.memo,
            recurringId: nil,
            paymentAccountId: input.paymentAccountId,
            transferToAccountId: input.transferToAccountId,
            taxDeductibleRate: input.taxDeductibleRate,
            taxAmount: input.taxAmount,
            taxCodeId: input.taxCodeId,
            taxRate: input.taxRate,
            isTaxIncluded: input.isTaxIncluded,
            taxCategory: input.taxCategory,
            counterpartyId: input.counterpartyId,
            counterparty: input.counterparty,
            source: input.candidateSource,
            snapshot: snapshot
        )

        let normalizedAllocations = calculateRatioAllocations(
            amount: input.amount,
            allocations: input.type == .transfer ? [] : input.allocations
        )
        let candidate = candidateWithProjectAllocations(
            posting.candidate.updated(status: .draft),
            allocations: normalizedAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) }
        )

        do {
            try await postingWorkflowUseCase.saveCandidate(candidate)
            return candidate
        } catch {
            throw AppError.saveFailed(underlying: error)
        }
    }

    func importTransactions(
        csvString: String,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async -> CSVImportResult {
        var successCount = 0
        var errorCount = 0
        var errors: [String] = []
        let formSnapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        var projects = formSnapshot.projects
        let categories = formSnapshot.activeCategories

        for entry in parseCSV(csvString: csvString) {
            let allocations: [(projectId: UUID, ratio: Int)]
            do {
                allocations = try resolvedImportAllocations(
                    for: entry,
                    projects: &projects
                )
            } catch let error as AppError {
                errorCount += 1
                errors.append(error.errorDescription ?? error.localizedDescription)
                continue
            } catch {
                errorCount += 1
                errors.append(error.localizedDescription)
                continue
            }

            if entry.type != .transfer {
                let totalRatio = allocations.reduce(0) { $0 + $1.ratio }
                guard totalRatio == 100 else {
                    errorCount += 1
                    errors.append("配分比率が不正です（合計: \(totalRatio)%）")
                    continue
                }
            }

            let categoryId: String
            switch entry.type {
            case .transfer:
                categoryId = ""
            case .income, .expense:
                let categoryType: CategoryType = entry.type == .income ? .income : .expense
                if let existing = categories.first(where: {
                    $0.name == entry.categoryName && $0.type == categoryType
                }) {
                    categoryId = existing.id
                } else if let fallback = categories.first(where: { $0.name == entry.categoryName }) {
                    categoryId = fallback.id
                } else {
                    errorCount += 1
                    errors.append("カテゴリが見つかりません: \(entry.categoryName)")
                    continue
                }
            }

            do {
                let posting = try buildApprovedPosting(
                    type: entry.type,
                    amount: entry.amount,
                    date: entry.date,
                    categoryId: categoryId,
                    memo: entry.memo,
                    recurringId: nil,
                    paymentAccountId: entry.paymentAccountId,
                    transferToAccountId: entry.type == .transfer ? entry.transferToAccountId : nil,
                    taxDeductibleRate: entry.type == .expense ? entry.taxDeductibleRate : nil,
                    taxAmount: entry.taxAmount,
                    taxCodeId: nil,
                    taxRate: entry.taxRate,
                    isTaxIncluded: entry.isTaxIncluded,
                    taxCategory: entry.taxCategory,
                    counterpartyId: nil,
                    counterparty: entry.counterparty,
                    source: .importFile,
                    snapshot: formSnapshot.replacing(projects: projects)
                )
                let normalizedAllocations = calculateRatioAllocations(
                    amount: entry.amount,
                    allocations: entry.type == .transfer ? [] : allocations
                )
                let candidate = candidateWithProjectAllocations(
                    posting.candidate,
                    allocations: normalizedAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) }
                )
                _ = try await postingWorkflowUseCase.syncApprovedCandidate(
                    candidate,
                    journalId: posting.journalId,
                    entryType: posting.entryType,
                    description: posting.description,
                    approvedAt: posting.approvedAt
                )
                successCount += 1
            } catch {
                errorCount += 1
                errors.append(error.localizedDescription)
            }
        }

        return CSVImportResult(successCount: successCount, errorCount: errorCount, errors: errors)
    }

    private func resolvedImportAllocations(
        for entry: CSVParsedTransaction,
        projects: inout [PPProject]
    ) throws -> [(projectId: UUID, ratio: Int)] {
        guard entry.type == .transfer || !entry.allocations.isEmpty else {
            throw AppError.invalidInput(message: "プロジェクトが見つかりません")
        }

        return try entry.allocations.map { allocation in
            if let existing = projects.first(where: { $0.name == allocation.projectName }) {
                return (projectId: existing.id, ratio: allocation.ratio)
            }

            let created = PPProject(name: allocation.projectName, projectDescription: "")
            projectRepository.insert(created)
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            projects.append(created)
            return (projectId: created.id, ratio: allocation.ratio)
        }
    }

    private func buildApprovedPosting(
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
        taxRate: Int?,
        isTaxIncluded: Bool?,
        taxCategory: TaxCategory?,
        counterpartyId: UUID?,
        counterparty: String?,
        source: CandidateSource,
        snapshot: TransactionFormSnapshot
    ) throws -> CanonicalTransactionPostingBridge.Posting {
        let taxYear = fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)
        guard WorkflowPersistenceSupport.canPostNormalEntry(modelContext: modelContext, year: taxYear) else {
            throw AppError.yearLocked(year: taxYear)
        }
        guard let businessId = snapshot.businessId else {
            throw AppError.invalidInput(message: "事業者プロフィールが未設定のため承認待ち候補を作成できません")
        }

        let safeCategoryId: String
        switch type {
        case .transfer:
            safeCategoryId = categoryId
        case .income, .expense:
            safeCategoryId = categoryId.isEmpty ? Self.defaultCategoryId(for: type) : categoryId
        }

        let explicitTaxCodeId = resolvedExplicitTaxCodeId(
            explicitTaxCodeId: taxCodeId,
            taxCategory: taxCategory,
            taxRate: taxRate
        )
        let resolvedCounterparty = try resolveCounterpartyReference(
            explicitId: counterpartyId,
            rawName: counterparty,
            defaultTaxCodeId: explicitTaxCodeId,
            businessId: businessId
        )

        let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)
        let transactionSnapshot = CanonicalTransactionPostingBridge.TransactionSnapshot(
            id: UUID(),
            type: type,
            amount: amount,
            date: date,
            categoryId: safeCategoryId,
            memo: memo,
            recurringId: recurringId,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            taxAmount: taxAmount,
            taxCodeId: explicitTaxCodeId,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyName: resolvedCounterparty.displayName,
            createdAt: Date(),
            updatedAt: Date(),
            journalEntryId: nil
        )

        guard let posting = bridge.buildApprovedPosting(
            for: transactionSnapshot,
            businessId: businessId,
            counterpartyId: resolvedCounterparty.id,
            source: source,
            categories: snapshot.activeCategories,
            legacyAccounts: snapshot.accounts
        ) else {
            throw AppError.invalidInput(message: "承認待ち候補の勘定科目または税区分を解決できません")
        }

        return posting
    }

    private func resolveCounterpartyReference(
        explicitId: UUID?,
        rawName: String?,
        defaultTaxCodeId: String?,
        businessId: UUID
    ) throws -> (id: UUID?, displayName: String?) {
        if let explicitId,
           let existing = try canonicalCounterparty(id: explicitId) {
            if defaultTaxCodeId != nil, existing.defaultTaxCodeId != defaultTaxCodeId {
                upsertCanonicalCounterparty(existing.updated(defaultTaxCodeId: .some(defaultTaxCodeId)))
            }
            return (existing.id, existing.displayName)
        }

        guard let displayName = normalizedOptionalString(rawName) else {
            return (nil, nil)
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

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func resolvedExplicitTaxCodeId(
        explicitTaxCodeId: String?,
        taxCategory: TaxCategory?,
        taxRate: Int?
    ) -> String? {
        if let explicitTaxCodeId {
            return explicitTaxCodeId
        }
        return TaxCode.resolve(
            legacyCategory: taxCategory,
            taxRate: taxRate
        )?.rawValue
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

    private func candidateWithProjectAllocations(
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

    private static func defaultCategoryId(for type: TransactionType) -> String {
        switch type {
        case .expense, .transfer:
            "cat-other-expense"
        case .income:
            "cat-other-income"
        }
    }
}

private extension TransactionFormSnapshot {
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
