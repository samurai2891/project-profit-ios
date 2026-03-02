import Foundation

/// 配賦対象の範囲
enum DistributionScope: String, Codable, Sendable, CaseIterable {
    case allProjects             // 全プロジェクト
    case allActiveProjectsInMonth // 当月アクティブプロジェクト
    case selectedProjects        // 選択プロジェクト
    case projectsByTag           // タグ別プロジェクト

    var displayName: String {
        switch self {
        case .allProjects: "全プロジェクト"
        case .allActiveProjectsInMonth: "当月アクティブ"
        case .selectedProjects: "選択プロジェクト"
        case .projectsByTag: "タグ別"
        }
    }
}
