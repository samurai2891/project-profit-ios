import Foundation
import SwiftData

/// SwiftData によるTaxYearProfile永続化実装
@MainActor
final class SwiftDataTaxYearProfileRepository: TaxYearProfileRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findById(_ id: UUID) async throws -> TaxYearProfile? {
        try await MainActor.run {
            let predicate = #Predicate<TaxYearProfileEntity> { $0.profileId == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let results = try modelContext.fetch(descriptor)
            return results.first.map(TaxYearProfileEntityMapper.toDomain)
        }
    }

    nonisolated func findByBusinessAndYear(businessId: UUID, taxYear: Int) async throws -> TaxYearProfile? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<TaxYearProfileEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                }
            )
            let results = try modelContext.fetch(descriptor)
            return results.first.map(TaxYearProfileEntityMapper.toDomain)
        }
    }

    nonisolated func findAllByBusiness(businessId: UUID) async throws -> [TaxYearProfile] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<TaxYearProfileEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [SortDescriptor(\.taxYear, order: .reverse)]
            )
            return try modelContext.fetch(descriptor).map(TaxYearProfileEntityMapper.toDomain)
        }
    }

    nonisolated func save(_ profile: TaxYearProfile) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<TaxYearProfileEntity>(
                predicate: #Predicate { $0.profileId == profile.id }
            )
            let existing = try modelContext.fetch(descriptor)

            if let entity = existing.first {
                TaxYearProfileEntityMapper.update(entity, from: profile)
            } else {
                modelContext.insert(TaxYearProfileEntityMapper.toEntity(profile))
            }
            try modelContext.save()
        }
    }

    nonisolated func delete(_ id: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<TaxYearProfileEntity>(
                predicate: #Predicate { $0.profileId == id }
            )
            let results = try modelContext.fetch(descriptor)
            results.forEach(modelContext.delete)
            try modelContext.save()
        }
    }
}
