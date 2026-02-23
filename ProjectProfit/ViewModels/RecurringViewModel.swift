import SwiftUI

// MARK: - RecurringViewModel

@MainActor
@Observable
final class RecurringViewModel {
    let dataStore: DataStore

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    // MARK: - Computed Properties

    var recurringTransactions: [PPRecurringTransaction] {
        dataStore.recurringTransactions
    }

    var hasRecurringTransactions: Bool {
        !dataStore.recurringTransactions.isEmpty
    }

    var totalCount: Int {
        dataStore.recurringTransactions.count
    }

    var activeCount: Int {
        dataStore.recurringTransactions.filter(\.isActive).count
    }

    var monthlyTotal: Int {
        dataStore.recurringTransactions
            .filter(\.isActive)
            .reduce(0) { total, recurring in
                let normalised = recurring.frequency == .monthly
                    ? recurring.amount
                    : recurring.amount / 12
                return recurring.type == .income
                    ? total + normalised
                    : total - normalised
            }
    }

    // MARK: - Display Helpers

    func frequencyLabel(_ recurring: PPRecurringTransaction) -> String {
        switch recurring.frequency {
        case .monthly:
            return "毎月\(recurring.dayOfMonth)日"
        case .yearly:
            if (recurring.yearlyAmortizationMode ?? .lumpSum) == .monthlySpread {
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
            dataStore.getProject(id: allocation.projectId)?.name
        }
        return names.joined(separator: ", ")
    }

    func categoryName(for categoryId: String) -> String? {
        dataStore.getCategory(id: categoryId)?.name
    }

    // MARK: - Actions

    func toggleActive(_ recurring: PPRecurringTransaction) {
        dataStore.updateRecurring(id: recurring.id, isActive: !recurring.isActive)
    }

    func confirmSkip(_ recurring: PPRecurringTransaction) {
        guard let info = getNextRegistrationDate(
            frequency: recurring.frequency,
            dayOfMonth: recurring.dayOfMonth,
            monthOfYear: recurring.monthOfYear,
            isActive: recurring.isActive,
            lastGeneratedDate: recurring.lastGeneratedDate
        ) else { return }

        let updatedSkipDates = recurring.skipDates + [info.date]
        dataStore.updateRecurring(id: recurring.id, skipDates: updatedSkipDates)
    }

    func deleteRecurring(_ recurring: PPRecurringTransaction) {
        dataStore.deleteRecurring(id: recurring.id)
    }

    func updateNotificationTiming(for recurring: PPRecurringTransaction, timing: NotificationTiming) {
        dataStore.updateRecurring(id: recurring.id, notificationTiming: timing)
    }

    func endDateLabel(_ recurring: PPRecurringTransaction) -> String? {
        guard let endDate = recurring.endDate else { return nil }
        return "終了日: \(formatDate(endDate))"
    }
}
