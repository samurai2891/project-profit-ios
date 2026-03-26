import SwiftData
import SwiftUI

struct RecurringHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let recurringId: UUID

    @State private var historyEntries: [RecurringHistoryEntry] = []

    private var recurringQueryUseCase: RecurringQueryUseCase {
        RecurringQueryUseCase(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.surface
                    .ignoresSafeArea()

                if historyEntries.isEmpty {
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
        .task {
            historyEntries = recurringQueryUseCase.historyEntries(recurringId: recurringId)
        }
    }

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

    private var transactionList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(historyEntries) { entry in
                    transactionRow(entry)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func transactionRow(_ entry: RecurringHistoryEntry) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(formatDate(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                if let categoryName = entry.categoryName {
                    Text(categoryName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                if !entry.projectNames.isEmpty {
                    Text(entry.projectNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(AppColors.muted)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(formatCurrency(entry.amount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(
                    entry.type == .expense ? AppColors.error
                        : entry.type == .transfer ? AppColors.warning
                        : AppColors.success
                )
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    RecurringHistoryView(recurringId: UUID())
        .modelContainer(try! ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))
}
