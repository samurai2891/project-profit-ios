import Foundation

/// 電子帳簿保存法の対応レベル
enum ElectronicBookLevel: String, Codable, Sendable, CaseIterable {
    case none
    case standard
    case superior

    var displayName: String {
        switch self {
        case .none: "未対応"
        case .standard: "標準"
        case .superior: "優良"
        }
    }
}
