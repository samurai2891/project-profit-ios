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
    case fixedAssetNotFound(id: UUID)
    case legacyTransactionMutationDisabled
    case legacyManualJournalMutationDisabled

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
        case .fixedAssetNotFound:
            return "固定資産が見つかりません"
        case .legacyTransactionMutationDisabled:
            return "canonical正本へ移行済みのため、この画面からの取引登録・編集・削除は停止しています。証憑タブから取り込み、承認タブで仕訳を確定してください"
        case .legacyManualJournalMutationDisabled:
            return "canonical正本へ移行済みのため、この画面からの手動仕訳登録・削除は停止しています。証憑タブと承認タブを利用し、決算整理は決算仕訳画面から実行してください"
        }
    }
}
