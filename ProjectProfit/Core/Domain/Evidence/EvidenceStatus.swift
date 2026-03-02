import Foundation

/// 証憑の処理ステータス
enum EvidenceProcessingStatus: String, Codable, Sendable, CaseIterable {
    case uploaded       // アップロード済み
    case ocrProcessing  // OCR処理中
    case ocrCompleted   // OCR完了
    case fieldsExtracted // フィールド抽出済み
    case candidateLinked // 仕訳候補に紐付け済み
    case posted         // 仕訳確定済み
    case archived       // アーカイブ済み

    var displayName: String {
        switch self {
        case .uploaded: "アップロード済み"
        case .ocrProcessing: "OCR処理中"
        case .ocrCompleted: "OCR完了"
        case .fieldsExtracted: "フィールド抽出済み"
        case .candidateLinked: "仕訳候補紐付け済み"
        case .posted: "仕訳確定済み"
        case .archived: "アーカイブ済み"
        }
    }
}
