import Foundation
import SwiftData

// MARK: - PPJournalEntry

/// 仕訳伝票（Journal Entry）
/// sourceKey で取引との紐付けを管理し、upsert 時の重複防止に使用する。
/// NOTE: modelContainer への登録は 4A-8 で一括で行う。
@Model
final class PPJournalEntry {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sourceKey: String  // "tx:<uuid>", "manual:<uuid>", "opening:<year>", "closing:<year>"
    var date: Date
    var entryType: JournalEntryType
    var memo: String                           // 摘要
    var isPosted: Bool                         // true = 確定済み（帳簿反映対象）
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sourceKey: String,
        date: Date,
        entryType: JournalEntryType,
        memo: String = "",
        isPosted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceKey = sourceKey
        self.date = date
        self.entryType = entryType
        self.memo = memo
        self.isPosted = isPosted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - PPJournalEntry Computed Properties

extension PPJournalEntry {
    /// sourceKey が "tx:<uuid>" 形式の場合、元の PPTransaction.id を返す
    var sourceTransactionId: UUID? {
        guard sourceKey.hasPrefix("tx:") else { return nil }
        return UUID(uuidString: String(sourceKey.dropFirst(3)))
    }

    static func transactionSourceKey(_ transactionId: UUID) -> String {
        "tx:\(transactionId.uuidString)"
    }

    static func manualSourceKey(_ entryId: UUID) -> String {
        "manual:\(entryId.uuidString)"
    }

    static func openingSourceKey(year: Int) -> String {
        "opening:\(year)"
    }

    static func closingSourceKey(year: Int) -> String {
        "closing:\(year)"
    }
}

// MARK: - PPJournalLine

/// 仕訳明細行（Journal Line）
/// entryId で PPJournalEntry と紐付ける（@Relationship 不使用、手動FK）。
/// 削除時は AccountingEngine / DataStore が関連行を一括削除する。
@Model
final class PPJournalLine {
    @Attribute(.unique) var id: UUID
    // NOTE: iOS 18+ で @Attribute(.indexed) を検討（entryId による検索頻度が高い）
    var entryId: UUID       // FK → PPJournalEntry.id
    var accountId: String   // FK → PPAccount.id
    var debit: Int          // 借方金額（0 or 正の整数、円単位）
    var credit: Int         // 貸方金額（0 or 正の整数、円単位）
    var memo: String
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date

    /// debit と credit は排他的（両方同時に正の値は不可）
    init(
        id: UUID = UUID(),
        entryId: UUID,
        accountId: String,
        debit: Int,
        credit: Int,
        memo: String = "",
        displayOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        precondition(
            !(debit > 0 && credit > 0),
            "PPJournalLine: debit と credit は同時に正の値にできません"
        )
        self.id = id
        self.entryId = entryId
        self.accountId = accountId
        self.debit = debit
        self.credit = credit
        self.memo = memo
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - PPJournalLine Computed Properties

extension PPJournalLine {
    var isDebit: Bool { debit > 0 }
    var isCredit: Bool { credit > 0 }
    /// 表示用の金額（借方・貸方のうち大きい方）
    var amount: Int { max(debit, credit) }
}
