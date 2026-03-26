import Foundation
import SwiftData
@testable import ProjectProfit

enum TestMutationSource: Sendable, Equatable {
    case systemGenerated
    case userInitiated
}

@MainActor
struct TestMutationDriver {
    private let store: ProjectProfit.DataStore
    private let modelContext: ModelContext
    private let postingSupport: CanonicalPostingSupport
    private let postingWorkflowUseCase: PostingWorkflowUseCase

    init(store: ProjectProfit.DataStore) {
        self.store = store
        self.modelContext = store.modelContext
        self.postingSupport = CanonicalPostingSupport(modelContext: store.modelContext)
        self.postingWorkflowUseCase = PostingWorkflowUseCase(modelContext: store.modelContext)
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
        mutationSource: TestMutationSource = .systemGenerated
    ) -> Result<PPTransaction, AppError> {
        do {
            if let blockedError = blockedLegacyTransactionMutation(source: mutationSource) {
                refreshStore(lastError: blockedError)
                return .failure(blockedError)
            }
            guard !store.cannotPostNormalEntry(for: date) else {
                let error = AppError.yearLocked(
                    year: fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)
                )
                refreshStore(lastError: error)
                return .failure(error)
            }

            let transactionId = UUID()
            let journal = try persistCanonicalTransaction(
                transactionId: transactionId,
                existingJournalId: nil,
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
                candidateSource: candidateSource ?? .manual
            )
            let transaction = upsertShadowTransaction(
                id: transactionId,
                journalEntryId: journal.id,
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
                counterparty: counterparty
            )
            try modelContext.save()
            refreshStore(lastError: nil)
            return .success(transaction)
        } catch let error as AppError {
            refreshStore(lastError: error)
            return .failure(error)
        } catch {
            let appError = AppError.saveFailed(underlying: error)
            refreshStore(lastError: appError)
            return .failure(appError)
        }
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
        reloadStoreAfterMutation: Bool = true,
        mutationSource: TestMutationSource = .systemGenerated
    ) -> PPTransaction {
        switch addTransactionResult(
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
            mutationSource: mutationSource
        ) {
        case .success(let transaction):
            if reloadStoreAfterMutation {
                store.loadData()
            }
            return transaction
        case .failure(let error):
            preconditionFailure("TestMutationDriver.addTransaction failed: \(error.localizedDescription)")
        }
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
        mutationSource: TestMutationSource = .systemGenerated
    ) -> Bool {
        if let blockedError = blockedLegacyTransactionMutation(source: mutationSource) {
            refreshStore(lastError: blockedError)
            return false
        }
        guard let transaction = store.allTransactions.first(where: { $0.id == id }) else {
            refreshStore(lastError: .transactionNotFound(id: id))
            return false
        }
        let targetDate = date ?? transaction.date
        guard !store.cannotPostNormalEntry(for: targetDate), !store.cannotPostNormalEntry(for: transaction.date) else {
            let error = AppError.yearLocked(
                year: fiscalYear(for: targetDate, startMonth: FiscalYearSettings.startMonth)
            )
            refreshStore(lastError: error)
            return false
        }

        do {
            let updatedType = type ?? transaction.type
            let updatedAmount = amount ?? transaction.amount
            let updatedCategoryId = categoryId ?? transaction.categoryId
            let updatedMemo = memo ?? transaction.memo
            let updatedAllocations = allocations ?? transaction.allocations.map { ($0.projectId, $0.ratio) }
            let updatedReceiptImagePath = receiptImagePath ?? transaction.receiptImagePath
            let updatedLineItems = lineItems ?? transaction.lineItems
            let updatedPaymentAccountId = paymentAccountId ?? transaction.paymentAccountId
            let updatedTransferToAccountId = transferToAccountId ?? transaction.transferToAccountId
            let updatedTaxDeductibleRate = taxDeductibleRate ?? transaction.taxDeductibleRate
            let updatedTaxAmount = taxAmount ?? transaction.taxAmount
            let updatedTaxRate = taxRate ?? transaction.taxRate
            let updatedIsTaxIncluded = isTaxIncluded ?? transaction.isTaxIncluded
            let updatedTaxCategory = taxCategory ?? transaction.taxCategory
            let updatedCounterpartyId = counterpartyId ?? transaction.counterpartyId
            let updatedCounterparty = counterparty ?? transaction.counterparty

            let journal = try persistCanonicalTransaction(
                transactionId: transaction.id,
                existingJournalId: transaction.journalEntryId,
                type: updatedType,
                amount: updatedAmount,
                date: targetDate,
                categoryId: updatedCategoryId,
                memo: updatedMemo,
                allocations: updatedAllocations,
                recurringId: transaction.recurringId,
                receiptImagePath: updatedReceiptImagePath,
                lineItems: updatedLineItems,
                paymentAccountId: updatedPaymentAccountId,
                transferToAccountId: updatedTransferToAccountId,
                taxDeductibleRate: updatedTaxDeductibleRate,
                taxAmount: updatedTaxAmount,
                taxRate: updatedTaxRate,
                isTaxIncluded: updatedIsTaxIncluded,
                taxCategory: updatedTaxCategory,
                counterpartyId: updatedCounterpartyId,
                counterparty: updatedCounterparty,
                candidateSource: candidateSource ?? .manual
            )

            _ = upsertShadowTransaction(
                id: transaction.id,
                journalEntryId: journal.id,
                type: updatedType,
                amount: updatedAmount,
                date: targetDate,
                categoryId: updatedCategoryId,
                memo: updatedMemo,
                allocations: updatedAllocations,
                recurringId: transaction.recurringId,
                receiptImagePath: updatedReceiptImagePath,
                lineItems: updatedLineItems,
                paymentAccountId: updatedPaymentAccountId,
                transferToAccountId: updatedTransferToAccountId,
                taxDeductibleRate: updatedTaxDeductibleRate,
                taxAmount: updatedTaxAmount,
                taxRate: updatedTaxRate,
                isTaxIncluded: updatedIsTaxIncluded,
                taxCategory: updatedTaxCategory,
                counterpartyId: updatedCounterpartyId,
                counterparty: updatedCounterparty,
                createdAt: transaction.createdAt
            )
            try modelContext.save()
            refreshStore(lastError: nil)
            return true
        } catch {
            refreshStore(lastError: normalizedAppError(error))
            return false
        }
    }

    func deleteTransaction(
        id: UUID,
        mutationSource: TestMutationSource = .systemGenerated
    ) {
        if let blockedError = blockedLegacyTransactionMutation(source: mutationSource) {
            refreshStore(lastError: blockedError)
            return
        }
        guard let transaction = store.allTransactions.first(where: { $0.id == id }) else {
            refreshStore(lastError: .transactionNotFound(id: id))
            return
        }
        guard !store.cannotPostNormalEntry(for: transaction.date) else {
            let error = AppError.yearLocked(
                year: fiscalYear(for: transaction.date, startMonth: FiscalYearSettings.startMonth)
            )
            refreshStore(lastError: error)
            return
        }

        do {
            if let journalId = transaction.journalEntryId {
                try deleteCanonicalJournal(journalId: journalId)
            }
            transaction.deletedAt = Date()
            transaction.updatedAt = Date()
            try modelContext.save()
            refreshStore(lastError: nil)
        } catch {
            refreshStore(lastError: normalizedAppError(error))
        }
    }

    @discardableResult
    func addRecurring(
        name: String,
        description: String = "",
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
        mutationSource: TestMutationSource = .systemGenerated
    ) -> PPJournalEntry? {
        if let blockedError = blockedLegacyManualJournalMutation(source: mutationSource) {
            refreshStore(lastError: blockedError)
            return nil
        }
        guard !lines.isEmpty else {
            refreshStore(lastError: nil)
            return nil
        }
        guard !store.isYearLocked(for: date) else {
            refreshStore(lastError: nil)
            return nil
        }
        guard let businessId = store.businessProfile?.id else {
            let error = AppError.invalidInput(message: "事業者プロフィールが未設定です")
            refreshStore(lastError: error)
            return nil
        }

        do {
            let entryId = UUID()
            let now = Date()
            let taxYear = fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)
            let canonicalLines = try lines.enumerated().map { index, line in
                guard let accountId = store.canonicalAccountId(for: line.accountId),
                      let account = store.canonicalAccount(id: accountId) else {
                    throw PostingWorkflowUseCaseError.accountNotFound(UUID())
                }
                return JournalLine(
                    journalId: entryId,
                    accountId: accountId,
                    debitAmount: Decimal(line.debit),
                    creditAmount: Decimal(line.credit),
                    legalReportLineId: account.defaultLegalReportLineId,
                    sortOrder: index
                )
            }
            let canonicalEntry = CanonicalJournalEntry(
                id: entryId,
                businessId: businessId,
                taxYear: taxYear,
                journalDate: date,
                voucherNo: try nextVoucherNumber(businessId: businessId, taxYear: taxYear, month: Calendar.current.component(.month, from: date)).value,
                entryType: .manual,
                description: memo,
                lines: canonicalLines,
                approvedAt: canonicalLinesBalanced(canonicalLines) ? now : nil,
                createdAt: now,
                updatedAt: now
            )

            modelContext.insert(CanonicalJournalEntryEntityMapper.toEntity(canonicalEntry))
            let legacyEntry = PPJournalEntry(
                id: entryId,
                sourceKey: PPJournalEntry.manualSourceKey(entryId),
                date: date,
                entryType: .manual,
                memo: memo,
                isPosted: canonicalEntry.isBalanced,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(legacyEntry)
            for (index, line) in lines.enumerated() {
                modelContext.insert(
                    PPJournalLine(
                        entryId: entryId,
                        accountId: line.accountId,
                        debit: line.debit,
                        credit: line.credit,
                        memo: line.memo,
                        displayOrder: index,
                        createdAt: now,
                        updatedAt: now
                    )
                )
            }
            try modelContext.save()
            try? LocalJournalSearchIndex(modelContext: modelContext).rebuild(
                businessId: businessId,
                taxYear: taxYear
            )
            refreshStore(lastError: nil)
            return legacyEntry
        } catch {
            refreshStore(lastError: normalizedAppError(error))
            return nil
        }
    }

    func deleteManualJournalEntry(
        id: UUID,
        mutationSource: TestMutationSource = .systemGenerated
    ) {
        if let blockedError = blockedLegacyManualJournalMutation(source: mutationSource) {
            refreshStore(lastError: blockedError)
            return
        }
        guard let entry = store.journalEntries.first(where: { $0.id == id && $0.entryType == .manual }) else {
            refreshStore(lastError: nil)
            return
        }
        guard !store.isYearLocked(for: entry.date) else {
            refreshStore(lastError: nil)
            return
        }

        do {
            try deleteCanonicalJournal(journalId: id)
            for line in store.journalLines where line.entryId == id {
                modelContext.delete(line)
            }
            modelContext.delete(entry)
            try modelContext.save()
            refreshStore(lastError: nil)
        } catch {
            refreshStore(lastError: normalizedAppError(error))
        }
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

    private func blockedLegacyTransactionMutation(source: TestMutationSource) -> AppError? {
        guard source == .userInitiated, FeatureFlags.useCanonicalPosting else {
            return nil
        }
        return .legacyTransactionMutationDisabled
    }

    private func blockedLegacyManualJournalMutation(source: TestMutationSource) -> AppError? {
        guard source == .userInitiated, FeatureFlags.useCanonicalPosting else {
            return nil
        }
        return .legacyManualJournalMutationDisabled
    }

    private func persistCanonicalTransaction(
        transactionId: UUID,
        existingJournalId: UUID?,
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        recurringId: UUID?,
        receiptImagePath: String?,
        lineItems: [ReceiptLineItem],
        paymentAccountId: String?,
        transferToAccountId: String?,
        taxDeductibleRate: Int?,
        taxAmount: Int?,
        taxRate: Int?,
        isTaxIncluded: Bool?,
        taxCategory: TaxCategory?,
        counterpartyId: UUID?,
        counterparty: String?,
        candidateSource: CandidateSource
    ) throws -> CanonicalJournalEntry {
        let snapshot = try postingSupport.snapshot()
        let resolvedTaxCode = TaxCode.resolve(
            legacyCategory: taxCategory,
            taxRate: taxRate
        )?.rawValue
        let posting = try postingSupport.buildApprovedPosting(
            seed: CanonicalPostingSeed(
                id: transactionId,
                type: type,
                amount: amount,
                date: date,
                categoryId: categoryId,
                memo: memo,
                recurringId: recurringId,
                paymentAccountId: paymentAccountId,
                transferToAccountId: type == .transfer ? transferToAccountId : nil,
                taxDeductibleRate: type == .expense ? taxDeductibleRate : nil,
                taxAmount: taxAmount,
                taxCodeId: resolvedTaxCode,
                isTaxIncluded: isTaxIncluded,
                receiptImagePath: receiptImagePath,
                lineItems: lineItems,
                counterpartyId: counterpartyId,
                counterpartyName: counterparty,
                source: candidateSource,
                createdAt: Date(),
                updatedAt: Date(),
                journalEntryId: existingJournalId
            ),
            snapshot: snapshot
        )
        let allocationAmounts = type == .transfer ? [] : calculateRatioAllocations(amount: amount, allocations: allocations)
        let actor = candidateSource == .importFile ? "user" : "system"
        return try postingSupport.persistApprovedPosting(
            posting: posting,
            allocationAmounts: allocationAmounts,
            actor: actor,
            saveChanges: false
        )
    }

    @discardableResult
    private func upsertShadowTransaction(
        id: UUID,
        journalEntryId: UUID,
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        recurringId: UUID?,
        receiptImagePath: String?,
        lineItems: [ReceiptLineItem],
        paymentAccountId: String?,
        transferToAccountId: String?,
        taxDeductibleRate: Int?,
        taxAmount: Int?,
        taxRate: Int?,
        isTaxIncluded: Bool?,
        taxCategory: TaxCategory?,
        counterpartyId: UUID?,
        counterparty: String?,
        createdAt: Date = Date()
    ) -> PPTransaction {
        let resolvedCounterparty = counterpartyId.flatMap { id in
            store.canonicalCounterparty(id: id)?.displayName
        } ?? counterparty
        let normalizedAllocations = type == .transfer ? [] : calculateRatioAllocations(amount: amount, allocations: allocations)
        if let existing = store.allTransactions.first(where: { $0.id == id }) {
            existing.type = type
            existing.amount = amount
            existing.date = date
            existing.categoryId = categoryId
            existing.memo = memo
            existing.allocations = normalizedAllocations
            existing.recurringId = recurringId
            existing.receiptImagePath = receiptImagePath
            existing.lineItems = lineItems
            existing.paymentAccountId = paymentAccountId
            existing.transferToAccountId = transferToAccountId
            existing.taxDeductibleRate = taxDeductibleRate
            existing.taxAmount = taxAmount
            existing.taxRate = taxRate
            existing.isTaxIncluded = isTaxIncluded
            existing.taxCategory = taxCategory
            existing.taxCodeId = TaxCode.resolve(legacyCategory: taxCategory, taxRate: taxRate)?.rawValue
            existing.counterpartyId = counterpartyId
            existing.counterparty = resolvedCounterparty
            existing.journalEntryId = journalEntryId
            existing.deletedAt = nil
            existing.updatedAt = Date()
            return existing
        }

        let transaction = PPTransaction.makeCompatibilityTransaction(
            id: id,
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: normalizedAllocations,
            recurringId: recurringId,
            receiptImagePath: receiptImagePath,
            lineItems: lineItems,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            journalEntryId: journalEntryId,
            taxAmount: taxAmount,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyId: counterpartyId,
            counterparty: resolvedCounterparty,
            createdAt: createdAt,
            updatedAt: Date()
        )
        modelContext.insert(transaction)
        return transaction
    }

    private func deleteCanonicalJournal(journalId: UUID) throws {
        let journalDescriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.journalId == journalId }
        )
        guard let journalEntity = try modelContext.fetch(journalDescriptor).first else {
            return
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
        try modelContext.save()
        try? LocalJournalSearchIndex(modelContext: modelContext).rebuild(
            businessId: businessId,
            taxYear: taxYear
        )
    }

    private func nextVoucherNumber(businessId: UUID, taxYear: Int, month: Int) throws -> VoucherNumber {
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

    private func canonicalLinesBalanced(_ lines: [JournalLine]) -> Bool {
        let debit = lines.reduce(Decimal.zero) { $0 + $1.debitAmount }
        let credit = lines.reduce(Decimal.zero) { $0 + $1.creditAmount }
        return debit == credit && debit > 0
    }

    private func normalizedAppError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .saveFailed(underlying: error)
    }

    private func refreshStore(lastError: AppError?) {
        store.loadData()
        store.lastError = lastError
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
