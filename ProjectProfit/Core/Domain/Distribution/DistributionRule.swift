import Foundation

/// 配賦ルールテンプレート
struct DistributionRule: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let name: String
    let scope: DistributionScope
    let basis: DistributionBasis
    let weights: [DistributionWeight]
    let roundingPolicy: RoundingPolicy
    let effectiveFrom: Date
    let effectiveTo: Date?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        businessId: UUID,
        name: String,
        scope: DistributionScope = .allActiveProjectsInMonth,
        basis: DistributionBasis = .equal,
        weights: [DistributionWeight] = [],
        roundingPolicy: RoundingPolicy = .lastProjectAdjust,
        effectiveFrom: Date = Date(),
        effectiveTo: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.name = name
        self.scope = scope
        self.basis = basis
        self.weights = weights
        self.roundingPolicy = roundingPolicy
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
        self.createdAt = createdAt
    }
}

/// プロジェクト重み（fixedWeight 用）
struct DistributionWeight: Codable, Sendable, Equatable {
    let projectId: UUID
    let weight: Decimal

    init(projectId: UUID, weight: Decimal) {
        self.projectId = projectId
        self.weight = weight
    }
}
