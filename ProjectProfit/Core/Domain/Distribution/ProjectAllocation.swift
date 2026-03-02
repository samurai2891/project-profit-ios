import Foundation

/// プロジェクト配賦結果
struct CanonicalProjectAllocation: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let projectId: UUID
    let amount: Decimal
    let ratio: Decimal?
    let basisAmount: Decimal?
    let source: AllocationSource

    init(
        id: UUID = UUID(),
        projectId: UUID,
        amount: Decimal,
        ratio: Decimal? = nil,
        basisAmount: Decimal? = nil,
        source: AllocationSource = .manual
    ) {
        self.id = id
        self.projectId = projectId
        self.amount = amount
        self.ratio = ratio
        self.basisAmount = basisAmount
        self.source = source
    }
}

/// 配賦の由来
enum AllocationSource: String, Codable, Sendable, CaseIterable {
    case manual       // ユーザー手動設定
    case fromRule     // 配賦ルールから自動計算
    case fromRecurring // 定期取引から生成

    var displayName: String {
        switch self {
        case .manual: "手動"
        case .fromRule: "ルール"
        case .fromRecurring: "定期取引"
        }
    }
}
