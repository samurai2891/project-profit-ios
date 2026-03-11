import Foundation

struct ApprovalQueueSnapshot {
    let businessId: UUID?
    let projects: [PPProject]
    let canonicalAccounts: [CanonicalAccount]
}

@MainActor
protocol ApprovalQueueRepository {
    func snapshot() throws -> ApprovalQueueSnapshot
    func yearLockState(businessId: UUID, taxYear: Int) throws -> YearLockState
    func projectName(id: UUID) throws -> String?
}
