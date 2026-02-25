import Foundation
import SwiftData

// MARK: - PPAccountingProfile

/// 会計設定プロファイル（1レコードのみ、id = "profile-default" で固定）
/// ブートストラップ時に存在チェック → 未作成なら初期値で生成する。
/// NOTE: modelContainer への登録は 4A-8 で一括で行う。
@Model
final class PPAccountingProfile {
    @Attribute(.unique) var id: String        // "profile-default" 固定
    var fiscalYear: Int                        // 対象年度（例: 2026）
    var bookkeepingMode: BookkeepingMode       // 簡易簿記 / 複式簿記
    var businessName: String                   // 屋号
    var ownerName: String                      // 氏名
    var taxOfficeCode: String?                 // 税務署コード
    var isBlueReturn: Bool                     // 青色申告かどうか
    var defaultPaymentAccountId: String        // デフォルト入出金口座（"acct-cash" 等）
    var openingDate: Date?                     // 開業日
    var lockedAt: Date?                        // 年度ロック日時（nil = 未ロック、T5対応基盤）
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = "profile-default",
        fiscalYear: Int,
        bookkeepingMode: BookkeepingMode = .doubleEntry,
        businessName: String = "",
        ownerName: String = "",
        taxOfficeCode: String? = nil,
        isBlueReturn: Bool = true,
        defaultPaymentAccountId: String = "acct-cash",
        openingDate: Date? = nil,
        lockedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fiscalYear = fiscalYear
        self.bookkeepingMode = bookkeepingMode
        self.businessName = businessName
        self.ownerName = ownerName
        self.taxOfficeCode = taxOfficeCode
        self.isBlueReturn = isBlueReturn
        self.defaultPaymentAccountId = defaultPaymentAccountId
        self.openingDate = openingDate
        self.lockedAt = lockedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Computed Properties

extension PPAccountingProfile {
    /// 年度がロック済みかどうか
    var isLocked: Bool { lockedAt != nil }
}
