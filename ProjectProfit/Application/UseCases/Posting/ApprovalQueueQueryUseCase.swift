import Foundation
import SwiftData

@MainActor
struct ApprovalQueueQueryUseCase {
    private let repository: any ApprovalQueueRepository
    private let postingCandidateRepository: (any PostingCandidateRepository)?
    private let approvalRequestRepository: (any ApprovalRequestRepository)?
    private let formDraftRepository: (any FormDraftRepository)?
    private let recurringWorkflowUseCase: RecurringWorkflowUseCase?
    private let startMonth: Int

    init(
        repository: any ApprovalQueueRepository,
        postingCandidateRepository: (any PostingCandidateRepository)? = nil,
        approvalRequestRepository: (any ApprovalRequestRepository)? = nil,
        formDraftRepository: (any FormDraftRepository)? = nil,
        recurringWorkflowUseCase: RecurringWorkflowUseCase? = nil,
        startMonth: Int = FiscalYearSettings.startMonth
    ) {
        self.repository = repository
        self.postingCandidateRepository = postingCandidateRepository
        self.approvalRequestRepository = approvalRequestRepository
        self.formDraftRepository = formDraftRepository
        self.recurringWorkflowUseCase = recurringWorkflowUseCase
        self.startMonth = startMonth
    }

    init(
        modelContext: ModelContext,
        startMonth: Int = FiscalYearSettings.startMonth
    ) {
        self.init(
            repository: SwiftDataApprovalQueueRepository(modelContext: modelContext),
            postingCandidateRepository: SwiftDataPostingCandidateRepository(modelContext: modelContext),
            approvalRequestRepository: SwiftDataApprovalRequestRepository(modelContext: modelContext),
            formDraftRepository: SwiftDataFormDraftRepository(modelContext: modelContext),
            recurringWorkflowUseCase: RecurringWorkflowUseCase(modelContext: modelContext),
            startMonth: startMonth
        )
    }

    func reloadKey(selectedFilterRawValue: String) -> String {
        [
            currentBusinessId()?.uuidString ?? "none",
            selectedFilterRawValue,
        ].joined(separator: ":")
    }

    func currentBusinessId() -> UUID? {
        try? repository.snapshot().businessId
    }

    func isYearLocked(date: Date) -> Bool {
        guard let businessId = currentBusinessId() else {
            return false
        }
        let taxYear = fiscalYear(for: date, startMonth: startMonth)
        let state = (try? repository.yearLockState(businessId: businessId, taxYear: taxYear)) ?? .open
        return !state.allowsNormalPosting
    }

    func canonicalAccounts() -> [CanonicalAccount] {
        (try? repository.snapshot().canonicalAccounts) ?? []
    }

    func availableProjects() -> [PPProject] {
        (try? repository.snapshot().projects) ?? []
    }

    func projectName(id: UUID?) -> String? {
        guard let id else { return nil }
        return try? repository.projectName(id: id)
    }

    func pendingItems() async throws -> [ApprovalQueueItem] {
        guard let businessId = currentBusinessId(),
              let postingCandidateRepository,
              let approvalRequestRepository else {
            return []
        }

        _ = await recurringWorkflowUseCase?.previewRecurringTransactions()
        let draftCandidates = try await postingCandidateRepository.findByStatus(businessId: businessId, status: .draft)
        let reviewCandidates = try await postingCandidateRepository.findByStatus(businessId: businessId, status: .needsReview)
        let requests = try await approvalRequestRepository.findByBusiness(
            businessId: businessId,
            statuses: [.pending],
            kinds: nil
        )
        return ((draftCandidates + reviewCandidates)
            .map(ApprovalQueueItem.candidate)
            + requests.map(ApprovalQueueItem.request))
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    func request(_ id: UUID) async throws -> ApprovalRequest? {
        try await approvalRequestRepository?.findById(id)
    }

    func formDraft(draftKey: String) async throws -> FormDraft? {
        try await formDraftRepository?.findByKey(draftKey)
    }

    func activeRequest(for draftKey: String) async throws -> ApprovalRequest? {
        guard let draft = try await formDraft(draftKey: draftKey),
              let requestId = draft.activeApprovalRequestId else {
            return nil
        }
        return try await request(requestId)
    }

    func recurringPreviewItems() async throws -> [RecurringPreviewItem] {
        await recurringWorkflowUseCase?.previewRecurringTransactions() ?? []
    }

    func pendingRecurringRequestCount() async throws -> Int {
        let items = try await recurringPreviewItems()
        return items.count
    }
}
