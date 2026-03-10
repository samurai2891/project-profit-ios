import SwiftUI

// MARK: - TransactionGroup

struct TransactionGroup: Identifiable {
    let yearMonth: String
    let displayLabel: String
    let transactions: [PPTransaction]
    let income: Int
    let expense: Int
    let transfer: Int

    var id: String { yearMonth }
}

// MARK: - LedgerRow

struct LedgerRow: Identifiable {
    let id: UUID
    let date: Date
    let memo: String
    let categoryName: String
    let type: TransactionType
    let debit: Int
    let credit: Int
    let runningBalance: Int
    let transaction: PPTransaction
}

// MARK: - TransactionsViewModel

@MainActor
@Observable
final class TransactionsViewModel {
    let dataStore: DataStore
    var filter = TransactionFilter()
    var sort = TransactionSort()

    var selectedType: TransactionType? {
        get { filter.type }
        set { filter = TransactionFilter(
            startDate: filter.startDate,
            endDate: filter.endDate,
            projectId: filter.projectId,
            categoryId: filter.categoryId,
            type: newValue,
            searchText: filter.searchText,
            amountMin: filter.amountMin,
            amountMax: filter.amountMax,
            counterparty: filter.counterparty
        )}
    }

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    // MARK: - Computed Properties

    var filteredTransactions: [PPTransaction] {
        dataStore.getFilteredTransactions(filter: filter, sort: sort)
    }

    var groupedTransactions: [TransactionGroup] {
        let grouped = Dictionary(grouping: filteredTransactions, by: yearMonthKey)
        return grouped
            .map { createTransactionGroup(yearMonth: $0, transactions: $1) }
            .sorted { $0.yearMonth > $1.yearMonth }
    }

    var incomeTotal: Int {
        filteredTransactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + effectiveAmount(for: $1) }
    }

    var expenseTotal: Int {
        filteredTransactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + effectiveAmount(for: $1) }
    }

    var transferTotal: Int {
        filteredTransactions
            .filter { $0.type == .transfer }
            .reduce(0) { $0 + effectiveAmount(for: $1) }
    }

    var netTotal: Int {
        incomeTotal - expenseTotal
    }

    var isTransferFilter: Bool {
        selectedType == .transfer
    }

    var canMutateLegacyTransactions: Bool {
        dataStore.isLegacyTransactionEditingEnabled
    }

    var hasActiveFilter: Bool {
        filter.startDate != nil
            || filter.endDate != nil
            || filter.projectId != nil
            || filter.categoryId != nil
            || filter.type != nil
            || !filter.searchText.isEmpty
            || filter.amountMin != nil
            || filter.amountMax != nil
            || filter.counterparty != nil
    }

    var searchText: String {
        get { filter.searchText }
        set {
            filter = TransactionFilter(
                startDate: filter.startDate,
                endDate: filter.endDate,
                projectId: filter.projectId,
                categoryId: filter.categoryId,
                type: filter.type,
                searchText: newValue,
                amountMin: filter.amountMin,
                amountMax: filter.amountMax
            )
        }
    }

    /// 帳簿表示用: 日付昇順で累計残高を計算した行配列
    var ledgerRows: [LedgerRow] {
        let sorted = filteredTransactions.sorted { $0.date < $1.date }
        var balance = 0
        return sorted.map { t in
            let debit: Int
            let credit: Int
            switch t.type {
            case .income:
                debit = 0
                credit = effectiveAmount(for: t)
            case .expense:
                debit = effectiveAmount(for: t)
                credit = 0
            case .transfer:
                debit = effectiveAmount(for: t)
                credit = 0
            }
            balance += credit - debit
            let categoryName = dataStore.getCategory(id: t.categoryId)?.name ?? "未分類"
            return LedgerRow(
                id: t.id,
                date: t.date,
                memo: t.memo,
                categoryName: categoryName,
                type: t.type,
                debit: debit,
                credit: credit,
                runningBalance: balance,
                transaction: t
            )
        }
    }

    func exportURL(exportAll: Bool = false) throws -> URL {
        let target = exportAll ? dataStore.transactions : filteredTransactions
        return try ExportCoordinator.export(
            target: .transactions,
            format: .csv,
            fiscalYear: exportFiscalYear(for: target),
            dataStore: dataStore,
            transactionOptions: .init(transactions: target)
        )
    }

    // MARK: - Private Helpers

    private func yearMonthKey(for transaction: PPTransaction) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: transaction.date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    private func createTransactionGroup(yearMonth: String, transactions: [PPTransaction]) -> TransactionGroup {
        TransactionGroup(
            yearMonth: yearMonth,
            displayLabel: displayLabel(from: yearMonth),
            transactions: sortTransactions(transactions),
            income: totalByType(.income, from: transactions),
            expense: totalByType(.expense, from: transactions),
            transfer: totalByType(.transfer, from: transactions)
        )
    }

    private func displayLabel(from yearMonth: String) -> String {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))
        else {
            return yearMonth
        }
        return formatYearMonth(date)
    }

    private func sortTransactions(_ transactions: [PPTransaction]) -> [PPTransaction] {
        switch sort.field {
        case .date:
            return sort.order == .desc
                ? transactions.sorted { $0.date > $1.date }
                : transactions.sorted { $0.date < $1.date }
        case .amount:
            return sort.order == .desc
                ? transactions.sorted { $0.amount > $1.amount }
                : transactions.sorted { $0.amount < $1.amount }
        }
    }

    private func totalByType(_ type: TransactionType, from transactions: [PPTransaction]) -> Int {
        transactions
            .filter { $0.type == type }
            .reduce(0) { $0 + effectiveAmount(for: $1) }
    }

    private func exportFiscalYear(for transactions: [PPTransaction]) -> Int {
        let referenceDate = transactions.max(by: { $0.date < $1.date })?.date ?? Date()
        return fiscalYear(for: referenceDate, startMonth: FiscalYearSettings.startMonth)
    }

    /// プロジェクトフィルタ適用時は配分額、未適用時は取引全額を返す
    private func effectiveAmount(for transaction: PPTransaction) -> Int {
        guard let projectId = filter.projectId else {
            return transaction.amount
        }
        return transaction.allocations.first { $0.projectId == projectId }?.amount ?? transaction.amount
    }
}
