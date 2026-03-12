import Foundation
import SwiftData

/// SwiftData による PostingCandidate 永続化実装
@MainActor
final class SwiftDataPostingCandidateRepository: PostingCandidateRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findById(_ id: UUID) async throws -> PostingCandidate? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<PostingCandidateEntity>(
                predicate: #Predicate { $0.candidateId == id }
            )
            return try modelContext.fetch(descriptor).first.map(PostingCandidateEntityMapper.toDomain)
        }
    }

    nonisolated func findByIds(_ ids: Set<UUID>) async throws -> [PostingCandidate] {
        guard !ids.isEmpty else {
            return []
        }
        return try await MainActor.run {
            let descriptor = FetchDescriptor<PostingCandidateEntity>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext
                .fetch(descriptor)
                .filter { ids.contains($0.candidateId) }
                .map(PostingCandidateEntityMapper.toDomain)
        }
    }

    nonisolated func findByEvidence(evidenceId: UUID) async throws -> [PostingCandidate] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<PostingCandidateEntity>(
                predicate: #Predicate { $0.evidenceId == evidenceId },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map(PostingCandidateEntityMapper.toDomain)
        }
    }

    nonisolated func findByStatus(businessId: UUID, status: CandidateStatus) async throws -> [PostingCandidate] {
        let rawStatus = status.rawValue
        return try await MainActor.run {
            let descriptor = FetchDescriptor<PostingCandidateEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.statusRaw == rawStatus
                },
                sortBy: [SortDescriptor(\.candidateDate, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map(PostingCandidateEntityMapper.toDomain)
        }
    }

    nonisolated func save(_ candidate: PostingCandidate) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<PostingCandidateEntity>(
                predicate: #Predicate { $0.candidateId == candidate.id }
            )
            let existing = try modelContext.fetch(descriptor)

            if let entity = existing.first {
                PostingCandidateEntityMapper.update(entity, from: candidate)
            } else {
                modelContext.insert(PostingCandidateEntityMapper.toEntity(candidate))
            }
            try modelContext.save()
        }
    }

    nonisolated func delete(_ id: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<PostingCandidateEntity>(
                predicate: #Predicate { $0.candidateId == id }
            )
            let results = try modelContext.fetch(descriptor)
            results.forEach(modelContext.delete)
            try modelContext.save()
        }
    }
}
