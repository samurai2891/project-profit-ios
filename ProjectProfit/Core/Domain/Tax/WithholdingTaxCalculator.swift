import Foundation

/// 源泉徴収税の計算結果
struct WithholdingTaxResult: Sendable, Equatable, Codable {
    /// 源泉徴収税額
    let withholdingAmount: Decimal
    /// 手取り額（税引後）
    let netAmount: Decimal
    /// 適用された税率（実効税率）
    let appliedRate: Decimal
    /// 基準額（100万円）超過かどうか
    let isOverThreshold: Bool
}

/// 源泉徴収税の計算器
/// 所得税法第204条に基づき、報酬の源泉徴収税額を算出する
enum WithholdingTaxCalculator {

    /// 源泉徴収税額を計算する
    /// - Parameters:
    ///   - grossAmount: 支払金額（税引前）
    ///   - code: 源泉徴収区分コード
    /// - Returns: 計算結果（税額・手取額・適用税率・基準超過フラグ）
    static func calculate(
        grossAmount: Decimal,
        code: WithholdingTaxCode
    ) -> WithholdingTaxResult {
        guard grossAmount > 0 else {
            return WithholdingTaxResult(
                withholdingAmount: 0,
                netAmount: grossAmount,
                appliedRate: 0,
                isOverThreshold: false
            )
        }

        let threshold = code.threshold
        let isOverThreshold = grossAmount > threshold

        let withholdingAmount: Decimal
        if isOverThreshold {
            // 100万円以下の部分: 10.21%
            let underThresholdTax = threshold * code.standardRate
            // 100万円超過分: 20.42%
            let overThresholdTax = (grossAmount - threshold) * code.excessRate
            withholdingAmount = roundDownToYen(underThresholdTax + overThresholdTax)
        } else {
            // 全額に対して 10.21%
            withholdingAmount = roundDownToYen(grossAmount * code.standardRate)
        }

        let netAmount = grossAmount - withholdingAmount

        // 実効税率 = 源泉徴収税額 / 支払金額
        let appliedRate: Decimal
        if grossAmount > 0 {
            appliedRate = withholdingAmount / grossAmount
        } else {
            appliedRate = 0
        }

        return WithholdingTaxResult(
            withholdingAmount: withholdingAmount,
            netAmount: netAmount,
            appliedRate: appliedRate,
            isOverThreshold: isOverThreshold
        )
    }

    /// 手取り額から逆算して支払金額を求める
    /// - Parameters:
    ///   - netAmount: 手取り額
    ///   - code: 源泉徴収区分コード
    /// - Returns: 税引前の支払金額
    static func grossFromNet(
        netAmount: Decimal,
        code: WithholdingTaxCode
    ) -> Decimal {
        guard netAmount > 0 else { return netAmount }

        let threshold = code.threshold
        // 100万円に対する手取り: 100万 × (1 - 0.1021)
        let netAtThreshold = threshold * (1 - code.standardRate)

        if netAmount <= netAtThreshold {
            // 全額が標準税率の範囲内
            // net = gross × (1 - rate)  →  gross = net / (1 - rate)
            return roundUpToYen(netAmount / (1 - code.standardRate))
        } else {
            // 超過税率が適用される
            // 100万円以下: threshold × standardRate
            // 超過分: (gross - threshold) × excessRate
            // net = gross - threshold × standardRate - (gross - threshold) × excessRate
            // net = gross - threshold × standardRate - gross × excessRate + threshold × excessRate
            // net = gross × (1 - excessRate) + threshold × (excessRate - standardRate)
            // gross = (net - threshold × (excessRate - standardRate)) / (1 - excessRate)
            let rateDiff = code.excessRate - code.standardRate
            return roundUpToYen(
                (netAmount - threshold * rateDiff) / (1 - code.excessRate)
            )
        }
    }

    /// 1円未満を切り捨て（源泉徴収税は1円未満切捨て）
    private static func roundDownToYen(_ value: Decimal) -> Decimal {
        var result = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, 0, .down)
        return rounded
    }

    /// 1円未満を切り上げ（逆算時に端数を切り上げて税額が手取りを下回らないようにする）
    private static func roundUpToYen(_ value: Decimal) -> Decimal {
        var result = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, 0, .up)
        return rounded
    }
}
