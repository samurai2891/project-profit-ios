import Foundation

/// UI 表示専用の取引 read model。
/// canonical 正本由来の項目を優先しつつ、legacy 取引からの変換にも対応する。
struct CanonicalTransactionListItem: Identifiable, Equatable {
    let id: UUID
    let journalId: UUID
    let sourceCandidateId: UUID?
    let sourceEvidenceId: UUID?
    let legacyTransactionId: UUID?
    let date: Date
    let type: TransactionType
    let amount: Int
    let projectAmount: Int?
    let projectRatio: Int?
    let projectAllocations: [CanonicalTransactionProjectAllocation]
    let categoryId: String
    let memo: String
    let lineItems: [ReceiptLineItem]
    let receiptImagePath: String?
    let counterpartyId: UUID?
    let counterpartyName: String?
    let recurringId: UUID?
    let isCanonicalOnly: Bool
    let canOpenLegacyTransactionDetail: Bool

    init(
        id: UUID,
        journalId: UUID,
        sourceCandidateId: UUID?,
        sourceEvidenceId: UUID?,
        legacyTransactionId: UUID?,
        date: Date,
        type: TransactionType,
        amount: Int,
        projectAmount: Int?,
        projectRatio: Int?,
        projectAllocations: [CanonicalTransactionProjectAllocation],
        categoryId: String,
        memo: String,
        lineItems: [ReceiptLineItem],
        receiptImagePath: String?,
        counterpartyId: UUID?,
        counterpartyName: String?,
        recurringId: UUID?,
        isCanonicalOnly: Bool,
        canOpenLegacyTransactionDetail: Bool
    ) {
        self.id = id
        self.journalId = journalId
        self.sourceCandidateId = sourceCandidateId
        self.sourceEvidenceId = sourceEvidenceId
        self.legacyTransactionId = legacyTransactionId
        self.date = date
        self.type = type
        self.amount = amount
        self.projectAmount = projectAmount
        self.projectRatio = projectRatio
        self.projectAllocations = projectAllocations
        self.categoryId = categoryId
        self.memo = memo
        self.lineItems = lineItems
        self.receiptImagePath = receiptImagePath
        self.counterpartyId = counterpartyId
        self.counterpartyName = counterpartyName
        self.recurringId = recurringId
        self.isCanonicalOnly = isCanonicalOnly
        self.canOpenLegacyTransactionDetail = canOpenLegacyTransactionDetail
    }

    init(_ legacyTransaction: PPTransaction) {
        self.init(
            id: legacyTransaction.id,
            journalId: legacyTransaction.journalEntryId ?? legacyTransaction.id,
            sourceCandidateId: nil,
            sourceEvidenceId: nil,
            legacyTransactionId: legacyTransaction.id,
            date: legacyTransaction.date,
            type: legacyTransaction.type,
            amount: legacyTransaction.amount,
            projectAmount: nil,
            projectRatio: nil,
            projectAllocations: legacyTransaction.allocations.map { allocation in
                CanonicalTransactionProjectAllocation(
                    projectId: allocation.projectId,
                    projectName: nil,
                    amount: allocation.amount,
                    ratio: allocation.ratio
                )
            },
            categoryId: legacyTransaction.categoryId,
            memo: legacyTransaction.memo,
            lineItems: legacyTransaction.lineItems,
            receiptImagePath: legacyTransaction.receiptImagePath,
            counterpartyId: legacyTransaction.counterpartyId,
            counterpartyName: legacyTransaction.counterparty,
            recurringId: legacyTransaction.recurringId,
            isCanonicalOnly: false,
            canOpenLegacyTransactionDetail: true
        )
    }

    init(_ transaction: CanonicalTransactionDisplayItem, focusedProjectId: UUID? = nil) {
        let focusedAllocation = focusedProjectId.flatMap { projectId in
            transaction.projectAllocations.first(where: { $0.projectId == projectId })
        }
        self.init(
            id: transaction.id,
            journalId: transaction.journalId,
            sourceCandidateId: transaction.sourceCandidateId,
            sourceEvidenceId: transaction.sourceEvidenceId,
            legacyTransactionId: transaction.legacyTransactionId,
            date: transaction.date,
            type: transaction.type,
            amount: transaction.amount,
            projectAmount: focusedAllocation?.amount ?? transaction.projectAmount,
            projectRatio: focusedAllocation?.ratio ?? transaction.projectRatio,
            projectAllocations: transaction.projectAllocations,
            categoryId: transaction.categoryId,
            memo: transaction.memo,
            lineItems: transaction.lineItems,
            receiptImagePath: transaction.receiptImagePath,
            counterpartyId: transaction.counterpartyId,
            counterpartyName: transaction.counterpartyName,
            recurringId: transaction.recurringId,
            isCanonicalOnly: transaction.isCanonicalOnly,
            canOpenLegacyTransactionDetail: transaction.canOpenLegacyTransactionDetail
        )
    }

    init(_ value: CanonicalTransactionListItem) {
        self = value
    }
}
