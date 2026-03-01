import Foundation

// MARK: - LedgerBridge

/// 納品 Codable struct ↔ SwiftData SDLedgerEntry 間の変換レイヤー。
/// 納品ファイル (LedgerModels.swift) は変更不可のため、
/// JSON シリアライズ経由で型安全に変換する。
enum LedgerBridge {

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        return enc
    }()

    private static let decoder = JSONDecoder()

    // MARK: - Generic Encode / Decode

    static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    // MARK: - Entry Encode (Codable struct → SDLedgerEntry)

    static func encodeEntry<T: Encodable>(
        _ entry: T,
        bookId: UUID,
        sortOrder: Int
    ) -> SDLedgerEntry? {
        guard let json = encode(entry) else { return nil }
        return SDLedgerEntry(
            bookId: bookId,
            entryJSON: json,
            sortOrder: sortOrder
        )
    }

    // MARK: - Entry Decode (SDLedgerEntry → Codable struct)

    static func decodeCashBookEntry(from sd: SDLedgerEntry) -> CashBookEntry? {
        decode(CashBookEntry.self, from: sd.entryJSON)
    }

    static func decodeBankAccountBookEntry(from sd: SDLedgerEntry) -> BankAccountBookEntry? {
        decode(BankAccountBookEntry.self, from: sd.entryJSON)
    }

    static func decodeAccountsReceivableEntry(from sd: SDLedgerEntry) -> AccountsReceivableEntry? {
        decode(AccountsReceivableEntry.self, from: sd.entryJSON)
    }

    static func decodeAccountsPayableEntry(from sd: SDLedgerEntry) -> AccountsPayableEntry? {
        decode(AccountsPayableEntry.self, from: sd.entryJSON)
    }

    static func decodeExpenseBookEntry(from sd: SDLedgerEntry) -> ExpenseBookEntry? {
        decode(ExpenseBookEntry.self, from: sd.entryJSON)
    }

    static func decodeGeneralLedgerEntry(from sd: SDLedgerEntry) -> GeneralLedgerEntry? {
        decode(GeneralLedgerEntry.self, from: sd.entryJSON)
    }

    static func decodeJournalEntry(from sd: SDLedgerEntry) -> JournalEntry? {
        decode(JournalEntry.self, from: sd.entryJSON)
    }

    static func decodeFixedAssetDepreciationEntry(from sd: SDLedgerEntry) -> FixedAssetDepreciationEntry? {
        decode(FixedAssetDepreciationEntry.self, from: sd.entryJSON)
    }

    static func decodeFixedAssetRegisterEntry(from sd: SDLedgerEntry) -> FixedAssetRegisterEntry? {
        decode(FixedAssetRegisterEntry.self, from: sd.entryJSON)
    }

    static func decodeTransportationExpenseEntry(from sd: SDLedgerEntry) -> TransportationExpenseEntry? {
        decode(TransportationExpenseEntry.self, from: sd.entryJSON)
    }

    static func decodeWhiteTaxBookkeepingEntry(from sd: SDLedgerEntry) -> WhiteTaxBookkeepingEntry? {
        decode(WhiteTaxBookkeepingEntry.self, from: sd.entryJSON)
    }

    // MARK: - Metadata Encode / Decode

    static func encodeCashBookMetadata(_ metadata: CashBookMetadata) -> String {
        encode(metadata) ?? "{}"
    }

    static func decodeCashBookMetadata(from json: String) -> CashBookMetadata {
        decode(CashBookMetadata.self, from: json) ?? CashBookMetadata()
    }

    static func encodeBankAccountBookMetadata(_ metadata: BankAccountBookMetadata) -> String {
        encode(metadata) ?? "{}"
    }

    static func decodeBankAccountBookMetadata(from json: String) -> BankAccountBookMetadata {
        decode(BankAccountBookMetadata.self, from: json) ?? BankAccountBookMetadata()
    }

    static func encodeAccountsReceivableMetadata(_ metadata: AccountsReceivableMetadata) -> String {
        encode(metadata) ?? "{}"
    }

    static func decodeAccountsReceivableMetadata(from json: String) -> AccountsReceivableMetadata {
        decode(AccountsReceivableMetadata.self, from: json) ?? AccountsReceivableMetadata()
    }

    static func encodeAccountsPayableMetadata(_ metadata: AccountsPayableMetadata) -> String {
        encode(metadata) ?? "{}"
    }

    static func decodeAccountsPayableMetadata(from json: String) -> AccountsPayableMetadata {
        decode(AccountsPayableMetadata.self, from: json) ?? AccountsPayableMetadata()
    }

    static func encodeExpenseBookMetadata(_ metadata: ExpenseBookMetadata) -> String {
        encode(metadata) ?? "{}"
    }

    static func decodeExpenseBookMetadata(from json: String) -> ExpenseBookMetadata {
        decode(ExpenseBookMetadata.self, from: json) ?? ExpenseBookMetadata()
    }

    static func encodeGeneralLedgerMetadata(_ metadata: GeneralLedgerMetadata) -> String {
        encode(metadata) ?? "{}"
    }

    static func decodeGeneralLedgerMetadata(from json: String) -> GeneralLedgerMetadata {
        decode(GeneralLedgerMetadata.self, from: json) ?? GeneralLedgerMetadata()
    }

    static func encodeFixedAssetDepreciationMetadata(_ metadata: FixedAssetDepreciationMetadata) -> String {
        encode(metadata) ?? "{}"
    }

    static func decodeFixedAssetDepreciationMetadata(from json: String) -> FixedAssetDepreciationMetadata {
        decode(FixedAssetDepreciationMetadata.self, from: json) ?? FixedAssetDepreciationMetadata()
    }

    static func encodeFixedAssetRegisterMetadata(_ metadata: FixedAssetRegisterMetadata) -> String {
        encode(metadata) ?? "{}"
    }

    static func decodeFixedAssetRegisterMetadata(from json: String) -> FixedAssetRegisterMetadata {
        decode(FixedAssetRegisterMetadata.self, from: json) ?? FixedAssetRegisterMetadata()
    }

    static func encodeTransportationExpenseMetadata(_ metadata: TransportationExpenseMetadata) -> String {
        encode(metadata) ?? "{}"
    }

    static func decodeTransportationExpenseMetadata(from json: String) -> TransportationExpenseMetadata {
        decode(TransportationExpenseMetadata.self, from: json) ?? TransportationExpenseMetadata()
    }

    static func encodeWhiteTaxBookkeepingMetadata(_ metadata: WhiteTaxBookkeepingMetadata) -> String {
        encode(metadata) ?? "{}"
    }

    static func decodeWhiteTaxBookkeepingMetadata(from json: String) -> WhiteTaxBookkeepingMetadata {
        decode(WhiteTaxBookkeepingMetadata.self, from: json) ?? WhiteTaxBookkeepingMetadata()
    }

    // MARK: - LedgerType-based Dispatch

    /// 台帳タイプに応じてエントリーをデコードし Any で返す。
    /// 呼び出し側で適切な型にキャストする。
    static func decodeAnyEntry(ledgerType: LedgerType, from sd: SDLedgerEntry) -> Any? {
        switch ledgerType {
        case .cashBook, .cashBookInvoice:
            return decodeCashBookEntry(from: sd)
        case .bankAccountBook, .bankAccountBookInvoice:
            return decodeBankAccountBookEntry(from: sd)
        case .accountsReceivable:
            return decodeAccountsReceivableEntry(from: sd)
        case .accountsPayable:
            return decodeAccountsPayableEntry(from: sd)
        case .expenseBook, .expenseBookInvoice:
            return decodeExpenseBookEntry(from: sd)
        case .generalLedger, .generalLedgerInvoice:
            return decodeGeneralLedgerEntry(from: sd)
        case .journal:
            return decodeJournalEntry(from: sd)
        case .fixedAssetDepreciation:
            return decodeFixedAssetDepreciationEntry(from: sd)
        case .fixedAssetRegister:
            return decodeFixedAssetRegisterEntry(from: sd)
        case .transportationExpense:
            return decodeTransportationExpenseEntry(from: sd)
        case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            return decodeWhiteTaxBookkeepingEntry(from: sd)
        }
    }
}
