import Foundation
import SwiftData

enum ApprovalQueueWorkflowError: LocalizedError {
    case approvalRequestNotFound(UUID)
    case formDraftNotFound(String)
    case invalidDistributionPayload(UUID)
    case invalidRecurringRequest(UUID)

    var errorDescription: String? {
        switch self {
        case .approvalRequestNotFound:
            return "承認依頼が見つかりません。"
        case .formDraftNotFound:
            return "フォーム草案が見つかりません。"
        case .invalidDistributionPayload:
            return "配賦承認データを読み込めませんでした。"
        case .invalidRecurringRequest:
            return "定期取引承認データを読み込めませんでした。"
        }
    }
}

@MainActor
struct ApprovalQueueWorkflowUseCase {
    private let approvalRequestRepository: any ApprovalRequestRepository
    private let formDraftRepository: any FormDraftRepository
    private let recurringWorkflowUseCase: RecurringWorkflowUseCase?
    private let distributionUseCase: DistributionTemplateApplicationUseCase

    init(
        approvalRequestRepository: any ApprovalRequestRepository,
        formDraftRepository: any FormDraftRepository,
        recurringWorkflowUseCase: RecurringWorkflowUseCase? = nil,
        distributionUseCase: DistributionTemplateApplicationUseCase = .init()
    ) {
        self.approvalRequestRepository = approvalRequestRepository
        self.formDraftRepository = formDraftRepository
        self.recurringWorkflowUseCase = recurringWorkflowUseCase
        self.distributionUseCase = distributionUseCase
    }

    init(modelContext: ModelContext) {
        self.init(
            approvalRequestRepository: SwiftDataApprovalRequestRepository(modelContext: modelContext),
            formDraftRepository: SwiftDataFormDraftRepository(modelContext: modelContext),
            recurringWorkflowUseCase: RecurringWorkflowUseCase(modelContext: modelContext)
        )
    }

    func request(_ id: UUID) async throws -> ApprovalRequest? {
        try await approvalRequestRepository.findById(id)
    }

    func formDraft(draftKey: String) async throws -> FormDraft? {
        try await formDraftRepository.findByKey(draftKey)
    }

    @discardableResult
    func saveFormDraft(
        businessId: UUID,
        draftKey: String,
        kind: FormDraftKind,
        snapshotJSON: String,
        activeApprovalRequestId: UUID?? = nil
    ) async throws -> FormDraft {
        let existing = try await formDraftRepository.findByKey(draftKey)
        let draft = (existing ?? FormDraft(
            businessId: businessId,
            draftKey: draftKey,
            kind: kind,
            snapshotJSON: snapshotJSON
        )).updated(
            snapshotJSON: snapshotJSON,
            activeApprovalRequestId: activeApprovalRequestId,
            updatedAt: Date()
        )
        try await formDraftRepository.save(draft)
        return draft
    }

    func clearFormDraft(draftKey: String) async throws {
        try await formDraftRepository.deleteByKey(draftKey)
    }

    @discardableResult
    func queueDistributionRequest(
        businessId: UUID,
        draftKey: String,
        draftKind: FormDraftKind,
        snapshotJSON: String,
        requestDraft: ApprovalRequestDraft
    ) async throws -> ApprovalRequest {
        let draft = try await saveFormDraft(
            businessId: businessId,
            draftKey: draftKey,
            kind: draftKind,
            snapshotJSON: snapshotJSON
        )

        if let activeId = draft.activeApprovalRequestId,
           let existing = try await approvalRequestRepository.findById(activeId),
           existing.kind == .distribution,
           existing.status == .pending {
            try await approvalRequestRepository.save(
                existing.updated(
                    status: .invalidated,
                    updatedAt: Date(),
                    resolvedAt: .some(Date())
                )
            )
        }

        let request = ApprovalRequest(
            businessId: requestDraft.businessId,
            kind: requestDraft.kind,
            status: .pending,
            targetKind: requestDraft.targetKind,
            targetKey: requestDraft.targetKey,
            title: requestDraft.title,
            subtitle: requestDraft.subtitle,
            payloadJSON: requestDraft.payloadJSON,
            createdAt: requestDraft.createdAt,
            updatedAt: requestDraft.createdAt,
            resolvedAt: nil
        )
        try await approvalRequestRepository.save(request)
        _ = try await saveFormDraft(
            businessId: businessId,
            draftKey: draftKey,
            kind: draftKind,
            snapshotJSON: snapshotJSON,
            activeApprovalRequestId: .some(request.id)
        )
        return request
    }

    func invalidatePendingDistributionRequest(
        draftKey: String,
        snapshotJSON: String
    ) async throws {
        guard let draft = try await formDraftRepository.findByKey(draftKey) else {
            return
        }
        _ = try await saveFormDraft(
            businessId: draft.businessId,
            draftKey: draft.draftKey,
            kind: draft.kind,
            snapshotJSON: snapshotJSON,
            activeApprovalRequestId: .some(nil)
        )
        guard let activeId = draft.activeApprovalRequestId,
              let request = try await approvalRequestRepository.findById(activeId),
              request.kind == .distribution,
              request.status == .pending else {
            return
        }
        try await approvalRequestRepository.save(
            request.updated(
                status: .invalidated,
                updatedAt: Date(),
                resolvedAt: .some(Date())
            )
        )
    }

    @discardableResult
    func approveRequest(_ id: UUID) async throws -> ApprovalRequest {
        guard let request = try await approvalRequestRepository.findById(id) else {
            throw ApprovalQueueWorkflowError.approvalRequestNotFound(id)
        }

        switch request.kind {
        case .distribution:
            return try await approveDistributionRequest(request)
        case .recurring:
            guard let recurringWorkflowUseCase else {
                throw ApprovalQueueWorkflowError.invalidRecurringRequest(id)
            }
            try await recurringWorkflowUseCase.approveRecurringRequest(id: id)
            guard let approved = try await approvalRequestRepository.findById(id) else {
                throw ApprovalQueueWorkflowError.approvalRequestNotFound(id)
            }
            return approved
        }
    }

    @discardableResult
    func rejectRequest(_ id: UUID) async throws -> ApprovalRequest {
        guard let request = try await approvalRequestRepository.findById(id) else {
            throw ApprovalQueueWorkflowError.approvalRequestNotFound(id)
        }

        switch request.kind {
        case .distribution:
            return try await restoreDistributionRequest(
                request,
                status: .rejected
            )
        case .recurring:
            let rejected = request.updated(
                status: .rejected,
                updatedAt: Date(),
                resolvedAt: .some(Date())
            )
            try await approvalRequestRepository.save(rejected)
            return rejected
        }
    }

    @discardableResult
    func invalidateRequest(_ id: UUID) async throws -> ApprovalRequest {
        guard let request = try await approvalRequestRepository.findById(id) else {
            throw ApprovalQueueWorkflowError.approvalRequestNotFound(id)
        }
        switch request.kind {
        case .distribution:
            return try await restoreDistributionRequest(
                request,
                status: .invalidated
            )
        case .recurring:
            let invalidated = request.updated(
                status: .invalidated,
                updatedAt: Date(),
                resolvedAt: .some(Date())
            )
            try await approvalRequestRepository.save(invalidated)
            return invalidated
        }
    }

    private func approveDistributionRequest(_ request: ApprovalRequest) async throws -> ApprovalRequest {
        guard let payload = request.payload(DistributionTemplateApplicationUseCase.DistributionApprovalPayload.self),
              let draft = try await formDraftRepository.findByKey(payload.draftKey) else {
            throw ApprovalQueueWorkflowError.invalidDistributionPayload(request.id)
        }

        let approved = try distributionUseCase.approve(payload)
        let updatedSnapshotJSON = try updateDraftSnapshot(
            draft: draft,
            allocationMode: approved.allocationMode,
            allocations: approved.allocations.map { DraftAllocationInput(projectId: $0.projectId, ratio: $0.ratio) }
        )
        _ = try await saveFormDraft(
            businessId: draft.businessId,
            draftKey: draft.draftKey,
            kind: draft.kind,
            snapshotJSON: updatedSnapshotJSON,
            activeApprovalRequestId: .some(request.id)
        )

        let approvedRequest = request.updated(
            status: .approved,
            updatedAt: Date(),
            resolvedAt: .some(Date())
        )
        try await approvalRequestRepository.save(approvedRequest)
        return approvedRequest
    }

    private func restoreDistributionRequest(
        _ request: ApprovalRequest,
        status: ApprovalRequestStatus
    ) async throws -> ApprovalRequest {
        guard let payload = request.payload(DistributionTemplateApplicationUseCase.DistributionApprovalPayload.self),
              let draft = try await formDraftRepository.findByKey(payload.draftKey) else {
            throw ApprovalQueueWorkflowError.invalidDistributionPayload(request.id)
        }

        let restored = try distributionUseCase.approve(
            DistributionTemplateApplicationUseCase.DistributionApprovalPayload(
                draftKey: payload.draftKey,
                draftKind: payload.draftKind,
                ruleId: payload.ruleId,
                ruleName: payload.ruleName,
                currentState: payload.currentState,
                proposedState: payload.currentState,
                warnings: payload.warnings
            )
        )
        let snapshotJSON = try updateDraftSnapshot(
            draft: draft,
            allocationMode: restored.allocationMode,
            allocations: restored.allocations.map { DraftAllocationInput(projectId: $0.projectId, ratio: $0.ratio) }
        )
        _ = try await saveFormDraft(
            businessId: draft.businessId,
            draftKey: draft.draftKey,
            kind: draft.kind,
            snapshotJSON: snapshotJSON,
            activeApprovalRequestId: .some(nil)
        )

        let updatedRequest = request.updated(
            status: status,
            updatedAt: Date(),
            resolvedAt: .some(Date())
        )
        try await approvalRequestRepository.save(updatedRequest)
        return updatedRequest
    }

    private func updateDraftSnapshot(
        draft: FormDraft,
        allocationMode: AllocationMode,
        allocations: [DraftAllocationInput]
    ) throws -> String {
        switch draft.kind {
        case .transaction:
            guard let snapshot = draft.transactionSnapshot() else {
                throw ApprovalQueueWorkflowError.formDraftNotFound(draft.draftKey)
            }
            let updated = TransactionFormDraftSnapshot(
                type: snapshot.type,
                amountText: snapshot.amountText,
                date: snapshot.date,
                categoryId: snapshot.categoryId,
                memo: snapshot.memo,
                allocations: allocations,
                paymentAccountId: snapshot.paymentAccountId,
                transferToAccountId: snapshot.transferToAccountId,
                taxDeductibleRate: snapshot.taxDeductibleRate,
                selectedTaxCodeId: snapshot.selectedTaxCodeId,
                isTaxIncluded: snapshot.isTaxIncluded,
                taxAmountText: snapshot.taxAmountText,
                selectedCounterpartyId: snapshot.selectedCounterpartyId,
                counterparty: snapshot.counterparty,
                isWithholdingEnabled: snapshot.isWithholdingEnabled,
                selectedWithholdingTaxCodeId: snapshot.selectedWithholdingTaxCodeId,
                selectedDistributionTemplateId: snapshot.selectedDistributionTemplateId
            )
            return CanonicalJSONCoder.encode(updated, fallback: draft.snapshotJSON)
        case .recurring:
            guard let snapshot = draft.recurringSnapshot() else {
                throw ApprovalQueueWorkflowError.formDraftNotFound(draft.draftKey)
            }
            let updated = RecurringFormDraftSnapshot(
                recurringId: snapshot.recurringId,
                name: snapshot.name,
                type: snapshot.type,
                amountText: snapshot.amountText,
                frequency: snapshot.frequency,
                dayOfMonth: snapshot.dayOfMonth,
                monthOfYear: snapshot.monthOfYear,
                selectedCategoryId: snapshot.selectedCategoryId,
                allocationMode: allocationMode,
                allocations: allocations,
                memo: snapshot.memo,
                isActive: snapshot.isActive,
                hasEndDate: snapshot.hasEndDate,
                endDate: snapshot.endDate,
                yearlyAmortizationMode: snapshot.yearlyAmortizationMode,
                paymentAccountId: snapshot.paymentAccountId,
                transferToAccountId: snapshot.transferToAccountId,
                taxDeductibleRate: snapshot.taxDeductibleRate,
                selectedCounterpartyId: snapshot.selectedCounterpartyId,
                counterparty: snapshot.counterparty,
                isWithholdingEnabled: snapshot.isWithholdingEnabled,
                selectedWithholdingTaxCodeId: snapshot.selectedWithholdingTaxCodeId,
                selectedDistributionTemplateId: snapshot.selectedDistributionTemplateId
            )
            return CanonicalJSONCoder.encode(updated, fallback: draft.snapshotJSON)
        }
    }
}
