import Foundation

/// Canonical帳簿生成サービス（SSOT: CanonicalJournalEntry から全帳簿を派生）
@MainActor
enum CanonicalBookService {

    // MARK: - 仕訳帳

    /// 仕訳帳を生成
    static func generateJournalBook(
        journals: [CanonicalJournalEntry],
        accounts: [CanonicalAccount],
        counterparties: [UUID: String] = [:],
        dateRange: ClosedRange<Date>? = nil
    ) -> [CanonicalJournalBookEntry] {
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        let filtered = journals
            .filter { journal in
                guard let range = dateRange else { return true }
                return range.contains(journal.journalDate)
            }
            .sorted { $0.journalDate < $1.journalDate }

        return filtered.map { journal in
            let lines = journal.lines.map { line in
                let account = accountMap[line.accountId]
                return CanonicalJournalBookLine(
                    id: line.id,
                    accountId: line.accountId,
                    accountCode: account?.code ?? "",
                    accountName: account?.name ?? "",
                    debitAmount: line.debitAmount,
                    creditAmount: line.creditAmount,
                    taxCodeId: line.taxCodeId,
                    counterpartyName: line.counterpartyId.flatMap { counterparties[$0] }
                )
            }
            return CanonicalJournalBookEntry(
                id: journal.id,
                journalDate: journal.journalDate,
                voucherNo: journal.voucherNo,
                description: journal.description,
                lines: lines,
                entryType: journal.entryType,
                isLocked: journal.lockedAt != nil
            )
        }
    }

    // MARK: - 総勘定元帳

    /// 特定勘定科目の元帳を生成
    static func generateGeneralLedger(
        journals: [CanonicalJournalEntry],
        accountId: UUID,
        accounts: [CanonicalAccount],
        counterparties: [UUID: String] = [:],
        dateRange: ClosedRange<Date>? = nil
    ) -> [CanonicalLedgerEntry] {
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let targetAccount = accountMap[accountId]
        let isDebitNormal = targetAccount?.normalBalance == .debit

        let filtered = journals.filter { journal in
            guard let range = dateRange else { return true }
            return range.contains(journal.journalDate)
        }

        // 対象勘定科目に関連する行を収集
        var collected: [CollectedLedgerLine] = []

        for journal in filtered {
            let matchingLines = journal.lines.filter { $0.accountId == accountId }
            let otherLines = journal.lines.filter { $0.accountId != accountId }
            for line in matchingLines {
                collected.append(CollectedLedgerLine(
                    date: journal.journalDate,
                    voucherNo: journal.voucherNo,
                    description: journal.description,
                    line: line,
                    accountId: accountId,
                    entryType: journal.entryType,
                    siblingLines: otherLines
                ))
            }
        }

        collected.sort { $0.date < $1.date }

        var runningBalance: Decimal = 0
        return collected.map { entry in
            let counterLine = entry.siblingLines.max(by: { $0.amount < $1.amount })
            let counterAccount = counterLine.flatMap { accountMap[$0.accountId] }
            let counterpartyName = entry.line.counterpartyId.flatMap { counterparties[$0] }

            if isDebitNormal {
                runningBalance += entry.line.debitAmount - entry.line.creditAmount
            } else {
                runningBalance += entry.line.creditAmount - entry.line.debitAmount
            }

            return CanonicalLedgerEntry(
                id: entry.line.id,
                journalDate: entry.date,
                voucherNo: entry.voucherNo,
                description: entry.description,
                accountId: accountId,
                accountCode: targetAccount?.code ?? "",
                accountName: targetAccount?.name ?? "",
                debitAmount: entry.line.debitAmount,
                creditAmount: entry.line.creditAmount,
                runningBalance: runningBalance,
                counterAccountId: counterLine?.accountId,
                counterAccountName: counterAccount?.name,
                counterpartyName: counterpartyName,
                taxCodeId: entry.line.taxCodeId,
                entryType: entry.entryType
            )
        }
    }

    // MARK: - 補助元帳

    /// 補助元帳を生成（現金/預金/売掛/買掛/経費）
    static func generateSubsidiaryLedger(
        journals: [CanonicalJournalEntry],
        type: CanonicalSubLedgerType,
        accounts: [CanonicalAccount],
        counterparties: [UUID: String] = [:],
        dateRange: ClosedRange<Date>? = nil
    ) -> [CanonicalLedgerEntry] {
        let targetAccountIds = resolveAccountIds(for: type, accounts: accounts)
        guard !targetAccountIds.isEmpty else { return [] }

        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let targetSet = Set(targetAccountIds)

        let filtered = journals.filter { journal in
            guard let range = dateRange else { return true }
            return range.contains(journal.journalDate)
        }

        // 対象勘定科目に関連する行を収集
        var collected: [CollectedLedgerLine] = []

        for journal in filtered {
            let matchingLines = journal.lines.filter { targetSet.contains($0.accountId) }
            let otherLines = journal.lines.filter { !targetSet.contains($0.accountId) }
            for line in matchingLines {
                collected.append(CollectedLedgerLine(
                    date: journal.journalDate,
                    voucherNo: journal.voucherNo,
                    description: journal.description,
                    line: line,
                    accountId: line.accountId,
                    entryType: journal.entryType,
                    siblingLines: otherLines
                ))
            }
        }

        collected.sort { $0.date < $1.date }

        var balanceByAccount: [UUID: Decimal] = [:]
        return collected.map { entry in
            let account = accountMap[entry.accountId]
            let isDebitNormal = account?.normalBalance == .debit
            let counterLine = entry.siblingLines.max(by: { $0.amount < $1.amount })
            let counterAccount = counterLine.flatMap { accountMap[$0.accountId] }
            let counterpartyName = entry.line.counterpartyId.flatMap { counterparties[$0] }

            let prev = balanceByAccount[entry.accountId, default: 0]
            let newBalance: Decimal
            if isDebitNormal {
                newBalance = prev + entry.line.debitAmount - entry.line.creditAmount
            } else {
                newBalance = prev + entry.line.creditAmount - entry.line.debitAmount
            }
            balanceByAccount[entry.accountId] = newBalance

            return CanonicalLedgerEntry(
                id: entry.line.id,
                journalDate: entry.date,
                voucherNo: entry.voucherNo,
                description: entry.description,
                accountId: entry.accountId,
                accountCode: account?.code ?? "",
                accountName: account?.name ?? "",
                debitAmount: entry.line.debitAmount,
                creditAmount: entry.line.creditAmount,
                runningBalance: newBalance,
                counterAccountId: counterLine?.accountId,
                counterAccountName: counterAccount?.name,
                counterpartyName: counterpartyName,
                taxCodeId: entry.line.taxCodeId,
                entryType: entry.entryType
            )
        }
    }

    // MARK: - Account Resolution

    /// 補助元帳の種類に対応する勘定科目IDを解決
    private static func resolveAccountIds(
        for type: CanonicalSubLedgerType,
        accounts: [CanonicalAccount]
    ) -> [UUID] {
        switch type {
        case .cash:
            return accounts.filter { $0.code == "101" || $0.name == "現金" }.map(\.id)
        case .deposit:
            return accounts.filter { $0.code.hasPrefix("102") || $0.name.contains("預金") }.map(\.id)
        case .accountsReceivable:
            return accounts.filter { $0.code == "103" || $0.name == "売掛金" }.map(\.id)
        case .accountsPayable:
            return accounts.filter { $0.code == "201" || $0.name == "買掛金" }.map(\.id)
        case .expense:
            return accounts.filter { $0.accountType == .expense && $0.archivedAt == nil }.map(\.id)
        }
    }
}

// MARK: - Internal Types

/// 元帳生成時の中間データ（行の収集結果）
private struct CollectedLedgerLine {
    let date: Date
    let voucherNo: String
    let description: String
    let line: JournalLine
    let accountId: UUID
    let entryType: CanonicalJournalEntryType
    let siblingLines: [JournalLine]
}
