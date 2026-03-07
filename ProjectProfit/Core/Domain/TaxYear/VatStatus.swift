import Foundation

/// 消費税の課税区分
enum VatStatus: String, Codable, Sendable, CaseIterable {
    case exempt
    case taxable

    var displayName: String {
        switch self {
        case .exempt: "免税事業者"
        case .taxable: "課税事業者"
        }
    }
}
