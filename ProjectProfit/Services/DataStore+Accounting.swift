import SwiftData
import SwiftUI

// MARK: - DataStore Accounting Extension

extension DataStore {
    // MARK: - Manual Journal Entry CRUD

    @discardableResult
    func addManualJournalEntry(
        date: Date,
        memo: String,
        lines: [(accountId: String, debit: Int, credit: Int, memo: String)]
    ) -> PPJournalEntry? {
        guard !lines.isEmpty else { return nil }
        // T5: 年度ロックガード
        guard !isYearLocked(for: date) else { return nil }

        let entry = PPJournalEntry(
            sourceKey: "manual:\(UUID().uuidString)",
            date: date,
            entryType: .manual,
            memo: memo,
            isPosted: false
        )
        modelContext.insert(entry)

        for (index, line) in lines.enumerated() {
            let journalLine = PPJournalLine(
                entryId: entry.id,
                accountId: line.accountId,
                debit: line.debit,
                credit: line.credit,
                memo: line.memo,
                displayOrder: index
            )
            modelContext.insert(journalLine)
        }

        // バリデーション: 借方合計 == 貸方合計 かつ金額正常
        let debitTotal = lines.reduce(0) { $0 + $1.debit }
        let creditTotal = lines.reduce(0) { $0 + $1.credit }
        let allLinesValid = lines.allSatisfy { line in
            line.debit >= 0 && line.credit >= 0
                && !(line.debit > 0 && line.credit > 0)
                && (line.debit > 0 || line.credit > 0)
        }
        if debitTotal == creditTotal && debitTotal > 0 && allLinesValid {
            entry.isPosted = true
        }

        save()
        refreshJournalEntries()
        refreshJournalLines()
        return entry
    }

    func deleteManualJournalEntry(id: UUID) {
        guard let entry = journalEntries.first(where: { $0.id == id }) else { return }
        guard entry.entryType == .manual else { return }
        // T5: 年度ロックガード
        if isYearLocked(for: entry.date) { return }

        let linesToDelete = journalLines.filter { $0.entryId == id }
        for line in linesToDelete {
            modelContext.delete(line)
        }
        modelContext.delete(entry)

        save()
        refreshJournalEntries()
        refreshJournalLines()
    }

    // MARK: - Account Balance

    func getAccountBalance(accountId: String, upTo date: Date? = nil) -> (debit: Int, credit: Int, balance: Int) {
        let relevantLines: [PPJournalLine]
        if let date {
            let postedEntryIds = Set(
                journalEntries
                    .filter { $0.isPosted && $0.date <= date }
                    .map(\.id)
            )
            relevantLines = journalLines.filter { postedEntryIds.contains($0.entryId) && $0.accountId == accountId }
        } else {
            let postedEntryIds = Set(journalEntries.filter(\.isPosted).map(\.id))
            relevantLines = journalLines.filter { postedEntryIds.contains($0.entryId) && $0.accountId == accountId }
        }

        let debitTotal = relevantLines.reduce(0) { $0 + $1.debit }
        let creditTotal = relevantLines.reduce(0) { $0 + $1.credit }

        // 正常残高方向に応じた残高計算
        let account = accounts.first { $0.id == accountId }
        let balance: Int
        if account?.normalBalance == .debit {
            balance = debitTotal - creditTotal
        } else {
            balance = creditTotal - debitTotal
        }

        return (debit: debitTotal, credit: creditTotal, balance: balance)
    }

    // MARK: - Ledger Entries

    struct LedgerEntry: Identifiable {
        let id: UUID
        let date: Date
        let memo: String
        let entryType: JournalEntryType
        let debit: Int
        let credit: Int
        let runningBalance: Int
    }

    func getLedgerEntries(
        accountId: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [LedgerEntry] {
        let postedEntryIds = Set(journalEntries.filter(\.isPosted).map(\.id))
        let entryMap = Dictionary(uniqueKeysWithValues: journalEntries.map { ($0.id, $0) })

        let relevantLines = journalLines
            .filter { $0.accountId == accountId && postedEntryIds.contains($0.entryId) }
            .compactMap { line -> (line: PPJournalLine, entry: PPJournalEntry)? in
                guard let entry = entryMap[line.entryId] else { return nil }
                if let start = startDate, entry.date < start { return nil }
                if let end = endDate, entry.date > end { return nil }
                return (line, entry)
            }
            .sorted { $0.entry.date < $1.entry.date }

        let account = accounts.first { $0.id == accountId }
        let isDebitNormal = account?.normalBalance == .debit

        var runningBalance = 0
        return relevantLines.map { pair in
            if isDebitNormal {
                runningBalance += pair.line.debit - pair.line.credit
            } else {
                runningBalance += pair.line.credit - pair.line.debit
            }
            return LedgerEntry(
                id: pair.line.id,
                date: pair.entry.date,
                memo: pair.entry.memo,
                entryType: pair.entry.entryType,
                debit: pair.line.debit,
                credit: pair.line.credit,
                runningBalance: runningBalance
            )
        }
    }

}
