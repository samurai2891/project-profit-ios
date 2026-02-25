import SwiftUI

// MARK: - TransactionGroup

struct TransactionGroup: Identifiable {
    let yearMonth: String
    let displayLabel: String
    let transactions: [PPTransaction]
    let income: Int
    let expense: Int

    var id: String { yearMonth }
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
            type: newValue
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

    var netTotal: Int {
        incomeTotal - expenseTotal
    }

    var hasActiveFilter: Bool {
        filter.startDate != nil
            || filter.endDate != nil
            || filter.projectId != nil
            || filter.categoryId != nil
            || filter.type != nil
    }

    // MARK: - Actions

    func deleteTransaction(id: UUID) {
        dataStore.deleteTransaction(id: id)
    }

    func generateCSVText(exportAll: Bool = false) -> String {
        let target = exportAll ? dataStore.transactions : filteredTransactions
        return generateCSV(
            transactions: target,
            getCategory: { self.dataStore.getCategory(id: $0) },
            getProject: { self.dataStore.getProject(id: $0) }
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
            expense: totalByType(.expense, from: transactions)
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

    /// プロジェクトフィルタ適用時は配分額、未適用時は取引全額を返す
    private func effectiveAmount(for transaction: PPTransaction) -> Int {
        guard let projectId = filter.projectId else {
            return transaction.amount
        }
        return transaction.allocations.first { $0.projectId == projectId }?.amount ?? transaction.amount
    }
}
