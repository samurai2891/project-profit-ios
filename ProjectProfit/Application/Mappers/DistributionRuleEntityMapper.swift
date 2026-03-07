import Foundation

/// DistributionRule ↔ DistributionRuleEntity の変換
enum DistributionRuleEntityMapper {
    static func toDomain(_ entity: DistributionRuleEntity) -> DistributionRule {
        DistributionRule(
            id: entity.ruleId,
            businessId: entity.businessId,
            name: entity.name,
            scope: DistributionScope(rawValue: entity.scopeRaw) ?? .allActiveProjectsInMonth,
            basis: DistributionBasis(rawValue: entity.basisRaw) ?? .equal,
            weights: CanonicalJSONCoder.decode([DistributionWeight].self, from: entity.weightsJSON, fallback: []),
            roundingPolicy: RoundingPolicy(rawValue: entity.roundingPolicyRaw) ?? .lastProjectAdjust,
            effectiveFrom: entity.effectiveFrom,
            effectiveTo: entity.effectiveTo,
            createdAt: entity.createdAt
        )
    }

    static func toEntity(_ domain: DistributionRule) -> DistributionRuleEntity {
        DistributionRuleEntity(
            ruleId: domain.id,
            businessId: domain.businessId,
            name: domain.name,
            scopeRaw: domain.scope.rawValue,
            basisRaw: domain.basis.rawValue,
            weightsJSON: CanonicalJSONCoder.encode(domain.weights, fallback: "[]"),
            roundingPolicyRaw: domain.roundingPolicy.rawValue,
            effectiveFrom: domain.effectiveFrom,
            effectiveTo: domain.effectiveTo,
            createdAt: domain.createdAt
        )
    }

    static func update(_ entity: DistributionRuleEntity, from domain: DistributionRule) {
        entity.businessId = domain.businessId
        entity.name = domain.name
        entity.scopeRaw = domain.scope.rawValue
        entity.basisRaw = domain.basis.rawValue
        entity.weightsJSON = CanonicalJSONCoder.encode(domain.weights, fallback: "[]")
        entity.roundingPolicyRaw = domain.roundingPolicy.rawValue
        entity.effectiveFrom = domain.effectiveFrom
        entity.effectiveTo = domain.effectiveTo
    }
}
