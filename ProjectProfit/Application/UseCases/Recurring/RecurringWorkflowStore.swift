import CryptoKit
import Foundation
import SwiftData

@MainActor
struct RecurringWorkflowStore {
    private let modelContext: ModelContext
    private let recurringRepository: any RecurringRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let postingWorkflowUseCase: PostingWorkflowUseCase
    private let onRecurringScheduleChanged: (([PPRecurringTransaction]) -> Void)?
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        recurringRepository: (any RecurringRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        postingWorkflowUseCase: PostingWorkflowUseCase? = nil,
        onRecurringScheduleChanged: (([PPRecurringTransaction]) -> Void)? = nil,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.recurringRepository = recurringRepository ?? SwiftDataRecurringRepository(modelContext: modelContext)
        self.transactionFormQueryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        self.postingWorkflowUseCase = postingWorkflowUseCase ?? PostingWorkflowUseCase(modelContext: modelContext)
        self.onRecurringScheduleChanged = onRecurringScheduleChanged
        self.calendar = calendar
    }

    @discardableResult
    func createRecurring(input: RecurringUpsertInput) -> PPRecurringTransaction {
        let snapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        let safeCategoryId = input.categoryId.isEmpty ? Self.defaultCategoryId(for: input.type) : input.categoryId
        let allocations: [Allocation] = switch input.allocationMode {
        case .equalAll:
            []
        case .manual:
            calculateRatioAllocations(
                amount: input.amount,
                allocations: input.allocations.map { ($0.projectId, $0.ratio) }
            )
        }
        let resolvedCounterparty = resolveCounterpartyReference(
            explicitId: input.counterpartyId,
            rawName: input.counterparty,
            businessId: snapshot.businessId
        )
        let recurring = PPRecurringTransaction(
            name: input.name,
            type: input.type,
            amount: input.amount,
            categoryId: safeCategoryId,
            memo: input.memo,
            allocationMode: input.allocationMode,
            allocations: allocations,
            frequency: input.frequency,
            dayOfMonth: input.dayOfMonth,
            monthOfYear: input.monthOfYear,
            isActive: input.isActive,
            endDate: input.endDate,
            yearlyAmortizationMode: input.yearlyAmortizationMode,
            receiptImagePath: input.receiptImagePath,
            paymentAccountId: input.paymentAccountId,
            transferToAccountId: input.transferToAccountId,
            taxDeductibleRate: input.taxDeductibleRate,
            counterpartyId: resolvedCounterparty.id,
            counterparty: resolvedCounterparty.displayName
        )
        recurringRepository.insert(recurring)
        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            notifyRecurringScheduleChanged()
        } catch {
            modelContext.rollback()
        }
        return recurring
    }

    func updateRecurring(id: UUID, input: RecurringUpsertInput) {
        let resolvedFrequency = input.frequency
        let resolvedMonthOfYear = resolvedFrequency == .yearly ? input.monthOfYear : nil
        let resolvedYearlyAmortizationMode: YearlyAmortizationMode = resolvedFrequency == .yearly
            ? input.yearlyAmortizationMode
            : .lumpSum
        updateRecurring(
            id: id,
            name: input.name,
            type: input.type,
            amount: input.amount,
            categoryId: .some(input.categoryId),
            memo: input.memo,
            allocationMode: input.allocationMode,
            allocations: input.allocations.map { ($0.projectId, $0.ratio) },
            frequency: resolvedFrequency,
            dayOfMonth: input.dayOfMonth,
            monthOfYear: resolvedMonthOfYear,
            isActive: input.isActive,
            endDate: .some(input.endDate),
            yearlyAmortizationMode: resolvedYearlyAmortizationMode,
            notificationTiming: nil,
            skipDates: nil,
            receiptImagePath: .some(input.receiptImagePath),
            paymentAccountId: .some(input.paymentAccountId),
            transferToAccountId: .some(input.transferToAccountId),
            taxDeductibleRate: .some(input.taxDeductibleRate),
            counterpartyId: .some(input.counterpartyId),
            counterparty: .some(input.counterparty)
        )
    }

    func deleteRecurring(id: UUID) {
        guard let recurring = try? recurringRepository.findById(id) else {
            return
        }

        let now = Date()
        for transaction in allTransactions() where transaction.recurringId == id {
            transaction.recurringId = nil
            transaction.updatedAt = now
        }

        let imageToDelete = recurring.receiptImagePath
        recurringRepository.delete(recurring)
        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            if let imageToDelete {
                ReceiptImageStore.deleteImage(fileName: imageToDelete)
            }
            notifyRecurringScheduleChanged()
        } catch {
            modelContext.rollback()
        }
    }

    func setRecurringActive(id: UUID, isActive: Bool) {
        updateRecurring(id: id, isActive: isActive)
    }

    func setRecurringSkipped(id: UUID, date: Date, isSkipped: Bool) {
        guard let recurring = try? recurringRepository.findById(id) else {
            return
        }

        var updatedSkipDates = recurring.skipDates.filter { !calendar.isDate($0, inSameDayAs: date) }
        if isSkipped {
            updatedSkipDates.append(date)
        }
        recurring.skipDates = updatedSkipDates
        recurring.updatedAt = Date()

        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            notifyRecurringScheduleChanged()
        } catch {
            modelContext.rollback()
        }
    }

    func setNotificationTiming(id: UUID, timing: NotificationTiming) {
        updateRecurring(id: id, notificationTiming: timing)
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
                _ = try saveApprovedPostingSynchronously(
                    posting,
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
                notifyRecurringScheduleChanged()
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
                let candidate = candidateWithProjectAllocations(
                    posting.candidate,
                    allocationAmounts: allocations
                )
                _ = try await postingWorkflowUseCase.syncApprovedCandidate(
                    candidate,
                    journalId: posting.journalId,
                    entryType: posting.entryType,
                    description: posting.description,
                    approvedAt: posting.approvedAt
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
                notifyRecurringScheduleChanged()
            } catch {
                modelContext.rollback()
            }
        }

        return generatedCount
    }

    private func updateRecurring(
        id: UUID,
        name: String? = nil,
        type: TransactionType? = nil,
        amount: Int? = nil,
        categoryId: String?? = nil,
        memo: String? = nil,
        allocationMode: AllocationMode? = nil,
        allocations: [(projectId: UUID, ratio: Int)]? = nil,
        frequency: RecurringFrequency? = nil,
        dayOfMonth: Int? = nil,
        monthOfYear: Int? = nil,
        isActive: Bool? = nil,
        endDate: Date?? = nil,
        yearlyAmortizationMode: YearlyAmortizationMode? = nil,
        notificationTiming: NotificationTiming? = nil,
        skipDates: [Date]? = nil,
        receiptImagePath: String?? = nil,
        paymentAccountId: String?? = nil,
        transferToAccountId: String?? = nil,
        taxDeductibleRate: Int?? = nil,
        counterpartyId: UUID?? = nil,
        counterparty: String?? = nil
    ) {
        guard let recurring = try? recurringRepository.findById(id) else {
            return
        }

        if let name { recurring.name = name }
        if let type { recurring.type = type }
        if let categoryId {
            recurring.categoryId = categoryId ?? Self.defaultCategoryId(for: recurring.type)
        }
        if let memo { recurring.memo = memo }
        if let allocationMode { recurring.allocationMode = allocationMode }
        if let frequency {
            let frequencyChanged = recurring.frequency != frequency
            recurring.frequency = frequency
            if frequency == .monthly {
                recurring.monthOfYear = nil
                recurring.yearlyAmortizationMode = .lumpSum
                recurring.lastGeneratedMonths = []
                if frequencyChanged {
                    recurring.lastGeneratedDate = nil
                }
            } else {
                if let monthOfYear {
                    recurring.monthOfYear = (1...12).contains(monthOfYear) ? monthOfYear : recurring.monthOfYear
                }
                if frequencyChanged {
                    recurring.lastGeneratedDate = nil
                    recurring.lastGeneratedMonths = []
                }
            }
        } else if let monthOfYear {
            recurring.monthOfYear = (1...12).contains(monthOfYear) ? monthOfYear : recurring.monthOfYear
        }
        if let dayOfMonth { recurring.dayOfMonth = min(28, max(1, dayOfMonth)) }
        if let isActive { recurring.isActive = isActive }
        if let endDate { recurring.endDate = endDate }
        if let yearlyAmortizationMode {
            let previousMode = recurring.yearlyAmortizationMode
            recurring.yearlyAmortizationMode = yearlyAmortizationMode
            if previousMode != yearlyAmortizationMode, yearlyAmortizationMode == .lumpSum {
                recurring.lastGeneratedMonths = []
            }
        }
        if let notificationTiming { recurring.notificationTiming = notificationTiming }
        if let skipDates { recurring.skipDates = skipDates }
        if let receiptImagePath { recurring.receiptImagePath = receiptImagePath }
        if let paymentAccountId { recurring.paymentAccountId = paymentAccountId }
        if let transferToAccountId { recurring.transferToAccountId = transferToAccountId }
        if let taxDeductibleRate { recurring.taxDeductibleRate = taxDeductibleRate }
        if let counterpartyId { recurring.counterpartyId = counterpartyId }
        if let counterparty { recurring.counterparty = counterparty }
        if counterpartyId != nil || counterparty != nil {
            let snapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
            let resolvedCounterparty = resolveCounterpartyReference(
                explicitId: recurring.counterpartyId,
                rawName: recurring.counterparty,
                businessId: snapshot.businessId
            )
            recurring.counterpartyId = resolvedCounterparty.id
            recurring.counterparty = resolvedCounterparty.displayName
        }

        let resolvedMode = allocationMode ?? recurring.allocationMode
        let finalAmount = amount ?? recurring.amount
        if let amount { recurring.amount = amount }

        switch resolvedMode {
        case .equalAll:
            recurring.allocations = []
        case .manual:
            if let allocations {
                recurring.allocations = calculateRatioAllocations(amount: finalAmount, allocations: allocations)
            } else if amount != nil {
                recurring.allocations = recalculateAllocationAmounts(amount: finalAmount, existingAllocations: recurring.allocations)
            }
        }

        recurring.updatedAt = Date()
        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            notifyRecurringScheduleChanged()
        } catch {
            modelContext.rollback()
        }
    }

    private func notifyRecurringScheduleChanged() {
        guard let onRecurringScheduleChanged else {
            return
        }
        onRecurringScheduleChanged(allRecurringTransactions())
    }

    private func allRecurringTransactions() -> [PPRecurringTransaction] {
        (try? recurringRepository.allRecurringTransactions()) ?? []
    }

    private func allTransactions() -> [PPTransaction] {
        let descriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? modelContext.fetch(descriptor)) ?? []
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

    private func buildApprovedPosting(
        recurring: PPRecurringTransaction,
        amount: Int,
        date: Date,
        memo: String,
        snapshot: TransactionFormSnapshot
    ) throws -> CanonicalTransactionPostingBridge.Posting {
        let taxYear = fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)
        guard WorkflowPersistenceSupport.canPostNormalEntry(modelContext: modelContext, year: taxYear) else {
            throw AppError.yearLocked(year: taxYear)
        }
        guard let businessId = snapshot.businessId else {
            throw AppError.invalidInput(message: "事業者プロフィールが未設定のため承認待ち候補を作成できません")
        }

        let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)
        let transactionSnapshot = CanonicalTransactionPostingBridge.TransactionSnapshot(
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
            taxRate: nil,
            isTaxIncluded: nil,
            taxCategory: nil,
            counterpartyName: recurring.counterparty,
            createdAt: Date(),
            updatedAt: Date(),
            journalEntryId: nil
        )

        guard let posting = bridge.buildApprovedPosting(
            for: transactionSnapshot,
            businessId: businessId,
            counterpartyId: recurring.counterpartyId,
            source: .recurring,
            categories: snapshot.activeCategories,
            legacyAccounts: snapshot.accounts
        ) else {
            throw AppError.invalidInput(message: "承認待ち候補の勘定科目または税区分を解決できません")
        }

        return posting
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

    private func resolveCounterpartyReference(
        explicitId: UUID?,
        rawName: String?,
        businessId: UUID?
    ) -> (id: UUID?, displayName: String?) {
        if let explicitId,
           let existing = try? canonicalCounterparty(id: explicitId) {
            return (existing.id, existing.displayName)
        }

        guard let businessId,
              let displayName = normalizedOptionalString(rawName) else {
            return (nil, normalizedOptionalString(rawName))
        }

        let counterparties = (try? fetchCanonicalCounterparties(businessId: businessId)) ?? []
        if let exactMatch = counterparties.first(where: {
            $0.displayName.compare(
                displayName,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) == .orderedSame
        }) {
            return (exactMatch.id, exactMatch.displayName)
        }

        let counterparty = Counterparty(
            id: stableCounterpartyId(businessId: businessId, displayName: displayName),
            businessId: businessId,
            displayName: displayName,
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

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func isYearLocked(for date: Date) -> Bool {
        let taxYear = fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)
        return !WorkflowPersistenceSupport.canPostNormalEntry(modelContext: modelContext, year: taxYear)
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
