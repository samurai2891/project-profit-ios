import Foundation

enum SearchIndexRepairVerificationError: LocalizedError {
    case countMismatch(indexCount: Int, sourceCount: Int)

    var errorDescription: String? {
        switch self {
        case .countMismatch(let indexCount, let sourceCount):
            return "索引件数 (\(indexCount)) と元データ件数 (\(sourceCount)) が一致しません"
        }
    }
}
