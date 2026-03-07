import Foundation

struct DistributionRuleBuilder {
    func build(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        businessId: UUID,
        name: String,
        scope: DistributionScope,
        basis: DistributionBasis,
        roundingPolicy: RoundingPolicy,
        effectiveFrom: Date,
        effectiveTo: Date?,
        selectedProjectIds: Set<UUID>,
        weightTexts: [UUID: String]
    ) throws -> DistributionRule {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ValidationError.emptyName
        }

        if let effectiveTo, effectiveTo < effectiveFrom {
            throw ValidationError.invalidEffectiveTo
        }

        if scope == .selectedProjects && selectedProjectIds.isEmpty {
            throw ValidationError.noSelectedProjects
        }

        if basis == .fixedWeight && scope != .selectedProjects {
            throw ValidationError.fixedWeightRequiresSelectedProjects
        }

        let orderedProjectIds = selectedProjectIds.sorted { $0.uuidString < $1.uuidString }
        let weights: [DistributionWeight]
        if scope == .selectedProjects {
            if basis == .fixedWeight {
                weights = try orderedProjectIds.map { projectId in
                    guard let rawValue = weightTexts[projectId],
                          let weight = Decimal(string: rawValue.replacingOccurrences(of: ",", with: ".")),
                          weight > 0
                    else {
                        throw ValidationError.invalidWeights
                    }
                    return DistributionWeight(projectId: projectId, weight: weight)
                }
            } else {
                weights = orderedProjectIds.map { DistributionWeight(projectId: $0, weight: 1) }
            }
        } else {
            weights = []
        }

        return DistributionRule(
            id: id,
            businessId: businessId,
            name: trimmedName,
            scope: scope,
            basis: basis,
            weights: weights,
            roundingPolicy: roundingPolicy,
            effectiveFrom: effectiveFrom,
            effectiveTo: effectiveTo,
            createdAt: createdAt
        )
    }
}

extension DistributionRuleBuilder {
    enum ValidationError: LocalizedError, Equatable {
        case emptyName
        case invalidEffectiveTo
        case noSelectedProjects
        case invalidWeights
        case fixedWeightRequiresSelectedProjects

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "テンプレート名を入力してください。"
            case .invalidEffectiveTo:
                return "終了日は開始日以降にしてください。"
            case .noSelectedProjects:
                return "対象プロジェクトを1件以上選択してください。"
            case .invalidWeights:
                return "固定重みを正の数で入力してください。"
            case .fixedWeightRequiresSelectedProjects:
                return "固定重みは選択プロジェクト指定で設定してください。"
            }
        }
    }
}
