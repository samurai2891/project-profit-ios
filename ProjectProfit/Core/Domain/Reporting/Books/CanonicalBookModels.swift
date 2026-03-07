import Foundation

/// 仕訳帳エントリ（canonical）
struct CanonicalJournalBookEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let journalDate: Date
    let voucherNo: String
    let description: String
    let lines: [CanonicalJournalBookLine]
    let entryType: CanonicalJournalEntryType
    let isLocked: Bool
}

struct CanonicalJournalBookLine: Identifiable, Sendable, Equatable {
    let id: UUID
    let accountId: UUID
    let accountCode: String
    let accountName: String
    let debitAmount: Decimal
    let creditAmount: Decimal
    let taxCodeId: String?
    let counterpartyName: String?
}

/// 元帳エントリ（canonical -- 総勘定元帳/補助元帳共通）
struct CanonicalLedgerEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let journalDate: Date
    let voucherNo: String
    let description: String
    let accountId: UUID
    let accountCode: String
    let accountName: String
    let debitAmount: Decimal
    let creditAmount: Decimal
    let runningBalance: Decimal
    let counterAccountId: UUID?
    let counterAccountName: String?
    let counterpartyName: String?
    let taxCodeId: String?
    let entryType: CanonicalJournalEntryType
}

/// 補助元帳の種類
enum CanonicalSubLedgerType: String, CaseIterable, Sendable {
    case cash                // 現金出納帳
    case deposit             // 預金出納帳
    case accountsReceivable  // 売掛帳
    case accountsPayable     // 買掛帳
    case expense             // 経費帳

    var displayName: String {
        switch self {
        case .cash: "現金出納帳"
        case .deposit: "預金出納帳"
        case .accountsReceivable: "売掛帳"
        case .accountsPayable: "買掛帳"
        case .expense: "経費帳"
        }
    }
}
