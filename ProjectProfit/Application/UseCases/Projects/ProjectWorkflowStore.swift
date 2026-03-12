import Foundation
import SwiftData

@MainActor
struct ProjectWorkflowStore {
    private let modelContext: ModelContext
    private let projectRepository: any ProjectRepository
    private let recurringRepository: any RecurringRepository
    private let transactionHistoryRepository: any TransactionHistoryRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        projectRepository: any ProjectRepository,
        recurringRepository: (any RecurringRepository)? = nil,
        transactionHistoryRepository: (any TransactionHistoryRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.projectRepository = projectRepository
        self.recurringRepository = recurringRepository ?? SwiftDataRecurringRepository(modelContext: modelContext)
        self.transactionHistoryRepository = transactionHistoryRepository ?? SwiftDataTransactionHistoryRepository(modelContext: modelContext)
        self.transactionFormQueryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        self.calendar = calendar
    }

    @discardableResult
    func createProject(input: ProjectUpsertInput) -> PPProject {
        let project = PPProject(
            name: input.name,
            projectDescription: input.description,
            status: input.status,
            startDate: input.startDate,
            completedAt: normalizedCompletedAt(
                startDate: input.startDate,
                completedAt: input.completedAt,
                status: input.status
            ),
            plannedEndDate: normalizedPlannedEndDate(
                startDate: input.startDate,
                plannedEndDate: input.plannedEndDate
            )
        )
        projectRepository.insert(project)

        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            reprocessEqualAllCurrentPeriodTransactions()
        } catch {
            modelContext.rollback()
        }

        return project
    }

    func updateProject(id: UUID, input: ProjectUpsertInput) {
        let project: PPProject
        do {
            guard let fetched = try projectRepository.project(id: id) else {
                return
            }
            project = fetched
        } catch {
            return
        }

        let previousStatus = project.status
        let previousCompletedAt = project.completedAt
        let previousStartDate = project.startDate
        let previousPlannedEndDate = project.plannedEndDate

        project.name = input.name
        project.projectDescription = input.description
        project.status = input.status
        project.startDate = input.startDate
        project.completedAt = normalizedCompletedAt(
            startDate: input.startDate,
            completedAt: input.completedAt,
            status: input.status
        )
        project.plannedEndDate = normalizedPlannedEndDate(
            startDate: input.startDate,
            plannedEndDate: input.plannedEndDate
        )
        project.updatedAt = Date()

        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
        } catch {
            modelContext.rollback()
            return
        }

        let completedAtChanged = project.completedAt != previousCompletedAt
        let startDateChanged = project.startDate != previousStartDate
        let plannedEndDateChanged = project.plannedEndDate != previousPlannedEndDate
        let statusChangedAwayFromCompleted = previousStatus == .completed && project.status != .completed

        if completedAtChanged || startDateChanged || plannedEndDateChanged {
            if project.startDate != nil || project.effectiveEndDate != nil {
                recalculateAllocationsForProject(projectId: id)
            } else if statusChangedAwayFromCompleted {
                reverseCompletionAllocations(projectId: id)
                recalculateAllPartialPeriodProjects()
            } else if previousStartDate != nil || previousCompletedAt != nil || previousPlannedEndDate != nil {
                reverseCompletionAllocations(projectId: id)
                recalculateAllPartialPeriodProjects()
            }
        }
    }

    func deleteProject(id: UUID) {
        guard (try? projectRepository.project(id: id)) != nil else {
            return
        }

        if projectHasHistoricalReferences(id) {
            archiveProjects(ids: [id])
        } else {
            hardDeleteProjects(ids: [id])
        }
    }

    func deleteProjects(ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        var idsToArchive = Set<UUID>()
        var idsToHardDelete = Set<UUID>()

        for id in ids {
            if projectHasHistoricalReferences(id) {
                idsToArchive.insert(id)
            } else {
                idsToHardDelete.insert(id)
            }
        }

        if !idsToArchive.isEmpty {
            archiveProjects(ids: idsToArchive)
        }
        if !idsToHardDelete.isEmpty {
            hardDeleteProjects(ids: idsToHardDelete)
        }
    }

    private func archiveProjects(ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        let now = Date()
        let archivedProjects = (try? projectRepository.projects(ids: ids)) ?? []

        for project in archivedProjects {
            project.isArchived = true
            project.updatedAt = now
        }

        let transactions = allTransactions()
        let recurrings = allRecurringTransactions()

        for transaction in transactions {
            guard transaction.isManuallyEdited == true,
                  transaction.allocations.contains(where: { ids.contains($0.projectId) }),
                  let recurringId = transaction.recurringId,
                  let recurring = recurrings.first(where: { $0.id == recurringId }),
                  recurring.allocationMode == .equalAll
            else {
                continue
            }
            transaction.isManuallyEdited = nil
        }

        for recurring in recurrings {
            let filtered = recurring.allocations.filter { !ids.contains($0.projectId) }
            if filtered.count != recurring.allocations.count {
                if filtered.isEmpty && recurring.allocationMode == .manual {
                    for transaction in transactions where transaction.recurringId == recurring.id {
                        transaction.recurringId = nil
                        transaction.updatedAt = now
                    }
                    recurringRepository.delete(recurring)
                } else if !filtered.isEmpty {
                    recurring.allocations = redistributeAllocations(
                        totalAmount: recurring.amount,
                        remainingAllocations: filtered
                    )
                }
            }
        }

        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            reprocessEqualAllCurrentPeriodTransactions()
        } catch {
            modelContext.rollback()
        }
    }

    private func hardDeleteProjects(ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        var imagesToDelete: [String] = []
        let recurrings = allRecurringTransactions()

        for recurring in recurrings {
            let filtered = recurring.allocations.filter { !ids.contains($0.projectId) }
            if filtered.count != recurring.allocations.count {
                if filtered.isEmpty {
                    if let imagePath = recurring.receiptImagePath {
                        imagesToDelete.append(imagePath)
                    }
                    recurringRepository.delete(recurring)
                } else {
                    recurring.allocations = redistributeAllocations(
                        totalAmount: recurring.amount,
                        remainingAllocations: filtered
                    )
                }
            }
        }

        let projects = (try? projectRepository.projects(ids: ids)) ?? []
        for project in projects {
            projectRepository.delete(project)
        }

        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            for imagePath in imagesToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
            reprocessEqualAllCurrentPeriodTransactions()
        } catch {
            modelContext.rollback()
        }
    }

    private func projectHasHistoricalReferences(_ id: UUID) -> Bool {
        if allTransactions().contains(where: { transaction in
            transaction.allocations.contains { $0.projectId == id }
        }) {
            return true
        }

        return canonicalJournalEntries().contains { journal in
            journal.lines.contains { $0.projectAllocationId == id }
        }
    }

    private func reprocessEqualAllCurrentPeriodTransactions() {
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
        if let businessId = snapshot.businessId {
            let recurringJournals = canonicalJournalEntries().filter { $0.entryType == .recurring }
            let candidateIds = Set(recurringJournals.compactMap(\.sourceCandidateId))
            let candidatesById = fetchPostingCandidates(ids: candidateIds)
            let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)

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

                let updatedSnapshot = CanonicalTransactionPostingBridge.TransactionSnapshot(
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
                    taxRate: nil,
                    isTaxIncluded: nil,
                    taxCategory: nil,
                    counterpartyName: recurring.counterparty,
                    createdAt: latestPosting.candidate.createdAt,
                    updatedAt: Date(),
                    journalEntryId: latestPosting.journal.id
                )
                guard let posting = bridge.buildApprovedPosting(
                    for: updatedSnapshot,
                    businessId: businessId,
                    counterpartyId: latestPosting.candidate.counterpartyId,
                    source: .recurring,
                    categories: snapshot.activeCategories,
                    legacyAccounts: snapshot.accounts
                ) else {
                    continue
                }

                do {
                    _ = try saveApprovedPostingSynchronously(
                        posting,
                        allocations: newAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) },
                        actor: "system"
                    )
                } catch {
                    continue
                }
            }
        }

        try? WorkflowPersistenceSupport.save(modelContext: modelContext)
    }

    private func reverseCompletionAllocations(projectId: UUID) {
        for transaction in allTransactions() {
            guard transaction.allocations.contains(where: { $0.projectId == projectId }) else {
                continue
            }
            transaction.allocations = recalculateAllocationAmounts(amount: transaction.amount, existingAllocations: transaction.allocations)
            transaction.updatedAt = Date()
        }
        try? WorkflowPersistenceSupport.save(modelContext: modelContext)
    }

    private func recalculateAllocationsForTransaction(_ transaction: PPTransaction, projects: [PPProject], isYearly: Bool = false) {
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

    private func recalculateAllocationsForProject(projectId: UUID) {
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
        if let businessId = snapshot.businessId {
            let recurringJournals = canonicalJournalEntries().filter { $0.entryType == .recurring }
            let candidateIds = Set(recurringJournals.compactMap(\.sourceCandidateId))
            let candidatesById = fetchPostingCandidates(ids: candidateIds)
            let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)

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

                let updatedSnapshot = CanonicalTransactionPostingBridge.TransactionSnapshot(
                    id: candidate.id,
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
                    taxRate: legacySnapshot.taxRate,
                    isTaxIncluded: legacySnapshot.isTaxIncluded,
                    taxCategory: legacySnapshot.taxCategory,
                    receiptImagePath: legacySnapshot.receiptImagePath,
                    lineItems: legacySnapshot.lineItems,
                    counterpartyName: legacySnapshot.counterpartyName,
                    createdAt: candidate.createdAt,
                    updatedAt: Date(),
                    journalEntryId: recurringJournal.id
                )
                guard let posting = bridge.buildApprovedPosting(
                    for: updatedSnapshot,
                    businessId: businessId,
                    counterpartyId: candidate.counterpartyId,
                    source: .recurring,
                    categories: snapshot.activeCategories,
                    legacyAccounts: snapshot.accounts
                ) else {
                    continue
                }

                do {
                    _ = try saveApprovedPostingSynchronously(
                        posting,
                        allocationAmounts: newAllocations,
                        actor: "system"
                    )
                } catch {
                    continue
                }
            }
        }

        try? WorkflowPersistenceSupport.save(modelContext: modelContext)
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

    private func recalculateAllPartialPeriodProjects() {
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

    private func normalizedCompletedAt(
        startDate: Date?,
        completedAt: Date?,
        status: ProjectStatus
    ) -> Date? {
        guard status == .completed else {
            return nil
        }

        let resolvedCompletedAt = completedAt ?? Date()
        guard let startDate else {
            return resolvedCompletedAt
        }

        return calendar.startOfDay(for: startDate) > calendar.startOfDay(for: resolvedCompletedAt)
            ? nil
            : resolvedCompletedAt
    }

    private func normalizedPlannedEndDate(
        startDate: Date?,
        plannedEndDate: Date?
    ) -> Date? {
        guard let plannedEndDate else {
            return nil
        }

        guard let startDate else {
            return plannedEndDate
        }

        return calendar.startOfDay(for: startDate) > calendar.startOfDay(for: plannedEndDate)
            ? nil
            : plannedEndDate
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

    @discardableResult
    private func saveApprovedPostingSynchronously(
        _ posting: CanonicalTransactionPostingBridge.Posting,
        allocations: [(projectId: UUID, ratio: Int)],
        actor: String
    ) throws -> CanonicalJournalEntry {
        let candidate = candidateWithProjectAllocations(posting.candidate, allocations: allocations)
        let approvedCandidate = candidate.updated(status: .approved)
        let journal = try upsertCanonicalJournal(
            from: approvedCandidate,
            journalId: posting.journalId,
            entryType: posting.entryType,
            description: posting.description,
            approvedAt: posting.approvedAt
        )

        let candidateDescriptor = FetchDescriptor<PostingCandidateEntity>(
            predicate: #Predicate { $0.candidateId == approvedCandidate.id }
        )
        if let existingCandidate = try modelContext.fetch(candidateDescriptor).first {
            PostingCandidateEntityMapper.update(existingCandidate, from: approvedCandidate)
        } else {
            modelContext.insert(PostingCandidateEntityMapper.toEntity(approvedCandidate))
        }

        try? LocalJournalSearchIndex(modelContext: modelContext).rebuild(
            businessId: journal.businessId,
            taxYear: journal.taxYear
        )
        _ = actor
        return journal
    }

    @discardableResult
    private func saveApprovedPostingSynchronously(
        _ posting: CanonicalTransactionPostingBridge.Posting,
        allocationAmounts: [Allocation],
        actor: String
    ) throws -> CanonicalJournalEntry {
        let candidate = candidateWithProjectAllocations(posting.candidate, allocationAmounts: allocationAmounts)
        let approvedCandidate = candidate.updated(status: .approved)
        let journal = try upsertCanonicalJournal(
            from: approvedCandidate,
            journalId: posting.journalId,
            entryType: posting.entryType,
            description: posting.description,
            approvedAt: posting.approvedAt
        )

        let candidateDescriptor = FetchDescriptor<PostingCandidateEntity>(
            predicate: #Predicate { $0.candidateId == approvedCandidate.id }
        )
        if let existingCandidate = try modelContext.fetch(candidateDescriptor).first {
            PostingCandidateEntityMapper.update(existingCandidate, from: approvedCandidate)
        } else {
            modelContext.insert(PostingCandidateEntityMapper.toEntity(approvedCandidate))
        }

        try? LocalJournalSearchIndex(modelContext: modelContext).rebuild(
            businessId: journal.businessId,
            taxYear: journal.taxYear
        )
        _ = actor
        return journal
    }

    private func upsertCanonicalJournal(
        from candidate: PostingCandidate,
        journalId: UUID,
        entryType: CanonicalJournalEntryType,
        description: String?,
        approvedAt: Date
    ) throws -> CanonicalJournalEntry {
        guard !candidate.proposedLines.isEmpty else {
            throw AppError.invalidInput(message: "仕訳候補に明細がありません")
        }

        let journalDescriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.journalId == journalId }
        )
        let existingJournalEntity = try modelContext.fetch(journalDescriptor).first
        let voucherNo: String
        if let existingJournalEntity {
            voucherNo = existingJournalEntity.voucherNo
        } else {
            let voucherMonth = calendar.component(.month, from: candidate.candidateDate)
            voucherNo = try nextCanonicalVoucherNumber(
                businessId: candidate.businessId,
                taxYear: candidate.taxYear,
                month: voucherMonth
            ).value
        }

        let journal = CanonicalJournalEntry(
            id: journalId,
            businessId: candidate.businessId,
            taxYear: candidate.taxYear,
            journalDate: candidate.candidateDate,
            voucherNo: voucherNo,
            sourceEvidenceId: candidate.evidenceId,
            sourceCandidateId: candidate.id,
            entryType: entryType,
            description: description ?? candidate.memo ?? "",
            lines: try makeJournalLinesSynchronously(from: candidate, journalId: journalId),
            approvedAt: approvedAt,
            createdAt: existingJournalEntity?.createdAt ?? approvedAt,
            updatedAt: approvedAt
        )

        guard journal.isBalanced else {
            throw AppError.invalidInput(message: "仕訳候補から生成した仕訳が借貸不一致です")
        }

        if let existingJournalEntity {
            let previousLines = existingJournalEntity.lines
            CanonicalJournalEntryEntityMapper.update(existingJournalEntity, from: journal)
            existingJournalEntity.lines = []
            previousLines.forEach(modelContext.delete)
            existingJournalEntity.lines = CanonicalJournalEntryEntityMapper.makeLineEntities(
                from: journal.lines,
                journalEntry: existingJournalEntity
            )
        } else {
            modelContext.insert(CanonicalJournalEntryEntityMapper.toEntity(journal))
        }

        return journal
    }

    private func makeJournalLinesSynchronously(
        from candidate: PostingCandidate,
        journalId: UUID
    ) throws -> [JournalLine] {
        var journalLines: [JournalLine] = []
        var sortOrder = 0

        for line in candidate.proposedLines {
            guard line.amount > 0 else {
                throw AppError.invalidInput(message: "仕訳候補の金額が不正です")
            }
            guard line.debitAccountId != nil || line.creditAccountId != nil else {
                throw AppError.invalidInput(message: "仕訳候補に勘定科目が設定されていません")
            }

            if let debitAccountId = line.debitAccountId {
                journalLines.append(
                    JournalLine(
                        journalId: journalId,
                        accountId: debitAccountId,
                        debitAmount: line.amount,
                        creditAmount: 0,
                        taxCodeId: line.taxCodeId,
                        legalReportLineId: try resolvedCanonicalLegalReportLineId(
                            accountId: debitAccountId,
                            fallback: line.legalReportLineId
                        ),
                        counterpartyId: candidate.counterpartyId,
                        projectAllocationId: line.projectAllocationId,
                        evidenceReferenceId: line.evidenceLineReferenceId ?? candidate.evidenceId,
                        sortOrder: sortOrder,
                        withholdingTaxCodeId: line.withholdingTaxCodeId,
                        withholdingTaxAmount: line.withholdingTaxAmount
                    )
                )
                sortOrder += 1
            }

            if let creditAccountId = line.creditAccountId {
                journalLines.append(
                    JournalLine(
                        journalId: journalId,
                        accountId: creditAccountId,
                        debitAmount: 0,
                        creditAmount: line.amount,
                        taxCodeId: line.taxCodeId,
                        legalReportLineId: try resolvedCanonicalLegalReportLineId(
                            accountId: creditAccountId,
                            fallback: line.legalReportLineId
                        ),
                        counterpartyId: candidate.counterpartyId,
                        projectAllocationId: line.projectAllocationId,
                        evidenceReferenceId: line.evidenceLineReferenceId ?? candidate.evidenceId,
                        sortOrder: sortOrder,
                        withholdingTaxCodeId: line.withholdingTaxCodeId,
                        withholdingTaxAmount: line.withholdingTaxAmount
                    )
                )
                sortOrder += 1
            }
        }

        return journalLines
    }

    private func resolvedCanonicalLegalReportLineId(
        accountId: UUID,
        fallback: String?
    ) throws -> String {
        let snapshot = try transactionFormQueryUseCase.snapshot()
        guard let businessId = snapshot.businessId else {
            throw AppError.invalidInput(message: "事業者プロフィールが未設定です")
        }
        guard let account = fetchCanonicalAccounts(businessId: businessId).first(where: { $0.id == accountId }) else {
            throw AppError.invalidInput(message: "勘定科目が見つかりません")
        }

        if let lineId = account.defaultLegalReportLineId,
           LegalReportLine(rawValue: lineId) != nil {
            return lineId
        }
        if let fallback, LegalReportLine(rawValue: fallback) != nil {
            return fallback
        }
        throw AppError.invalidInput(message: "勘定科目に決算書表示行が設定されていません")
    }

    private func nextCanonicalVoucherNumber(
        businessId: UUID,
        taxYear: Int,
        month: Int
    ) throws -> VoucherNumber {
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == taxYear
            },
            sortBy: [SortDescriptor(\.voucherNo, order: .reverse)]
        )
        let sequence = try modelContext.fetch(descriptor)
            .compactMap { VoucherNumber(rawValue: $0.voucherNo) }
            .filter { $0.taxYear == taxYear && $0.month == month }
            .compactMap(\.sequence)
            .max() ?? 0
        return VoucherNumber(taxYear: taxYear, month: month, sequence: sequence + 1)
    }

    private func fetchCanonicalAccounts(businessId: UUID) -> [CanonicalAccount] {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(
            predicate: #Predicate { $0.businessId == businessId },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(CanonicalAccountEntityMapper.toDomain)
    }

    private func candidateWithProjectAllocations(
        _ candidate: PostingCandidate,
        allocations: [(projectId: UUID, ratio: Int)]
    ) -> PostingCandidate {
        let amount = candidate.proposedLines.reduce(0) { partialResult, line in
            partialResult + NSDecimalNumber(decimal: line.amount).intValue
        }
        let allocationAmounts = calculateRatioAllocations(amount: amount, allocations: allocations)
        return candidateWithProjectAllocations(candidate, allocationAmounts: allocationAmounts)
    }

    private func candidateWithProjectAllocations(
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
}
