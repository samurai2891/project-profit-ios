import Foundation

/// Canonical repository 共通エラー
enum CanonicalRepositoryError: LocalizedError {
    case recordNotFound(String, UUID)

    var errorDescription: String? {
        switch self {
        case .recordNotFound(let name, _):
            return "\(name) が見つかりません"
        }
    }
}
