import Foundation

/// 消費税の計算方式
enum VatMethod: String, Codable, Sendable, CaseIterable {
    case general
    case simplified
    case twoTenths

    var displayName: String {
        switch self {
        case .general: "一般課税（本則課税）"
        case .simplified: "簡易課税"
        case .twoTenths: "2割特例"
        }
    }
}
