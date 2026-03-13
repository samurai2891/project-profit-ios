#if DEBUG
import Foundation
import SwiftData
@testable import ProjectProfit

@MainActor
struct LegacyTransactionCompatibilityUseCase {
    private let modelContext: ModelContext
    private let store: ProjectProfit.DataStore

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.store = ProjectProfit.DataStore(modelContext: modelContext)
        self.store.loadData()
    }

    var lastError: AppError? {
        store.lastError
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
        store.loadData()
        if let error = guardLegacyTransactionMutationAllowed(source: mutationSource) {
            return .failure(error)
        }
        guard !store.cannotPostNormalEntry(for: date) else {
            return .failure(.yearLocked(year: fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)))
        }

        let safeCategoryId: String
        switch type {
        case .transfer:
            safeCategoryId = categoryId
        case .income, .expense:
            safeCategoryId = categoryId.isEmpty ? Self.defaultCategoryId(for: type) : categoryId
        }

        let baseAllocations = type == .transfer ? [] : allocations
        let resolvedCounterparty = resolveLegacyCounterpartyReference(
            explicitId: counterpartyId,
            rawName: counterparty,
            defaultTaxCodeId: TaxCode.resolve(
                legacyCategory: taxCategory,
                taxRate: taxRate
            )?.rawValue
        )
        let transaction = PPTransaction(
            type: type,
            amount: amount,
            date: date,
            categoryId: safeCategoryId,
            memo: memo,
            allocations: calculateRatioAllocations(amount: amount, allocations: baseAllocations),
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
            counterpartyId: resolvedCounterparty.id,
            counterparty: resolvedCounterparty.displayName
        )
        modelContext.insert(transaction)

        guard saveAndRefreshTransactions() else {
            return .failure(currentError())
        }
        let result: Result<PPTransaction, AppError> = .success(transaction)
        #if DEBUG
        if enqueueCanonicalSync, case .success(let transaction) = result {
            _ = LegacyTransactionTestSupport(store: store).syncCanonicalArtifactsSynchronously(
                forTransactionId: transaction.id,
                source: candidateSource
            )
        }
        #endif
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
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
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
            enqueueCanonicalSync: enqueueCanonicalSync,
            mutationSource: mutationSource
        ) {
        case .success(let transaction):
            return transaction
        case .failure(let error):
            preconditionFailure("LegacyTransactionCompatibilityUseCase.addTransaction failed: \(error.localizedDescription). Use addTransactionResult() for failure handling.")
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
        enqueueCanonicalSync: Bool = true,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> Bool {
        store.loadData()
        if guardLegacyTransactionMutationAllowed(source: mutationSource) != nil {
            return false
        }
        guard let transaction = store.transactions.first(where: { $0.id == id }) else {
            store.lastError = .transactionNotFound(id: id)
            return false
        }
        if store.cannotPostNormalEntry(for: transaction.date) {
            return false
        }
        if let date, store.cannotPostNormalEntry(for: date) {
            return false
        }

        store.lastError = nil
        let transactionId = transaction.id
        if let type {
            logFieldChange(transactionId: transactionId, fieldName: "type", oldValue: transaction.type.rawValue, newValue: type.rawValue)
            transaction.type = type
        }
        if let date {
            logFieldChange(transactionId: transactionId, fieldName: "date", oldValue: transaction.date.ISO8601Format(), newValue: date.ISO8601Format())
            transaction.date = date
        }
        if let categoryId {
            logFieldChange(transactionId: transactionId, fieldName: "categoryId", oldValue: transaction.categoryId, newValue: categoryId)
            transaction.categoryId = categoryId
        }
        if let memo {
            logFieldChange(transactionId: transactionId, fieldName: "memo", oldValue: transaction.memo, newValue: memo)
            transaction.memo = memo
        }
        if let receiptImagePath {
            logFieldChange(transactionId: transactionId, fieldName: "receiptImagePath", oldValue: transaction.receiptImagePath, newValue: receiptImagePath)
            transaction.receiptImagePath = receiptImagePath
        }
        if let lineItems {
            transaction.lineItems = lineItems
        }
        if let paymentAccountId {
            logFieldChange(transactionId: transactionId, fieldName: "paymentAccountId", oldValue: transaction.paymentAccountId, newValue: paymentAccountId)
            transaction.paymentAccountId = paymentAccountId
        }
        if let transferToAccountId {
            logFieldChange(transactionId: transactionId, fieldName: "transferToAccountId", oldValue: transaction.transferToAccountId, newValue: transferToAccountId)
            transaction.transferToAccountId = transferToAccountId
        }
        if let taxDeductibleRate {
            logFieldChange(transactionId: transactionId, fieldName: "taxDeductibleRate", oldValue: transaction.taxDeductibleRate.map(String.init), newValue: taxDeductibleRate.map(String.init))
            transaction.taxDeductibleRate = taxDeductibleRate
        }
        if let taxAmount {
            logFieldChange(transactionId: transactionId, fieldName: "taxAmount", oldValue: transaction.taxAmount.map(String.init), newValue: taxAmount.map(String.init))
            transaction.taxAmount = taxAmount
        }
        if let taxRate {
            logFieldChange(transactionId: transactionId, fieldName: "taxRate", oldValue: transaction.taxRate.map(String.init), newValue: taxRate.map(String.init))
            transaction.taxRate = taxRate
        }
        if let isTaxIncluded {
            logFieldChange(transactionId: transactionId, fieldName: "isTaxIncluded", oldValue: transaction.isTaxIncluded.map(String.init), newValue: isTaxIncluded.map(String.init))
            transaction.isTaxIncluded = isTaxIncluded
        }
        if let taxCategory {
            logFieldChange(transactionId: transactionId, fieldName: "taxCategory", oldValue: transaction.taxCategory?.rawValue, newValue: taxCategory?.rawValue)
            transaction.taxCategory = taxCategory
        }
        if taxRate != nil || taxCategory != nil {
            let resolvedTaxCode = TaxCode.resolve(
                legacyCategory: transaction.taxCategory,
                taxRate: transaction.taxRate
            )
            transaction.taxCodeId = resolvedTaxCode?.rawValue
            if let resolvedTaxCode {
                transaction.taxRate = resolvedTaxCode.taxRatePercent
                transaction.taxCategory = resolvedTaxCode.legacyCategory
            }
        }
        if let counterpartyId {
            logFieldChange(
                transactionId: transactionId,
                fieldName: "counterpartyId",
                oldValue: transaction.counterpartyId?.uuidString,
                newValue: counterpartyId?.uuidString
            )
            transaction.counterpartyId = counterpartyId
        }
        if let counterparty {
            logFieldChange(transactionId: transactionId, fieldName: "counterparty", oldValue: transaction.counterparty, newValue: counterparty)
            transaction.counterparty = counterparty
        }

        if counterpartyId != nil || counterparty != nil {
            let resolvedCounterparty = resolveLegacyCounterpartyReference(
                explicitId: transaction.counterpartyId,
                rawName: transaction.counterparty,
                defaultTaxCodeId: TaxCode.resolve(
                    legacyCategory: taxCategory ?? transaction.taxCategory,
                    taxRate: taxRate ?? transaction.taxRate
                )?.rawValue
            )
            transaction.counterpartyId = resolvedCounterparty.id
            transaction.counterparty = resolvedCounterparty.displayName
        }

        let finalAmount = amount ?? transaction.amount
        if let amount {
            logFieldChange(transactionId: transactionId, fieldName: "amount", oldValue: String(transaction.amount), newValue: String(amount))
            transaction.amount = amount
        }

        if let allocations {
            transaction.allocations = calculateRatioAllocations(amount: finalAmount, allocations: allocations)
            if let recurringId = transaction.recurringId,
               let recurring = store.recurringTransactions.first(where: { $0.id == recurringId }),
               recurring.allocationMode == .equalAll {
                transaction.isManuallyEdited = true
            }
        } else if amount != nil {
            transaction.allocations = recalculateAllocationAmounts(amount: finalAmount, existingAllocations: transaction.allocations)
            reapplyProRataIfNeeded(transaction: transaction, amount: finalAmount)
        }

        transaction.updatedAt = Date()

        guard saveAndRefreshTransactions() else {
            return false
        }
        let updated = true
        #if DEBUG
        if updated && enqueueCanonicalSync {
            _ = LegacyTransactionTestSupport(store: store).syncCanonicalArtifactsSynchronously(
                forTransactionId: id,
                source: candidateSource
            )
        }
        #endif
        return updated
    }

    func deleteTransaction(
        id: UUID,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) {
        store.loadData()
        if guardLegacyTransactionMutationAllowed(source: mutationSource) != nil {
            return
        }
        guard let transaction = store.allTransactions.first(where: { $0.id == id }) else {
            return
        }
        if store.cannotPostNormalEntry(for: transaction.date) {
            return
        }

        transaction.deletedAt = Date()
        transaction.updatedAt = Date()
        if let recurringId = transaction.recurringId,
           let recurring = store.recurringTransactions.first(where: { $0.id == recurringId }) {
            rollBackRecurringGenerationState(recurring: recurring, deletedTransactionDate: transaction.date)
        }

        guard saveAndRefreshTransactions(refreshRecurring: true) else {
            return
        }
        _ = LegacyTransactionTestSupport(store: store).removeCanonicalArtifactsSynchronously(forTransactionId: id)
    }

    @discardableResult
    func addManualJournalEntry(
        date: Date,
        memo: String,
        lines: [(accountId: String, debit: Int, credit: Int, memo: String)],
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> PPJournalEntry? {
        store.loadData()
        guard !lines.isEmpty else {
            return nil
        }
        if mutationSource == .userInitiated, FeatureFlags.useCanonicalPosting {
            store.lastError = .legacyManualJournalMutationDisabled
            return nil
        }
        guard !store.isYearLocked(for: date) else {
            return nil
        }

        let entry = PPJournalEntry(
            sourceKey: "manual:\(UUID().uuidString)",
            date: date,
            entryType: .manual,
            memo: memo,
            isPosted: false
        )
        modelContext.insert(entry)

        for (index, line) in lines.enumerated() {
            let journalLine = PPJournalLine(
                entryId: entry.id,
                accountId: line.accountId,
                debit: line.debit,
                credit: line.credit,
                memo: line.memo,
                displayOrder: index
            )
            modelContext.insert(journalLine)
        }

        let debitTotal = lines.reduce(0) { $0 + $1.debit }
        let creditTotal = lines.reduce(0) { $0 + $1.credit }
        let allLinesValid = lines.allSatisfy { line in
            line.debit >= 0 && line.credit >= 0
                && !(line.debit > 0 && line.credit > 0)
                && (line.debit > 0 || line.credit > 0)
        }
        if debitTotal == creditTotal && debitTotal > 0 && allLinesValid {
            entry.isPosted = true
        }

        guard saveAndRefreshManualJournals() else {
            return nil
        }
        return entry
    }

    func deleteManualJournalEntry(
        id: UUID,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) {
        store.loadData()
        guard let entry = store.journalEntries.first(where: { $0.id == id }) else {
            return
        }
        guard entry.entryType == .manual else {
            return
        }
        if mutationSource == .userInitiated, FeatureFlags.useCanonicalPosting {
            store.lastError = .legacyManualJournalMutationDisabled
            return
        }
        if store.isYearLocked(for: entry.date) {
            return
        }

        for line in store.journalLines where line.entryId == id {
            modelContext.delete(line)
        }
        modelContext.delete(entry)
        _ = saveAndRefreshManualJournals()
    }

    private var postingSupport: CanonicalPostingSupport {
        CanonicalPostingSupport(modelContext: modelContext)
    }

    private static func defaultCategoryId(for type: TransactionType) -> String {
        switch type {
        case .expense, .transfer:
            return "cat-other-expense"
        case .income:
            return "cat-other-income"
        }
    }

    private func guardLegacyTransactionMutationAllowed(
        source: LegacyTransactionMutationSource
    ) -> AppError? {
        guard source == .userInitiated, FeatureFlags.useCanonicalPosting else {
            return nil
        }
        let error = AppError.legacyTransactionMutationDisabled
        store.lastError = error
        return error
    }

    private func resolveLegacyCounterpartyReference(
        explicitId: UUID?,
        rawName: String?,
        defaultTaxCodeId: String?
    ) -> (id: UUID?, displayName: String?) {
        do {
            return try postingSupport.resolveCounterpartyReference(
                explicitId: explicitId,
                rawName: rawName,
                defaultTaxCodeId: defaultTaxCodeId,
                businessId: store.businessProfile?.id
            )
        } catch {
            AppLogger.dataStore.warning("Legacy counterparty resolution failed: \(error.localizedDescription)")
            return (explicitId, normalizedOptionalString(rawName))
        }
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func saveAndRefreshTransactions(refreshRecurring: Bool = false) -> Bool {
        guard store.save() else {
            return false
        }
        store.lastError = nil
        store.refreshTransactions()
        store.refreshJournalEntries()
        store.refreshJournalLines()
        if refreshRecurring {
            store.refreshRecurring()
        }
        return true
    }

    private func saveAndRefreshManualJournals() -> Bool {
        guard store.save() else {
            return false
        }
        store.lastError = nil
        store.refreshJournalEntries()
        store.refreshJournalLines()
        return true
    }

    private func currentError() -> AppError {
        store.lastError ?? .saveFailed(
            underlying: NSError(
                domain: "LegacyTransactionCompatibilityUseCase",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Legacy transaction mutation failed"]
            )
        )
    }

    private func logFieldChange(transactionId: UUID, fieldName: String, oldValue: String?, newValue: String?) {
        guard oldValue != newValue else {
            return
        }
        modelContext.insert(
            PPTransactionLog(
                transactionId: transactionId,
                fieldName: fieldName,
                oldValue: oldValue,
                newValue: newValue
            )
        )
    }

    private func reapplyProRataIfNeeded(transaction: PPTransaction, amount: Int) {
        let calendar = Calendar.current
        let txComponents = calendar.dateComponents([.year, .month], from: transaction.date)
        guard let txYear = txComponents.year, let txMonth = txComponents.month else {
            return
        }

        let isYearly = transaction.recurringId.flatMap { recurringId in
            store.recurringTransactions.first(where: { $0.id == recurringId })
        }.map { $0.frequency == .yearly } ?? false

        let totalDays = isYearly
            ? daysInYear(txYear)
            : daysInMonth(year: txYear, month: txMonth)

        let needsProRata = transaction.allocations.contains { allocation in
            guard let project = store.projects.first(where: { $0.id == allocation.projectId }) else {
                return false
            }
            let activeDays = isYearly
                ? calculateActiveDaysInYear(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear)
                : calculateActiveDaysInMonth(
                    startDate: project.startDate,
                    completedAt: project.effectiveEndDate,
                    year: txYear,
                    month: txMonth
                )
            return activeDays < totalDays
        }
        guard needsProRata else {
            return
        }

        let inputs = transaction.allocations.map { allocation in
            let project = store.projects.first(where: { $0.id == allocation.projectId })
            let activeDays = isYearly
                ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                : calculateActiveDaysInMonth(
                    startDate: project?.startDate,
                    completedAt: project?.effectiveEndDate,
                    year: txYear,
                    month: txMonth
                )
            return HolisticProRataInput(projectId: allocation.projectId, ratio: allocation.ratio, activeDays: activeDays)
        }
        transaction.allocations = calculateHolisticProRata(
            totalAmount: amount,
            totalDays: totalDays,
            inputs: inputs
        )
    }

    private func rollBackRecurringGenerationState(
        recurring: PPRecurringTransaction,
        deletedTransactionDate: Date
    ) {
        let calendar = Calendar.current
        let remainingTransactions = store.transactions
            .filter { $0.recurringId == recurring.id }
            .sorted { $0.date < $1.date }

        if recurring.frequency == .yearly,
           recurring.yearlyAmortizationMode == .monthlySpread {
            let deletedComponents = calendar.dateComponents([.year, .month], from: deletedTransactionDate)
            if let year = deletedComponents.year, let month = deletedComponents.month {
                let monthKey = String(format: "%d-%02d", year, month)
                recurring.lastGeneratedMonths = recurring.lastGeneratedMonths.filter { $0 != monthKey }
            }
            recurring.lastGeneratedDate = remainingTransactions.last?.date
        } else {
            recurring.lastGeneratedDate = remainingTransactions.last?.date
        }

        recurring.updatedAt = Date()
    }
}
#endif
