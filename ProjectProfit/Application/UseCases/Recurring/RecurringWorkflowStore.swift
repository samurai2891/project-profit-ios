import Foundation
import SwiftData

@MainActor
struct RecurringWorkflowStore {
    private let modelContext: ModelContext
    private let recurringRepository: any RecurringRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let postingSupport: CanonicalPostingSupport
    private let onRecurringScheduleChanged: (([PPRecurringTransaction]) -> Void)?
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        recurringRepository: (any RecurringRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        postingSupport: CanonicalPostingSupport? = nil,
        onRecurringScheduleChanged: (([PPRecurringTransaction]) -> Void)? = nil,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        let recurringRepository = recurringRepository ?? SwiftDataRecurringRepository(modelContext: modelContext)
        let transactionFormQueryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        let postingSupport = postingSupport ?? CanonicalPostingSupport(
            modelContext: modelContext,
            transactionFormQueryUseCase: transactionFormQueryUseCase
        )
        self.recurringRepository = recurringRepository
        self.transactionFormQueryUseCase = transactionFormQueryUseCase
        self.postingSupport = postingSupport
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
        let resolvedCounterparty = (try? postingSupport.resolveCounterpartyReference(
            explicitId: input.counterpartyId,
            rawName: input.counterparty,
            businessId: snapshot.businessId
        )) ?? (id: input.counterpartyId, displayName: input.counterparty)
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
            if let resolvedCounterparty = try? postingSupport.resolveCounterpartyReference(
                explicitId: recurring.counterpartyId,
                rawName: recurring.counterparty,
                businessId: snapshot.businessId
            ) {
                recurring.counterpartyId = resolvedCounterparty.id
                recurring.counterparty = resolvedCounterparty.displayName
            }
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

    private static func defaultCategoryId(for type: TransactionType) -> String {
        switch type {
        case .expense, .transfer:
            "cat-other-expense"
        case .income:
            "cat-other-income"
        }
    }
}
