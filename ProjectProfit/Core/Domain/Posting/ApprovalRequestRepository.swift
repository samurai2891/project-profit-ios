import Foundation

protocol ApprovalRequestRepository: Sendable {
    func findById(_ id: UUID) async throws -> ApprovalRequest?
    func findByIds(_ ids: Set<UUID>) async throws -> [ApprovalRequest]
    func findByBusiness(
        businessId: UUID,
        statuses: [ApprovalRequestStatus],
        kinds: [ApprovalRequestKind]?
    ) async throws -> [ApprovalRequest]
    func findByTarget(
        targetKey: String,
        kind: ApprovalRequestKind?,
        statuses: [ApprovalRequestStatus]?
    ) async throws -> [ApprovalRequest]
    func save(_ request: ApprovalRequest) async throws
}

protocol FormDraftRepository: Sendable {
    func findById(_ id: UUID) async throws -> FormDraft?
    func findByKey(_ draftKey: String) async throws -> FormDraft?
    func save(_ draft: FormDraft) async throws
    func deleteByKey(_ draftKey: String) async throws
}
