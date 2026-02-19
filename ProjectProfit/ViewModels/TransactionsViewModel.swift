import SwiftUI

// MARK: - TransactionsViewModel

@MainActor
@Observable
final class TransactionsViewModel {
    let dataStore: DataStore
    var filter = TransactionFilter()
    var sort = TransactionSort()

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    // MARK: - Computed Properties

    var filteredTransactions: [PPTransaction] {
        dataStore.getFilteredTransactions(filter: filter, sort: sort)
    }

    var incomeTotal: Int {
        filteredTransactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
    }

    var expenseTotal: Int {
        filteredTransactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
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

    func generateCSVText() -> String {
        generateCSV(
            transactions: filteredTransactions,
            getCategory: { self.dataStore.getCategory(id: $0) },
            getProject: { self.dataStore.getProject(id: $0) }
        )
    }
}
