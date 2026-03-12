import Foundation
import SwiftData

struct ManualPostingCandidateInput: Sendable {
    let type: TransactionType
    let amount: Int
    let date: Date
    let categoryId: String
    let memo: String
    let allocations: [(projectId: UUID, ratio: Int)]
    let paymentAccountId: String?
    let transferToAccountId: String?
    let taxDeductibleRate: Int?
    let taxAmount: Int?
    let taxCodeId: String?
    let taxRate: Int?
    let isTaxIncluded: Bool?
    let taxCategory: TaxCategory?
    let counterpartyId: UUID?
    let counterparty: String?
    let candidateSource: CandidateSource
}

@MainActor
struct PostingIntakeUseCase {
    private let repository: any PostingIntakeRepository
    private let postingWorkflowUseCase: PostingWorkflowUseCase

    fileprivate init(
        repository: any PostingIntakeRepository,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) {
        self.repository = repository
        self.postingWorkflowUseCase = postingWorkflowUseCase
    }

    init(modelContext: ModelContext) {
        self.init(
            repository: SwiftDataPostingIntakeRepository(modelContext: modelContext),
            postingWorkflowUseCase: PostingWorkflowUseCase(modelContext: modelContext)
        )
    }

    func saveManualCandidate(input: ManualPostingCandidateInput) async throws -> PostingCandidate {
        try await repository.saveManualCandidate(
            input: input,
            postingWorkflowUseCase: postingWorkflowUseCase
        )
    }

    func importTransactions(csvString: String) async -> CSVImportResult {
        await repository.importTransactions(
            csvString: csvString,
            postingWorkflowUseCase: postingWorkflowUseCase
        )
    }
}

@MainActor
private protocol PostingIntakeRepository {
    func saveManualCandidate(
        input: ManualPostingCandidateInput,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async throws -> PostingCandidate
    func importTransactions(
        csvString: String,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async -> CSVImportResult
}

@MainActor
private struct SwiftDataPostingIntakeRepository: PostingIntakeRepository {
    private let store: PostingIntakeStore

    init(modelContext: ModelContext) {
        self.store = PostingIntakeStore(modelContext: modelContext)
    }

    func saveManualCandidate(
        input: ManualPostingCandidateInput,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async throws -> PostingCandidate {
        try await store.makeManualCandidate(
            input: input,
            postingWorkflowUseCase: postingWorkflowUseCase
        )
    }

    func importTransactions(
        csvString: String,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async -> CSVImportResult {
        await store.importTransactions(
            csvString: csvString,
            postingWorkflowUseCase: postingWorkflowUseCase
        )
    }
}
