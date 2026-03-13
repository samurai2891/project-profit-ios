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
    private let store: RecurringWorkflowStore
    private let postingCoordinator: RecurringPostingCoordinator

    init(
        modelContext: ModelContext,
        recurringRepository: (any RecurringRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        postingWorkflowUseCase: PostingWorkflowUseCase? = nil,
        postingSupport: CanonicalPostingSupport? = nil,
        onRecurringScheduleChanged: (([PPRecurringTransaction]) -> Void)? = nil,
        calendar: Calendar = .current
    ) {
        let recurringRepository = recurringRepository ?? SwiftDataRecurringRepository(modelContext: modelContext)
        let transactionFormQueryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        let postingWorkflowUseCase = postingWorkflowUseCase ?? PostingWorkflowUseCase(modelContext: modelContext)
        let postingSupport = postingSupport ?? CanonicalPostingSupport(
            modelContext: modelContext,
            transactionFormQueryUseCase: transactionFormQueryUseCase,
            postingWorkflowUseCase: postingWorkflowUseCase
        )
        self.store = RecurringWorkflowStore(
            modelContext: modelContext,
            recurringRepository: recurringRepository,
            transactionFormQueryUseCase: transactionFormQueryUseCase,
            postingSupport: postingSupport,
            onRecurringScheduleChanged: onRecurringScheduleChanged,
            calendar: calendar
        )
        self.postingCoordinator = RecurringPostingCoordinator(
            modelContext: modelContext,
            recurringRepository: recurringRepository,
            transactionFormQueryUseCase: transactionFormQueryUseCase,
            postingSupport: postingSupport,
            onRecurringScheduleChanged: { [onRecurringScheduleChanged] in
                guard let onRecurringScheduleChanged else {
                    return
                }
                let recurrings = (try? recurringRepository.allRecurringTransactions()) ?? []
                onRecurringScheduleChanged(recurrings)
            },
            calendar: calendar
        )
    }

    @discardableResult
    func createRecurring(input: RecurringUpsertInput) -> PPRecurringTransaction {
        store.createRecurring(input: input)
    }

    func updateRecurring(id: UUID, input: RecurringUpsertInput) {
        store.updateRecurring(id: id, input: input)
    }

    func deleteRecurring(id: UUID) {
        store.deleteRecurring(id: id)
    }

    func setRecurringActive(id: UUID, isActive: Bool) {
        store.setRecurringActive(id: id, isActive: isActive)
    }

    func setRecurringSkipped(id: UUID, date: Date, isSkipped: Bool) {
        store.setRecurringSkipped(id: id, date: date, isSkipped: isSkipped)
    }

    func setNotificationTiming(id: UUID, timing: NotificationTiming) {
        store.setNotificationTiming(id: id, timing: timing)
    }

    func previewRecurringTransactions() -> [RecurringPreviewItem] {
        postingCoordinator.previewRecurringTransactions()
    }

    func processDueRecurringTransactions() -> Int {
        postingCoordinator.processDueRecurringTransactions()
    }

    func approveRecurringItems(_ approvedIds: Set<UUID>, from items: [RecurringPreviewItem]) async -> Int {
        await postingCoordinator.approveRecurringItems(approvedIds, from: items)
    }
}
