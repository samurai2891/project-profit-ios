import Foundation
import SwiftData

@MainActor
struct DistributionTemplateUseCase {
    private let distributionTemplateRepository: any DistributionTemplateRepository

    init(distributionTemplateRepository: any DistributionTemplateRepository) {
        self.distributionTemplateRepository = distributionTemplateRepository
    }

    init(modelContext: ModelContext) {
        self.init(distributionTemplateRepository: SwiftDataDistributionTemplateRepository(modelContext: modelContext))
    }

    func rule(_ id: UUID) async throws -> DistributionRule? {
        try await distributionTemplateRepository.findById(id)
    }

    func rules(businessId: UUID) async throws -> [DistributionRule] {
        try await distributionTemplateRepository.findByBusiness(businessId: businessId)
    }

    func activeRules(businessId: UUID, at date: Date) async throws -> [DistributionRule] {
        try await distributionTemplateRepository.findActive(businessId: businessId, at: date)
    }

    func save(_ rule: DistributionRule) async throws {
        try await distributionTemplateRepository.save(rule)
    }

    func delete(_ id: UUID) async throws {
        try await distributionTemplateRepository.delete(id)
    }
}
