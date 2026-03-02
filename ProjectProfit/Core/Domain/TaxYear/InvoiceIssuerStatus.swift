import Foundation

/// インボイス発行事業者の登録状態
enum InvoiceIssuerStatus: String, Codable, Sendable {
    case registered
    case unregistered
    case unknown

    var displayName: String {
        switch self {
        case .registered: "登録済み"
        case .unregistered: "未登録"
        case .unknown: "不明"
        }
    }
}
