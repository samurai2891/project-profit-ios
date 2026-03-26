import Foundation
import SwiftData

@MainActor
final class SwiftDataApprovalRequestRepository: ApprovalRequestRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findById(_ id: UUID) async throws -> ApprovalRequest? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<ApprovalRequestEntity>(
                predicate: #Predicate { $0.requestId == id }
            )
            return try modelContext.fetch(descriptor).first.map(ApprovalRequestEntityMapper.toDomain)
        }
    }

    nonisolated func findByIds(_ ids: Set<UUID>) async throws -> [ApprovalRequest] {
        guard !ids.isEmpty else {
            return []
        }
        return try await MainActor.run {
            let descriptor = FetchDescriptor<ApprovalRequestEntity>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext
                .fetch(descriptor)
                .filter { ids.contains($0.requestId) }
                .map(ApprovalRequestEntityMapper.toDomain)
        }
    }

    nonisolated func findByBusiness(
        businessId: UUID,
        statuses: [ApprovalRequestStatus],
        kinds: [ApprovalRequestKind]?
    ) async throws -> [ApprovalRequest] {
        let rawStatuses = Set(statuses.map(\.rawValue))
        let rawKinds = kinds.map { Set($0.map(\.rawValue)) }
        return try await MainActor.run {
            let descriptor = FetchDescriptor<ApprovalRequestEntity>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext
                .fetch(descriptor)
                .filter { entity in
                    entity.businessId == businessId
                        && rawStatuses.contains(entity.statusRaw)
                        && (rawKinds?.contains(entity.kindRaw) ?? true)
                }
                .map(ApprovalRequestEntityMapper.toDomain)
        }
    }

    nonisolated func findByTarget(
        targetKey: String,
        kind: ApprovalRequestKind?,
        statuses: [ApprovalRequestStatus]?
    ) async throws -> [ApprovalRequest] {
        let rawStatusSet = statuses.map { Set($0.map(\.rawValue)) }
        let rawKind = kind?.rawValue
        return try await MainActor.run {
            let descriptor = FetchDescriptor<ApprovalRequestEntity>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try modelContext
                .fetch(descriptor)
                .filter { entity in
                    entity.targetKey == targetKey
                        && (rawKind == nil || entity.kindRaw == rawKind)
                        && (rawStatusSet?.contains(entity.statusRaw) ?? true)
                }
                .map(ApprovalRequestEntityMapper.toDomain)
        }
    }

    nonisolated func save(_ request: ApprovalRequest) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<ApprovalRequestEntity>(
                predicate: #Predicate { $0.requestId == request.id }
            )
            if let existing = try modelContext.fetch(descriptor).first {
                ApprovalRequestEntityMapper.update(existing, from: request)
            } else {
                modelContext.insert(ApprovalRequestEntityMapper.toEntity(request))
            }
            try modelContext.save()
        }
    }
}
