import Foundation
import SwiftData

enum CSVImportChannel: Sendable, Equatable {
    case settingsTransactionCSV
    case ledgerBook(ledgerType: LedgerType, metadataJSON: String?)
}

struct CSVImportRequest: Sendable, Equatable {
    let csvString: String
    let originalFileName: String
    let fileData: Data
    let mimeType: String
    let channel: CSVImportChannel
}

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
    let isTaxIncluded: Bool?
    let counterpartyId: UUID?
    let counterparty: String?
    let isWithholdingEnabled: Bool
    let withholdingTaxCodeId: String?
    let withholdingTaxAmount: Decimal?
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

    func importTransactions(request: CSVImportRequest) async -> CSVImportResult {
        await repository.importTransactions(
            request: request,
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
        request: CSVImportRequest,
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
        request: CSVImportRequest,
        postingWorkflowUseCase: PostingWorkflowUseCase
    ) async -> CSVImportResult {
        await store.importTransactions(
            request: request,
            postingWorkflowUseCase: postingWorkflowUseCase
        )
    }
}
