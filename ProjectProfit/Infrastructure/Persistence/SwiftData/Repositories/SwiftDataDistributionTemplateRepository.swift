import Foundation
import SwiftData

/// SwiftData による配賦ルールテンプレート永続化実装
@MainActor
final class SwiftDataDistributionTemplateRepository: DistributionTemplateRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func findById(_ id: UUID) async throws -> DistributionRule? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<DistributionRuleEntity>(
                predicate: #Predicate { $0.ruleId == id }
            )
            return try modelContext.fetch(descriptor).first.map(DistributionRuleEntityMapper.toDomain)
        }
    }

    nonisolated func findByBusiness(businessId: UUID) async throws -> [DistributionRule] {
        try await MainActor.run {
            let descriptor = FetchDescriptor<DistributionRuleEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [
                    SortDescriptor(\.effectiveFrom, order: .reverse),
                    SortDescriptor(\.name)
                ]
            )
            return try modelContext.fetch(descriptor).map(DistributionRuleEntityMapper.toDomain)
        }
    }

    nonisolated func findActive(businessId: UUID, at date: Date) async throws -> [DistributionRule] {
        try await findByBusiness(businessId: businessId)
            .filter { rule in
                rule.effectiveFrom <= date && (rule.effectiveTo == nil || date <= rule.effectiveTo!)
            }
    }

    nonisolated func save(_ rule: DistributionRule) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<DistributionRuleEntity>(
                predicate: #Predicate { $0.ruleId == rule.id }
            )
            let existing = try modelContext.fetch(descriptor)

            if let entity = existing.first {
                DistributionRuleEntityMapper.update(entity, from: rule)
            } else {
                modelContext.insert(DistributionRuleEntityMapper.toEntity(rule))
            }
            try modelContext.save()
        }
    }

    nonisolated func delete(_ id: UUID) async throws {
        try await MainActor.run {
            let descriptor = FetchDescriptor<DistributionRuleEntity>(
                predicate: #Predicate { $0.ruleId == id }
            )
            let entities = try modelContext.fetch(descriptor)
            entities.forEach(modelContext.delete)
            try modelContext.save()
        }
    }
}
