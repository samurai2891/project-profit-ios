import Foundation

/// 勘定科目の分類
enum CanonicalAccountType: String, Codable, Sendable, CaseIterable {
    case asset     // 資産
    case liability // 負債
    case equity    // 資本（元入金等）
    case revenue   // 収益
    case expense   // 費用

    var displayName: String {
        switch self {
        case .asset: "資産"
        case .liability: "負債"
        case .equity: "資本"
        case .revenue: "収益"
        case .expense: "費用"
        }
    }
}

// NormalBalance は既存の Models/AccountingEnums.swift で定義済み
// 移行完了後にこちらへ移動する
