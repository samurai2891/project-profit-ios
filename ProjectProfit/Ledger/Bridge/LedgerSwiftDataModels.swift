import Foundation
import SwiftData

// MARK: - SDLedgerBook

/// 台帳インスタンス（1台帳 = 1レコード）。
/// メタデータは台帳タイプごとに異なるため JSON 文字列で保存する。
@Model final class SDLedgerBook {
    @Attribute(.unique) var id: UUID
    var ledgerTypeRaw: String
    var title: String
    var metadataJSON: String
    var includeInvoice: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ledgerType: LedgerType,
        title: String,
        metadataJSON: String = "{}",
        includeInvoice: Bool = false
    ) {
        self.id = id
        self.ledgerTypeRaw = ledgerType.rawValue
        self.title = title
        self.metadataJSON = metadataJSON
        self.includeInvoice = includeInvoice
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var ledgerType: LedgerType? {
        LedgerType(rawValue: ledgerTypeRaw)
    }
}

// MARK: - SDLedgerEntry

/// 台帳エントリー（各行のデータ）。
/// 台帳タイプごとにプロパティが異なるため JSON 文字列で保存し、
/// LedgerBridge で型安全に変換する。
@Model final class SDLedgerEntry {
    @Attribute(.unique) var id: UUID
    var bookId: UUID
    var entryJSON: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bookId: UUID,
        entryJSON: String,
        sortOrder: Int
    ) {
        self.id = id
        self.bookId = bookId
        self.entryJSON = entryJSON
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
