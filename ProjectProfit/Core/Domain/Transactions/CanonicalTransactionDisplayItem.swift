import Foundation

struct CanonicalTransactionProjectAllocation: Identifiable, Equatable {
    let projectId: UUID
    let projectName: String?
    let amount: Int
    let ratio: Int?

    var id: UUID { projectId }
}

struct CanonicalTransactionDisplayItem: Identifiable, Equatable {
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

    func focused(on projectId: UUID?) -> CanonicalTransactionDisplayItem {
        guard let projectId,
              let allocation = projectAllocations.first(where: { $0.projectId == projectId }) else {
            return self
        }

        return CanonicalTransactionDisplayItem(
            id: id,
            journalId: journalId,
            sourceCandidateId: sourceCandidateId,
            sourceEvidenceId: sourceEvidenceId,
            legacyTransactionId: legacyTransactionId,
            date: date,
            type: type,
            amount: amount,
            projectAmount: allocation.amount,
            projectRatio: allocation.ratio,
            projectAllocations: projectAllocations,
            categoryId: categoryId,
            memo: memo,
            lineItems: lineItems,
            receiptImagePath: receiptImagePath,
            counterpartyId: counterpartyId,
            counterpartyName: counterpartyName,
            recurringId: recurringId,
            isCanonicalOnly: isCanonicalOnly,
            canOpenLegacyTransactionDetail: canOpenLegacyTransactionDetail
        )
    }
}
