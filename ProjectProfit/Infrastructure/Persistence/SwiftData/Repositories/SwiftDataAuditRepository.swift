import Foundation
import SwiftData

/// SwiftData によるAuditEvent永続化実装
@MainActor
final class SwiftDataAuditRepository: AuditRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findById(_ id: UUID) async throws -> AuditEvent? {
        try await MainActor.run {
            let predicate = #Predicate<AuditEventEntity> { $0.eventId == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let results = try modelContext.fetch(descriptor)
            return results.first.map(AuditEventEntityMapper.toDomain)
        }
    }

    nonisolated func findByAggregate(aggregateType: String, aggregateId: UUID) async throws -> [AuditEvent] {
        try await MainActor.run {
            let predicate = #Predicate<AuditEventEntity> {
                $0.aggregateType == aggregateType && $0.aggregateId == aggregateId
            }
            let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.createdAt)])
            return try modelContext.fetch(descriptor).map(AuditEventEntityMapper.toDomain)
        }
    }

    nonisolated func findByBusiness(businessId: UUID, limit: Int) async throws -> [AuditEvent] {
        try await MainActor.run {
            let predicate = #Predicate<AuditEventEntity> { $0.businessId == businessId }
            var descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            descriptor.fetchLimit = limit
            return try modelContext.fetch(descriptor).map(AuditEventEntityMapper.toDomain)
        }
    }

    nonisolated func findByDateRange(businessId: UUID, from: Date, to: Date) async throws -> [AuditEvent] {
        try await MainActor.run {
            let predicate = #Predicate<AuditEventEntity> {
                $0.businessId == businessId && $0.createdAt >= from && $0.createdAt <= to
            }
            let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.createdAt)])
            return try modelContext.fetch(descriptor).map(AuditEventEntityMapper.toDomain)
        }
    }

    nonisolated func save(_ event: AuditEvent) async throws {
        try await MainActor.run {
            let entity = AuditEventEntityMapper.toEntity(event)
            modelContext.insert(entity)
            try modelContext.save()
        }
    }
}
