import Foundation
import SwiftData

@MainActor
struct EvidenceCatalogUseCase {
    private let evidenceRepository: any EvidenceRepository

    init(evidenceRepository: any EvidenceRepository) {
        self.evidenceRepository = evidenceRepository
    }

    init(modelContext: ModelContext) {
        self.init(evidenceRepository: SwiftDataEvidenceRepository(modelContext: modelContext))
    }

    func evidence(_ id: UUID) async throws -> EvidenceDocument? {
        try await evidenceRepository.findById(id)
    }

    func loadEvidence(businessId: UUID, taxYear: Int) async throws -> [EvidenceDocument] {
        try await evidenceRepository.findByBusinessAndYear(businessId: businessId, taxYear: taxYear)
    }

    func search(_ criteria: EvidenceSearchCriteria) async throws -> [EvidenceDocument] {
        try await evidenceRepository.search(criteria: criteria)
    }

    func save(_ evidence: EvidenceDocument) async throws {
        try await evidenceRepository.save(evidence)
    }

    func delete(_ id: UUID) async throws {
        try await evidenceRepository.delete(id)
    }

    func versions(evidenceId: UUID) async throws -> [EvidenceVersion] {
        try await evidenceRepository.findVersions(evidenceId: evidenceId)
    }

    func saveVersion(_ version: EvidenceVersion) async throws {
        try await evidenceRepository.saveVersion(version)
    }
}
