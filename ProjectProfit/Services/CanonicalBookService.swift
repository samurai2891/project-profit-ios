import Foundation

/// Canonical帳簿生成サービス（SSOT: CanonicalJournalEntry から全帳簿を派生）
@MainActor
enum CanonicalBookService {
    static func generateJournalBook(
        journals: [CanonicalJournalEntry],
        accounts: [CanonicalAccount],
        counterparties: [UUID: String] = [:],
        dateRange: ClosedRange<Date>? = nil
    ) -> [CanonicalJournalBookEntry] {
        BookProjectionEngine(
            journals: journals,
            accounts: accounts,
            counterparties: counterparties,
            dateRange: dateRange
        ).journalBookEntries()
    }

    static func generateGeneralLedger(
        journals: [CanonicalJournalEntry],
        accountId: UUID,
        accounts: [CanonicalAccount],
        counterparties: [UUID: String] = [:],
        dateRange: ClosedRange<Date>? = nil
    ) -> [CanonicalLedgerEntry] {
        BookProjectionEngine(
            journals: journals,
            accounts: accounts,
            counterparties: counterparties,
            dateRange: dateRange
        ).generalLedgerEntries(accountId: accountId)
    }

    static func generateSubsidiaryLedger(
        journals: [CanonicalJournalEntry],
        type: CanonicalSubLedgerType,
        accounts: [CanonicalAccount],
        counterparties: [UUID: String] = [:],
        dateRange: ClosedRange<Date>? = nil
    ) -> [CanonicalLedgerEntry] {
        BookProjectionEngine(
            journals: journals,
            accounts: accounts,
            counterparties: counterparties,
            dateRange: dateRange
        ).subsidiaryLedgerEntries(type: type)
    }
}

private struct BookProjectionEngine {
    private let journals: [CanonicalJournalEntry]
    private let accountsById: [UUID: CanonicalAccount]
    private let counterparties: [UUID: String]
    private let dateRange: ClosedRange<Date>?

    init(
        journals: [CanonicalJournalEntry],
        accounts: [CanonicalAccount],
        counterparties: [UUID: String],
        dateRange: ClosedRange<Date>?
    ) {
        self.journals = journals
        self.accountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        self.counterparties = counterparties
        self.dateRange = dateRange
    }

    func journalBookEntries() -> [CanonicalJournalBookEntry] {
        filteredJournals().map { journal in
            CanonicalJournalBookEntry(
                id: journal.id,
                journalDate: journal.journalDate,
                voucherNo: journal.voucherNo,
                description: journal.description,
                lines: journal.lines.map { line in
                    let account = accountsById[line.accountId]
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
                },
                entryType: journal.entryType,
                isLocked: journal.lockedAt != nil
            )
        }
    }

    func generalLedgerEntries(accountId: UUID) -> [CanonicalLedgerEntry] {
        guard let account = accountsById[accountId] else {
            return []
        }

        let rows = collectLedgerRows(targetAccountIds: [accountId])
        var runningBalance: Decimal = 0

        return rows.map { row in
            if account.normalBalance == .debit {
                runningBalance += row.line.debitAmount - row.line.creditAmount
            } else {
                runningBalance += row.line.creditAmount - row.line.debitAmount
            }
            return makeLedgerEntry(
                row: row,
                account: account,
                runningBalance: runningBalance
            )
        }
    }

    func subsidiaryLedgerEntries(type: CanonicalSubLedgerType) -> [CanonicalLedgerEntry] {
        let targetAccountIds = BookSpecRegistry.accountIds(for: type, accountsById: accountsById)
        guard !targetAccountIds.isEmpty else {
            return []
        }

        let rows = collectLedgerRows(targetAccountIds: targetAccountIds)
        var balanceByAccount: [UUID: Decimal] = [:]

        return rows.compactMap { row in
            guard let account = accountsById[row.accountId] else {
                return nil
            }
            let previousBalance = balanceByAccount[row.accountId, default: 0]
            let nextBalance: Decimal
            if account.normalBalance == .debit {
                nextBalance = previousBalance + row.line.debitAmount - row.line.creditAmount
            } else {
                nextBalance = previousBalance + row.line.creditAmount - row.line.debitAmount
            }
            balanceByAccount[row.accountId] = nextBalance
            return makeLedgerEntry(
                row: row,
                account: account,
                runningBalance: nextBalance
            )
        }
    }

    private func filteredJournals() -> [CanonicalJournalEntry] {
        journals
            .filter { journal in
                guard let dateRange else { return true }
                return dateRange.contains(journal.journalDate)
            }
            .sorted { $0.journalDate < $1.journalDate }
    }

    private func collectLedgerRows(targetAccountIds: [UUID]) -> [CollectedLedgerRow] {
        let targetSet = Set(targetAccountIds)
        var rows: [CollectedLedgerRow] = []

        for journal in filteredJournals() {
            let siblingLines = journal.lines.filter { !targetSet.contains($0.accountId) }
            for line in journal.lines where targetSet.contains(line.accountId) {
                rows.append(
                    CollectedLedgerRow(
                        journalDate: journal.journalDate,
                        voucherNo: journal.voucherNo,
                        description: journal.description,
                        line: line,
                        accountId: line.accountId,
                        entryType: journal.entryType,
                        siblingLines: siblingLines
                    )
                )
            }
        }

        return rows.sorted { lhs, rhs in
            if lhs.journalDate != rhs.journalDate {
                return lhs.journalDate < rhs.journalDate
            }
            if lhs.voucherNo != rhs.voucherNo {
                return lhs.voucherNo < rhs.voucherNo
            }
            return lhs.line.sortOrder < rhs.line.sortOrder
        }
    }

    private func makeLedgerEntry(
        row: CollectedLedgerRow,
        account: CanonicalAccount,
        runningBalance: Decimal
    ) -> CanonicalLedgerEntry {
        let counterLine = row.siblingLines.max(by: { $0.amount < $1.amount })
        let counterAccount = counterLine.flatMap { accountsById[$0.accountId] }

        return CanonicalLedgerEntry(
            id: row.line.id,
            journalDate: row.journalDate,
            voucherNo: row.voucherNo,
            description: row.description,
            accountId: row.accountId,
            accountCode: account.code,
            accountName: account.name,
            debitAmount: row.line.debitAmount,
            creditAmount: row.line.creditAmount,
            runningBalance: runningBalance,
            counterAccountId: counterLine?.accountId,
            counterAccountName: counterAccount?.name,
            counterpartyName: row.line.counterpartyId.flatMap { counterparties[$0] },
            taxCodeId: row.line.taxCodeId,
            entryType: row.entryType
        )
    }
}

private enum BookSpecRegistry {
    static func accountIds(
        for type: CanonicalSubLedgerType,
        accountsById: [UUID: CanonicalAccount]
    ) -> [UUID] {
        accountsById.values
            .filter { account in
                switch type {
                case .cash:
                    return account.code == "101" || account.name == "現金"
                case .deposit:
                    return account.code.hasPrefix("102") || account.name.contains("預金")
                case .accountsReceivable:
                    return account.code == "103" || account.name == "売掛金"
                case .accountsPayable:
                    return account.code == "201" || account.name == "買掛金"
                case .expense:
                    return account.accountType == .expense && account.archivedAt == nil
                }
            }
            .map(\.id)
    }
}

private struct CollectedLedgerRow {
    let journalDate: Date
    let voucherNo: String
    let description: String
    let line: JournalLine
    let accountId: UUID
    let entryType: CanonicalJournalEntryType
    let siblingLines: [JournalLine]
}
