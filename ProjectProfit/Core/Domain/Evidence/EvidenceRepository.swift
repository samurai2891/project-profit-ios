import Foundation

/// 証憑リポジトリプロトコル
protocol EvidenceRepository: Sendable {
    func findById(_ id: UUID) async throws -> EvidenceDocument?
    func findByBusinessAndYear(businessId: UUID, taxYear: Int) async throws -> [EvidenceDocument]
    func search(criteria: EvidenceSearchCriteria) async throws -> [EvidenceDocument]
    func save(_ evidence: EvidenceDocument) async throws
    func delete(_ id: UUID) async throws

    func findVersions(evidenceId: UUID) async throws -> [EvidenceVersion]
    func saveVersion(_ version: EvidenceVersion) async throws
}
