import Foundation
import SwiftData

// MARK: - PPAccountingProfile

/// レガシー会計設定プロファイル（migration-only compat）
/// SwiftData @Model として残し、旧ストア読込と旧スナップショット互換の移行入口だけに使う。
/// 現行の正本は BusinessProfile / TaxYearProfile。
@available(*, deprecated, message: "Use BusinessProfile / TaxYearProfile instead. Migration-only legacy model.")
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
    var lockedAt: Date?                        // レガシー互換の単年度ロック日時（nil = 未ロック）
    // e-Tax 申告者情報フィールド
    var ownerNameKana: String?               // 氏名カナ
    var postalCode: String?                  // 郵便番号（ハイフンなし7桁）
    var address: String?                     // 住所
    var phoneNumber: String?                 // 電話番号
    var dateOfBirth: Date?                   // 生年月日
    var businessCategory: String?            // 事業種類（例: "ソフトウェア開発"）
    var myNumberFlag: Bool?                  // マイナンバー提出フラグ
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
        ownerNameKana: String? = nil,
        postalCode: String? = nil,
        address: String? = nil,
        phoneNumber: String? = nil,
        dateOfBirth: Date? = nil,
        businessCategory: String? = nil,
        myNumberFlag: Bool? = nil,
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
        self.ownerNameKana = ownerNameKana
        self.postalCode = postalCode
        self.address = address
        self.phoneNumber = phoneNumber
        self.dateOfBirth = dateOfBirth
        self.businessCategory = businessCategory
        self.myNumberFlag = myNumberFlag
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Computed Properties

extension PPAccountingProfile {
    /// 年度がロック済みかどうか（レガシー互換: 単年度 lockedAt 基盤）
    var isLocked: Bool { lockedAt != nil }

    /// 指定年度がロック済みかどうか
    func isYearLocked(_ year: Int) -> Bool {
        fiscalYear == year && lockedAt != nil
    }

    /// 年度をロックする
    func lockYear(_ year: Int) {
        guard !isYearLocked(year) else { return }
        guard fiscalYear == year else { return }
        lockedAt = Date()
        updatedAt = Date()
    }

    /// 年度のロックを解除する
    func unlockYear(_ year: Int) {
        guard fiscalYear == year else { return }
        lockedAt = nil
        updatedAt = Date()
    }
}
