import Foundation
import SwiftData

struct RecurringAllocationInput: Equatable, Sendable {
    let projectId: UUID
    let ratio: Int
}

struct RecurringUpsertInput: Equatable, Sendable {
    let name: String
    let type: TransactionType
    let amount: Int
    let categoryId: String
    let memo: String
    let allocationMode: AllocationMode
    let allocations: [RecurringAllocationInput]
    let frequency: RecurringFrequency
    let dayOfMonth: Int
    let monthOfYear: Int?
    let isActive: Bool
    let endDate: Date?
    let yearlyAmortizationMode: YearlyAmortizationMode
    let receiptImagePath: String?
    let paymentAccountId: String?
    let transferToAccountId: String?
    let taxDeductibleRate: Int?
    let counterpartyId: UUID?
    let counterparty: String?
}

@MainActor
struct RecurringWorkflowUseCase {
    private let modelContext: ModelContext
    private let onRecurringScheduleChanged: (([PPRecurringTransaction]) -> Void)?
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        onRecurringScheduleChanged: (([PPRecurringTransaction]) -> Void)? = nil,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.onRecurringScheduleChanged = onRecurringScheduleChanged
        self.calendar = calendar
    }

    @discardableResult
    func createRecurring(input: RecurringUpsertInput) -> PPRecurringTransaction {
        withDataStore { dataStore in
            dataStore.addRecurring(
            name: input.name,
            type: input.type,
            amount: input.amount,
            categoryId: input.categoryId,
            memo: input.memo,
            allocationMode: input.allocationMode,
            allocations: input.allocations.map { ($0.projectId, $0.ratio) },
            frequency: input.frequency,
            dayOfMonth: input.dayOfMonth,
            monthOfYear: input.monthOfYear,
            endDate: input.endDate,
            yearlyAmortizationMode: input.yearlyAmortizationMode,
            receiptImagePath: input.receiptImagePath,
            paymentAccountId: input.paymentAccountId,
            transferToAccountId: input.transferToAccountId,
            taxDeductibleRate: input.taxDeductibleRate,
            counterpartyId: input.counterpartyId,
            counterparty: input.counterparty
        )
        }
    }

    func updateRecurring(id: UUID, input: RecurringUpsertInput) {
        withDataStore { dataStore in
            dataStore.updateRecurring(
            id: id,
            name: input.name,
            type: input.type,
            amount: input.amount,
            categoryId: input.categoryId,
            memo: input.memo,
            allocationMode: input.allocationMode,
            allocations: input.allocations.map { ($0.projectId, $0.ratio) },
            frequency: input.frequency,
            dayOfMonth: input.dayOfMonth,
            monthOfYear: input.monthOfYear,
            isActive: input.isActive,
            endDate: .some(input.endDate),
            yearlyAmortizationMode: input.yearlyAmortizationMode,
            receiptImagePath: .some(input.receiptImagePath),
            paymentAccountId: .some(input.paymentAccountId),
            transferToAccountId: .some(input.transferToAccountId),
            taxDeductibleRate: .some(input.taxDeductibleRate),
            counterpartyId: .some(input.counterpartyId),
            counterparty: .some(input.counterparty)
        )
        }
    }

    func deleteRecurring(id: UUID) {
        withDataStore { dataStore in
            dataStore.deleteRecurring(id: id)
        }
    }

    func setRecurringActive(id: UUID, isActive: Bool) {
        withDataStore { dataStore in
            dataStore.updateRecurring(id: id, isActive: isActive)
        }
    }

    func setRecurringSkipped(id: UUID, date: Date, isSkipped: Bool) {
        withDataStore { dataStore in
            guard let recurring = dataStore.getRecurring(id: id) else {
                return
            }

            var updatedSkipDates = recurring.skipDates.filter { !calendar.isDate($0, inSameDayAs: date) }
            if isSkipped {
                updatedSkipDates.append(date)
            }
            dataStore.updateRecurring(id: id, skipDates: updatedSkipDates)
        }
    }

    func setNotificationTiming(id: UUID, timing: NotificationTiming) {
        withDataStore { dataStore in
            dataStore.updateRecurring(id: id, notificationTiming: timing)
        }
    }

    func previewRecurringTransactions() -> [RecurringPreviewItem] {
        withDataStore { dataStore in
            dataStore.previewRecurringTransactions()
        }
    }

    func approveRecurringItems(_ approvedIds: Set<UUID>, from items: [RecurringPreviewItem]) async -> Int {
        let dataStore = configuredDataStore()
        return await dataStore.approveRecurringItems(approvedIds, from: items)
    }

    private func withDataStore<T>(_ body: (DataStore) -> T) -> T {
        body(configuredDataStore())
    }

    private func configuredDataStore() -> DataStore {
        let dataStore = DataStore(modelContext: modelContext)
        dataStore.onRecurringScheduleChanged = onRecurringScheduleChanged
        dataStore.loadData()
        return dataStore
    }
}
