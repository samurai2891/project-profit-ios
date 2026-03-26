import SwiftData
import SwiftUI

// MARK: - RecurringViewModel

@MainActor
@Observable
final class RecurringViewModel {
    private let recurringQueryUseCase: RecurringQueryUseCase
    private let recurringWorkflowUseCase: RecurringWorkflowUseCase
    private let calendar: Calendar

    private(set) var listSnapshot: RecurringListSnapshot = .empty

    init(
        modelContext: ModelContext,
        onRecurringScheduleChanged: (([PPRecurringTransaction]) -> Void)? = nil,
        calendar: Calendar = .current
    ) {
        self.recurringQueryUseCase = RecurringQueryUseCase(modelContext: modelContext)
        self.recurringWorkflowUseCase = RecurringWorkflowUseCase(
            modelContext: modelContext,
            onRecurringScheduleChanged: onRecurringScheduleChanged,
            calendar: calendar
        )
        self.calendar = calendar
        reload()
    }

    // MARK: - Computed Properties

    var recurringTransactions: [PPRecurringTransaction] {
        listSnapshot.recurringTransactions
    }

    var hasRecurringTransactions: Bool {
        !recurringTransactions.isEmpty
    }

    var totalCount: Int {
        recurringTransactions.count
    }

    var activeCount: Int {
        recurringTransactions.filter(\.isActive).count
    }

    var monthlyTotal: Int {
        recurringTransactions
            .filter(\.isActive)
            .reduce(0) { total, recurring in
                let normalised = recurring.frequency == .monthly
                    ? recurring.amount
                    : recurring.amount / 12
                switch recurring.type {
                case .income: return total + normalised
                case .expense: return total - normalised
                case .transfer: return total
                }
            }
    }

    // MARK: - Display Helpers

    func reload() {
        listSnapshot = recurringQueryUseCase.listSnapshot()
    }

    func frequencyLabel(_ recurring: PPRecurringTransaction) -> String {
        switch recurring.frequency {
        case .monthly:
            return "毎月\(recurring.dayOfMonth)日"
        case .yearly:
            if recurring.yearlyAmortizationMode == .monthlySpread {
                return "毎月\(recurring.dayOfMonth)日（年次分割）"
            }
            if let month = recurring.monthOfYear {
                return "毎年\(month)月\(recurring.dayOfMonth)日"
            }
            return "毎年\(recurring.dayOfMonth)日"
        }
    }

    func projectNamesText(_ allocations: [Allocation]) -> String {
        let names = allocations.compactMap { allocation in
            listSnapshot.projectNamesById[allocation.projectId]
        }
        return names.joined(separator: ", ")
    }

    func categoryName(for categoryId: String) -> String? {
        listSnapshot.categoryNamesById[categoryId]
    }

    // MARK: - Actions

    func toggleActive(_ recurring: PPRecurringTransaction) {
        recurringWorkflowUseCase.setRecurringActive(id: recurring.id, isActive: !recurring.isActive)
        reload()
    }

    func confirmSkip(_ recurring: PPRecurringTransaction) {
        guard let info = getNextRegistrationDate(
            frequency: recurring.frequency,
            dayOfMonth: recurring.dayOfMonth,
            monthOfYear: recurring.monthOfYear,
            isActive: recurring.isActive,
            lastGeneratedDate: recurring.lastGeneratedDate
        ) else { return }

        recurringWorkflowUseCase.setRecurringSkipped(id: recurring.id, date: info.date, isSkipped: true)
        reload()
    }

    func cancelSkip(_ recurring: PPRecurringTransaction) {
        guard let info = getNextRegistrationDate(
            frequency: recurring.frequency,
            dayOfMonth: recurring.dayOfMonth,
            monthOfYear: recurring.monthOfYear,
            isActive: recurring.isActive,
            lastGeneratedDate: recurring.lastGeneratedDate
        ) else { return }

        recurringWorkflowUseCase.setRecurringSkipped(id: recurring.id, date: info.date, isSkipped: false)
        reload()
    }

    func isNextDateSkipped(_ recurring: PPRecurringTransaction) -> Bool {
        guard let info = getNextRegistrationDate(
            frequency: recurring.frequency,
            dayOfMonth: recurring.dayOfMonth,
            monthOfYear: recurring.monthOfYear,
            isActive: recurring.isActive,
            lastGeneratedDate: recurring.lastGeneratedDate
        ) else { return false }

        return recurring.skipDates.contains {
            calendar.isDate($0, inSameDayAs: info.date)
        }
    }

    func deleteRecurring(_ recurring: PPRecurringTransaction) {
        recurringWorkflowUseCase.deleteRecurring(id: recurring.id)
        reload()
    }

    func updateNotificationTiming(for recurring: PPRecurringTransaction, timing: NotificationTiming) {
        recurringWorkflowUseCase.setNotificationTiming(id: recurring.id, timing: timing)
        reload()
    }

    func endDateLabel(_ recurring: PPRecurringTransaction) -> String? {
        guard let endDate = recurring.endDate else { return nil }
        return "終了日: \(formatDate(endDate))"
    }
}
