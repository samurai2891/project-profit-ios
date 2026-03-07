import Foundation

/// 仕訳候補の生成元
enum CandidateSource: String, Codable, Sendable, CaseIterable {
    case ocr          // OCR による自動抽出
    case recurring    // 定期取引からの自動生成
    case importFile   // ファイルインポート
    case manual       // ユーザー手入力
    case carryForward // 前年度繰越

    var displayName: String {
        switch self {
        case .ocr: "OCR抽出"
        case .recurring: "定期取引"
        case .importFile: "インポート"
        case .manual: "手入力"
        case .carryForward: "繰越"
        }
    }
}

/// 仕訳候補のステータス
enum CandidateStatus: String, Codable, Sendable, CaseIterable {
    case draft       // 下書き
    case needsReview // 確認必要
    case approved    // 承認済み
    case rejected    // 却下

    var displayName: String {
        switch self {
        case .draft: "下書き"
        case .needsReview: "要確認"
        case .approved: "承認済み"
        case .rejected: "却下"
        }
    }
}

/// 仕訳の種類
enum CanonicalJournalEntryType: String, Codable, Sendable, CaseIterable {
    case normal              // 通常仕訳
    case opening             // 期首残高
    case closing             // 期末決算
    case depreciation        // 減価償却
    case inventoryAdjustment // 棚卸調整
    case recurring           // 定期仕訳
    case taxAdjustment       // 税務調整
    case reversal            // 取消仕訳

    var displayName: String {
        switch self {
        case .normal: "通常仕訳"
        case .opening: "期首残高"
        case .closing: "期末決算"
        case .depreciation: "減価償却"
        case .inventoryAdjustment: "棚卸調整"
        case .recurring: "定期仕訳"
        case .taxAdjustment: "税務調整"
        case .reversal: "取消仕訳"
        }
    }
}
