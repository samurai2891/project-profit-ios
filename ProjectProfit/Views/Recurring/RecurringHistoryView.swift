import SwiftData
import SwiftUI

struct RecurringHistoryView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    let recurringId: UUID

    // MARK: - Computed Properties

    private var historyTransactions: [PPTransaction] {
        dataStore.transactions
            .filter { $0.recurringId == recurringId }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.surface
                    .ignoresSafeArea()

                if historyTransactions.isEmpty {
                    emptyStateView
                } else {
                    transactionList
                }
            }
            .navigationTitle("定期取引履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("まだ登録された取引はありません")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("定期取引が実行されると、ここに履歴が表示されます")
                .font(.subheadline)
                .foregroundStyle(AppColors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // MARK: - Transaction List

    private var transactionList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(historyTransactions) { transaction in
                    transactionRow(transaction)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Transaction Row

    private func transactionRow(_ transaction: PPTransaction) -> some View {
        HStack(spacing: 12) {
            // Date column
            VStack(spacing: 2) {
                Text(formatDate(transaction.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            // Details column
            VStack(alignment: .leading, spacing: 2) {
                let categoryName = dataStore.getCategory(id: transaction.categoryId)?.name
                if let categoryName {
                    Text(categoryName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                let projectNames = projectNamesForTransaction(transaction)
                if !projectNames.isEmpty {
                    Text(projectNames)
                        .font(.caption)
                        .foregroundStyle(AppColors.muted)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Amount
            Text(formatCurrency(transaction.amount))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    transaction.type == .expense ? AppColors.error
                        : transaction.type == .transfer ? AppColors.warning
                        : AppColors.success
                )
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func projectNamesForTransaction(_ transaction: PPTransaction) -> String {
        let names = transaction.allocations.compactMap { allocation in
            dataStore.getProject(id: allocation.projectId)?.name
        }
        return names.joined(separator: ", ")
    }
}

#Preview {
    RecurringHistoryView(recurringId: UUID())
        .environment(DataStore(modelContext: try! ModelContext(ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))))
}
