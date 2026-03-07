import Foundation

/// 記帳方式
enum BookkeepingBasis: String, Codable, Sendable, CaseIterable {
    case singleEntry
    case doubleEntry
    case cashBasis

    var displayName: String {
        switch self {
        case .singleEntry: "簡易簿記"
        case .doubleEntry: "複式簿記"
        case .cashBasis: "現金主義"
        }
    }
}
