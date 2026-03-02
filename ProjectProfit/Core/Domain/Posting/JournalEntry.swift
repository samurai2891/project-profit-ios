import Foundation

/// 確定仕訳（正本 = Single Source of Truth）
/// 全帳簿・帳票はこの PostedJournal からの派生生成
struct CanonicalJournalEntry: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let taxYear: Int
    let journalDate: Date
    let voucherNo: String
    let sourceEvidenceId: UUID?
    let sourceCandidateId: UUID?
    let entryType: CanonicalJournalEntryType
    let description: String
    let lines: [JournalLine]
    let approvedAt: Date?
    let lockedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        businessId: UUID,
        taxYear: Int,
        journalDate: Date,
        voucherNo: String,
        sourceEvidenceId: UUID? = nil,
        sourceCandidateId: UUID? = nil,
        entryType: CanonicalJournalEntryType = .normal,
        description: String = "",
        lines: [JournalLine] = [],
        approvedAt: Date? = nil,
        lockedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.taxYear = taxYear
        self.journalDate = journalDate
        self.voucherNo = voucherNo
        self.sourceEvidenceId = sourceEvidenceId
        self.sourceCandidateId = sourceCandidateId
        self.entryType = entryType
        self.description = description
        self.lines = lines
        self.approvedAt = approvedAt
        self.lockedAt = lockedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 借方合計
    var totalDebit: Decimal {
        lines.reduce(Decimal(0)) { $0 + $1.debitAmount }
    }

    /// 貸方合計
    var totalCredit: Decimal {
        lines.reduce(Decimal(0)) { $0 + $1.creditAmount }
    }

    /// 借貸一致チェック
    var isBalanced: Bool {
        totalDebit == totalCredit
    }

    /// イミュータブル更新
    func updated(
        lines: [JournalLine]? = nil,
        description: String? = nil,
        approvedAt: Date?? = nil,
        lockedAt: Date?? = nil
    ) -> CanonicalJournalEntry {
        CanonicalJournalEntry(
            id: self.id,
            businessId: self.businessId,
            taxYear: self.taxYear,
            journalDate: self.journalDate,
            voucherNo: self.voucherNo,
            sourceEvidenceId: self.sourceEvidenceId,
            sourceCandidateId: self.sourceCandidateId,
            entryType: self.entryType,
            description: description ?? self.description,
            lines: lines ?? self.lines,
            approvedAt: approvedAt ?? self.approvedAt,
            lockedAt: lockedAt ?? self.lockedAt,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}
