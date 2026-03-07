import Foundation
import SwiftData

/// SwiftData Entity: 配賦ルールテンプレート
@Model
final class DistributionRuleEntity {
    @Attribute(.unique) var ruleId: UUID
    var businessId: UUID
    var name: String
    var scopeRaw: String
    var basisRaw: String
    var weightsJSON: String
    var roundingPolicyRaw: String
    var effectiveFrom: Date
    var effectiveTo: Date?
    var createdAt: Date

    init(
        ruleId: UUID = UUID(),
        businessId: UUID = UUID(),
        name: String = "",
        scopeRaw: String = DistributionScope.allActiveProjectsInMonth.rawValue,
        basisRaw: String = DistributionBasis.equal.rawValue,
        weightsJSON: String = "[]",
        roundingPolicyRaw: String = RoundingPolicy.lastProjectAdjust.rawValue,
        effectiveFrom: Date = Date(),
        effectiveTo: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.ruleId = ruleId
        self.businessId = businessId
        self.name = name
        self.scopeRaw = scopeRaw
        self.basisRaw = basisRaw
        self.weightsJSON = weightsJSON
        self.roundingPolicyRaw = roundingPolicyRaw
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
        self.createdAt = createdAt
    }
}
