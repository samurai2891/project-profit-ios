import Foundation

/// 年度ロック状態
enum YearLockState: String, Codable, Sendable, CaseIterable {
    /// 通常（編集可能）
    case open
    /// 仮締め（修正可、追加制限あり）
    case softClose
    /// 税務締め（決算整理仕訳のみ可能）
    case taxClose
    /// 申告済み（変更不可、調整仕訳のみ）
    case filed
    /// 最終ロック（完全凍結）
    case finalLock

    var displayName: String {
        switch self {
        case .open: "未締め"
        case .softClose: "仮締め"
        case .taxClose: "税務締め"
        case .filed: "申告済み"
        case .finalLock: "最終確定"
        }
    }

    /// 通常仕訳の追加が可能か
    var allowsNormalPosting: Bool {
        switch self {
        case .open, .softClose: true
        case .taxClose, .filed, .finalLock: false
        }
    }

    /// 決算整理仕訳が可能か
    var allowsAdjustingEntries: Bool {
        switch self {
        case .open, .softClose, .taxClose: true
        case .filed, .finalLock: false
        }
    }

    /// 編集が完全に禁止されているか
    var isFullyLocked: Bool {
        self == .finalLock
    }
}
