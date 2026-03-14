import Foundation

enum ApprovalRequestKind: String, Codable, CaseIterable, Sendable {
    case distribution
    case recurring

    var displayName: String {
        switch self {
        case .distribution:
            return "配賦承認"
        case .recurring:
            return "定期取引承認"
        }
    }
}

enum ApprovalRequestStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case approved
    case rejected
    case invalidated

    var displayName: String {
        switch self {
        case .pending:
            return "承認待ち"
        case .approved:
            return "承認済み"
        case .rejected:
            return "却下"
        case .invalidated:
            return "失効"
        }
    }
}

enum ApprovalRequestTargetKind: String, Codable, CaseIterable, Sendable {
    case transactionDraft
    case recurringDraft
    case recurringOccurrence
}

struct ApprovalRequestDraft: Sendable, Equatable {
    let businessId: UUID
    let kind: ApprovalRequestKind
    let targetKind: ApprovalRequestTargetKind
    let targetKey: String
    let title: String
    let subtitle: String?
    let payloadJSON: String
    let createdAt: Date

    init(
        businessId: UUID,
        kind: ApprovalRequestKind,
        targetKind: ApprovalRequestTargetKind,
        targetKey: String,
        title: String,
        subtitle: String? = nil,
        payloadJSON: String,
        createdAt: Date = Date()
    ) {
        self.businessId = businessId
        self.kind = kind
        self.targetKind = targetKind
        self.targetKey = targetKey
        self.title = title
        self.subtitle = subtitle
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

struct ApprovalRequest: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let kind: ApprovalRequestKind
    let status: ApprovalRequestStatus
    let targetKind: ApprovalRequestTargetKind
    let targetKey: String
    let title: String
    let subtitle: String?
    let payloadJSON: String
    let createdAt: Date
    let updatedAt: Date
    let resolvedAt: Date?

    init(
        id: UUID = UUID(),
        businessId: UUID,
        kind: ApprovalRequestKind,
        status: ApprovalRequestStatus = .pending,
        targetKind: ApprovalRequestTargetKind,
        targetKey: String,
        title: String,
        subtitle: String? = nil,
        payloadJSON: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.businessId = businessId
        self.kind = kind
        self.status = status
        self.targetKind = targetKind
        self.targetKey = targetKey
        self.title = title
        self.subtitle = subtitle
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
    }

    func payload<T: Decodable>(_ type: T.Type) -> T? {
        CanonicalJSONCoder.decodeIfPresent(T.self, from: payloadJSON)
    }

    func updated(
        status: ApprovalRequestStatus? = nil,
        title: String? = nil,
        subtitle: String?? = nil,
        payloadJSON: String? = nil,
        updatedAt: Date = Date(),
        resolvedAt: Date?? = nil
    ) -> ApprovalRequest {
        ApprovalRequest(
            id: id,
            businessId: businessId,
            kind: kind,
            status: status ?? self.status,
            targetKind: targetKind,
            targetKey: targetKey,
            title: title ?? self.title,
            subtitle: subtitle ?? self.subtitle,
            payloadJSON: payloadJSON ?? self.payloadJSON,
            createdAt: createdAt,
            updatedAt: updatedAt,
            resolvedAt: resolvedAt ?? self.resolvedAt
        )
    }
}

enum FormDraftKind: String, Codable, CaseIterable, Sendable {
    case transaction
    case recurring
}

struct DraftAllocationInput: Codable, Equatable, Sendable {
    let projectId: UUID
    let ratio: Int
}

struct TransactionFormDraftSnapshot: Codable, Equatable, Sendable {
    let type: TransactionType
    let amountText: String
    let date: Date
    let categoryId: String
    let memo: String
    let allocations: [DraftAllocationInput]
    let paymentAccountId: String?
    let transferToAccountId: String?
    let taxDeductibleRate: Int
    let selectedTaxCodeId: String?
    let isTaxIncluded: Bool
    let taxAmountText: String
    let selectedCounterpartyId: UUID?
    let counterparty: String
    let isWithholdingEnabled: Bool
    let selectedWithholdingTaxCodeId: String?
    let selectedDistributionTemplateId: UUID?
}

struct RecurringFormDraftSnapshot: Codable, Equatable, Sendable {
    let recurringId: UUID?
    let name: String
    let type: TransactionType
    let amountText: String
    let frequency: RecurringFrequency
    let dayOfMonth: Int
    let monthOfYear: Int
    let selectedCategoryId: String?
    let allocationMode: AllocationMode
    let allocations: [DraftAllocationInput]
    let memo: String
    let isActive: Bool
    let hasEndDate: Bool
    let endDate: Date
    let yearlyAmortizationMode: YearlyAmortizationMode
    let paymentAccountId: String?
    let transferToAccountId: String?
    let taxDeductibleRate: Int
    let selectedCounterpartyId: UUID?
    let counterparty: String
    let selectedDistributionTemplateId: UUID?
}

struct FormDraft: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let draftKey: String
    let kind: FormDraftKind
    let snapshotJSON: String
    let activeApprovalRequestId: UUID?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        businessId: UUID,
        draftKey: String,
        kind: FormDraftKind,
        snapshotJSON: String,
        activeApprovalRequestId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.draftKey = draftKey
        self.kind = kind
        self.snapshotJSON = snapshotJSON
        self.activeApprovalRequestId = activeApprovalRequestId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func transactionSnapshot() -> TransactionFormDraftSnapshot? {
        CanonicalJSONCoder.decodeIfPresent(TransactionFormDraftSnapshot.self, from: snapshotJSON)
    }

    func recurringSnapshot() -> RecurringFormDraftSnapshot? {
        CanonicalJSONCoder.decodeIfPresent(RecurringFormDraftSnapshot.self, from: snapshotJSON)
    }

    func updated(
        snapshotJSON: String? = nil,
        activeApprovalRequestId: UUID?? = nil,
        updatedAt: Date = Date()
    ) -> FormDraft {
        FormDraft(
            id: id,
            businessId: businessId,
            draftKey: draftKey,
            kind: kind,
            snapshotJSON: snapshotJSON ?? self.snapshotJSON,
            activeApprovalRequestId: activeApprovalRequestId ?? self.activeApprovalRequestId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

enum ApprovalQueueItem: Identifiable, Sendable, Equatable {
    case candidate(PostingCandidate)
    case request(ApprovalRequest)

    var id: UUID {
        switch self {
        case .candidate(let candidate):
            return candidate.id
        case .request(let request):
            return request.id
        }
    }

    var updatedAt: Date {
        switch self {
        case .candidate(let candidate):
            return candidate.updatedAt
        case .request(let request):
            return request.updatedAt
        }
    }
}

struct RecurringApprovalPayload: Codable, Sendable, Equatable {
    let recurringId: UUID
    let recurringName: String
    let type: TransactionType
    let amount: Int
    let scheduledDate: Date
    let categoryId: String
    let memo: String
    let postingMemo: String
    let isMonthlySpread: Bool
    let monthKey: String?
    let projectName: String?
    let allocationMode: AllocationMode
}
