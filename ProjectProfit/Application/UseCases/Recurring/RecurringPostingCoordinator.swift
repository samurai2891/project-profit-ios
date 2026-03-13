import Foundation
import SwiftData

@MainActor
struct RecurringPostingCoordinator {
    private let modelContext: ModelContext
    private let recurringRepository: any RecurringRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let postingSupport: CanonicalPostingSupport
    private let onRecurringScheduleChanged: (() -> Void)?
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        recurringRepository: any RecurringRepository,
        transactionFormQueryUseCase: TransactionFormQueryUseCase,
        postingSupport: CanonicalPostingSupport,
        onRecurringScheduleChanged: (() -> Void)? = nil,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.recurringRepository = recurringRepository
        self.transactionFormQueryUseCase = transactionFormQueryUseCase
        self.postingSupport = postingSupport
        self.onRecurringScheduleChanged = onRecurringScheduleChanged
        self.calendar = calendar
    }

    func previewRecurringTransactions() -> [RecurringPreviewItem] {
        dueRecurringOccurrences()
            .filter { !$0.isSkipped && !$0.isYearLocked }
            .map { occurrence in
                let recurring = allRecurringTransactions().first(where: { $0.id == occurrence.recurringId })
                return RecurringPreviewItem(
                    recurringId: occurrence.recurringId,
                    recurringName: recurring?.name ?? "",
                    type: recurring?.type ?? .expense,
                    amount: occurrence.amount,
                    scheduledDate: occurrence.scheduledDate,
                    categoryId: occurrence.categoryId,
                    memo: occurrence.previewMemo,
                    isMonthlySpread: occurrence.isMonthlySpread,
                    projectName: occurrence.projectName,
                    allocationMode: occurrence.allocationMode
                )
            }
    }

    @discardableResult
    func processDueRecurringTransactions() -> Int {
        let today = todayDate()
        let recurrings = allRecurringTransactions()
        let snapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        var generatedCount = 0
        var didMutateRecurringState = pruneRecurringGeneratedMonthsForCurrentYear(on: today)

        for occurrence in dueRecurringOccurrences(on: today) {
            guard let recurring = recurrings.first(where: { $0.id == occurrence.recurringId }) else {
                continue
            }

            if occurrence.isSkipped {
                didMutateRecurringState = consumeRecurringSkipOccurrence(occurrence, recurring: recurring) || didMutateRecurringState
                continue
            }
            if occurrence.isYearLocked {
                continue
            }
            guard let allocations = recurringAllocations(
                for: recurring,
                amount: occurrence.amount,
                txDate: occurrence.scheduledDate,
                treatAsYearly: recurring.frequency == .yearly && !occurrence.isMonthlySpread,
                projects: snapshot.projects
            ) else {
                continue
            }

            do {
                let posting = try buildApprovedPosting(
                    recurring: recurring,
                    amount: occurrence.amount,
                    date: occurrence.scheduledDate,
                    memo: occurrence.postingMemo,
                    snapshot: snapshot
                )
                _ = try postingSupport.persistApprovedPosting(
                    posting: posting,
                    allocationAmounts: allocations,
                    actor: "system"
                )
                didMutateRecurringState = applyRecurringProcessedOccurrence(occurrence, recurring: recurring) || didMutateRecurringState
                generatedCount += 1
            } catch {
                continue
            }
        }

        for recurring in recurrings where recurring.isActive {
            if let endDate = recurring.endDate, today > endDate {
                recurring.isActive = false
                recurring.updatedAt = Date()
                didMutateRecurringState = true
            }
        }

        if didMutateRecurringState || generatedCount > 0 {
            do {
                try WorkflowPersistenceSupport.save(modelContext: modelContext)
                onRecurringScheduleChanged?()
            } catch {
                modelContext.rollback()
            }
        }

        return generatedCount
    }

    func approveRecurringItems(_ approvedIds: Set<UUID>, from items: [RecurringPreviewItem]) async -> Int {
        let approvedItems = items.filter { approvedIds.contains($0.id) }
        var generatedCount = 0
        var didMutateRecurringState = pruneRecurringGeneratedMonthsForCurrentYear(on: todayDate())
        let recurrings = allRecurringTransactions()
        let snapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty

        for occurrence in dueRecurringOccurrences().filter(\.isSkipped) {
            guard let recurring = recurrings.first(where: { $0.id == occurrence.recurringId }) else {
                continue
            }
            didMutateRecurringState = consumeRecurringSkipOccurrence(occurrence, recurring: recurring) || didMutateRecurringState
        }

        for item in approvedItems {
            guard let recurring = recurrings.first(where: { $0.id == item.recurringId }) else {
                continue
            }
            if isYearLocked(for: item.scheduledDate) {
                continue
            }
            guard let allocations = recurringAllocations(
                for: recurring,
                amount: item.amount,
                txDate: item.scheduledDate,
                treatAsYearly: recurring.frequency == .yearly && !item.isMonthlySpread,
                projects: snapshot.projects
            ) else {
                continue
            }

            let occurrence = RecurringDueOccurrence(
                recurringId: recurring.id,
                scheduledDate: item.scheduledDate,
                amount: item.amount,
                previewMemo: item.memo,
                postingMemo: recurringPostingMemo(for: recurring, isMonthlySpread: item.isMonthlySpread),
                categoryId: recurring.categoryId,
                isMonthlySpread: item.isMonthlySpread,
                monthKey: item.isMonthlySpread
                    ? String(
                        format: "%d-%02d",
                        calendar.component(.year, from: item.scheduledDate),
                        calendar.component(.month, from: item.scheduledDate)
                    )
                    : nil,
                projectName: item.projectName,
                allocationMode: recurring.allocationMode,
                isSkipped: false,
                isYearLocked: false
            )

            do {
                let posting = try buildApprovedPosting(
                    recurring: recurring,
                    amount: item.amount,
                    date: item.scheduledDate,
                    memo: occurrence.postingMemo,
                    snapshot: snapshot
                )
                _ = try await postingSupport.syncApprovedCandidate(
                    posting: posting,
                    allocationAmounts: allocations,
                    actor: "system"
                )
                didMutateRecurringState = applyRecurringProcessedOccurrence(occurrence, recurring: recurring) || didMutateRecurringState
                generatedCount += 1
            } catch {
                continue
            }
        }

        if didMutateRecurringState || generatedCount > 0 {
            do {
                try WorkflowPersistenceSupport.save(modelContext: modelContext)
                onRecurringScheduleChanged?()
            } catch {
                modelContext.rollback()
            }
        }

        return generatedCount
    }

    private struct RecurringDueOccurrence {
        let recurringId: UUID
        let scheduledDate: Date
        let amount: Int
        let previewMemo: String
        let postingMemo: String
        let categoryId: String
        let isMonthlySpread: Bool
        let monthKey: String?
        let projectName: String?
        let allocationMode: AllocationMode
        let isSkipped: Bool
        let isYearLocked: Bool
    }

    private func buildApprovedPosting(
        recurring: PPRecurringTransaction,
        amount: Int,
        date: Date,
        memo: String,
        snapshot: TransactionFormSnapshot
    ) throws -> CanonicalTransactionPostingBridge.Posting {
        try postingSupport.buildApprovedPosting(
            seed: CanonicalPostingSeed(
                id: UUID(),
                type: recurring.type,
                amount: amount,
                date: date,
                categoryId: recurring.categoryId,
                memo: memo,
                recurringId: recurring.id,
                paymentAccountId: recurring.paymentAccountId,
                transferToAccountId: recurring.transferToAccountId,
                taxDeductibleRate: recurring.taxDeductibleRate,
                taxAmount: nil,
                taxCodeId: nil,
                isTaxIncluded: nil,
                receiptImagePath: nil,
                lineItems: [],
                counterpartyId: recurring.counterpartyId,
                counterpartyName: recurring.counterparty,
                source: .recurring,
                createdAt: Date(),
                updatedAt: Date(),
                journalEntryId: nil
            ),
            snapshot: snapshot
        )
    }

    private func dueRecurringOccurrences(on today: Date = todayDate()) -> [RecurringDueOccurrence] {
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentYear = todayComponents.year,
              let currentMonth = todayComponents.month,
              let currentDay = todayComponents.day else {
            return []
        }

        let recurrings = allRecurringTransactions()
        let projects = ((try? transactionFormQueryUseCase.snapshot()) ?? .empty).projects
        var occurrences: [RecurringDueOccurrence] = []

        for recurring in recurrings {
            guard recurring.isActive else { continue }
            if recurring.allocationMode == .manual && recurring.allocations.isEmpty { continue }

            let projectName = recurringProjectName(recurring, projects: projects)

            if recurring.frequency == .monthly {
                var iterYear: Int
                var iterMonth: Int

                if let lastGen = recurring.lastGeneratedDate {
                    let lastComponents = calendar.dateComponents([.year, .month], from: lastGen)
                    iterYear = lastComponents.year ?? currentYear
                    iterMonth = (lastComponents.month ?? currentMonth) + 1
                    if iterMonth > 12 {
                        iterMonth = 1
                        iterYear += 1
                    }
                } else {
                    iterYear = currentYear
                    iterMonth = currentMonth
                }

                while iterYear < currentYear || (iterYear == currentYear && iterMonth <= currentMonth) {
                    if iterYear == currentYear && iterMonth == currentMonth && currentDay < recurring.dayOfMonth {
                        break
                    }

                    guard let scheduledDate = calendar.date(
                        from: DateComponents(year: iterYear, month: iterMonth, day: recurring.dayOfMonth)
                    ) else {
                        iterMonth += 1
                        if iterMonth > 12 {
                            iterMonth = 1
                            iterYear += 1
                        }
                        continue
                    }

                    if let endDate = recurring.endDate, scheduledDate > endDate {
                        break
                    }

                    occurrences.append(
                        RecurringDueOccurrence(
                            recurringId: recurring.id,
                            scheduledDate: scheduledDate,
                            amount: recurring.amount,
                            previewMemo: recurringPreviewMemo(for: recurring, isMonthlySpread: false),
                            postingMemo: recurringPostingMemo(for: recurring, isMonthlySpread: false),
                            categoryId: recurring.categoryId,
                            isMonthlySpread: false,
                            monthKey: nil,
                            projectName: projectName,
                            allocationMode: recurring.allocationMode,
                            isSkipped: recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: scheduledDate) },
                            isYearLocked: isYearLocked(for: scheduledDate)
                        )
                    )

                    iterMonth += 1
                    if iterMonth > 12 {
                        iterMonth = 1
                        iterYear += 1
                    }
                }
                continue
            }

            if recurring.yearlyAmortizationMode == .monthlySpread {
                if let endDate = recurring.endDate, today > endDate {
                    continue
                }

                let startMonth = recurring.monthOfYear ?? 1
                let actualMonthCount = 12 - startMonth + 1
                let monthlyAmount = recurring.amount / actualMonthCount
                let remainder = recurring.amount - (monthlyAmount * actualMonthCount)
                let eligibleRemainderMonth = monthlySpreadEligibleRemainderMonth(
                    recurring: recurring,
                    year: currentYear
                )
                let currentYearPrefix = String(format: "%d-", currentYear)
                let generatedMonths = Set(recurring.lastGeneratedMonths.filter { $0.hasPrefix(currentYearPrefix) })

                for month in startMonth...12 {
                    guard currentMonth > month || (currentMonth == month && currentDay >= recurring.dayOfMonth) else {
                        continue
                    }
                    let monthKey = String(format: "%d-%02d", currentYear, month)
                    guard !generatedMonths.contains(monthKey) else { continue }
                    guard let scheduledDate = calendar.date(
                        from: DateComponents(year: currentYear, month: month, day: recurring.dayOfMonth)
                    ) else {
                        continue
                    }
                    if let endDate = recurring.endDate, scheduledDate > endDate {
                        continue
                    }

                    occurrences.append(
                        RecurringDueOccurrence(
                            recurringId: recurring.id,
                            scheduledDate: scheduledDate,
                            amount: month == eligibleRemainderMonth ? monthlyAmount + remainder : monthlyAmount,
                            previewMemo: recurringPreviewMemo(for: recurring, isMonthlySpread: true),
                            postingMemo: recurringPostingMemo(for: recurring, isMonthlySpread: true),
                            categoryId: recurring.categoryId,
                            isMonthlySpread: true,
                            monthKey: monthKey,
                            projectName: projectName,
                            allocationMode: recurring.allocationMode,
                            isSkipped: recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: scheduledDate) },
                            isYearLocked: isYearLocked(for: scheduledDate)
                        )
                    )
                }
                continue
            }

            let targetMonth = recurring.monthOfYear ?? 1
            let startYear: Int
            if let lastGen = recurring.lastGeneratedDate {
                startYear = calendar.component(.year, from: lastGen) + 1
            } else {
                startYear = currentYear
            }

            guard startYear <= currentYear else { continue }
            for iterYear in startYear...currentYear {
                if iterYear == currentYear,
                   (currentMonth < targetMonth || (currentMonth == targetMonth && currentDay < recurring.dayOfMonth)) {
                    break
                }

                guard let scheduledDate = calendar.date(
                    from: DateComponents(year: iterYear, month: targetMonth, day: recurring.dayOfMonth)
                ) else {
                    continue
                }
                if let endDate = recurring.endDate, scheduledDate > endDate {
                    break
                }

                occurrences.append(
                    RecurringDueOccurrence(
                        recurringId: recurring.id,
                        scheduledDate: scheduledDate,
                        amount: recurring.amount,
                        previewMemo: recurringPreviewMemo(for: recurring, isMonthlySpread: false),
                        postingMemo: recurringPostingMemo(for: recurring, isMonthlySpread: false),
                        categoryId: recurring.categoryId,
                        isMonthlySpread: false,
                        monthKey: nil,
                        projectName: projectName,
                        allocationMode: recurring.allocationMode,
                        isSkipped: recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: scheduledDate) },
                        isYearLocked: isYearLocked(for: scheduledDate)
                    )
                )
            }
        }

        return occurrences.sorted { lhs, rhs in
            if lhs.scheduledDate == rhs.scheduledDate {
                return lhs.recurringId.uuidString < rhs.recurringId.uuidString
            }
            return lhs.scheduledDate < rhs.scheduledDate
        }
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

    @discardableResult
    private func consumeRecurringSkipOccurrence(
        _ occurrence: RecurringDueOccurrence,
        recurring: PPRecurringTransaction
    ) -> Bool {
        guard occurrence.isSkipped else {
            return false
        }

        recurring.skipDates = recurring.skipDates.filter { !calendar.isDate($0, inSameDayAs: occurrence.scheduledDate) }
        if occurrence.isMonthlySpread {
            if let monthKey = occurrence.monthKey, !recurring.lastGeneratedMonths.contains(monthKey) {
                recurring.lastGeneratedMonths = recurring.lastGeneratedMonths + [monthKey]
            }
        } else {
            recurring.lastGeneratedDate = occurrence.scheduledDate
        }
        recurring.updatedAt = Date()
        return true
    }

    @discardableResult
    private func applyRecurringProcessedOccurrence(
        _ occurrence: RecurringDueOccurrence,
        recurring: PPRecurringTransaction
    ) -> Bool {
        if occurrence.isMonthlySpread,
           let monthKey = occurrence.monthKey,
           !recurring.lastGeneratedMonths.contains(monthKey) {
            recurring.lastGeneratedMonths = recurring.lastGeneratedMonths + [monthKey]
        }
        recurring.lastGeneratedDate = occurrence.scheduledDate
        recurring.updatedAt = Date()
        return true
    }

    @discardableResult
    private func pruneRecurringGeneratedMonthsForCurrentYear(on today: Date) -> Bool {
        let currentYear = calendar.component(.year, from: today)
        let currentYearPrefix = String(format: "%d-", currentYear)
        var mutated = false

        for recurring in allRecurringTransactions() where recurring.yearlyAmortizationMode == .monthlySpread {
            let filteredMonths = recurring.lastGeneratedMonths.filter { $0.hasPrefix(currentYearPrefix) }
            if filteredMonths.count != recurring.lastGeneratedMonths.count {
                recurring.lastGeneratedMonths = filteredMonths
                recurring.updatedAt = Date()
                mutated = true
            }
        }
        return mutated
    }

    private func recurringProjectName(_ recurring: PPRecurringTransaction, projects: [PPProject]) -> String? {
        recurring.allocations.first.flatMap { allocation in
            projects.first(where: { $0.id == allocation.projectId })?.name
        }
    }

    private func recurringPostingMemo(for recurring: PPRecurringTransaction, isMonthlySpread: Bool) -> String {
        let prefix = isMonthlySpread ? "[定期/月次]" : "[定期]"
        return "\(prefix) \(recurring.name)" + (recurring.memo.isEmpty ? "" : " - \(recurring.memo)")
    }

    private func recurringPreviewMemo(for recurring: PPRecurringTransaction, isMonthlySpread: Bool) -> String {
        let prefix = isMonthlySpread ? "[定期/月次]" : "[定期]"
        return "\(prefix) \(recurring.name)"
    }

    private func monthlySpreadEligibleRemainderMonth(
        recurring: PPRecurringTransaction,
        year: Int
    ) -> Int? {
        let startMonth = recurring.monthOfYear ?? 1
        var lastEligibleMonth = 12

        if let endDate = recurring.endDate {
            for month in stride(from: 12, through: startMonth, by: -1) {
                if let date = calendar.date(from: DateComponents(year: year, month: month, day: recurring.dayOfMonth)),
                   date <= endDate {
                    lastEligibleMonth = month
                    break
                }
                if month == startMonth {
                    lastEligibleMonth = startMonth
                }
            }
        }

        for month in stride(from: lastEligibleMonth, through: startMonth, by: -1) {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: recurring.dayOfMonth)) else {
                continue
            }
            if !recurring.skipDates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                return month
            }
        }
        return nil
    }

    private func allRecurringTransactions() -> [PPRecurringTransaction] {
        (try? recurringRepository.allRecurringTransactions()) ?? []
    }

    private func isYearLocked(for date: Date) -> Bool {
        let taxYear = fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)
        return !WorkflowPersistenceSupport.canPostNormalEntry(modelContext: modelContext, year: taxYear)
    }
}
