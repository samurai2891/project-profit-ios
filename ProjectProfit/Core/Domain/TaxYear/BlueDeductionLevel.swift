import Foundation

/// 青色申告特別控除額の段階
enum BlueDeductionLevel: Int, Codable, Sendable, CaseIterable {
    case none = 0
    case ten = 100000
    case fiftyFive = 550000
    case sixtyFive = 650000

    var displayName: String {
        switch self {
        case .none: "控除なし"
        case .ten: "10万円控除"
        case .fiftyFive: "55万円控除"
        case .sixtyFive: "65万円控除"
        }
    }

    var amount: Decimal {
        Decimal(rawValue)
    }
}
