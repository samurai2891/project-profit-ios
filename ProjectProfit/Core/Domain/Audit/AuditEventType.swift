import Foundation

/// 監査イベントの種類
enum AuditEventType: String, Codable, Sendable, CaseIterable {
    case evidenceCreated
    case evidenceModified
    case evidenceDeleted
    case evidenceLocked
    case candidateCreated
    case candidateApproved
    case candidateRejected
    case journalApproved
    case journalCancelled
    case journalModified
    case journalLocked
    case yearLockChanged
    case accountChanged
    case taxCodeChanged
    case counterpartyChanged
    case distributionRuleChanged
    case taxYearSettingChanged
    case businessProfileChanged

    var displayName: String {
        switch self {
        case .evidenceCreated: "証憑登録"
        case .evidenceModified: "証憑変更"
        case .evidenceDeleted: "証憑削除"
        case .evidenceLocked: "証憑ロック"
        case .candidateCreated: "仕訳候補作成"
        case .candidateApproved: "仕訳候補承認"
        case .candidateRejected: "仕訳候補却下"
        case .journalApproved: "仕訳確定"
        case .journalCancelled: "仕訳取消"
        case .journalModified: "仕訳修正"
        case .journalLocked: "仕訳ロック"
        case .yearLockChanged: "年度ロック変更"
        case .accountChanged: "勘定科目変更"
        case .taxCodeChanged: "税区分変更"
        case .counterpartyChanged: "取引先変更"
        case .distributionRuleChanged: "配賦ルール変更"
        case .taxYearSettingChanged: "年分設定変更"
        case .businessProfileChanged: "事業者情報変更"
        }
    }
}
