import Foundation
import SwiftData

@MainActor
struct RecurringPostingCoordinator {
    private let modelContext: ModelContext
    private let recurringRepository: any RecurringRepository
    private let approvalRequestRepository: any ApprovalRequestRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let postingWorkflowUseCase: PostingWorkflowUseCase
    private let postingSupport: CanonicalPostingSupport
    private let onRecurringScheduleChanged: (() -> Void)?
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        recurringRepository: any RecurringRepository,
        approvalRequestRepository: any ApprovalRequestRepository,
        transactionFormQueryUseCase: TransactionFormQueryUseCase,
        postingWorkflowUseCase: PostingWorkflowUseCase,
        postingSupport: CanonicalPostingSupport,
        onRecurringScheduleChanged: (() -> Void)? = nil,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.recurringRepository = recurringRepository
        self.approvalRequestRepository = approvalRequestRepository
        self.transactionFormQueryUseCase = transactionFormQueryUseCase
        self.postingWorkflowUseCase = postingWorkflowUseCase
        self.postingSupport = postingSupport
        self.onRecurringScheduleChanged = onRecurringScheduleChanged
        self.calendar = calendar
    }

    func previewRecurringTransactions() async -> [RecurringPreviewItem] {
        await syncRecurringApprovalRequests()
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

    func approveRecurringItems(_ approvedIds: Set<UUID>) async -> Int {
        let requests = ((try? await approvalRequestRepository.findByIds(approvedIds)) ?? [])
            .filter { $0.kind == .recurring && $0.status == .pending }
        var generatedCount = 0
        var didMutateRecurringState = pruneRecurringGeneratedMonthsForCurrentYear(on: todayDate())
        let snapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty

        for occurrence in dueRecurringOccurrences().filter(\.isSkipped) {
            guard let recurring = allRecurringTransactions().first(where: { $0.id == occurrence.recurringId }) else {
                continue
            }
            didMutateRecurringState = consumeRecurringSkipOccurrence(occurrence, recurring: recurring) || didMutateRecurringState
        }

        for request in requests {
            if await approveRecurringRequest(request, snapshot: snapshot) {
                generatedCount += 1
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

    func approveRecurringRequest(id: UUID) async throws {
        guard let request = try await approvalRequestRepository.findById(id) else {
            throw ApprovalQueueWorkflowError.approvalRequestNotFound(id)
        }
        let snapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        guard await approveRecurringRequest(request, snapshot: snapshot) else {
            throw ApprovalQueueWorkflowError.invalidRecurringRequest(id)
        }
        try WorkflowPersistenceSupport.save(modelContext: modelContext)
        onRecurringScheduleChanged?()
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
                isWithholdingEnabled: recurring.isWithholdingEnabled,
                withholdingTaxCodeId: recurring.withholdingTaxCodeId,
                withholdingTaxAmount: recurring.withholdingTaxAmount,
                createdAt: Date(),
                updatedAt: Date(),
                journalEntryId: nil
            ),
            snapshot: snapshot
        )
    }

    private func syncRecurringApprovalRequests() async -> [RecurringPreviewItem] {
        let snapshot = (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        guard let businessId = snapshot.businessId else {
            return []
        }

        let dueOccurrences = dueRecurringOccurrences()
            .filter { !$0.isSkipped && !$0.isYearLocked }
        let dueKeys = Set(dueOccurrences.map(recurringTargetKey(for:)))
        let pendingRequests = (try? await approvalRequestRepository.findByBusiness(
            businessId: businessId,
            statuses: [.pending],
            kinds: [.recurring]
        )) ?? []

        for request in pendingRequests where !dueKeys.contains(request.targetKey) {
            let invalidated = request.updated(
                status: .invalidated,
                updatedAt: Date(),
                resolvedAt: .some(Date())
            )
            try? await approvalRequestRepository.save(invalidated)
        }

        for occurrence in dueOccurrences {
            try? await upsertRecurringApprovalRequest(
                businessId: businessId,
                occurrence: occurrence
            )
        }

        let refreshedPending = ((try? await approvalRequestRepository.findByBusiness(
            businessId: businessId,
            statuses: [.pending],
            kinds: [.recurring]
        )) ?? [])
            .sorted { lhs, rhs in
                let lhsDate = lhs.payload(RecurringApprovalPayload.self)?.scheduledDate ?? lhs.updatedAt
                let rhsDate = rhs.payload(RecurringApprovalPayload.self)?.scheduledDate ?? rhs.updatedAt
                if lhsDate == rhsDate {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhsDate < rhsDate
            }

        return refreshedPending.compactMap(recurringPreviewItem(from:))
    }

    private func recurringTargetKey(for occurrence: RecurringDueOccurrence) -> String {
        let year = calendar.component(.year, from: occurrence.scheduledDate)
        let month = calendar.component(.month, from: occurrence.scheduledDate)
        let day = calendar.component(.day, from: occurrence.scheduledDate)
        return [
            "recurring",
            occurrence.recurringId.uuidString,
            String(format: "%04d-%02d-%02d", year, month, day),
            occurrence.isMonthlySpread ? "spread" : "single",
        ].joined(separator: ":")
    }

    private func makeRecurringApprovalPayload(
        occurrence: RecurringDueOccurrence
    ) -> RecurringApprovalPayload {
        let recurring = allRecurringTransactions().first(where: { $0.id == occurrence.recurringId })
        return RecurringApprovalPayload(
            recurringId: occurrence.recurringId,
            recurringName: recurring?.name ?? "",
            type: recurring?.type ?? .expense,
            amount: occurrence.amount,
            scheduledDate: occurrence.scheduledDate,
            categoryId: occurrence.categoryId,
            memo: occurrence.previewMemo,
            postingMemo: occurrence.postingMemo,
            isMonthlySpread: occurrence.isMonthlySpread,
            monthKey: occurrence.monthKey,
            projectName: occurrence.projectName,
            allocationMode: occurrence.allocationMode
        )
    }

    private func upsertRecurringApprovalRequest(
        businessId: UUID,
        occurrence: RecurringDueOccurrence
    ) async throws {
        let targetKey = recurringTargetKey(for: occurrence)
        let payload = makeRecurringApprovalPayload(occurrence: occurrence)
        let payloadJSON = CanonicalJSONCoder.encode(payload, fallback: "{}")
        let existing = try await approvalRequestRepository.findByTarget(
            targetKey: targetKey,
            kind: .recurring,
            statuses: nil
        )

        if let pending = existing.first(where: { $0.status == .pending }) {
            let updated = pending.updated(
                title: payload.recurringName,
                subtitle: formatRecurringSubtitle(payload),
                payloadJSON: payloadJSON,
                updatedAt: Date()
            )
            try await approvalRequestRepository.save(updated)
            return
        }

        if existing.contains(where: { $0.status == .approved || $0.status == .rejected }) {
            return
        }

        let request = ApprovalRequest(
            businessId: businessId,
            kind: .recurring,
            status: .pending,
            targetKind: .recurringOccurrence,
            targetKey: targetKey,
            title: payload.recurringName,
            subtitle: formatRecurringSubtitle(payload),
            payloadJSON: payloadJSON
        )
        try await approvalRequestRepository.save(request)
    }

    private func recurringPreviewItem(from request: ApprovalRequest) -> RecurringPreviewItem? {
        guard let payload = request.payload(RecurringApprovalPayload.self) else {
            return nil
        }
        return RecurringPreviewItem(
            id: request.id,
            recurringId: payload.recurringId,
            recurringName: payload.recurringName,
            type: payload.type,
            amount: payload.amount,
            scheduledDate: payload.scheduledDate,
            categoryId: payload.categoryId,
            memo: payload.memo,
            isMonthlySpread: payload.isMonthlySpread,
            projectName: payload.projectName,
            allocationMode: payload.allocationMode
        )
    }

    private func formatRecurringSubtitle(_ payload: RecurringApprovalPayload) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: payload.scheduledDate)
    }

    private func approveRecurringRequest(
        _ request: ApprovalRequest,
        snapshot: TransactionFormSnapshot
    ) async -> Bool {
        guard request.kind == .recurring,
              request.status == .pending,
              let payload = request.payload(RecurringApprovalPayload.self),
              let recurring = allRecurringTransactions().first(where: { $0.id == payload.recurringId }),
              !isYearLocked(for: payload.scheduledDate),
              let allocations = recurringAllocations(
                for: recurring,
                amount: payload.amount,
                txDate: payload.scheduledDate,
                treatAsYearly: recurring.frequency == .yearly && !payload.isMonthlySpread,
                projects: snapshot.projects
              )
        else {
            return false
        }

        let occurrence = RecurringDueOccurrence(
            recurringId: payload.recurringId,
            scheduledDate: payload.scheduledDate,
            amount: payload.amount,
            previewMemo: payload.memo,
            postingMemo: payload.postingMemo,
            categoryId: payload.categoryId,
            isMonthlySpread: payload.isMonthlySpread,
            monthKey: payload.monthKey,
            projectName: payload.projectName,
            allocationMode: payload.allocationMode,
            isSkipped: false,
            isYearLocked: false
        )

        do {
            let posting = try buildApprovedPosting(
                recurring: recurring,
                amount: payload.amount,
                date: payload.scheduledDate,
                memo: payload.postingMemo,
                snapshot: snapshot
            )
            let candidate = try await postingSupport.saveDraftCandidate(
                posting: posting,
                allocationAmounts: allocations
            )
            _ = try await postingWorkflowUseCase.approveCandidate(
                candidateId: candidate.id,
                entryType: posting.entryType,
                description: posting.description,
                approvedAt: posting.approvedAt,
                actor: "system"
            )
            _ = applyRecurringProcessedOccurrence(occurrence, recurring: recurring)
            let approved = request.updated(
                status: .approved,
                updatedAt: Date(),
                resolvedAt: .some(Date())
            )
            try await approvalRequestRepository.save(approved)
            return true
        } catch {
            return false
        }
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
