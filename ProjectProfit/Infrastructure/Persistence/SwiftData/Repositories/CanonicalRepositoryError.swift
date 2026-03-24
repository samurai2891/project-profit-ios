import Foundation

/// Canonical repository 共通エラー
enum CanonicalRepositoryError: LocalizedError {
    case recordNotFound(String, UUID)
    case searchIndexCorrupted(indexName: String, recordId: UUID, field: String)
    case searchIndexRebuildFailed(indexName: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .recordNotFound(let name, _):
            return "\(name) が見つかりません"
        case .searchIndexCorrupted(let indexName, let recordId, let field):
            return "\(indexName) の索引データが破損しています（recordId: \(recordId.uuidString), field: \(field)）"
        case .searchIndexRebuildFailed(let indexName, let underlying):
            return "\(indexName) の再索引に失敗しました: \(underlying.localizedDescription)"
        }
    }
}
