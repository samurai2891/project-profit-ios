import Foundation

enum AppError: LocalizedError {
    case dataLoadFailed(underlying: Error)
    case saveFailed(underlying: Error)
    case projectNotFound(id: UUID)
    case transactionNotFound(id: UUID)
    case categoryNotFound(id: String)
    case recurringNotFound(id: UUID)
    case cannotDeleteDefaultCategory
    case invalidInput(message: String)
    case yearLocked(year: Int)

    var errorDescription: String? {
        switch self {
        case .dataLoadFailed:
            return "データの読み込みに失敗しました"
        case .saveFailed:
            return "データの保存に失敗しました"
        case .projectNotFound:
            return "プロジェクトが見つかりません"
        case .transactionNotFound:
            return "取引が見つかりません"
        case .categoryNotFound:
            return "カテゴリが見つかりません"
        case .recurringNotFound:
            return "定期取引が見つかりません"
        case .cannotDeleteDefaultCategory:
            return "デフォルトカテゴリは削除できません"
        case .invalidInput(let message):
            return message
        case .yearLocked(let year):
            return "\(year)年度はロックされています。変更するにはロックを解除してください"
        }
    }
}
