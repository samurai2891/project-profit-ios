import Foundation
import SwiftData

/// SwiftData によるBusinessProfile永続化実装
@MainActor
final class SwiftDataBusinessProfileRepository: BusinessProfileRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findById(_ id: UUID) async throws -> BusinessProfile? {
        try await MainActor.run {
            let predicate = #Predicate<BusinessProfileEntity> { $0.businessId == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let results = try modelContext.fetch(descriptor)
            return results.first.map(BusinessProfileEntityMapper.toDomain)
        }
    }

    nonisolated func findDefault() async throws -> BusinessProfile? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<BusinessProfileEntity>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
            let results = try modelContext.fetch(descriptor)
            return results.first.map(BusinessProfileEntityMapper.toDomain)
        }
    }

    nonisolated func save(_ profile: BusinessProfile) async throws {
        try await MainActor.run {
            let predicate = #Predicate<BusinessProfileEntity> { $0.businessId == profile.id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let existing = try modelContext.fetch(descriptor)

            if let entity = existing.first {
                BusinessProfileEntityMapper.update(entity, from: profile)
            } else {
                let entity = BusinessProfileEntityMapper.toEntity(profile)
                modelContext.insert(entity)
            }
            try modelContext.save()
        }
    }

    nonisolated func delete(_ id: UUID) async throws {
        try await MainActor.run {
            let predicate = #Predicate<BusinessProfileEntity> { $0.businessId == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let results = try modelContext.fetch(descriptor)
            results.forEach { modelContext.delete($0) }
            try modelContext.save()
        }
    }
}
