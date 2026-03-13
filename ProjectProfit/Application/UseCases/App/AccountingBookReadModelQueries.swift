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

    init(modelContext: ModelContext) {
        self.init(support: AccountingReadSupport(modelContext: modelContext))
    }

    init(support: AccountingReadSupport) {
        self.support = support
    }

    func accountBalance(accountId: String, upTo date: Date? = nil) -> GeneralLedgerBalance {
        let entries = entries(accountId: accountId, startDate: nil, endDate: date)
        return GeneralLedgerBalance(
            debit: entries.reduce(0) { $0 + $1.debit },
            credit: entries.reduce(0) { $0 + $1.credit },
            balance: entries.last?.runningBalance ?? 0
        )
    }

    func entries(
        accountId: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [AccountingLedgerEntry] {
        let requestedFiscalYear = requestedFiscalYear(startDate: startDate, endDate: endDate)
        let context = support.canonicalReadContext(fiscalYear: requestedFiscalYear)
        guard let canonicalAccount = context.canonicalAccountsByLegacyId[accountId] else {
            return []
        }

        return CanonicalBookService.generateGeneralLedger(
            journals: context.journals,
            accountId: canonicalAccount.id,
            accounts: context.accounts,
            counterparties: context.counterpartiesById,
            dateRange: effectiveDateRange(
                fiscalYear: requestedFiscalYear,
                startDate: startDate,
                endDate: endDate
            )
        ).map { entry in
            AccountingLedgerEntry(
                id: entry.id,
                date: entry.journalDate,
                memo: entry.description,
                entryType: ledgerEntryType(for: entry.entryType),
                debit: decimalInt(entry.debitAmount),
                credit: decimalInt(entry.creditAmount),
                runningBalance: decimalInt(entry.runningBalance),
                counterparty: entry.counterpartyName,
                taxCategory: TaxCode.resolve(id: entry.taxCodeId)?.legacyCategory
            )
        }
    }
}

@MainActor
struct SubLedgerReadModelQuery {
    private let support: AccountingReadSupport

    init(modelContext: ModelContext) {
        self.init(support: AccountingReadSupport(modelContext: modelContext))
    }

    init(support: AccountingReadSupport) {
        self.support = support
    }

    func entries(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil,
        accountFilter: String? = nil,
        counterpartyFilter: String? = nil
    ) -> [SubLedgerEntry] {
        let requestedFiscalYear = requestedFiscalYear(startDate: startDate, endDate: endDate)
        let context = support.canonicalReadContext(fiscalYear: requestedFiscalYear)

        return CanonicalBookService.generateSubsidiaryLedger(
            journals: context.journals,
            type: canonicalSubLedgerType(for: type),
            accounts: context.accounts,
            counterparties: context.counterpartiesById,
            dateRange: effectiveDateRange(
                fiscalYear: requestedFiscalYear,
                startDate: startDate,
                endDate: endDate
            )
        )
        .filter { entry in
            if let accountFilter, context.legacyAccountId(for: entry.accountId) != accountFilter {
                return false
            }
            if let counterpartyFilter {
                let counterparty = entry.counterpartyName ?? ""
                return counterpartyFilter.isEmpty ? counterparty.isEmpty : counterparty == counterpartyFilter
            }
            return true
        }
        .map { entry in
            let legacyAccount = context.legacyAccount(for: entry.accountId)
            return SubLedgerEntry(
                id: entry.id,
                date: entry.journalDate,
                accountId: context.legacyAccountId(for: entry.accountId),
                accountCode: legacyAccount?.code ?? entry.accountCode,
                accountName: legacyAccount?.name ?? entry.accountName,
                memo: entry.description,
                debit: decimalInt(entry.debitAmount),
                credit: decimalInt(entry.creditAmount),
                runningBalance: decimalInt(entry.runningBalance),
                counterAccountId: entry.counterAccountId.map { context.legacyAccountId(for: $0) },
                counterparty: entry.counterpartyName,
                taxCategory: TaxCode.resolve(id: entry.taxCodeId)?.legacyCategory
            )
        }
    }
}

private func requestedFiscalYear(startDate: Date?, endDate: Date?) -> Int? {
    if let startDate {
        return fiscalYear(for: startDate, startMonth: FiscalYearSettings.startMonth)
    }
    if let endDate {
        return fiscalYear(for: endDate, startMonth: FiscalYearSettings.startMonth)
    }
    return nil
}

private func effectiveDateRange(
    fiscalYear: Int?,
    startDate: Date?,
    endDate: Date?
) -> ClosedRange<Date>? {
    guard startDate != nil || endDate != nil || fiscalYear != nil else {
        return nil
    }

    let bounds = fiscalYear.map {
        fiscalYearDateBounds(year: $0, startMonth: FiscalYearSettings.startMonth)
    }
    let lowerBound = startDate ?? bounds?.lowerBound ?? .distantPast
    let upperBound = endDate ?? bounds?.upperBound ?? .distantFuture
    return lowerBound...upperBound
}

private func fiscalYearDateBounds(year: Int, startMonth: Int) -> ClosedRange<Date> {
    let calendar = Calendar(identifier: .gregorian)
    let startYear = startMonth == 1 ? year : year - 1
    let startDate = calendar.date(from: DateComponents(year: startYear, month: startMonth, day: 1)) ?? .distantPast
    let endMonth = startMonth == 1 ? 12 : startMonth - 1
    let endYear = startMonth == 1 ? year : year
    let monthStart = calendar.date(from: DateComponents(year: endYear, month: endMonth, day: 1)) ?? .distantFuture
    let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? .distantFuture
    return startDate...endDate
}

private func canonicalSubLedgerType(for type: SubLedgerType) -> CanonicalSubLedgerType {
    switch type {
    case .cashBook:
        return .cash
    case .accountsReceivableBook:
        return .accountsReceivable
    case .accountsPayableBook:
        return .accountsPayable
    case .expenseBook:
        return .expense
    }
}

private func ledgerEntryType(for entryType: CanonicalJournalEntryType) -> JournalEntryType {
    switch entryType {
    case .normal:
        return .auto
    case .opening:
        return .opening
    case .closing:
        return .closing
    case .depreciation, .inventoryAdjustment, .recurring, .taxAdjustment, .reversal:
        return .auto
    }
}

private func decimalInt(_ value: Decimal) -> Int {
    NSDecimalNumber(decimal: value).intValue
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
