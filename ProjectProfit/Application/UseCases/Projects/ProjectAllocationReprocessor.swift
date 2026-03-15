import Foundation
import SwiftData

@MainActor
struct ProjectAllocationReprocessor {
    private let modelContext: ModelContext
    private let projectRepository: any ProjectRepository
    private let recurringRepository: any RecurringRepository
    private let transactionHistoryRepository: any TransactionHistoryRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let postingSupport: CanonicalPostingSupport
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        projectRepository: any ProjectRepository,
        recurringRepository: any RecurringRepository,
        transactionHistoryRepository: any TransactionHistoryRepository,
        transactionFormQueryUseCase: TransactionFormQueryUseCase,
        postingSupport: CanonicalPostingSupport,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.projectRepository = projectRepository
        self.recurringRepository = recurringRepository
        self.transactionHistoryRepository = transactionHistoryRepository
        self.transactionFormQueryUseCase = transactionFormQueryUseCase
        self.postingSupport = postingSupport
        self.calendar = calendar
    }

    func reprocessEqualAllCurrentPeriodTransactions() {
        let today = todayDate()
        let todayComps = calendar.dateComponents([.year, .month], from: today)
        let transactions = allTransactions()
        let recurrings = allRecurringTransactions()
        let projects = allProjects()

        for recurring in recurrings {
            guard recurring.isActive,
                  recurring.allocationMode == .equalAll else {
                continue
            }

            guard let latestTx = transactions
                .filter({ $0.recurringId == recurring.id })
                .sorted(by: { $0.date > $1.date })
                .first else {
                continue
            }
            guard latestTx.isManuallyEdited != true else {
                continue
            }

            let txComps = calendar.dateComponents([.year, .month], from: latestTx.date)
            let isCurrentPeriod: Bool
            if recurring.frequency == .monthly {
                isCurrentPeriod = txComps.year == todayComps.year && txComps.month == todayComps.month
            } else {
                isCurrentPeriod = txComps.year == todayComps.year
            }
            guard isCurrentPeriod else {
                continue
            }

            let activeProjectIds = projects.filter { $0.status == .active && $0.isArchived != true }.map(\.id)
            let completedThisPeriod = projects.filter { project in
                guard project.status == .completed,
                      project.isArchived != true,
                      let completedAt = project.completedAt else {
                    return false
                }
                let compComps = calendar.dateComponents([.year, .month], from: completedAt)
                return compComps.year == txComps.year && compComps.month == txComps.month
            }
            let allEligibleIds = activeProjectIds + completedThisPeriod.map(\.id)
            guard !allEligibleIds.isEmpty else {
                continue
            }

            var newAllocations = calculateEqualSplitAllocations(amount: recurring.amount, projectIds: allEligibleIds)
            if let txYear = txComps.year, let txMonth = txComps.month {
                let totalDays = recurring.frequency == .yearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
                let needsProRata = newAllocations.contains { alloc in
                    guard let project = projects.first(where: { $0.id == alloc.projectId }) else { return false }
                    let activeDays = recurring.frequency == .yearly
                        ? calculateActiveDaysInYear(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear)
                        : calculateActiveDaysInMonth(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear, month: txMonth)
                    return activeDays < totalDays
                }
                if needsProRata {
                    let inputs: [HolisticProRataInput] = newAllocations.map { alloc in
                        let project = projects.first { $0.id == alloc.projectId }
                        let activeDays = recurring.frequency == .yearly
                            ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                            : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                        return HolisticProRataInput(projectId: alloc.projectId, ratio: alloc.ratio, activeDays: activeDays)
                    }
                    newAllocations = calculateHolisticProRata(
                        totalAmount: recurring.amount,
                        totalDays: totalDays,
                        inputs: inputs
                    )
                }
            }

            latestTx.allocations = newAllocations
            latestTx.updatedAt = Date()
        }

        let snapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        guard snapshot.businessId != nil else {
            try? WorkflowPersistenceSupport.save(modelContext: modelContext)
            return
        }

        let recurringJournals = canonicalJournalEntries().filter { $0.entryType == .recurring }
        let candidateIds = Set(recurringJournals.compactMap(\.sourceCandidateId))
        let candidatesById = fetchPostingCandidates(ids: candidateIds)

        for recurring in recurrings {
            guard recurring.isActive,
                  recurring.allocationMode == .equalAll else {
                continue
            }

            guard let latestPosting = recurringJournals
                .compactMap({ journal -> (journal: CanonicalJournalEntry, candidate: PostingCandidate)? in
                    guard let candidateId = journal.sourceCandidateId,
                          let candidate = candidatesById[candidateId],
                          candidate.legacySnapshot?.recurringId == recurring.id else {
                        return nil
                    }
                    return (journal, candidate)
                })
                .sorted(by: { $0.journal.journalDate > $1.journal.journalDate })
                .first else {
                continue
            }

            let txComps = calendar.dateComponents([.year, .month], from: latestPosting.journal.journalDate)
            let isCurrentPeriod: Bool
            if recurring.frequency == .monthly {
                isCurrentPeriod = txComps.year == todayComps.year && txComps.month == todayComps.month
            } else {
                isCurrentPeriod = txComps.year == todayComps.year
            }
            guard isCurrentPeriod else {
                continue
            }

            let activeProjectIds = projects.filter { $0.status == .active && $0.isArchived != true }.map(\.id)
            let completedThisPeriod = projects.filter { project in
                guard project.status == .completed,
                      project.isArchived != true,
                      let completedAt = project.completedAt else {
                    return false
                }
                let compComps = calendar.dateComponents([.year, .month], from: completedAt)
                return compComps.year == txComps.year && compComps.month == txComps.month
            }
            let allEligibleIds = activeProjectIds + completedThisPeriod.map(\.id)
            guard !allEligibleIds.isEmpty else {
                continue
            }

            var newAllocations = calculateEqualSplitAllocations(amount: recurring.amount, projectIds: allEligibleIds)
            let isYearly = recurring.frequency == .yearly
            if let txYear = txComps.year, let txMonth = txComps.month {
                let totalDays = isYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
                let needsProRata = newAllocations.contains { allocation in
                    guard let project = projects.first(where: { $0.id == allocation.projectId }) else { return false }
                    let activeDays = isYearly
                        ? calculateActiveDaysInYear(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear)
                        : calculateActiveDaysInMonth(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear, month: txMonth)
                    return activeDays < totalDays
                }
                if needsProRata {
                    let inputs: [HolisticProRataInput] = newAllocations.map { allocation in
                        let project = projects.first { $0.id == allocation.projectId }
                        let activeDays = isYearly
                            ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                            : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                        return HolisticProRataInput(projectId: allocation.projectId, ratio: allocation.ratio, activeDays: activeDays)
                    }
                    newAllocations = calculateHolisticProRata(
                        totalAmount: recurring.amount,
                        totalDays: totalDays,
                        inputs: inputs
                    )
                }
            }

            do {
                let posting = try postingSupport.buildApprovedPosting(
                    seed: CanonicalPostingSeed(
                        id: latestPosting.candidate.id,
                        type: recurring.type,
                        amount: recurring.amount,
                        date: latestPosting.journal.journalDate,
                        categoryId: recurring.categoryId,
                        memo: latestPosting.journal.description,
                        recurringId: recurring.id,
                        paymentAccountId: recurring.paymentAccountId,
                        transferToAccountId: recurring.transferToAccountId,
                        taxDeductibleRate: recurring.taxDeductibleRate,
                        taxAmount: nil,
                        taxCodeId: nil,
                        isTaxIncluded: nil,
                        receiptImagePath: nil,
                        lineItems: [],
                        counterpartyId: latestPosting.candidate.counterpartyId,
                        counterpartyName: recurring.counterparty,
                        source: .recurring,
                        createdAt: latestPosting.candidate.createdAt,
                        updatedAt: Date(),
                        journalEntryId: latestPosting.journal.id
                    ),
                    snapshot: snapshot
                )
                _ = try postingSupport.persistApprovedPosting(
                    posting: posting,
                    allocations: newAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) },
                    actor: "system"
                )
            } catch {
                continue
            }
        }

        try? WorkflowPersistenceSupport.save(modelContext: modelContext)
    }

    func reverseCompletionAllocations(projectId: UUID) {
        for transaction in allTransactions() {
            guard transaction.allocations.contains(where: { $0.projectId == projectId }) else {
                continue
            }
            transaction.allocations = recalculateAllocationAmounts(amount: transaction.amount, existingAllocations: transaction.allocations)
            transaction.updatedAt = Date()
        }
        try? WorkflowPersistenceSupport.save(modelContext: modelContext)
    }

    func recalculateAllocationsForProject(projectId: UUID) {
        let projects = allProjects()
        guard let project = projects.first(where: { $0.id == projectId }),
              project.startDate != nil || project.effectiveEndDate != nil else {
            return
        }

        let recurrings = allRecurringTransactions()
        for transaction in allTransactions() {
            guard transaction.allocations.contains(where: { $0.projectId == projectId }) else {
                continue
            }
            let isYearly = transaction.recurringId.flatMap { recurringId in
                recurrings.first(where: { $0.id == recurringId })
            }.map { $0.frequency == .yearly } ?? false
            recalculateAllocationsForTransaction(transaction, projects: projects, isYearly: isYearly)
        }

        let snapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        guard snapshot.businessId != nil else {
            try? WorkflowPersistenceSupport.save(modelContext: modelContext)
            return
        }

        let recurringJournals = canonicalJournalEntries().filter { $0.entryType == .recurring }
        let candidateIds = Set(recurringJournals.compactMap(\.sourceCandidateId))
        let candidatesById = fetchPostingCandidates(ids: candidateIds)

        for recurringJournal in recurringJournals {
            guard let candidateId = recurringJournal.sourceCandidateId,
                  let candidate = candidatesById[candidateId],
                  let legacySnapshot = candidate.legacySnapshot,
                  let recurringId = legacySnapshot.recurringId,
                  let recurring = recurrings.first(where: { $0.id == recurringId }),
                  candidate.proposedLines.contains(where: { $0.projectAllocationId == projectId }) else {
                continue
            }

            let isMonthlySpread = recurringJournal.description.hasPrefix("[定期/月次]")
            let candidateAmount = candidate.proposedLines.reduce(0) { partialResult, line in
                switch legacySnapshot.type {
                case .income:
                    guard line.creditAccountId != nil else { return partialResult }
                case .expense:
                    guard line.debitAccountId != nil else { return partialResult }
                case .transfer:
                    return partialResult
                }
                return partialResult + NSDecimalNumber(decimal: line.amount).intValue
            }
            guard let newAllocations = recurringAllocations(
                for: recurring,
                amount: candidateAmount,
                txDate: recurringJournal.journalDate,
                treatAsYearly: recurring.frequency == .yearly && !isMonthlySpread,
                projects: projects
            ) else {
                continue
            }

            do {
                let posting = try postingSupport.buildApprovedPosting(
                    seed: CanonicalPostingSeed(
                        compatibility: candidate.id,
                        type: legacySnapshot.type,
                        amount: candidateAmount,
                        date: recurringJournal.journalDate,
                        categoryId: legacySnapshot.categoryId,
                        memo: recurringJournal.description,
                        recurringId: legacySnapshot.recurringId,
                        paymentAccountId: legacySnapshot.paymentAccountId,
                        transferToAccountId: legacySnapshot.transferToAccountId,
                        taxDeductibleRate: legacySnapshot.taxDeductibleRate,
                        taxAmount: legacySnapshot.taxAmount,
                        taxCodeId: legacySnapshot.taxCodeId,
                        legacyTaxRate: legacySnapshot.taxRate,
                        isTaxIncluded: legacySnapshot.isTaxIncluded,
                        legacyTaxCategory: legacySnapshot.taxCategory,
                        receiptImagePath: legacySnapshot.receiptImagePath,
                        lineItems: legacySnapshot.lineItems,
                        counterpartyId: candidate.counterpartyId,
                        counterpartyName: legacySnapshot.counterpartyName,
                        source: candidate.source,
                        createdAt: candidate.createdAt,
                        updatedAt: Date(),
                        journalEntryId: recurringJournal.id
                    ),
                    snapshot: snapshot
                )
                _ = try postingSupport.persistApprovedPosting(
                    posting: posting,
                    allocationAmounts: newAllocations,
                    actor: "system"
                )
            } catch {
                continue
            }
        }

        try? WorkflowPersistenceSupport.save(modelContext: modelContext)
    }

    func recalculateAllPartialPeriodProjects() {
        let projects = allProjects()
        let partialProjects = projects.filter {
            $0.startDate != nil || ($0.status == .completed && $0.completedAt != nil) || $0.plannedEndDate != nil
        }
        guard !partialProjects.isEmpty else {
            return
        }

        let partialProjectIds = Set(partialProjects.map(\.id))
        let recurrings = allRecurringTransactions()
        var processedIds = Set<UUID>()

        for transaction in allTransactions() {
            guard !processedIds.contains(transaction.id) else {
                continue
            }
            let hasPartialProject = transaction.allocations.contains { partialProjectIds.contains($0.projectId) }
            guard hasPartialProject else {
                continue
            }
            let isYearly = transaction.recurringId.flatMap { recurringId in
                recurrings.first(where: { $0.id == recurringId })
            }.map { $0.frequency == .yearly } ?? false
            recalculateAllocationsForTransaction(transaction, projects: projects, isYearly: isYearly)
            processedIds.insert(transaction.id)
        }

        try? WorkflowPersistenceSupport.save(modelContext: modelContext)
    }

    private func recalculateAllocationsForTransaction(
        _ transaction: PPTransaction,
        projects: [PPProject],
        isYearly: Bool = false
    ) {
        let txComps = calendar.dateComponents([.year, .month], from: transaction.date)
        guard let txYear = txComps.year, let txMonth = txComps.month else {
            return
        }

        let totalDays = isYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
        let inputs: [HolisticProRataInput] = transaction.allocations.map { alloc in
            let project = projects.first { $0.id == alloc.projectId }
            let activeDays: Int
            if isYearly {
                activeDays = calculateActiveDaysInYear(
                    startDate: project?.startDate,
                    completedAt: project?.effectiveEndDate,
                    year: txYear
                )
            } else {
                activeDays = calculateActiveDaysInMonth(
                    startDate: project?.startDate,
                    completedAt: project?.effectiveEndDate,
                    year: txYear,
                    month: txMonth
                )
            }
            return HolisticProRataInput(projectId: alloc.projectId, ratio: alloc.ratio, activeDays: activeDays)
        }

        guard !inputs.allSatisfy({ $0.activeDays >= totalDays }) else {
            return
        }

        transaction.allocations = calculateHolisticProRata(
            totalAmount: transaction.amount,
            totalDays: totalDays,
            inputs: inputs
        )
        transaction.updatedAt = Date()
    }

    private func recurringAllocations(
        for recurring: PPRecurringTransaction,
        amount: Int,
        txDate: Date,
        treatAsYearly: Bool,
        projects: [PPProject]
    ) -> [Allocation]? {
        var resolvedAllocations: [Allocation]

        switch recurring.allocationMode {
        case .equalAll:
            let activeProjectIds = projects.filter { $0.status == .active && $0.isArchived != true }.map(\.id)
            let completedInPeriod = projects.filter { project in
                guard project.status == .completed,
                      project.isArchived != true,
                      let completedAt = project.completedAt else {
                    return false
                }
                let completedComponents = calendar.dateComponents([.year, .month], from: completedAt)
                let txComponents = calendar.dateComponents([.year, .month], from: txDate)
                return completedComponents.year == txComponents.year && completedComponents.month == txComponents.month
            }
            let projectIds = activeProjectIds + completedInPeriod.map(\.id)
            guard !projectIds.isEmpty else { return nil }
            resolvedAllocations = calculateEqualSplitAllocations(amount: amount, projectIds: projectIds)
        case .manual:
            resolvedAllocations = recalculateAllocationAmounts(amount: amount, existingAllocations: recurring.allocations)
        }

        let txComponents = calendar.dateComponents([.year, .month], from: txDate)
        guard let txYear = txComponents.year, let txMonth = txComponents.month else {
            return resolvedAllocations
        }

        let totalDays = treatAsYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
        let needsProRata: Bool
        switch recurring.allocationMode {
        case .equalAll:
            needsProRata = resolvedAllocations.contains { allocation in
                guard let project = projects.first(where: { $0.id == allocation.projectId }) else {
                    return false
                }
                let activeDays = treatAsYearly
                    ? calculateActiveDaysInYear(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear)
                    : calculateActiveDaysInMonth(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear, month: txMonth)
                return activeDays < totalDays
            }
        case .manual:
            needsProRata = recurring.allocations.contains { allocation in
                guard let project = projects.first(where: { $0.id == allocation.projectId }) else {
                    return false
                }
                return project.startDate != nil || project.effectiveEndDate != nil
            }
        }

        guard needsProRata else {
            return resolvedAllocations
        }

        let inputs: [HolisticProRataInput]
        switch recurring.allocationMode {
        case .equalAll:
            inputs = resolvedAllocations.map { allocation in
                let project = projects.first { $0.id == allocation.projectId }
                let activeDays = treatAsYearly
                    ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                    : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                return HolisticProRataInput(projectId: allocation.projectId, ratio: allocation.ratio, activeDays: activeDays)
            }
        case .manual:
            inputs = recurring.allocations.map { allocation in
                let project = projects.first { $0.id == allocation.projectId }
                let activeDays = treatAsYearly
                    ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                    : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                return HolisticProRataInput(projectId: allocation.projectId, ratio: allocation.ratio, activeDays: activeDays)
            }
        }

        return calculateHolisticProRata(
            totalAmount: amount,
            totalDays: totalDays,
            inputs: inputs
        )
    }

    private func allTransactions() -> [PPTransaction] {
        (try? transactionHistoryRepository.allTransactions()) ?? []
    }

    private func allRecurringTransactions() -> [PPRecurringTransaction] {
        (try? recurringRepository.allRecurringTransactions()) ?? []
    }

    private func allProjects() -> [PPProject] {
        (try? projectRepository.allProjects()) ?? []
    }

    private func canonicalJournalEntries() -> [CanonicalJournalEntry] {
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            sortBy: [
                SortDescriptor(\.journalDate, order: .reverse),
                SortDescriptor(\.voucherNo, order: .reverse)
            ]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(CanonicalJournalEntryEntityMapper.toDomain)
    }

    private func fetchPostingCandidates(ids: Set<UUID>) -> [UUID: PostingCandidate] {
        guard !ids.isEmpty else {
            return [:]
        }
        let descriptor = FetchDescriptor<PostingCandidateEntity>()
        let candidates = ((try? modelContext.fetch(descriptor)) ?? [])
            .map(PostingCandidateEntityMapper.toDomain)
            .filter { ids.contains($0.id) }
        return Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
    }
}
