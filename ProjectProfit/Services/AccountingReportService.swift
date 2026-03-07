import Foundation

@MainActor
enum AccountingReportService {

    // MARK: - Trial Balance

    static func generateTrialBalance(
        fiscalYear: Int,
        accounts: [PPAccount],
        journalEntries: [PPJournalEntry],
        journalLines: [PPJournalLine],
        startMonth: Int = 1
    ) -> TrialBalanceReport {
        let (startDate, endDate) = fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        let postedEntryIds = postedEntryIdsInRange(
            entries: journalEntries, start: startDate, end: endDate,
            excludeTypes: [.closing]
        )

        let rows = accounts.filter(\.isActive).compactMap { account -> TrialBalanceRow? in
            let lines = journalLines.filter { $0.accountId == account.id && postedEntryIds.contains($0.entryId) }
            let debitTotal = lines.reduce(0) { $0 + $1.debit }
            let creditTotal = lines.reduce(0) { $0 + $1.credit }
            guard debitTotal > 0 || creditTotal > 0 else { return nil }

            let balance: Int
            if account.normalBalance == .debit {
                balance = debitTotal - creditTotal
            } else {
                balance = creditTotal - debitTotal
            }

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
        let (startDate, endDate) = fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        let postedEntryIds = postedEntryIdsInRange(
            entries: journalEntries, start: startDate, end: endDate,
            excludeTypes: [.closing]
        )

        let revenueAccounts = accounts.filter { $0.accountType == .revenue && $0.isActive }
        let expenseAccounts = accounts.filter { $0.accountType == .expense && $0.isActive }

        let revenueItems = revenueAccounts.compactMap { account -> ProfitLossItem? in
            let lines = journalLines.filter { $0.accountId == account.id && postedEntryIds.contains($0.entryId) }
            let amount = lines.reduce(0) { $0 + $1.credit } - lines.reduce(0) { $0 + $1.debit }
            guard amount != 0 else { return nil }
            return ProfitLossItem(
                id: account.id, code: account.code, name: account.name,
                amount: amount, deductibleAmount: amount
            )
        }
        .sorted { $0.code < $1.code }

        let expenseItems = expenseAccounts.compactMap { account -> ProfitLossItem? in
            let lines = journalLines.filter { $0.accountId == account.id && postedEntryIds.contains($0.entryId) }
            let amount = lines.reduce(0) { $0 + $1.debit } - lines.reduce(0) { $0 + $1.credit }
            guard amount != 0 else { return nil }
            return ProfitLossItem(
                id: account.id, code: account.code, name: account.name,
                amount: amount, deductibleAmount: amount
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
        let (startDate, endDate) = fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        let postedEntryIds = postedEntryIdsInRange(
            entries: journalEntries, start: startDate, end: endDate,
            excludeTypes: [.closing]
        )

        func buildItems(type: AccountType) -> [BalanceSheetItem] {
            accounts
                .filter { $0.accountType == type && $0.isActive }
                .compactMap { account -> BalanceSheetItem? in
                    let lines = journalLines.filter { $0.accountId == account.id && postedEntryIds.contains($0.entryId) }
                    let debit = lines.reduce(0) { $0 + $1.debit }
                    let credit = lines.reduce(0) { $0 + $1.credit }
                    guard debit > 0 || credit > 0 else { return nil }

                    let balance: Int
                    switch type {
                    case .asset:
                        // 資産は借方正常: debit - credit
                        balance = debit - credit
                    case .liability:
                        // 負債は貸方正常: credit - debit
                        balance = credit - debit
                    case .equity:
                        // 資本: 借方正常（事業主貸等）は貸方正常から控除
                        if account.normalBalance == .debit {
                            balance = -(debit - credit)  // 控除項目として符号反転
                        } else {
                            balance = credit - debit
                        }
                    case .revenue, .expense:
                        balance = 0  // B/Sには含まれないが、安全策
                    }
                    guard balance != 0 else { return nil }
                    return BalanceSheetItem(
                        id: account.id, code: account.code, name: account.name, balance: balance
                    )
                }
                .sorted { $0.code < $1.code }
        }

        // P&L → 当期純利益を資本に加算
        let pl = generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journalEntries: journalEntries,
            journalLines: journalLines,
            startMonth: startMonth
        )

        var equityItems = buildItems(type: .equity)
        if pl.netIncome != 0 {
            equityItems.append(BalanceSheetItem(
                id: "retained-earnings",
                code: "399",
                name: "当期純利益",
                balance: pl.netIncome
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
        let (startDate, endDate) = fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        let filteredJournals = journals.filter { entry in
            entry.approvedAt != nil
                && entry.journalDate >= startDate
                && entry.journalDate <= endDate
                && entry.entryType != .closing
        }

        let activeAccounts = accounts.filter { $0.archivedAt == nil }
        let accountsById = Dictionary(uniqueKeysWithValues: activeAccounts.map { ($0.id, $0) })

        var debitByAccount: [UUID: Decimal] = [:]
        var creditByAccount: [UUID: Decimal] = [:]

        for journal in filteredJournals {
            for line in journal.lines {
                debitByAccount[line.accountId, default: 0] += line.debitAmount
                creditByAccount[line.accountId, default: 0] += line.creditAmount
            }
        }

        let rows = activeAccounts.compactMap { account -> CanonicalTrialBalanceRow? in
            let debit = debitByAccount[account.id] ?? 0
            let credit = creditByAccount[account.id] ?? 0
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
        let range: (Date, Date)
        if let dateRange {
            range = (dateRange.lowerBound, dateRange.upperBound)
        } else {
            range = fiscalYearRange(year: fiscalYear, startMonth: startMonth)
        }

        let filteredJournals = journals.filter { entry in
            entry.approvedAt != nil
                && entry.journalDate >= range.0
                && entry.journalDate <= range.1
                && entry.entryType != .closing
        }

        let activeAccounts = accounts.filter { $0.archivedAt == nil }

        var debitByAccount: [UUID: Decimal] = [:]
        var creditByAccount: [UUID: Decimal] = [:]

        for journal in filteredJournals {
            for line in journal.lines {
                debitByAccount[line.accountId, default: 0] += line.debitAmount
                creditByAccount[line.accountId, default: 0] += line.creditAmount
            }
        }

        let revenueItems = activeAccounts
            .filter { $0.accountType == .revenue }
            .compactMap { account -> CanonicalProfitLossItem? in
                let amount = (creditByAccount[account.id] ?? 0) - (debitByAccount[account.id] ?? 0)
                guard amount != 0 else { return nil }
                return CanonicalProfitLossItem(id: account.id, code: account.code, name: account.name, amount: amount)
            }
            .sorted { $0.code < $1.code }

        let expenseItems = activeAccounts
            .filter { $0.accountType == .expense }
            .compactMap { account -> CanonicalProfitLossItem? in
                let amount = (debitByAccount[account.id] ?? 0) - (creditByAccount[account.id] ?? 0)
                guard amount != 0 else { return nil }
                return CanonicalProfitLossItem(id: account.id, code: account.code, name: account.name, amount: amount)
            }
            .sorted { $0.code < $1.code }

        return CanonicalProfitLossReport(
            fiscalYear: fiscalYear,
            generatedAt: Date(),
            revenueItems: revenueItems,
            expenseItems: expenseItems
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
        let endDate = asOf ?? fiscalEnd

        let filteredJournals = journals.filter { entry in
            entry.approvedAt != nil
                && entry.journalDate >= startDate
                && entry.journalDate <= endDate
                && entry.entryType != .closing
        }

        let activeAccounts = accounts.filter { $0.archivedAt == nil }

        var debitByAccount: [UUID: Decimal] = [:]
        var creditByAccount: [UUID: Decimal] = [:]

        for journal in filteredJournals {
            for line in journal.lines {
                debitByAccount[line.accountId, default: 0] += line.debitAmount
                creditByAccount[line.accountId, default: 0] += line.creditAmount
            }
        }

        func buildItems(type: CanonicalAccountType) -> [CanonicalBalanceSheetItem] {
            activeAccounts
                .filter { $0.accountType == type }
                .compactMap { account -> CanonicalBalanceSheetItem? in
                    let debit = debitByAccount[account.id] ?? 0
                    let credit = creditByAccount[account.id] ?? 0
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
                    return CanonicalBalanceSheetItem(id: account.id, code: account.code, name: account.name, balance: balance)
                }
                .sorted { $0.code < $1.code }
        }

        let pl = generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journals: journals,
            startMonth: startMonth
        )

        var equityItems = buildItems(type: .equity)
        if pl.netIncome != 0 {
            equityItems.append(CanonicalBalanceSheetItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000399")!,
                code: "399",
                name: "当期純利益",
                balance: pl.netIncome
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
        // end を日末に設定
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
}
