import Foundation

struct EvidenceInboxSnapshot {
    let businessId: UUID?
    let isCurrentYearLocked: Bool
    let projects: [PPProject]
}

@MainActor
protocol EvidenceInboxRepository {
    func snapshot(startMonth: Int) throws -> EvidenceInboxSnapshot
    func projectNames(ids: [UUID]) throws -> [String]
}
