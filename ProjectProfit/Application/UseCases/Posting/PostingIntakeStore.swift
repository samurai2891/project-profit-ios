import Foundation
import SwiftData

@MainActor
struct PostingIntakeStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func makeManualCandidate(
        input: ManualPostingCandidateInput,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async throws -> PostingCandidate {
        let dataStore = loadedDataStore()
        let result = dataStore.buildCanonicalPostingSync(
            type: input.type,
            amount: input.amount,
            date: input.date,
            categoryId: input.categoryId,
            memo: input.memo,
            allocations: input.allocations,
            recurringId: nil,
            paymentAccountId: input.paymentAccountId,
            transferToAccountId: input.transferToAccountId,
            taxDeductibleRate: input.taxDeductibleRate,
            taxAmount: input.taxAmount,
            taxCodeId: input.taxCodeId,
            taxRate: input.taxRate,
            isTaxIncluded: input.isTaxIncluded,
            taxCategory: input.taxCategory,
            counterpartyId: input.counterpartyId,
            counterparty: input.counterparty,
            source: input.candidateSource
        )

        let posting: CanonicalTransactionPostingBridge.Posting
        switch result {
        case .success(let builtPosting):
            posting = builtPosting
        case .failure(let error):
            throw error
        }

        let normalizedAllocations = calculateRatioAllocations(
            amount: input.amount,
            allocations: input.type == .transfer ? [] : input.allocations
        )
        let candidate = dataStore.candidateWithProjectAllocations(
            posting.candidate.updated(status: .draft),
            allocations: normalizedAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) }
        )

        do {
            try await postingWorkflowUseCase.saveCandidate(candidate)
            return candidate
        } catch {
            throw AppError.saveFailed(underlying: error)
        }
    }

    func importTransactions(csvString: String) async -> CSVImportResult {
        let dataStore = loadedDataStore()
        var successCount = 0
        var errorCount = 0
        var errors: [String] = []

        for entry in parseCSV(csvString: csvString) {
            let allocations: [(projectId: UUID, ratio: Int)] = entry.allocations.compactMap { allocation in
                if let existing = dataStore.projects.first(where: { $0.name == allocation.projectName }) {
                    return (projectId: existing.id, ratio: allocation.ratio)
                }
                let created = dataStore.addProject(name: allocation.projectName, description: "")
                return (projectId: created.id, ratio: allocation.ratio)
            }

            if entry.type != .transfer {
                guard !allocations.isEmpty else {
                    errorCount += 1
                    errors.append("プロジェクトが見つかりません")
                    continue
                }

                let totalRatio = allocations.reduce(0) { $0 + $1.ratio }
                guard totalRatio == 100 else {
                    errorCount += 1
                    errors.append("配分比率が不正です（合計: \(totalRatio)%）")
                    continue
                }
            }

            let categoryId: String
            switch entry.type {
            case .transfer:
                categoryId = ""
            case .income, .expense:
                let categoryType: CategoryType = entry.type == .income ? .income : .expense
                if let existing = dataStore.categories.first(where: {
                    $0.name == entry.categoryName && $0.type == categoryType
                }) {
                    categoryId = existing.id
                } else if let fallback = dataStore.categories.first(where: { $0.name == entry.categoryName }) {
                    categoryId = fallback.id
                } else {
                    errorCount += 1
                    errors.append("カテゴリが見つかりません: \(entry.categoryName)")
                    continue
                }
            }

            let result = dataStore.saveApprovedPostingSync(
                type: entry.type,
                amount: entry.amount,
                date: entry.date,
                categoryId: categoryId,
                memo: entry.memo,
                allocations: entry.type == .transfer ? [] : allocations,
                paymentAccountId: entry.paymentAccountId,
                transferToAccountId: entry.type == .transfer ? entry.transferToAccountId : nil,
                taxDeductibleRate: entry.type == .expense ? entry.taxDeductibleRate : nil,
                taxAmount: entry.taxAmount,
                taxCodeId: nil,
                taxRate: entry.taxRate,
                isTaxIncluded: entry.isTaxIncluded,
                taxCategory: entry.taxCategory,
                counterparty: entry.counterparty,
                candidateSource: .importFile
            )

            switch result {
            case .success:
                successCount += 1
            case .failure(let error):
                errorCount += 1
                errors.append(error.localizedDescription)
            }
        }

        return CSVImportResult(successCount: successCount, errorCount: errorCount, errors: errors)
    }

    private func loadedDataStore() -> DataStore {
        let dataStore = DataStore(modelContext: modelContext)
        dataStore.loadData()
        return dataStore
    }
}
