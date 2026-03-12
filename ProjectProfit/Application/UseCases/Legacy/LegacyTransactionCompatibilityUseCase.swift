#if DEBUG
import Foundation
import SwiftData

@MainActor
struct LegacyTransactionCompatibilityUseCase {
    private let store: DataStore

    init(modelContext: ModelContext) {
        self.store = DataStore(modelContext: modelContext)
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
        let result = store.addTransactionResult(
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
        if enqueueCanonicalSync, case .success(let transaction) = result {
            _ = store.syncCanonicalArtifactsSynchronously(
                forTransactionId: transaction.id,
                source: candidateSource
            )
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
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> PPTransaction {
        store.loadData()
        let transaction = store.addTransaction(
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
        if enqueueCanonicalSync {
            _ = store.syncCanonicalArtifactsSynchronously(
                forTransactionId: transaction.id,
                source: candidateSource
            )
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
        store.loadData()
        let updated = store.updateTransaction(
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
            mutationSource: mutationSource
        )
        if updated && enqueueCanonicalSync {
            _ = store.syncCanonicalArtifactsSynchronously(
                forTransactionId: id,
                source: candidateSource
            )
        }
        return updated
    }

    func deleteTransaction(
        id: UUID,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) {
        store.loadData()
        store.deleteTransaction(id: id, mutationSource: mutationSource)
        _ = store.removeCanonicalArtifactsSynchronously(forTransactionId: id)
    }

    @discardableResult
    func addManualJournalEntry(
        date: Date,
        memo: String,
        lines: [(accountId: String, debit: Int, credit: Int, memo: String)],
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> PPJournalEntry? {
        store.loadData()
        return store.addManualJournalEntry(
            date: date,
            memo: memo,
            lines: lines,
            mutationSource: mutationSource
        )
    }

    func deleteManualJournalEntry(
        id: UUID,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) {
        store.loadData()
        store.deleteManualJournalEntry(id: id, mutationSource: mutationSource)
    }
}
#endif
