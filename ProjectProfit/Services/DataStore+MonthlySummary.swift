import Foundation

// MARK: - Monthly Summary Types

/// 月別総括集計表の1行
struct MonthlySummaryRow: Identifiable {
    let id: String
    let label: String
    let isSubtotal: Bool
    let amounts: [Int]  // 12要素 (1月〜12月)
    let total: Int
}

/// 仕訳行コンテキスト（相手勘定付き）
private struct JournalLineContext {
    let accountId: String
    let debit: Int
    let credit: Int
    let month: Int
    let counterAccountIds: [String]
}

// MARK: - DataStore Monthly Summary Extension

extension DataStore {

    /// NTA「帳簿の記帳のしかた」p.18-19 準拠: 月別総括集計表を生成
    func getMonthlySummary(year: Int) -> [MonthlySummaryRow] {
        let start = startOfYear(year)
        let end = endOfYear(year)
        let projected = projectedCanonicalJournals(fiscalYear: year)
        let postedEntryIds = Set(projected.entries.filter(\.isPosted).map(\.id))
        let entryMap = Dictionary(uniqueKeysWithValues: projected.entries.map { ($0.id, $0) })
        let linesByEntry = Dictionary(grouping: projected.lines) { $0.entryId }
        let calendar = Calendar.current

        // 月別・科目別集計 (key: accountId, value: 12要素タプル配列)
        var monthlyTotals: [String: [(debit: Int, credit: Int)]] = [:]
        var lineContexts: [JournalLineContext] = []

        for journalLine in projected.lines {
            guard postedEntryIds.contains(journalLine.entryId),
                  let entry = entryMap[journalLine.entryId] else { continue }
            guard entry.date >= start, entry.date <= end else { continue }

            let month = calendar.component(.month, from: entry.date)
            let siblings = linesByEntry[entry.id]?.filter { $0.id != journalLine.id } ?? []

            lineContexts.append(JournalLineContext(
                accountId: journalLine.accountId,
                debit: journalLine.debit,
                credit: journalLine.credit,
                month: month,
                counterAccountIds: siblings.map(\.accountId)
            ))

            let idx = month - 1
            guard (0..<12).contains(idx) else { continue }
            if monthlyTotals[journalLine.accountId] == nil {
                monthlyTotals[journalLine.accountId] = Array(repeating: (0, 0), count: 12)
            }
            monthlyTotals[journalLine.accountId]![idx].debit += journalLine.debit
            monthlyTotals[journalLine.accountId]![idx].credit += journalLine.credit
        }

        var rows: [MonthlySummaryRow] = []

        // ── 売上収入金額 ──
        let salesLines = lineContexts.filter { $0.accountId == AccountingConstants.salesAccountId }
        let cashSales = aggregateMonthly(salesLines, counter: AccountingConstants.cashAccountId, useCredit: true)
        let creditSales = aggregateMonthly(salesLines, counter: AccountingConstants.accountsReceivableAccountId, useCredit: true)
        let otherSalesLines = salesLines.filter {
            !$0.counterAccountIds.contains(AccountingConstants.cashAccountId)
                && !$0.counterAccountIds.contains(AccountingConstants.accountsReceivableAccountId)
        }
        let otherSales = monthlySum(otherSalesLines, useCredit: true)
        let totalSales = addArrays(cashSales, addArrays(creditSales, otherSales))

        rows.append(makeRow(id: "sales-cash", label: "  現金売上", amounts: cashSales))
        rows.append(makeRow(id: "sales-credit", label: "  掛売上", amounts: creditSales))
        if otherSales.contains(where: { $0 > 0 }) {
            rows.append(makeRow(id: "sales-other", label: "  その他売上", amounts: otherSales))
        }
        rows.append(makeRow(id: "sales-total", label: "売上（収入）金額 計", amounts: totalSales, isSubtotal: true))

        // 雑収入
        let otherIncome = extractCredit(monthlyTotals[AccountingConstants.otherIncomeAccountId])
        rows.append(makeRow(id: "other-income", label: "雑収入", amounts: otherIncome))

        // ── 仕入金額 ──
        let purchaseLines = lineContexts.filter { $0.accountId == AccountingConstants.purchasesAccountId }
        let cashPurchases = aggregateMonthly(purchaseLines, counter: AccountingConstants.cashAccountId, useCredit: false)
        let creditPurchases = aggregateMonthly(purchaseLines, counter: AccountingConstants.accountsPayableAccountId, useCredit: false)
        let totalPurchases = addArrays(cashPurchases, creditPurchases)

        rows.append(makeRow(id: "purchases-cash", label: "  現金仕入", amounts: cashPurchases))
        rows.append(makeRow(id: "purchases-credit", label: "  掛仕入", amounts: creditPurchases))
        rows.append(makeRow(id: "purchases-total", label: "仕入金額 計", amounts: totalPurchases, isSubtotal: true))

        // ── 経費 ──
        let skipIds: Set<String> = [
            AccountingConstants.purchasesAccountId,
            AccountingConstants.openingInventoryAccountId,
            AccountingConstants.closingInventoryAccountId,
            AccountingConstants.cogsAccountId,
        ]
        let expenseAccounts = accounts
            .filter { $0.isActive && $0.accountType == .expense && !skipIds.contains($0.id) }
            .sorted { $0.displayOrder < $1.displayOrder }

        var expenseTotal = Array(repeating: 0, count: 12)
        for account in expenseAccounts {
            let amounts = extractDebit(monthlyTotals[account.id])
            if amounts.contains(where: { $0 > 0 }) {
                rows.append(makeRow(id: "expense-\(account.id)", label: "  \(account.name)", amounts: amounts))
                expenseTotal = addArrays(expenseTotal, amounts)
            }
        }
        rows.append(makeRow(id: "expense-total", label: "経費 計", amounts: expenseTotal, isSubtotal: true))

        return rows
    }

    // MARK: - Private Helpers

    private func makeRow(id: String, label: String, amounts: [Int], isSubtotal: Bool = false) -> MonthlySummaryRow {
        MonthlySummaryRow(id: id, label: label, isSubtotal: isSubtotal, amounts: amounts, total: amounts.reduce(0, +))
    }

    private func extractCredit(_ totals: [(debit: Int, credit: Int)]?) -> [Int] {
        totals?.map(\.credit) ?? Array(repeating: 0, count: 12)
    }

    private func extractDebit(_ totals: [(debit: Int, credit: Int)]?) -> [Int] {
        totals?.map(\.debit) ?? Array(repeating: 0, count: 12)
    }

    /// 特定の相手勘定を持つ仕訳行を月別集計
    private func aggregateMonthly(_ lines: [JournalLineContext], counter: String, useCredit: Bool) -> [Int] {
        let filtered = lines.filter { $0.counterAccountIds.contains(counter) }
        return monthlySum(filtered, useCredit: useCredit)
    }

    /// 仕訳行コンテキスト配列を月別集計
    private func monthlySum(_ lines: [JournalLineContext], useCredit: Bool) -> [Int] {
        var result = Array(repeating: 0, count: 12)
        for line in lines {
            guard line.month >= 1, line.month <= 12 else { continue }
            result[line.month - 1] += useCredit ? line.credit : line.debit
        }
        return result
    }
}

// MARK: - Array Helper

private func addArrays(_ a: [Int], _ b: [Int]) -> [Int] {
    (0..<12).map { (a.indices.contains($0) ? a[$0] : 0) + (b.indices.contains($0) ? b[$0] : 0) }
}
