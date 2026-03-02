import Foundation

/// 配賦基準
enum DistributionBasis: String, Codable, Sendable, CaseIterable {
    case equal         // 均等配賦
    case fixedWeight   // 固定重み配賦
    case activeDays    // 稼働日数按分
    case revenueRatio  // 売上比按分
    case expenseRatio  // 経費比按分
    case customFormula // カスタム計算式

    var displayName: String {
        switch self {
        case .equal: "均等"
        case .fixedWeight: "固定重み"
        case .activeDays: "稼働日数"
        case .revenueRatio: "売上比"
        case .expenseRatio: "経費比"
        case .customFormula: "カスタム"
        }
    }
}

/// 端数調整方式
enum RoundingPolicy: String, Codable, Sendable, CaseIterable {
    case lastProjectAdjust    // 最後のプロジェクトで調整
    case largestWeightAdjust  // 最大重みのプロジェクトで調整

    var displayName: String {
        switch self {
        case .lastProjectAdjust: "最終プロジェクト調整"
        case .largestWeightAdjust: "最大重み調整"
        }
    }
}
