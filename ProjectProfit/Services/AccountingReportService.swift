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
            entries: journalEntries, start: startDate, end: endDate
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
            entries: journalEntries, start: startDate, end: endDate
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
            entries: journalEntries, start: startDate, end: endDate
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
        end: Date
    ) -> Set<UUID> {
        Set(
            entries
                .filter { $0.isPosted && $0.date >= start && $0.date <= end }
                .map(\.id)
        )
    }
}
