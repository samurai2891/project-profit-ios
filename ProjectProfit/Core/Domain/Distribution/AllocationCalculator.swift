import Foundation

/// 配賦計算エンジン
/// 配賦計算ロジックを独立した責務として分離
struct AllocationCalculator: Sendable {

    /// 均等配賦
    /// - Parameters:
    ///   - totalAmount: 配賦元金額
    ///   - projectIds: 対象プロジェクトID
    ///   - roundingPolicy: 端数調整方式
    /// - Returns: プロジェクトごとの配賦結果
    static func equalSplit(
        totalAmount: Decimal,
        projectIds: [UUID],
        roundingPolicy: RoundingPolicy = .lastProjectAdjust
    ) -> [CanonicalProjectAllocation] {
        guard !projectIds.isEmpty else { return [] }

        let count = Decimal(projectIds.count)
        let baseAmount = (totalAmount / count).rounded(scale: 0)
        var allocations: [CanonicalProjectAllocation] = []
        var remaining = totalAmount

        for (index, projectId) in projectIds.enumerated() {
            let isLast = index == projectIds.count - 1
            let amount: Decimal

            switch roundingPolicy {
            case .lastProjectAdjust:
                amount = isLast ? remaining : baseAmount
            case .largestWeightAdjust:
                // 均等配賦では最後で調整と同じ
                amount = isLast ? remaining : baseAmount
            }

            remaining -= amount

            allocations.append(CanonicalProjectAllocation(
                projectId: projectId,
                amount: amount,
                ratio: Decimal(1) / count,
                basisAmount: totalAmount,
                source: .fromRule
            ))
        }

        return allocations
    }

    /// 重み付き配賦
    /// - Parameters:
    ///   - totalAmount: 配賦元金額
    ///   - weights: プロジェクトごとの重み
    ///   - roundingPolicy: 端数調整方式
    /// - Returns: プロジェクトごとの配賦結果
    static func weightedSplit(
        totalAmount: Decimal,
        weights: [DistributionWeight],
        roundingPolicy: RoundingPolicy = .lastProjectAdjust
    ) -> [CanonicalProjectAllocation] {
        guard !weights.isEmpty else { return [] }

        let totalWeight = weights.reduce(Decimal(0)) { $0 + $1.weight }
        guard totalWeight > 0 else { return [] }

        // 最大重みのインデックスを取得（largestWeightAdjust 用）
        let maxWeightIndex = weights.enumerated()
            .max(by: { $0.element.weight < $1.element.weight })?.offset ?? 0
        let adjustTargetIndex: Int = switch roundingPolicy {
        case .lastProjectAdjust:
            weights.count - 1
        case .largestWeightAdjust:
            maxWeightIndex
        }

        let ratios = weights.map { $0.weight / totalWeight }
        let provisionalAmounts = ratios.enumerated().map { index, ratio in
            index == adjustTargetIndex ? Decimal?.none : (totalAmount * ratio).rounded(scale: 0)
        }
        let adjustedAmount = totalAmount - provisionalAmounts.compactMap { $0 }.reduce(Decimal(0), +)

        return weights.enumerated().map { index, weight in
            CanonicalProjectAllocation(
                projectId: weight.projectId,
                amount: provisionalAmounts[index] ?? adjustedAmount,
                ratio: ratios[index],
                basisAmount: totalAmount,
                source: .fromRule
            )
        }
    }
}

// MARK: - Decimal Rounding Helper

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
