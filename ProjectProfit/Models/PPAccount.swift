import Foundation
import SwiftData

// MARK: - PPAccount

/// 勘定科目（Chart of Accounts）
/// id は固定文字列（例: "acct-cash", "acct-sales"）を使用し、ブートストラップやFKの安定参照を実現する。
/// NOTE: modelContainer への登録は 4A-8 で PPJournalEntry/PPJournalLine/PPAccountingProfile と一括で行う。
@Model
final class PPAccount {
    @Attribute(.unique) var id: String
    var code: String              // 勘定科目コード（"101", "401" 等、表示・ソート用）
    var name: String              // 表示名（"現金", "売上高" 等）
    var accountType: AccountType
    var normalBalance: NormalBalance
    var subtype: AccountSubtype?
    var parentAccountId: String?  // 階層構造用（親勘定科目のid）
    var isSystem: Bool            // デフォルト勘定科目（削除不可）
    var isActive: Bool
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        code: String,
        name: String,
        accountType: AccountType,
        normalBalance: NormalBalance? = nil,
        subtype: AccountSubtype? = nil,
        parentAccountId: String? = nil,
        isSystem: Bool = false,
        isActive: Bool = true,
        displayOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.accountType = accountType
        self.normalBalance = normalBalance ?? accountType.normalBalance
        self.subtype = subtype
        self.parentAccountId = parentAccountId
        self.isSystem = isSystem
        self.isActive = isActive
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Computed Properties

extension PPAccount {
    /// 取引フォームの口座ピッカーに表示する「実務口座」かどうか
    /// 事業主借・事業主貸は振替取引で使用するため、ここには含めない
    var isPaymentAccount: Bool {
        guard let subtype else { return false }
        return [.cash, .ordinaryDeposit, .creditCard, .accountsReceivable, .accountsPayable]
            .contains(subtype)
    }
}
