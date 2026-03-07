import Foundation
import SwiftData

/// SwiftData による Evidence 永続化実装
@MainActor
final class SwiftDataEvidenceRepository: EvidenceRepository {
    private let modelContext: ModelContext
    private let searchIndex: LocalEvidenceSearchIndex

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.searchIndex = LocalEvidenceSearchIndex(modelContext: modelContext)
    }

    nonisolated func findById(_ id: UUID) async throws -> EvidenceDocument? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.evidenceId == id }
            )
            return try modelContext.fetch(descriptor).first.map(EvidenceRecordEntityMapper.toDomain)
        }
    }

    nonisolated func findByBusinessAndYear(businessId: UUID, taxYear: Int) async throws -> [EvidenceDocument] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                },
                sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map(EvidenceRecordEntityMapper.toDomain)
        }
    }

    nonisolated func search(criteria: EvidenceSearchCriteria) async throws -> [EvidenceDocument] {
        try await MainActor.run {
            try autoRepairSearchIndexIfNeeded(criteria: criteria)
            let searchResultIds = try searchIndex.search(criteria: criteria)
            guard !searchResultIds.isEmpty else { return [] }

            let order = Dictionary(uniqueKeysWithValues: searchResultIds.enumerated().map { ($1, $0) })
            let descriptor = FetchDescriptor<EvidenceRecordEntity>()
            return try modelContext.fetch(descriptor)
                .map(EvidenceRecordEntityMapper.toDomain)
                .filter { evidence in
                    guard order[evidence.id] != nil else { return false }
                    if let counterpartyId = criteria.counterpartyId {
                        return evidence.linkedCounterpartyId == counterpartyId
                    }
                    return true
                }
                .sorted {
                    (order[$0.id] ?? .max) < (order[$1.id] ?? .max)
                }
        }
    }

    nonisolated func save(_ evidence: EvidenceDocument) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.evidenceId == evidence.id }
            )
            let existing = try modelContext.fetch(descriptor)

            if let entity = existing.first {
                EvidenceRecordEntityMapper.update(entity, from: evidence)
            } else {
                modelContext.insert(EvidenceRecordEntityMapper.toEntity(evidence))
            }
            try modelContext.save()
            try searchIndex.upsert(evidence)
        }
    }

    nonisolated func delete(_ id: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.evidenceId == id }
            )
            let results = try modelContext.fetch(descriptor)
            results.forEach(modelContext.delete)
            try modelContext.save()
            try searchIndex.remove(evidenceId: id)
        }
    }

    nonisolated func findVersions(evidenceId: UUID) async throws -> [EvidenceVersion] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.evidenceId == evidenceId }
            )
            guard let entity = try modelContext.fetch(descriptor).first else {
                return []
            }
            return CanonicalJSONCoder.decode([EvidenceVersion].self, from: entity.versionsJSON, fallback: [])
                .sorted { $0.changedAt < $1.changedAt }
        }
    }

    nonisolated func saveVersion(_ version: EvidenceVersion) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.evidenceId == version.evidenceId }
            )
            guard let entity = try modelContext.fetch(descriptor).first else {
                throw CanonicalRepositoryError.recordNotFound("Evidence", version.evidenceId)
            }

            var versions = CanonicalJSONCoder.decode([EvidenceVersion].self, from: entity.versionsJSON, fallback: [])
            if let index = versions.firstIndex(where: { $0.id == version.id }) {
                versions[index] = version
            } else {
                versions.append(version)
            }
            versions.sort { $0.changedAt < $1.changedAt }
            entity.versionsJSON = CanonicalJSONCoder.encode(versions, fallback: "[]")
            entity.updatedAt = max(entity.updatedAt, version.changedAt)
            try modelContext.save()
        }
    }

    private func autoRepairSearchIndexIfNeeded(criteria: EvidenceSearchCriteria) throws {
        let indexCount = try searchIndex.indexCount(businessId: criteria.businessId, taxYear: criteria.taxYear)
        guard indexCount == 0 else { return }
        let sourceCount = try searchIndex.sourceCount(businessId: criteria.businessId, taxYear: criteria.taxYear)
        guard sourceCount > 0 else { return }
        try searchIndex.rebuild(businessId: criteria.businessId, taxYear: criteria.taxYear)
    }
}
