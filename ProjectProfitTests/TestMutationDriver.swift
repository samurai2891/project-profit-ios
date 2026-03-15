import Foundation
import SwiftData
@testable import ProjectProfit

enum LegacyTransactionMutationSource: Sendable, Equatable {
    case systemGenerated
    case userInitiated
}

@MainActor
struct LegacyTransactionTestSupport {
    private let store: ProjectProfit.DataStore
    private let modelContext: ModelContext
    private let postingSupport: CanonicalPostingSupport

    init(store: ProjectProfit.DataStore) {
        self.store = store
        self.modelContext = store.modelContext
        self.postingSupport = CanonicalPostingSupport(modelContext: store.modelContext)
    }

    func syncCanonicalArtifacts(
        forTransactionId transactionId: UUID,
        source: CandidateSource? = nil
    ) async -> ProjectProfit.DataStore.CanonicalTransactionSyncResult {
        syncCanonicalArtifactsSynchronously(
            forTransactionId: transactionId,
            source: source
        )
    }

    func syncCanonicalArtifactsSynchronously(
        forTransactionId transactionId: UUID,
        source: CandidateSource? = nil
    ) -> ProjectProfit.DataStore.CanonicalTransactionSyncResult {
        store.loadData()
        guard let transaction = store.allTransactions.first(where: { $0.id == transactionId }) else {
            return ProjectProfit.DataStore.CanonicalTransactionSyncResult(
                counterpartyStatus: .skippedSourceNotFound,
                postingStatus: .skippedSourceNotFound
            )
        }

        let explicitTaxCodeId = compatibilityTaxCodeId(
            explicitTaxCodeId: transaction.taxCodeId,
            legacyCategory: transaction.taxCategory,
            taxRate: transaction.taxRate
        )
        let counterpartyStatus = syncCanonicalCounterpartyNow(
            explicitId: transaction.counterpartyId,
            rawName: transaction.counterparty,
            defaultTaxCodeId: explicitTaxCodeId
        )
        let counterpartyId: UUID?
        switch counterpartyStatus {
        case .synced(let id):
            counterpartyId = id
        case .skippedSourceNotFound, .skippedBusinessProfileUnavailable, .skippedBlankName, .failed:
            counterpartyId = nil
        }

        let posting: CanonicalTransactionPostingBridge.Posting
        do {
            posting = try buildCanonicalPosting(
                for: transaction,
                counterpartyId: counterpartyId,
                source: source ?? .manual
            )
        } catch AppError.invalidInput(let message)
            where message.contains("事業者プロフィールが未設定") {
            return ProjectProfit.DataStore.CanonicalTransactionSyncResult(
                counterpartyStatus: counterpartyStatus,
                postingStatus: .skippedBusinessProfileUnavailable
            )
        } catch AppError.yearLocked {
            return ProjectProfit.DataStore.CanonicalTransactionSyncResult(
                counterpartyStatus: counterpartyStatus,
                postingStatus: .skippedBusinessProfileUnavailable
            )
        } catch {
            return ProjectProfit.DataStore.CanonicalTransactionSyncResult(
                counterpartyStatus: counterpartyStatus,
                postingStatus: .skippedLegacyJournalUnavailable
            )
        }

        do {
            let journal = try postingSupport.persistApprovedPosting(
                posting: posting,
                allocationAmounts: transaction.allocations.filter { $0.amount > 0 },
                actor: source == .importFile ? "user" : "system",
                saveChanges: true
            )
            if transaction.journalEntryId != journal.id {
                transaction.journalEntryId = journal.id
                _ = store.save()
                store.refreshTransactions()
            }
            return ProjectProfit.DataStore.CanonicalTransactionSyncResult(
                counterpartyStatus: counterpartyStatus,
                postingStatus: .synced(candidateId: posting.candidate.id, journalId: journal.id)
            )
        } catch {
            AppLogger.dataStore.warning("Canonical posting sync failed: \(error.localizedDescription)")
            return ProjectProfit.DataStore.CanonicalTransactionSyncResult(
                counterpartyStatus: counterpartyStatus,
                postingStatus: .failed(error.localizedDescription)
            )
        }
    }

    @discardableResult
    func removeCanonicalArtifactsSynchronously(forTransactionId transactionId: UUID) -> Bool {
        store.loadData()
        guard let transaction = store.allTransactions.first(where: { $0.id == transactionId }),
              let journalId = transaction.journalEntryId else {
            return true
        }

        do {
            let journalDescriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate { $0.journalId == journalId }
            )
            guard let journalEntity = try modelContext.fetch(journalDescriptor).first else {
                transaction.journalEntryId = nil
                _ = store.save()
                store.refreshTransactions()
                return true
            }

            let businessId = journalEntity.businessId
            let taxYear = journalEntity.taxYear
            let sourceCandidateId = journalEntity.sourceCandidateId

            modelContext.delete(journalEntity)

            if let sourceCandidateId {
                let candidateDescriptor = FetchDescriptor<PostingCandidateEntity>(
                    predicate: #Predicate { $0.candidateId == sourceCandidateId }
                )
                try modelContext.fetch(candidateDescriptor).forEach(modelContext.delete)
            }

            transaction.journalEntryId = nil
            try modelContext.save()
            try? LocalJournalSearchIndex(modelContext: modelContext).rebuild(
                businessId: businessId,
                taxYear: taxYear
            )
            store.refreshTransactions()
            store.refreshJournalEntries()
            store.refreshJournalLines()
            return true
        } catch {
            AppLogger.dataStore.warning("Canonical artifact removal failed: \(error.localizedDescription)")
            return false
        }
    }

    private func compatibilityTaxCodeId(
        explicitTaxCodeId: String?,
        legacyCategory: TaxCategory?,
        taxRate: Int?
    ) -> String? {
        if let taxCodeId = TaxCode.resolve(id: explicitTaxCodeId)?.rawValue {
            return taxCodeId
        }
        return TaxCode.resolve(legacyCategory: legacyCategory, taxRate: taxRate)?.rawValue
    }

    private func syncCanonicalCounterpartyNow(
        explicitId: UUID?,
        rawName: String?,
        defaultTaxCodeId: String?
    ) -> ProjectProfit.DataStore.CanonicalCounterpartySyncStatus {
        do {
            let resolved = try postingSupport.resolveCounterpartyReference(
                explicitId: explicitId,
                rawName: rawName,
                defaultTaxCodeId: defaultTaxCodeId,
                businessId: store.businessProfile?.id
            )
            guard let counterpartyId = resolved.id else {
                if explicitId != nil || store.businessProfile == nil {
                    return .skippedBusinessProfileUnavailable
                }
                return .skippedBlankName
            }
            try modelContext.save()
            return .synced(counterpartyId)
        } catch {
            AppLogger.dataStore.warning("Canonical counterparty sync failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private func buildCanonicalPosting(
        for transaction: PPTransaction,
        counterpartyId: UUID?,
        source: CandidateSource
    ) throws -> CanonicalTransactionPostingBridge.Posting {
        try postingSupport.buildApprovedPosting(
            seed: CanonicalPostingSeed(
                id: transaction.id,
                type: transaction.type,
                amount: transaction.amount,
                date: transaction.date,
                categoryId: transaction.categoryId,
                memo: transaction.memo,
                recurringId: transaction.recurringId,
                paymentAccountId: transaction.paymentAccountId,
                transferToAccountId: transaction.transferToAccountId,
                taxDeductibleRate: transaction.taxDeductibleRate,
                taxAmount: transaction.taxAmount,
                taxCodeId: transaction.taxCodeId,
                isTaxIncluded: transaction.isTaxIncluded,
                receiptImagePath: transaction.receiptImagePath,
                lineItems: transaction.lineItems,
                counterpartyId: counterpartyId,
                counterpartyName: transaction.counterparty,
                source: source,
                createdAt: transaction.createdAt,
                updatedAt: transaction.updatedAt,
                journalEntryId: transaction.journalEntryId
            ),
            snapshot: try postingSupport.snapshot()
        )
    }
}

@MainActor
struct TestMutationDriver {
    private let store: ProjectProfit.DataStore
    private let modelContext: ModelContext
    private let legacySupport: LegacyTransactionTestSupport

    init(store: ProjectProfit.DataStore) {
        self.store = store
        self.modelContext = store.modelContext
        self.legacySupport = LegacyTransactionTestSupport(store: store)
    }

    @discardableResult
    func addProject(
        name: String,
        description: String,
        startDate: Date? = nil,
        plannedEndDate: Date? = nil
    ) -> PPProject {
        let project = ProjectWorkflowUseCase(modelContext: modelContext).createProject(
            input: ProjectUpsertInput(
                name: name,
                description: description,
                status: .active,
                startDate: startDate,
                completedAt: nil,
                plannedEndDate: plannedEndDate
            )
        )
        store.loadData()
        return project
    }

    func updateProject(
        id: UUID,
        name: String? = nil,
        description: String? = nil,
        status: ProjectStatus? = nil,
        startDate: Date?? = nil,
        completedAt: Date?? = nil,
        plannedEndDate: Date?? = nil
    ) {
        guard let project = store.getProject(id: id) else { return }

        let resolvedStatus = status ?? project.status
        let resolvedStartDate = startDate ?? project.startDate
        let resolvedCompletedAt: Date? = {
            if let completedAt { return completedAt }
            if resolvedStatus == .completed {
                return project.completedAt ?? Date()
            }
            return nil
        }()
        let resolvedPlannedEndDate = plannedEndDate ?? project.plannedEndDate

        ProjectWorkflowUseCase(modelContext: modelContext).updateProject(
            id: id,
            input: ProjectUpsertInput(
                name: name ?? project.name,
                description: description ?? project.projectDescription,
                status: resolvedStatus,
                startDate: resolvedStartDate,
                completedAt: resolvedCompletedAt,
                plannedEndDate: resolvedPlannedEndDate
            )
        )
        store.loadData()
    }

    func deleteProject(id: UUID) {
        ProjectWorkflowUseCase(modelContext: modelContext).deleteProject(id: id)
        store.loadData()
    }

    func deleteProjects(ids: Set<UUID>) {
        ProjectWorkflowUseCase(modelContext: modelContext).deleteProjects(ids: ids)
        store.loadData()
    }

    func archiveProject(id: UUID) {
        store.archiveProject(id: id)
        store.loadData()
    }

    func addTransactionResult(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        recurringId: UUID? = nil,
        receiptImagePath: String? = nil,
        lineItems: [ReceiptLineItem] = [],
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        taxAmount: Int? = nil,
        taxRate: Int? = nil,
        isTaxIncluded: Bool? = nil,
        taxCategory: TaxCategory? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil,
        candidateSource: CandidateSource? = nil,
        enqueueCanonicalSync: Bool = true,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> Result<PPTransaction, AppError> {
        let result = LegacyTransactionCompatibilityUseCase(modelContext: modelContext).addTransactionResult(
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocations,
            recurringId: recurringId,
            receiptImagePath: receiptImagePath,
            lineItems: lineItems,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            taxAmount: taxAmount,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyId: counterpartyId,
            counterparty: counterparty,
            candidateSource: candidateSource,
            enqueueCanonicalSync: enqueueCanonicalSync,
            mutationSource: mutationSource
        )
        store.loadData()
        if case .failure(let error) = result {
            store.lastError = error
        } else {
            store.lastError = nil
        }
        return result
    }

    @discardableResult
    func addTransaction(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        recurringId: UUID? = nil,
        receiptImagePath: String? = nil,
        lineItems: [ReceiptLineItem] = [],
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        taxAmount: Int? = nil,
        taxRate: Int? = nil,
        isTaxIncluded: Bool? = nil,
        taxCategory: TaxCategory? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil,
        candidateSource: CandidateSource? = nil,
        enqueueCanonicalSync: Bool = true,
        reloadStoreAfterMutation: Bool = true,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> PPTransaction {
        let transaction = LegacyTransactionCompatibilityUseCase(modelContext: modelContext).addTransaction(
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocations,
            recurringId: recurringId,
            receiptImagePath: receiptImagePath,
            lineItems: lineItems,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            taxAmount: taxAmount,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyId: counterpartyId,
            counterparty: counterparty,
            candidateSource: candidateSource,
            enqueueCanonicalSync: enqueueCanonicalSync,
            mutationSource: mutationSource
        )
        if reloadStoreAfterMutation {
            store.loadData()
        }
        return transaction
    }

    @discardableResult
    func updateTransaction(
        id: UUID,
        type: TransactionType? = nil,
        amount: Int? = nil,
        date: Date? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        allocations: [(projectId: UUID, ratio: Int)]? = nil,
        receiptImagePath: String?? = nil,
        lineItems: [ReceiptLineItem]? = nil,
        paymentAccountId: String?? = nil,
        transferToAccountId: String?? = nil,
        taxDeductibleRate: Int?? = nil,
        taxAmount: Int?? = nil,
        taxRate: Int?? = nil,
        isTaxIncluded: Bool?? = nil,
        taxCategory: TaxCategory?? = nil,
        counterpartyId: UUID?? = nil,
        counterparty: String?? = nil,
        candidateSource: CandidateSource? = nil,
        enqueueCanonicalSync: Bool = true,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> Bool {
        let useCase = LegacyTransactionCompatibilityUseCase(modelContext: modelContext)
        let updated = useCase.updateTransaction(
            id: id,
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocations,
            receiptImagePath: receiptImagePath,
            lineItems: lineItems,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            taxAmount: taxAmount,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyId: counterpartyId,
            counterparty: counterparty,
            candidateSource: candidateSource,
            enqueueCanonicalSync: enqueueCanonicalSync,
            mutationSource: mutationSource
        )
        store.loadData()
        store.lastError = useCase.lastError
        return updated
    }

    func deleteTransaction(
        id: UUID,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) {
        let useCase = LegacyTransactionCompatibilityUseCase(modelContext: modelContext)
        useCase.deleteTransaction(
            id: id,
            mutationSource: mutationSource
        )
        store.loadData()
        store.lastError = useCase.lastError
    }

    func syncCanonicalArtifacts(
        forTransactionId transactionId: UUID,
        source: CandidateSource? = nil
    ) async -> ProjectProfit.DataStore.CanonicalTransactionSyncResult {
        let result = await legacySupport.syncCanonicalArtifacts(
            forTransactionId: transactionId,
            source: source
        )
        store.loadData()
        return result
    }

    @discardableResult
    func addRecurring(
        name: String,
        type: TransactionType,
        amount: Int,
        categoryId: String,
        memo: String,
        allocationMode: AllocationMode = .manual,
        allocations: [(projectId: UUID, ratio: Int)],
        frequency: RecurringFrequency,
        dayOfMonth: Int,
        monthOfYear: Int? = nil,
        endDate: Date? = nil,
        yearlyAmortizationMode: YearlyAmortizationMode = .lumpSum,
        receiptImagePath: String? = nil,
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil
    ) -> PPRecurringTransaction {
        let recurring = recurringWorkflowUseCase().createRecurring(
            input: RecurringUpsertInput(
                name: name,
                type: type,
                amount: amount,
                categoryId: categoryId,
                memo: memo,
                allocationMode: allocationMode,
                allocations: allocations.map { RecurringAllocationInput(projectId: $0.projectId, ratio: $0.ratio) },
                frequency: frequency,
                dayOfMonth: dayOfMonth,
                monthOfYear: monthOfYear,
                isActive: true,
                endDate: endDate,
                yearlyAmortizationMode: yearlyAmortizationMode,
                receiptImagePath: receiptImagePath,
                paymentAccountId: paymentAccountId,
                transferToAccountId: transferToAccountId,
                taxDeductibleRate: taxDeductibleRate,
                counterpartyId: counterpartyId,
                counterparty: counterparty
            )
        )
        store.loadData()
        return recurring
    }

    func updateRecurring(
        id: UUID,
        name: String? = nil,
        type: TransactionType? = nil,
        amount: Int? = nil,
        categoryId: String? = nil,
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
        guard let recurring = store.getRecurring(id: id) else { return }

        let updatedInput = RecurringUpsertInput(
            name: name ?? recurring.name,
            type: type ?? recurring.type,
            amount: amount ?? recurring.amount,
            categoryId: categoryId ?? recurring.categoryId,
            memo: memo ?? recurring.memo,
            allocationMode: allocationMode ?? recurring.allocationMode,
            allocations: (allocations ?? recurring.allocations.map { ($0.projectId, $0.ratio) })
                .map { RecurringAllocationInput(projectId: $0.projectId, ratio: $0.ratio) },
            frequency: frequency ?? recurring.frequency,
            dayOfMonth: dayOfMonth ?? recurring.dayOfMonth,
            monthOfYear: monthOfYear ?? recurring.monthOfYear,
            isActive: isActive ?? recurring.isActive,
            endDate: endDate ?? recurring.endDate,
            yearlyAmortizationMode: yearlyAmortizationMode ?? recurring.yearlyAmortizationMode,
            receiptImagePath: receiptImagePath ?? recurring.receiptImagePath,
            paymentAccountId: paymentAccountId ?? recurring.paymentAccountId,
            transferToAccountId: transferToAccountId ?? recurring.transferToAccountId,
            taxDeductibleRate: taxDeductibleRate ?? recurring.taxDeductibleRate,
            counterpartyId: counterpartyId ?? recurring.counterpartyId,
            counterparty: counterparty ?? recurring.counterparty
        )

        let useCase = recurringWorkflowUseCase()
        useCase.updateRecurring(id: id, input: updatedInput)

        if let notificationTiming {
            useCase.setNotificationTiming(id: id, timing: notificationTiming)
        }

        if let skipDates {
            let currentSkipDates = Set(recurring.skipDates.map(dayKey(for:)))
            let requestedSkipDates = Set(skipDates.map(dayKey(for:)))

            for date in skipDates where !currentSkipDates.contains(dayKey(for: date)) {
                useCase.setRecurringSkipped(id: id, date: date, isSkipped: true)
            }
            for date in recurring.skipDates where !requestedSkipDates.contains(dayKey(for: date)) {
                useCase.setRecurringSkipped(id: id, date: date, isSkipped: false)
            }
        }

        store.loadData()
    }

    func deleteRecurring(id: UUID) {
        recurringWorkflowUseCase().deleteRecurring(id: id)
        store.loadData()
    }

    @discardableResult
    func processRecurringTransactions() -> Int {
        let count = recurringWorkflowUseCase().processDueRecurringTransactions()
        store.loadData()
        return count
    }

    @discardableResult
    func addManualJournalEntry(
        date: Date,
        memo: String,
        lines: [(accountId: String, debit: Int, credit: Int, memo: String)],
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> PPJournalEntry? {
        let useCase = LegacyTransactionCompatibilityUseCase(modelContext: modelContext)
        let entry = useCase.addManualJournalEntry(
            date: date,
            memo: memo,
            lines: lines,
            mutationSource: mutationSource
        )
        store.loadData()
        store.lastError = useCase.lastError
        return entry
    }

    func deleteManualJournalEntry(
        id: UUID,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) {
        let useCase = LegacyTransactionCompatibilityUseCase(modelContext: modelContext)
        useCase.deleteManualJournalEntry(
            id: id,
            mutationSource: mutationSource
        )
        store.loadData()
        store.lastError = useCase.lastError
    }

    @discardableResult
    func addInventoryRecord(
        fiscalYear: Int,
        openingInventory: Int = 0,
        purchases: Int = 0,
        closingInventory: Int = 0,
        memo: String? = nil
    ) -> PPInventoryRecord? {
        let record = InventoryWorkflowUseCase(
            modelContext: modelContext,
            reloadInventoryRecords: { self.store.refreshInventoryRecords() },
            setError: { self.store.lastError = $0 }
        ).createInventoryRecord(
            input: InventoryUpsertInput(
                fiscalYear: fiscalYear,
                openingInventory: openingInventory,
                purchases: purchases,
                closingInventory: closingInventory,
                memo: memo
            )
        )
        store.loadData()
        return record
    }

    @discardableResult
    func updateInventoryRecord(
        id: UUID,
        openingInventory: Int? = nil,
        purchases: Int? = nil,
        closingInventory: Int? = nil,
        memo: String?? = nil
    ) -> Bool {
        guard let record = store.inventoryRecords.first(where: { $0.id == id }) else { return false }
        let saved = InventoryWorkflowUseCase(
            modelContext: modelContext,
            reloadInventoryRecords: { self.store.refreshInventoryRecords() },
            setError: { self.store.lastError = $0 }
        ).updateInventoryRecord(
            id: id,
            input: InventoryUpsertInput(
                fiscalYear: record.fiscalYear,
                openingInventory: openingInventory ?? record.openingInventory,
                purchases: purchases ?? record.purchases,
                closingInventory: closingInventory ?? record.closingInventory,
                memo: memo ?? record.memo
            )
        )
        store.loadData()
        return saved
    }

    @discardableResult
    func deleteInventoryRecord(id: UUID) -> Bool {
        let deleted = InventoryWorkflowUseCase(
            modelContext: modelContext,
            reloadInventoryRecords: { self.store.refreshInventoryRecords() },
            setError: { self.store.lastError = $0 }
        ).deleteInventoryRecord(id: id)
        store.loadData()
        return deleted
    }

    func lockFiscalYear(_ year: Int) {
        store.lockFiscalYear(year)
        store.loadData()
    }

    func unlockFiscalYear(_ year: Int) {
        store.unlockFiscalYear(year)
        store.loadData()
    }

    @discardableResult
    func transitionFiscalYearState(_ state: YearLockState, for year: Int) -> Bool {
        do {
            _ = try ClosingWorkflowUseCase(modelContext: modelContext)
                .transitionFiscalYearState(state, for: year)
            store.loadData()
            return true
        } catch {
            store.lastError = error as? AppError ?? .saveFailed(underlying: error)
            store.loadData()
            return false
        }
    }

    func importTransactions(from csvString: String) async -> CSVImportResult {
        let result = await PostingIntakeUseCase(modelContext: modelContext).importTransactions(
            request: CSVImportRequest(
                csvString: csvString,
                originalFileName: "test-import.csv",
                fileData: Data(csvString.utf8),
                mimeType: "text/csv",
                channel: .settingsTransactionCSV
            )
        )
        store.loadData()
        return result
    }

    func deleteAllData() {
        SettingsMaintenanceUseCase(
            modelContext: modelContext,
            resetStoreState: { self.store.loadData() }
        ).deleteAllData()
    }

    private func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func recurringWorkflowUseCase() -> RecurringWorkflowUseCase {
        RecurringWorkflowUseCase(
            modelContext: modelContext,
            onRecurringScheduleChanged: store.onRecurringScheduleChanged
        )
    }
}

@MainActor
func mutations(_ store: ProjectProfit.DataStore) -> TestMutationDriver {
    TestMutationDriver(store: store)
}
