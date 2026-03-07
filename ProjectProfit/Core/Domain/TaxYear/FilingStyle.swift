import Foundation

/// 申告方式
enum FilingStyle: String, Codable, Sendable, CaseIterable {
    /// 青色申告（一般用・発生主義）
    case blueGeneral
    /// 青色申告（現金主義用）
    case blueCashBasis
    /// 白色申告
    case white

    var displayName: String {
        switch self {
        case .blueGeneral: "青色申告（一般）"
        case .blueCashBasis: "青色申告（現金主義）"
        case .white: "白色申告"
        }
    }

    var isBlue: Bool {
        switch self {
        case .blueGeneral, .blueCashBasis: true
        case .white: false
        }
    }
}
