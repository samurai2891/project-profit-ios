import Foundation

// MARK: - SubLedgerType

enum SubLedgerType: String, CaseIterable, Identifiable {
    case cashBook
    case accountsReceivableBook
    case accountsPayableBook
    case expenseBook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cashBook: "現金出納帳"
        case .accountsReceivableBook: "売掛帳"
        case .accountsPayableBook: "買掛帳"
        case .expenseBook: "経費帳"
        }
    }

    var subtitle: String {
        switch self {
        case .cashBook: "現金勘定の増減明細"
        case .accountsReceivableBook: "売掛金の増減明細"
        case .accountsPayableBook: "買掛金の増減明細"
        case .expenseBook: "費用科目の明細"
        }
    }
}

// MARK: - SubLedgerEntry

struct SubLedgerEntry: Identifiable {
    let id: UUID
    let date: Date
    let accountId: String
    let accountCode: String
    let accountName: String
    let memo: String
    let debit: Int
    let credit: Int
    let runningBalance: Int
    let counterAccountId: String?
    let counterparty: String?
    let taxCategory: TaxCategory?
}

// MARK: - SubLedgerSummary

struct SubLedgerSummary {
    let count: Int
    let debitTotal: Int
    let creditTotal: Int
    let periodStart: Date?
    let periodEnd: Date?
}

// MARK: - DataStore Sub-Ledger Extension

extension DataStore {

    /// 経費帳から除外する勘定科目ID（仕入・売上原価セクションに属する科目）
    /// NTA p.15: 仕入高・期首棚卸高・売上原価は経費帳ではなく仕入帳に記載
    static let expenseBookExcludedAccountIds: Set<String> = [
        AccountingConstants.purchasesAccountId,
        AccountingConstants.openingInventoryAccountId,
        AccountingConstants.cogsAccountId,
    ]

    func subLedgerAccountIds(for type: SubLedgerType) -> [String] {
        switch type {
        case .cashBook:
            return [AccountingConstants.cashAccountId]
        case .accountsReceivableBook:
            return [AccountingConstants.accountsReceivableAccountId]
        case .accountsPayableBook:
            return [AccountingConstants.accountsPayableAccountId]
        case .expenseBook:
            return accounts.filter { $0.isActive && $0.accountType == .expense
                && !Self.expenseBookExcludedAccountIds.contains($0.id) }.map(\.id)
        }
    }

    /// NTA準拠の補助簿エントリを返す
    /// - Parameters:
    ///   - type: 帳簿種類
    ///   - startDate: 開始日
    ///   - endDate: 終了日
    ///   - accountFilter: 経費帳の科目フィルタ（特定のaccountIdのみ取得）
    ///   - counterpartyFilter: 売掛帳/買掛帳の取引先フィルタ（nil=全件、""=不明、"name"=特定取引先）
    func getSubLedgerEntries(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil,
        accountFilter: String? = nil,
        counterpartyFilter: String? = nil
    ) -> [SubLedgerEntry] {
        let targetAccountIds: [String]
        if let accountFilter {
            targetAccountIds = [accountFilter]
        } else {
            targetAccountIds = subLedgerAccountIds(for: type)
        }
        guard !targetAccountIds.isEmpty else { return [] }

        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let requestedFiscalYear: Int?
        if let startDate {
            requestedFiscalYear = fiscalYear(for: startDate, startMonth: FiscalYearSettings.startMonth)
        } else if let endDate {
            requestedFiscalYear = fiscalYear(for: endDate, startMonth: FiscalYearSettings.startMonth)
        } else {
            requestedFiscalYear = nil
        }
        let projected = projectedCanonicalJournals(fiscalYear: requestedFiscalYear)
        let postedEntryIds = Set(projected.entries.filter(\.isPosted).map(\.id))
        let entryMap = Dictionary(uniqueKeysWithValues: projected.entries.map { ($0.id, $0) })
        let transactionMap = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let linesByEntry = Dictionary(grouping: projected.lines) { $0.entryId }
        let targetAccountIdSet = Set(targetAccountIds)
        let canonicalCounterpartyByEntryId: [UUID: UUID] = {
            guard let businessId = businessProfile?.id else { return [:] }
            return Dictionary(
                uniqueKeysWithValues: fetchCanonicalJournalEntries(businessId: businessId, taxYear: requestedFiscalYear).compactMap { journal in
                    guard let counterpartyId = journal.lines.compactMap({ $0.counterpartyId }).first else {
                        return nil
                    }
                    return (journal.id, counterpartyId)
                }
            )
        }()

        // Collect enriched line data
        var enrichedLines: [(
            lineId: UUID,
            entryDate: Date,
            accountId: String,
            accountCode: String,
            accountName: String,
            memo: String,
            debit: Int,
            credit: Int,
            counterAccountId: String?,
            counterparty: String?,
            taxCategory: TaxCategory?
        )] = []

        for journalLine in projected.lines {
            guard targetAccountIdSet.contains(journalLine.accountId),
                  postedEntryIds.contains(journalLine.entryId),
                  let entry = entryMap[journalLine.entryId] else { continue }

            if let start = startDate, entry.date < start { continue }
            if let end = endDate, entry.date > end { continue }

            let account = accountMap[journalLine.accountId]
            let code = account?.code ?? journalLine.accountId
            let name = account?.name ?? journalLine.accountId

            // 相手勘定の特定: 同一仕訳の他行から最大金額の行を選択（複合仕訳対応）
            let siblingLines = linesByEntry[entry.id]?.filter { $0.id != journalLine.id } ?? []
            let counterAccountId = siblingLines
                .max(by: { $0.amount < $1.amount })?
                .accountId

            // 元取引から取引先・消費税区分を取得
            let transaction = entry.sourceTransactionId.flatMap { transactionMap[$0] }
            let resolvedCounterparty = (transaction?.counterpartyId ?? canonicalCounterpartyByEntryId[entry.id])
                .flatMap { canonicalCounterparty(id: $0)?.displayName }
                ?? transaction?.counterparty

            enrichedLines.append((
                lineId: journalLine.id,
                entryDate: entry.date,
                accountId: journalLine.accountId,
                accountCode: code,
                accountName: name,
                memo: entry.memo,
                debit: journalLine.debit,
                credit: journalLine.credit,
                counterAccountId: counterAccountId,
                counterparty: resolvedCounterparty,
                taxCategory: transaction?.taxCategory
            ))
        }

        // 日付→科目コード→IDでソート
        enrichedLines.sort {
            if $0.entryDate != $1.entryDate { return $0.entryDate < $1.entryDate }
            if $0.accountCode != $1.accountCode { return $0.accountCode < $1.accountCode }
            return $0.lineId.uuidString < $1.lineId.uuidString
        }

        // 取引先フィルタ適用
        if let filter = counterpartyFilter {
            enrichedLines = enrichedLines.filter { line in
                let cp = line.counterparty ?? ""
                return filter.isEmpty ? cp.isEmpty : cp == filter
            }
        }

        // 残高計算: 帳簿種類に応じてグループキーを決定
        var runningBalances: [String: Int] = [:]

        return enrichedLines.map { line in
            let account = accountMap[line.accountId]
            let isDebitNormal = account?.normalBalance == .debit

            // 売掛帳/買掛帳は常に取引先別残高、その他は科目別残高
            let balanceKey: String
            switch type {
            case .accountsReceivableBook, .accountsPayableBook:
                balanceKey = line.counterparty ?? ""
            case .cashBook, .expenseBook:
                balanceKey = line.accountId
            }

            let prev = runningBalances[balanceKey, default: 0]
            let newBalance: Int
            if isDebitNormal {
                newBalance = prev + line.debit - line.credit
            } else {
                newBalance = prev + line.credit - line.debit
            }
            runningBalances[balanceKey] = newBalance

            return SubLedgerEntry(
                id: line.lineId,
                date: line.entryDate,
                accountId: line.accountId,
                accountCode: line.accountCode,
                accountName: line.accountName,
                memo: line.memo,
                debit: line.debit,
                credit: line.credit,
                runningBalance: newBalance,
                counterAccountId: line.counterAccountId,
                counterparty: line.counterparty,
                taxCategory: line.taxCategory
            )
        }
    }

    /// 補助簿の取引先一覧を返す（売掛帳/買掛帳用）
    func getSubLedgerCounterparties(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [String] {
        let entries = getSubLedgerEntries(type: type, startDate: startDate, endDate: endDate)
        let counterparties = Set(entries.compactMap(\.counterparty).filter { !$0.isEmpty })
        return counterparties.sorted()
    }

    // MARK: - Summary

    func getSubLedgerSummary(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> SubLedgerSummary {
        let entries = getSubLedgerEntries(type: type, startDate: startDate, endDate: endDate)
        return SubLedgerSummary(
            count: entries.count,
            debitTotal: entries.reduce(0) { $0 + $1.debit },
            creditTotal: entries.reduce(0) { $0 + $1.credit },
            periodStart: startDate,
            periodEnd: endDate
        )
    }

    // MARK: - CSV Export

    func exportSubLedgerCSV(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil,
        accountFilter: String? = nil,
        counterpartyFilter: String? = nil
    ) -> String {
        let rows = getSubLedgerEntries(
            type: type,
            startDate: startDate,
            endDate: endDate,
            accountFilter: accountFilter,
            counterpartyFilter: counterpartyFilter
        )
        var lines: [String] = [
            "date,accountCode,accountName,memo,counterparty,debit,credit,runningBalance,counterAccountId,taxCategory"
        ]
        let formatter = ISO8601DateFormatter()
        for row in rows {
            let dateText = formatter.string(from: row.date)
            let memo = row.memo.replacingOccurrences(of: "\"", with: "\"\"")
            let accountName = row.accountName.replacingOccurrences(of: "\"", with: "\"\"")
            let counterparty = (row.counterparty ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let taxCat = row.taxCategory?.rawValue ?? ""
            lines.append(
                "\(dateText),\(row.accountCode),\"\(accountName)\",\"\(memo)\",\"\(counterparty)\","
                + "\(row.debit),\(row.credit),\(row.runningBalance),"
                + "\(row.counterAccountId ?? ""),\(taxCat)"
            )
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Canonical Sub-Ledger

    /// Canonical仕訳帳を生成
    func canonicalJournalBook(
        fiscalYear: Int
    ) -> [CanonicalJournalBookEntry] {
        let accounts = canonicalAccounts()
        let journals = canonicalJournalEntries(fiscalYear: fiscalYear)
        return CanonicalBookService.generateJournalBook(
            journals: journals,
            accounts: accounts
        )
    }

    /// Canonical総勘定元帳を生成（特定勘定科目）
    func canonicalGeneralLedger(
        fiscalYear: Int,
        accountId: UUID
    ) -> [CanonicalLedgerEntry] {
        let accounts = canonicalAccounts()
        let journals = canonicalJournalEntries(fiscalYear: fiscalYear)
        return CanonicalBookService.generateGeneralLedger(
            journals: journals,
            accountId: accountId,
            accounts: accounts
        )
    }

    /// Canonical補助元帳を生成
    func canonicalSubsidiaryLedger(
        fiscalYear: Int,
        type: CanonicalSubLedgerType
    ) -> [CanonicalLedgerEntry] {
        let accounts = canonicalAccounts()
        let journals = canonicalJournalEntries(fiscalYear: fiscalYear)
        return CanonicalBookService.generateSubsidiaryLedger(
            journals: journals,
            type: type,
            accounts: accounts
        )
    }
}
