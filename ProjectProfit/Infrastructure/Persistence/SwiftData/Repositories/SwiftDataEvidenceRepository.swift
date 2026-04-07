import Foundation
import SwiftData

@MainActor
protocol EvidenceSearchIndexing: AnyObject {
    func search(criteria: EvidenceSearchCriteria) throws -> [UUID]
    func upsert(_ evidence: EvidenceDocument) throws
    func remove(evidenceId: UUID) throws
    func rebuild(businessId: UUID?, taxYear: Int?) throws
    func indexCount(businessId: UUID?, taxYear: Int?) throws -> Int
    func sourceCount(businessId: UUID?, taxYear: Int?) throws -> Int
    func validateIntegrity(businessId: UUID?, taxYear: Int?) throws
}

extension LocalEvidenceSearchIndex: EvidenceSearchIndexing {}

/// SwiftData による Evidence 永続化実装
@MainActor
final class SwiftDataEvidenceRepository: EvidenceRepository {
    private let modelContext: ModelContext
    private let searchIndex: any EvidenceSearchIndexing

    convenience init(modelContext: ModelContext) {
        self.init(
            modelContext: modelContext,
            searchIndex: LocalEvidenceSearchIndex(modelContext: modelContext)
        )
    }

    init(modelContext: ModelContext, searchIndex: any EvidenceSearchIndexing) {
        self.modelContext = modelContext
        self.searchIndex = searchIndex
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
            if searchResultIds.count == 1, let evidenceId = searchResultIds.first {
                let descriptor = evidenceDescriptor(criteria: criteria, evidenceId: evidenceId)
                return try modelContext.fetch(descriptor)
                    .map(EvidenceRecordEntityMapper.toDomain)
                    .filter { evidence in
                        if let counterpartyId = criteria.counterpartyId {
                            return evidence.linkedCounterpartyId == counterpartyId
                        }
                        return true
                    }
            }

            let descriptor = scopedEvidenceDescriptor(criteria: criteria)
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

    private func evidenceDescriptor(
        criteria: EvidenceSearchCriteria,
        evidenceId: UUID
    ) -> FetchDescriptor<EvidenceRecordEntity> {
        switch (criteria.businessId, criteria.taxYear) {
        case let (.some(businessId), .some(taxYear)):
            return FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate {
                    $0.evidenceId == evidenceId
                        && $0.businessId == businessId
                        && $0.taxYear == taxYear
                }
            )
        case let (.some(businessId), nil):
            return FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate {
                    $0.evidenceId == evidenceId
                        && $0.businessId == businessId
                }
            )
        case let (nil, .some(taxYear)):
            return FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate {
                    $0.evidenceId == evidenceId
                        && $0.taxYear == taxYear
                }
            )
        case (nil, nil):
            return FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.evidenceId == evidenceId }
            )
        }
    }

    private func scopedEvidenceDescriptor(
        criteria: EvidenceSearchCriteria
    ) -> FetchDescriptor<EvidenceRecordEntity> {
        switch (criteria.businessId, criteria.taxYear) {
        case let (.some(businessId), .some(taxYear)):
            return FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                },
                sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
            )
        case let (.some(businessId), nil):
            return FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
            )
        case let (nil, .some(taxYear)):
            return FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.taxYear == taxYear },
                sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
            )
        case (nil, nil):
            return FetchDescriptor<EvidenceRecordEntity>(
                sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
            )
        }
    }

    nonisolated func save(_ evidence: EvidenceDocument) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.evidenceId == evidence.id }
            )
            let existing = try modelContext.fetch(descriptor)
            let previousSnapshot = existing.first.map(EvidenceRecordEntityMapper.toDomain)
            let insertedNewRecord = existing.isEmpty

            if let entity = existing.first {
                EvidenceRecordEntityMapper.update(entity, from: evidence)
            } else {
                modelContext.insert(EvidenceRecordEntityMapper.toEntity(evidence))
            }
            try modelContext.save()
            do {
                try searchIndex.upsert(evidence)
            } catch {
                try rollbackSavedEvidence(
                    evidenceId: evidence.id,
                    previousSnapshot: previousSnapshot,
                    insertedNewRecord: insertedNewRecord
                )
                throw error
            }
        }
    }

    nonisolated func delete(_ id: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.evidenceId == id }
            )
            let results = try modelContext.fetch(descriptor)
            let deletedSnapshots = results.map(EvidenceRecordEntityMapper.toDomain)
            results.forEach(modelContext.delete)
            try modelContext.save()
            do {
                try searchIndex.remove(evidenceId: id)
            } catch {
                try restoreDeletedEvidence(deletedSnapshots)
                throw error
            }
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
        let sourceCount = try searchIndex.sourceCount(businessId: criteria.businessId, taxYear: criteria.taxYear)
        let indexCount = try searchIndex.indexCount(businessId: criteria.businessId, taxYear: criteria.taxYear)

        if sourceCount == 0, indexCount == 0 {
            return
        }

        let needsRepair = try indexCount != sourceCount || isIntegrityCorrupted(criteria: criteria)
        guard needsRepair else { return }

        do {
            try searchIndex.rebuild(businessId: criteria.businessId, taxYear: criteria.taxYear)
        } catch {
            throw CanonicalRepositoryError.searchIndexRebuildFailed(
                indexName: LocalEvidenceSearchIndex.indexName,
                underlying: error
            )
        }

        try verifyRebuiltSearchIndex(criteria: criteria)
    }

    private func isIntegrityCorrupted(criteria: EvidenceSearchCriteria) throws -> Bool {
        do {
            try searchIndex.validateIntegrity(businessId: criteria.businessId, taxYear: criteria.taxYear)
            return false
        } catch let error as CanonicalRepositoryError {
            switch error {
            case .searchIndexCorrupted:
                return true
            default:
                throw error
            }
        } catch {
            throw error
        }
    }

    private func verifyRebuiltSearchIndex(criteria: EvidenceSearchCriteria) throws {
        let sourceCount = try searchIndex.sourceCount(businessId: criteria.businessId, taxYear: criteria.taxYear)
        let indexCount = try searchIndex.indexCount(businessId: criteria.businessId, taxYear: criteria.taxYear)

        guard sourceCount == indexCount else {
            throw CanonicalRepositoryError.searchIndexRebuildFailed(
                indexName: LocalEvidenceSearchIndex.indexName,
                underlying: SearchIndexRepairVerificationError.countMismatch(
                    indexCount: indexCount,
                    sourceCount: sourceCount
                )
            )
        }

        do {
            try searchIndex.validateIntegrity(businessId: criteria.businessId, taxYear: criteria.taxYear)
        } catch {
            throw CanonicalRepositoryError.searchIndexRebuildFailed(
                indexName: LocalEvidenceSearchIndex.indexName,
                underlying: error
            )
        }
    }

    private func rollbackSavedEvidence(
        evidenceId: UUID,
        previousSnapshot: EvidenceDocument?,
        insertedNewRecord: Bool
    ) throws {
        let descriptor = FetchDescriptor<EvidenceRecordEntity>(
            predicate: #Predicate { $0.evidenceId == evidenceId }
        )
        let persisted = try modelContext.fetch(descriptor)

        if insertedNewRecord {
            persisted.forEach(modelContext.delete)
        } else if let previousSnapshot, let entity = persisted.first {
            EvidenceRecordEntityMapper.update(entity, from: previousSnapshot)
        }

        try modelContext.save()
    }

    private func restoreDeletedEvidence(_ snapshots: [EvidenceDocument]) throws {
        for snapshot in snapshots {
            modelContext.insert(EvidenceRecordEntityMapper.toEntity(snapshot))
        }
        try modelContext.save()
    }
}
