import Foundation

/// 法的書類タイプ（電子帳簿保存法の分類）
/// 既存の LegalDocumentType (PPDocumentRecord) との衝突を避けるため Canonical prefix
enum CanonicalLegalDocumentType: String, Codable, Sendable, CaseIterable {
    case receipt          // 領収書
    case invoice          // 請求書
    case qualifiedInvoice // 適格請求書
    case simplifiedQualifiedInvoice // 簡易適格請求書
    case deliveryNote     // 納品書
    case estimate         // 見積書
    case contract         // 契約書
    case statement        // 明細書
    case cashRegisterReceipt // レジレシート
    case other            // その他

    var displayName: String {
        switch self {
        case .receipt: "領収書"
        case .invoice: "請求書"
        case .qualifiedInvoice: "適格請求書"
        case .simplifiedQualifiedInvoice: "簡易適格請求書"
        case .deliveryNote: "納品書"
        case .estimate: "見積書"
        case .contract: "契約書"
        case .statement: "明細書"
        case .cashRegisterReceipt: "レジレシート"
        case .other: "その他"
        }
    }
}

/// 保存区分（電子帳簿保存法）
enum StorageCategory: String, Codable, Sendable, CaseIterable {
    case paperScan              // 紙→スキャン保存
    case electronicTransaction  // 電子取引データ保存
}

/// コンプライアンスステータス
enum ComplianceStatus: String, Codable, Sendable, CaseIterable {
    case compliant      // 適合
    case pendingReview  // 確認待ち
    case nonCompliant   // 不適合
    case unknown        // 不明
}

/// モデルソース（変更の由来）
enum ModelSource: String, Codable, Sendable, CaseIterable {
    case ai     // AI/OCR による抽出
    case rule   // ルールベース推論
    case user   // ユーザー手入力
}
