import Foundation

@MainActor
enum AccountingReportService {
    private struct LegacyAccountTotals {
        let activeAccounts: [PPAccount]
        let debitByAccount: [String: Int]
        let creditByAccount: [String: Int]
    }

    private struct CanonicalAccountTotals {
        let activeAccounts: [CanonicalAccount]
        let debitByAccount: [UUID: Decimal]
        let creditByAccount: [UUID: Decimal]
    }

    // MARK: - Trial Balance

    static func generateTrialBalance(
        fiscalYear: Int,
        accounts: [PPAccount],
        journalEntries: [PPJournalEntry],
        journalLines: [PPJournalLine],
        startMonth: Int = 1
    ) -> TrialBalanceReport {
        let totals = accumulateLegacyAccountTotals(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journalEntries: journalEntries,
            journalLines: journalLines,
            startMonth: startMonth
        )

        let rows = totals.activeAccounts.compactMap { account -> TrialBalanceRow? in
            let debitTotal = totals.debitByAccount[account.id] ?? 0
            let creditTotal = totals.creditByAccount[account.id] ?? 0
            guard debitTotal > 0 || creditTotal > 0 else { return nil }

            let balance = account.normalBalance == .debit
                ? debitTotal - creditTotal
                : creditTotal - debitTotal

            return TrialBalanceRow(
                id: account.id,
                code: account.code,
                name: account.name,
                accountType: account.accountType,
                debit: debitTotal,
                credit: creditTotal,
                balance: balance
            )
        }
        .sorted { $0.code < $1.code }

        return TrialBalanceReport(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            rows: rows
        )
    }

    // MARK: - Profit & Loss

    static func generateProfitLoss(
        fiscalYear: Int,
        accounts: [PPAccount],
        journalEntries: [PPJournalEntry],
        journalLines: [PPJournalLine],
        startMonth: Int = 1
    ) -> ProfitLossReport {
        let totals = accumulateLegacyAccountTotals(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journalEntries: journalEntries,
            journalLines: journalLines,
            startMonth: startMonth
        )

        let revenueItems = totals.activeAccounts
            .filter { $0.accountType == .revenue }
            .compactMap { account -> ProfitLossItem? in
                let amount = (totals.creditByAccount[account.id] ?? 0) - (totals.debitByAccount[account.id] ?? 0)
                guard amount != 0 else { return nil }
                return ProfitLossItem(
                    id: account.id,
                    code: account.code,
                    name: account.name,
                    amount: amount,
                    deductibleAmount: amount
                )
            }
            .sorted { $0.code < $1.code }

        let expenseItems = totals.activeAccounts
            .filter { $0.accountType == .expense }
            .compactMap { account -> ProfitLossItem? in
                let amount = (totals.debitByAccount[account.id] ?? 0) - (totals.creditByAccount[account.id] ?? 0)
                guard amount != 0 else { return nil }
                return ProfitLossItem(
                    id: account.id,
                    code: account.code,
                    name: account.name,
                    amount: amount,
                    deductibleAmount: amount
                )
            }
            .sorted { $0.code < $1.code }

        return ProfitLossReport(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            revenueItems: revenueItems,
            expenseItems: expenseItems
        )
    }

    // MARK: - Balance Sheet

    static func generateBalanceSheet(
        fiscalYear: Int,
        accounts: [PPAccount],
        journalEntries: [PPJournalEntry],
        journalLines: [PPJournalLine],
        startMonth: Int = 1
    ) -> BalanceSheetReport {
        let totals = accumulateLegacyAccountTotals(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journalEntries: journalEntries,
            journalLines: journalLines,
            startMonth: startMonth
        )

        func buildItems(type: AccountType) -> [BalanceSheetItem] {
            totals.activeAccounts
                .filter { $0.accountType == type }
                .compactMap { account -> BalanceSheetItem? in
                    let debit = totals.debitByAccount[account.id] ?? 0
                    let credit = totals.creditByAccount[account.id] ?? 0
                    guard debit > 0 || credit > 0 else { return nil }

                    let balance: Int
                    switch type {
                    case .asset:
                        balance = debit - credit
                    case .liability:
                        balance = credit - debit
                    case .equity:
                        balance = account.normalBalance == .debit
                            ? -(debit - credit)
                            : credit - debit
                    case .revenue, .expense:
                        balance = 0
                    }
                    guard balance != 0 else { return nil }

                    return BalanceSheetItem(
                        id: account.id,
                        code: account.code,
                        name: account.name,
                        balance: balance
                    )
                }
                .sorted { $0.code < $1.code }
        }

        let netIncome = totals.activeAccounts.reduce(into: 0) { result, account in
            switch account.accountType {
            case .revenue:
                result += (totals.creditByAccount[account.id] ?? 0) - (totals.debitByAccount[account.id] ?? 0)
            case .expense:
                result -= (totals.debitByAccount[account.id] ?? 0) - (totals.creditByAccount[account.id] ?? 0)
            case .asset, .liability, .equity:
                break
            }
        }

        var equityItems = buildItems(type: .equity)
        if netIncome != 0 {
            equityItems.append(BalanceSheetItem(
                id: "retained-earnings",
                code: "399",
                name: "当期純利益",
                balance: netIncome
            ))
        }

        return BalanceSheetReport(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            assetItems: buildItems(type: .asset),
            liabilityItems: buildItems(type: .liability),
            equityItems: equityItems
        )
    }

    // MARK: - Canonical Trial Balance

    static func generateTrialBalance(
        fiscalYear: Int,
        accounts: [CanonicalAccount],
        journals: [CanonicalJournalEntry],
        startMonth: Int = 1
    ) -> CanonicalTrialBalanceReport {
        let totals = accumulateCanonicalAccountTotals(
            accounts: accounts,
            journals: journals,
            dateRange: fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        )

        let rows = totals.activeAccounts.compactMap { account -> CanonicalTrialBalanceRow? in
            let debit = totals.debitByAccount[account.id] ?? 0
            let credit = totals.creditByAccount[account.id] ?? 0
            guard debit > 0 || credit > 0 else { return nil }

            let balance: Decimal = account.normalBalance == .debit
                ? debit - credit
                : credit - debit

            return CanonicalTrialBalanceRow(
                id: account.id,
                code: account.code,
                name: account.name,
                accountType: account.accountType,
                normalBalance: account.normalBalance,
                debit: debit,
                credit: credit,
                balance: balance
            )
        }
        .sorted { $0.code < $1.code }

        return CanonicalTrialBalanceReport(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            rows: rows
        )
    }

    // MARK: - Canonical Profit & Loss

    static func generateProfitLoss(
        fiscalYear: Int,
        accounts: [CanonicalAccount],
        journals: [CanonicalJournalEntry],
        dateRange: ClosedRange<Date>? = nil,
        startMonth: Int = 1
    ) -> CanonicalProfitLossReport {
        let totals = accumulateCanonicalAccountTotals(
            accounts: accounts,
            journals: journals,
            dateRange: dateRange.map { ($0.lowerBound, $0.upperBound) }
                ?? fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        )
        let breakdown = canonicalProfitLossBreakdown(from: totals)

        return CanonicalProfitLossReport(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            revenueItems: breakdown.revenueItems,
            expenseItems: breakdown.expenseItems
        )
    }

    // MARK: - Canonical Balance Sheet

    static func generateBalanceSheet(
        fiscalYear: Int,
        accounts: [CanonicalAccount],
        journals: [CanonicalJournalEntry],
        asOf: Date? = nil,
        startMonth: Int = 1
    ) -> CanonicalBalanceSheetReport {
        let (startDate, fiscalEnd) = fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        let totals = accumulateCanonicalAccountTotals(
            accounts: accounts,
            journals: journals,
            dateRange: (startDate, asOf ?? fiscalEnd)
        )
        let profitLossBreakdown = canonicalProfitLossBreakdown(from: totals)

        func buildItems(type: CanonicalAccountType) -> [CanonicalBalanceSheetItem] {
            totals.activeAccounts
                .filter { $0.accountType == type }
                .compactMap { account -> CanonicalBalanceSheetItem? in
                    let debit = totals.debitByAccount[account.id] ?? 0
                    let credit = totals.creditByAccount[account.id] ?? 0
                    guard debit > 0 || credit > 0 else { return nil }

                    let balance: Decimal
                    switch type {
                    case .asset:
                        balance = debit - credit
                    case .liability:
                        balance = credit - debit
                    case .equity:
                        balance = account.normalBalance == .debit
                            ? -(debit - credit)
                            : credit - debit
                    case .revenue, .expense:
                        balance = 0
                    }
                    guard balance != 0 else { return nil }

                    return CanonicalBalanceSheetItem(
                        id: account.id,
                        code: account.code,
                        name: account.name,
                        balance: balance
                    )
                }
                .sorted { $0.code < $1.code }
        }

        var equityItems = buildItems(type: .equity)
        if profitLossBreakdown.netIncome != 0 {
            equityItems.append(CanonicalBalanceSheetItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000399")!,
                code: "399",
                name: "当期純利益",
                balance: profitLossBreakdown.netIncome
            ))
        }

        return CanonicalBalanceSheetReport(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            assetItems: buildItems(type: .asset),
            liabilityItems: buildItems(type: .liability),
            equityItems: equityItems
        )
    }

    // MARK: - Helpers

    private static func fiscalYearRange(year: Int, startMonth: Int) -> (start: Date, end: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1))!
        let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start)!
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end)!
        return (start, endOfDay)
    }

    private static func postedEntryIdsInRange(
        entries: [PPJournalEntry],
        start: Date,
        end: Date,
        excludeTypes: Set<JournalEntryType> = []
    ) -> Set<UUID> {
        Set(
            entries
                .filter {
                    $0.isPosted && $0.date >= start && $0.date <= end
                        && !excludeTypes.contains($0.entryType)
                }
                .map(\.id)
        )
    }

    private static func accumulateLegacyAccountTotals(
        fiscalYear: Int,
        accounts: [PPAccount],
        journalEntries: [PPJournalEntry],
        journalLines: [PPJournalLine],
        startMonth: Int
    ) -> LegacyAccountTotals {
        let (startDate, endDate) = fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        let postedEntryIds = postedEntryIdsInRange(
            entries: journalEntries,
            start: startDate,
            end: endDate,
            excludeTypes: [.closing]
        )

        var debitByAccount: [String: Int] = [:]
        var creditByAccount: [String: Int] = [:]
        for line in journalLines where postedEntryIds.contains(line.entryId) {
            debitByAccount[line.accountId, default: 0] += line.debit
            creditByAccount[line.accountId, default: 0] += line.credit
        }

        return LegacyAccountTotals(
            activeAccounts: accounts.filter(\.isActive),
            debitByAccount: debitByAccount,
            creditByAccount: creditByAccount
        )
    }

    private static func accumulateCanonicalAccountTotals(
        accounts: [CanonicalAccount],
        journals: [CanonicalJournalEntry],
        dateRange: (start: Date, end: Date)
    ) -> CanonicalAccountTotals {
        var debitByAccount: [UUID: Decimal] = [:]
        var creditByAccount: [UUID: Decimal] = [:]

        for journal in journals where
            journal.approvedAt != nil &&
            journal.journalDate >= dateRange.start &&
            journal.journalDate <= dateRange.end &&
            journal.entryType != .closing
        {
            for line in journal.lines {
                debitByAccount[line.accountId, default: 0] += line.debitAmount
                creditByAccount[line.accountId, default: 0] += line.creditAmount
            }
        }

        return CanonicalAccountTotals(
            activeAccounts: accounts.filter { $0.archivedAt == nil },
            debitByAccount: debitByAccount,
            creditByAccount: creditByAccount
        )
    }

    private static func canonicalProfitLossBreakdown(
        from totals: CanonicalAccountTotals
    ) -> (revenueItems: [CanonicalProfitLossItem], expenseItems: [CanonicalProfitLossItem], netIncome: Decimal) {
        let revenueItems = totals.activeAccounts
            .filter { $0.accountType == .revenue }
            .compactMap { account -> CanonicalProfitLossItem? in
                let amount = (totals.creditByAccount[account.id] ?? 0) - (totals.debitByAccount[account.id] ?? 0)
                guard amount != 0 else { return nil }
                return CanonicalProfitLossItem(id: account.id, code: account.code, name: account.name, amount: amount)
            }
            .sorted { $0.code < $1.code }

        let expenseItems = totals.activeAccounts
            .filter { $0.accountType == .expense }
            .compactMap { account -> CanonicalProfitLossItem? in
                let amount = (totals.debitByAccount[account.id] ?? 0) - (totals.creditByAccount[account.id] ?? 0)
                guard amount != 0 else { return nil }
                return CanonicalProfitLossItem(id: account.id, code: account.code, name: account.name, amount: amount)
            }
            .sorted { $0.code < $1.code }

        let netIncome = revenueItems.reduce(Decimal.zero) { $0 + $1.amount }
            - expenseItems.reduce(Decimal.zero) { $0 + $1.amount }

        return (revenueItems: revenueItems, expenseItems: expenseItems, netIncome: netIncome)
    }
}
