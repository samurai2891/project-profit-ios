import Foundation
import SwiftData

@MainActor
struct ProjectedJournalReadModelQuery {
    private let support: AccountingReadSupport
    private let supplementalSourcePrefixes: Set<String>

    init(
        modelContext: ModelContext,
        supplementalSourcePrefixes: Set<String> = ["manual:", "opening:", "closing:"]
    ) {
        self.init(
            support: AccountingReadSupport(modelContext: modelContext),
            supplementalSourcePrefixes: supplementalSourcePrefixes
        )
    }

    init(
        support: AccountingReadSupport,
        supplementalSourcePrefixes: Set<String> = ["manual:", "opening:", "closing:"]
    ) {
        self.support = support
        self.supplementalSourcePrefixes = supplementalSourcePrefixes
    }

    func snapshot(fiscalYear requestedFiscalYear: Int? = nil) -> ProjectedJournalSnapshot {
        guard let businessProfile = support.fetchBusinessProfile() else {
            return ProjectedJournalSnapshot(businessId: nil, entries: [], lines: [])
        }

        let projected = LegacyProjectedJournalAssembler.assemble(
            businessId: businessProfile.id,
            fiscalYear: requestedFiscalYear,
            canonicalAccounts: support.fetchCanonicalAccounts(businessId: businessProfile.id),
            canonicalJournals: support.fetchCanonicalJournalEntries(
                businessId: businessProfile.id,
                taxYear: requestedFiscalYear
            ),
            legacyEntries: support.fetchJournalEntries(),
            legacyLines: support.fetchJournalLines(),
            supplementalSourcePrefixes: supplementalSourcePrefixes
        )
        return ProjectedJournalSnapshot(
            businessId: projected.businessId,
            entries: projected.entries,
            lines: projected.lines
        )
    }
}

@MainActor
struct AccountingLedgerReadModelQuery {
    private let support: AccountingReadSupport
    private let projectedJournalQuery: ProjectedJournalReadModelQuery

    init(modelContext: ModelContext) {
        let support = AccountingReadSupport(modelContext: modelContext)
        self.init(support: support)
    }

    init(support: AccountingReadSupport) {
        self.support = support
        self.projectedJournalQuery = ProjectedJournalReadModelQuery(support: support)
    }

    func accountBalance(accountId: String, upTo date: Date? = nil) -> GeneralLedgerBalance {
        let requestedFiscalYear = date.map { fiscalYear(for: $0, startMonth: FiscalYearSettings.startMonth) }
        let projected = projectedJournalQuery.snapshot(fiscalYear: requestedFiscalYear)
        let entryMap = Dictionary(uniqueKeysWithValues: projected.entries.map { ($0.id, $0) })

        let relevantLines: [PPJournalLine]
        if let date {
            let postedEntryIds = Set(
                projected.entries
                    .filter { $0.isPosted && $0.date <= date }
                    .map(\.id)
            )
            relevantLines = projected.lines.filter { line in
                guard postedEntryIds.contains(line.entryId),
                      line.accountId == accountId,
                      let entry = entryMap[line.entryId]
                else {
                    return false
                }
                return entry.date <= date
            }
        } else {
            let postedEntryIds = Set(projected.entries.filter(\.isPosted).map(\.id))
            relevantLines = projected.lines.filter {
                postedEntryIds.contains($0.entryId) && $0.accountId == accountId
            }
        }

        let debitTotal = relevantLines.reduce(0) { $0 + $1.debit }
        let creditTotal = relevantLines.reduce(0) { $0 + $1.credit }
        let account = support.fetchAccounts().first { $0.id == accountId }
        let balance = account?.normalBalance == .debit
            ? debitTotal - creditTotal
            : creditTotal - debitTotal

        return GeneralLedgerBalance(
            debit: debitTotal,
            credit: creditTotal,
            balance: balance
        )
    }

    func entries(
        accountId: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [AccountingLedgerEntry] {
        let requestedFiscalYear: Int?
        if let startDate {
            requestedFiscalYear = fiscalYear(for: startDate, startMonth: FiscalYearSettings.startMonth)
        } else if let endDate {
            requestedFiscalYear = fiscalYear(for: endDate, startMonth: FiscalYearSettings.startMonth)
        } else {
            requestedFiscalYear = nil
        }

        let projected = projectedJournalQuery.snapshot(fiscalYear: requestedFiscalYear)
        let postedEntryIds = Set(projected.entries.filter(\.isPosted).map(\.id))
        let entryMap = Dictionary(uniqueKeysWithValues: projected.entries.map { ($0.id, $0) })
        let transactions = support.fetchTransactions()
        let transactionMap = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let transactionMapByJournalEntryId: [UUID: PPTransaction] = Dictionary(
            uniqueKeysWithValues: transactions.compactMap { transaction in
                guard let journalEntryId = transaction.journalEntryId else {
                    return nil
                }
                return (journalEntryId, transaction)
            }
        )
        let canonicalCounterpartyByEntryId = canonicalCounterpartyIds(
            businessId: projected.businessId,
            requestedFiscalYear: requestedFiscalYear
        )

        let relevantLines = projected.lines
            .filter { $0.accountId == accountId && postedEntryIds.contains($0.entryId) }
            .compactMap { line -> (PPJournalLine, PPJournalEntry)? in
                guard let entry = entryMap[line.entryId] else { return nil }
                if let startDate, entry.date < startDate { return nil }
                if let endDate, entry.date > endDate { return nil }
                return (line, entry)
            }
            .sorted { $0.1.date < $1.1.date }

        let account = support.fetchAccounts().first { $0.id == accountId }
        let isDebitNormal = account?.normalBalance == .debit
        var runningBalance = 0

        return relevantLines.map { line, entry in
            if isDebitNormal {
                runningBalance += line.debit - line.credit
            } else {
                runningBalance += line.credit - line.debit
            }

            let transaction = entry.sourceTransactionId.flatMap { transactionMap[$0] }
                ?? transactionMapByJournalEntryId[entry.id]
            let resolvedCounterparty = (transaction?.counterpartyId ?? canonicalCounterpartyByEntryId[entry.id])
                .flatMap { support.fetchCanonicalCounterparty(id: $0)?.displayName }
                ?? transaction?.counterparty
            let resolvedTaxCategory = transaction?.resolvedTaxCategory

            return AccountingLedgerEntry(
                id: line.id,
                date: entry.date,
                memo: entry.memo,
                entryType: entry.entryType,
                debit: line.debit,
                credit: line.credit,
                runningBalance: runningBalance,
                counterparty: resolvedCounterparty,
                taxCategory: resolvedTaxCategory
            )
        }
    }

    private func canonicalCounterpartyIds(
        businessId: UUID?,
        requestedFiscalYear: Int?
    ) -> [UUID: UUID] {
        guard let businessId else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues: support.fetchCanonicalJournalEntries(
                businessId: businessId,
                taxYear: requestedFiscalYear
            ).compactMap { journal in
                guard let counterpartyId = journal.lines.compactMap(\.counterpartyId).first else {
                    return nil
                }
                return (journal.id, counterpartyId)
            }
        )
    }
}

@MainActor
struct SubLedgerReadModelQuery {
    private let support: AccountingReadSupport
    private let projectedJournalQuery: ProjectedJournalReadModelQuery

    init(modelContext: ModelContext) {
        let support = AccountingReadSupport(modelContext: modelContext)
        self.init(support: support)
    }

    init(support: AccountingReadSupport) {
        self.support = support
        self.projectedJournalQuery = ProjectedJournalReadModelQuery(support: support)
    }

    func entries(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil,
        accountFilter: String? = nil,
        counterpartyFilter: String? = nil
    ) -> [SubLedgerEntry] {
        let accounts = support.fetchAccounts()
        let targetAccountIds: [String]
        if let accountFilter {
            targetAccountIds = [accountFilter]
        } else {
            targetAccountIds = subLedgerAccountIds(for: type, accounts: accounts)
        }
        guard !targetAccountIds.isEmpty else {
            return []
        }

        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let requestedFiscalYear: Int?
        if let startDate {
            requestedFiscalYear = fiscalYear(for: startDate, startMonth: FiscalYearSettings.startMonth)
        } else if let endDate {
            requestedFiscalYear = fiscalYear(for: endDate, startMonth: FiscalYearSettings.startMonth)
        } else {
            requestedFiscalYear = nil
        }

        let projected = projectedJournalQuery.snapshot(fiscalYear: requestedFiscalYear)
        let postedEntryIds = Set(projected.entries.filter(\.isPosted).map(\.id))
        let entryMap = Dictionary(uniqueKeysWithValues: projected.entries.map { ($0.id, $0) })
        let transactions = support.fetchTransactions()
        let transactionMap = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let transactionMapByJournalEntryId: [UUID: PPTransaction] = Dictionary(
            uniqueKeysWithValues: transactions.compactMap { transaction in
                guard let journalEntryId = transaction.journalEntryId else {
                    return nil
                }
                return (journalEntryId, transaction)
            }
        )
        let linesByEntry = Dictionary(grouping: projected.lines) { $0.entryId }
        let targetAccountIdSet = Set(targetAccountIds)
        let canonicalCounterpartyByEntryId = canonicalCounterpartyIds(
            businessId: projected.businessId,
            requestedFiscalYear: requestedFiscalYear
        )

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
                  let entry = entryMap[journalLine.entryId]
            else {
                continue
            }
            if let startDate, entry.date < startDate { continue }
            if let endDate, entry.date > endDate { continue }

            let account = accountMap[journalLine.accountId]
            let siblingLines = linesByEntry[entry.id]?.filter { $0.id != journalLine.id } ?? []
            let transaction = entry.sourceTransactionId.flatMap { transactionMap[$0] }
                ?? transactionMapByJournalEntryId[entry.id]
            let resolvedCounterparty = (transaction?.counterpartyId ?? canonicalCounterpartyByEntryId[entry.id])
                .flatMap { support.fetchCanonicalCounterparty(id: $0)?.displayName }
                ?? transaction?.counterparty
            let resolvedTaxCategory = transaction?.resolvedTaxCategory

            enrichedLines.append((
                lineId: journalLine.id,
                entryDate: entry.date,
                accountId: journalLine.accountId,
                accountCode: account?.code ?? journalLine.accountId,
                accountName: account?.name ?? journalLine.accountId,
                memo: entry.memo,
                debit: journalLine.debit,
                credit: journalLine.credit,
                counterAccountId: siblingLines.max(by: { $0.amount < $1.amount })?.accountId,
                counterparty: resolvedCounterparty,
                taxCategory: resolvedTaxCategory
            ))
        }

        enrichedLines.sort {
            if $0.entryDate != $1.entryDate { return $0.entryDate < $1.entryDate }
            if $0.accountCode != $1.accountCode { return $0.accountCode < $1.accountCode }
            return $0.lineId.uuidString < $1.lineId.uuidString
        }

        if let counterpartyFilter {
            enrichedLines = enrichedLines.filter { line in
                let counterparty = line.counterparty ?? ""
                return counterpartyFilter.isEmpty ? counterparty.isEmpty : counterparty == counterpartyFilter
            }
        }

        var runningBalances: [String: Int] = [:]
        return enrichedLines.map { line in
            let account = accountMap[line.accountId]
            let isDebitNormal = account?.normalBalance == .debit
            let balanceKey: String
            switch type {
            case .accountsReceivableBook, .accountsPayableBook:
                balanceKey = line.counterparty ?? ""
            case .cashBook, .expenseBook:
                balanceKey = line.accountId
            }

            let previousBalance = runningBalances[balanceKey, default: 0]
            let newBalance = isDebitNormal
                ? previousBalance + line.debit - line.credit
                : previousBalance + line.credit - line.debit
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

    private func canonicalCounterpartyIds(
        businessId: UUID?,
        requestedFiscalYear: Int?
    ) -> [UUID: UUID] {
        guard let businessId else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues: support.fetchCanonicalJournalEntries(
                businessId: businessId,
                taxYear: requestedFiscalYear
            ).compactMap { journal in
                guard let counterpartyId = journal.lines.compactMap(\.counterpartyId).first else {
                    return nil
                }
                return (journal.id, counterpartyId)
            }
        )
    }

    private func subLedgerAccountIds(for type: SubLedgerType, accounts: [PPAccount]) -> [String] {
        switch type {
        case .cashBook:
            return [AccountingConstants.cashAccountId]
        case .accountsReceivableBook:
            return [AccountingConstants.accountsReceivableAccountId]
        case .accountsPayableBook:
            return [AccountingConstants.accountsPayableAccountId]
        case .expenseBook:
            return accounts
                .filter {
                    $0.isActive
                        && $0.accountType == .expense
                        && !expenseBookExcludedAccountIds.contains($0.id)
                }
                .map(\.id)
        }
    }

    private var expenseBookExcludedAccountIds: Set<String> {
        [
            AccountingConstants.purchasesAccountId,
            AccountingConstants.openingInventoryAccountId,
            AccountingConstants.cogsAccountId,
        ]
    }
}

@MainActor
struct MonthlySummaryRowReadModelQuery {
    private let support: AccountingReadSupport
    private let projectedJournalQuery: ProjectedJournalReadModelQuery

    init(modelContext: ModelContext) {
        let support = AccountingReadSupport(modelContext: modelContext)
        self.init(support: support)
    }

    init(support: AccountingReadSupport) {
        self.support = support
        self.projectedJournalQuery = ProjectedJournalReadModelQuery(support: support)
    }

    func rows(year: Int) -> [MonthlySummaryRow] {
        let start = startOfYear(year)
        let end = endOfYear(year)
        let projected = projectedJournalQuery.snapshot(fiscalYear: year)
        let postedEntryIds = Set(projected.entries.filter(\.isPosted).map(\.id))
        let entryMap = Dictionary(uniqueKeysWithValues: projected.entries.map { ($0.id, $0) })
        let linesByEntry = Dictionary(grouping: projected.lines) { $0.entryId }
        let calendar = Calendar.current

        var monthlyTotals: [String: [(debit: Int, credit: Int)]] = [:]
        var lineContexts: [AccountingMonthlyJournalLineContext] = []

        for journalLine in projected.lines {
            guard postedEntryIds.contains(journalLine.entryId),
                  let entry = entryMap[journalLine.entryId],
                  entry.date >= start,
                  entry.date <= end
            else {
                continue
            }

            let month = calendar.component(.month, from: entry.date)
            let siblings = linesByEntry[entry.id]?.filter { $0.id != journalLine.id } ?? []
            lineContexts.append(
                AccountingMonthlyJournalLineContext(
                    accountId: journalLine.accountId,
                    debit: journalLine.debit,
                    credit: journalLine.credit,
                    month: month,
                    counterAccountIds: siblings.map(\.accountId)
                )
            )

            let index = month - 1
            guard (0..<12).contains(index) else { continue }
            if monthlyTotals[journalLine.accountId] == nil {
                monthlyTotals[journalLine.accountId] = Array(repeating: (0, 0), count: 12)
            }
            monthlyTotals[journalLine.accountId]?[index].debit += journalLine.debit
            monthlyTotals[journalLine.accountId]?[index].credit += journalLine.credit
        }

        var rows: [MonthlySummaryRow] = []
        let salesLines = lineContexts.filter { $0.accountId == AccountingConstants.salesAccountId }
        let cashSales = aggregateMonthly(salesLines, counter: AccountingConstants.cashAccountId, useCredit: true)
        let creditSales = aggregateMonthly(
            salesLines,
            counter: AccountingConstants.accountsReceivableAccountId,
            useCredit: true
        )
        let otherSalesLines = salesLines.filter {
            !$0.counterAccountIds.contains(AccountingConstants.cashAccountId)
                && !$0.counterAccountIds.contains(AccountingConstants.accountsReceivableAccountId)
        }
        let otherSales = monthlySum(otherSalesLines, useCredit: true)
        let totalSales = addMonthlyArrays(cashSales, addMonthlyArrays(creditSales, otherSales))

        rows.append(makeMonthlySummaryRow(id: "sales-cash", label: "  現金売上", amounts: cashSales))
        rows.append(makeMonthlySummaryRow(id: "sales-credit", label: "  掛売上", amounts: creditSales))
        if otherSales.contains(where: { $0 > 0 }) {
            rows.append(makeMonthlySummaryRow(id: "sales-other", label: "  その他売上", amounts: otherSales))
        }
        rows.append(makeMonthlySummaryRow(id: "sales-total", label: "売上（収入）金額 計", amounts: totalSales, isSubtotal: true))

        let otherIncome = extractCredit(monthlyTotals[AccountingConstants.otherIncomeAccountId])
        rows.append(makeMonthlySummaryRow(id: "other-income", label: "雑収入", amounts: otherIncome))

        let purchaseLines = lineContexts.filter { $0.accountId == AccountingConstants.purchasesAccountId }
        let cashPurchases = aggregateMonthly(purchaseLines, counter: AccountingConstants.cashAccountId, useCredit: false)
        let creditPurchases = aggregateMonthly(
            purchaseLines,
            counter: AccountingConstants.accountsPayableAccountId,
            useCredit: false
        )
        let totalPurchases = addMonthlyArrays(cashPurchases, creditPurchases)

        rows.append(makeMonthlySummaryRow(id: "purchases-cash", label: "  現金仕入", amounts: cashPurchases))
        rows.append(makeMonthlySummaryRow(id: "purchases-credit", label: "  掛仕入", amounts: creditPurchases))
        rows.append(makeMonthlySummaryRow(id: "purchases-total", label: "仕入金額 計", amounts: totalPurchases, isSubtotal: true))

        let skippedAccountIds: Set<String> = [
            AccountingConstants.purchasesAccountId,
            AccountingConstants.openingInventoryAccountId,
            AccountingConstants.closingInventoryAccountId,
            AccountingConstants.cogsAccountId,
        ]
        let expenseAccounts = support.fetchAccounts()
            .filter { $0.isActive && $0.accountType == .expense && !skippedAccountIds.contains($0.id) }
            .sorted { $0.displayOrder < $1.displayOrder }

        var expenseTotal = Array(repeating: 0, count: 12)
        for account in expenseAccounts {
            let amounts = extractDebit(monthlyTotals[account.id])
            if amounts.contains(where: { $0 > 0 }) {
                rows.append(makeMonthlySummaryRow(id: "expense-\(account.id)", label: "  \(account.name)", amounts: amounts))
                expenseTotal = addMonthlyArrays(expenseTotal, amounts)
            }
        }
        rows.append(makeMonthlySummaryRow(id: "expense-total", label: "経費 計", amounts: expenseTotal, isSubtotal: true))
        return rows
    }
}

private struct AccountingMonthlyJournalLineContext {
    let accountId: String
    let debit: Int
    let credit: Int
    let month: Int
    let counterAccountIds: [String]
}

private func makeMonthlySummaryRow(
    id: String,
    label: String,
    amounts: [Int],
    isSubtotal: Bool = false
) -> MonthlySummaryRow {
    MonthlySummaryRow(
        id: id,
        label: label,
        isSubtotal: isSubtotal,
        amounts: amounts,
        total: amounts.reduce(0, +)
    )
}

private func extractCredit(_ totals: [(debit: Int, credit: Int)]?) -> [Int] {
    totals?.map(\.credit) ?? Array(repeating: 0, count: 12)
}

private func extractDebit(_ totals: [(debit: Int, credit: Int)]?) -> [Int] {
    totals?.map(\.debit) ?? Array(repeating: 0, count: 12)
}

private func aggregateMonthly(
    _ lines: [AccountingMonthlyJournalLineContext],
    counter: String,
    useCredit: Bool
) -> [Int] {
    monthlySum(lines.filter { $0.counterAccountIds.contains(counter) }, useCredit: useCredit)
}

private func monthlySum(
    _ lines: [AccountingMonthlyJournalLineContext],
    useCredit: Bool
) -> [Int] {
    var result = Array(repeating: 0, count: 12)
    for line in lines where (1...12).contains(line.month) {
        result[line.month - 1] += useCredit ? line.credit : line.debit
    }
    return result
}

private func addMonthlyArrays(_ lhs: [Int], _ rhs: [Int]) -> [Int] {
    (0..<12).map { index in
        (lhs.indices.contains(index) ? lhs[index] : 0)
            + (rhs.indices.contains(index) ? rhs[index] : 0)
    }
}
