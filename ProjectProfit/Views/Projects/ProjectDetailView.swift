import SwiftData
import SwiftUI

// MARK: - ProjectDetailView

struct ProjectDetailView: View {
    let project: PPProject

    @Environment(DataStore.self) private var dataStore
    @State private var showEditSheet = false
    @State private var showAddTransactionSheet = false
    @State private var transactionToDelete: PPTransaction?
    @State private var showDeleteConfirmation = false

    private var currentProject: PPProject {
        dataStore.projects.first(where: { $0.id == project.id }) ?? project
    }

    private var summary: ProjectSummary? {
        dataStore.getProjectSummary(projectId: currentProject.id)
    }

    private var projectIncome: Int {
        summary?.totalIncome ?? 0
    }

    private var projectExpense: Int {
        summary?.totalExpense ?? 0
    }

    private var projectProfit: Int {
        summary?.profit ?? 0
    }

    private var recentTransactions: [PPTransaction] {
        dataStore.transactions
            .filter { t in t.allocations.contains(where: { $0.projectId == currentProject.id }) }
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                descriptionSection
                profitCard
                incomeExpenseCards
                recentTransactionsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(currentProject.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                addTransactionButton
            }
        }
        .sheet(isPresented: $showEditSheet) {
            ProjectFormView(project: currentProject)
        }
        .sheet(isPresented: $showAddTransactionSheet) {
            TransactionFormView(defaultProjectId: currentProject.id)
        }
        .alert("取引を削除", isPresented: $showDeleteConfirmation) {
            deleteAlertActions
        } message: {
            Text("この取引を削除しますか？この操作は取り消せません。")
        }
    }
}

// MARK: - Header Card

private extension ProjectDetailView {

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentProject.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    StatusBadge(status: currentProject.status)
                }

                Spacer()

                editButton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    var editButton: some View {
        Button {
            showEditSheet = true
        } label: {
            Image(systemName: "pencil.circle.fill")
                .font(.title2)
                .foregroundStyle(AppColors.primary)
        }
    }
}

// MARK: - Description Section

private extension ProjectDetailView {

    @ViewBuilder
    var descriptionSection: some View {
        if !currentProject.projectDescription.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("説明")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(currentProject.projectDescription)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        }
    }
}

// MARK: - Profit Card

private extension ProjectDetailView {

    var profitCard: some View {
        let isPositive = projectProfit >= 0

        return VStack(spacing: 8) {
            Text("利益")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.8))

            Text(formatCurrency(projectProfit))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if projectIncome > 0 {
                let margin = Double(projectProfit) / Double(projectIncome) * 100
                Text("利益率: \(String(format: "%.1f", margin))%")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: isPositive
                            ? [AppColors.success, AppColors.success.opacity(0.8)]
                            : [AppColors.error, AppColors.error.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(
            color: (isPositive ? AppColors.success : AppColors.error).opacity(0.3),
            radius: 8,
            x: 0,
            y: 4
        )
    }
}

// MARK: - Income / Expense Cards

private extension ProjectDetailView {

    var incomeExpenseCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: "収入",
                amount: projectIncome,
                icon: "arrow.up.circle.fill",
                color: AppColors.success
            )

            summaryCard(
                title: "支出",
                amount: projectExpense,
                icon: "arrow.down.circle.fill",
                color: AppColors.error
            )
        }
    }

    func summaryCard(
        title: String,
        amount: Int,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(formatCurrency(amount))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Recent Transactions

private extension ProjectDetailView {

    var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            if recentTransactions.isEmpty {
                transactionsEmptyState
            } else {
                transactionsList
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    var sectionHeader: some View {
        HStack {
            Text("最近の取引")
                .font(.headline)

            Spacer()

            Text("\(recentTransactions.count)件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var transactionsEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("取引がありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showAddTransactionSheet = true
            } label: {
                Label("取引を追加", systemImage: "plus")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    var transactionsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(recentTransactions) { transaction in
                TransactionRow(
                    transaction: transaction,
                    projectId: currentProject.id,
                    onDelete: {
                        transactionToDelete = transaction
                        showDeleteConfirmation = true
                    }
                )

                if transaction.id != recentTransactions.last?.id {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
    }

    var addTransactionButton: some View {
        Button {
            showAddTransactionSheet = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(AppColors.primary)
        }
    }

    @ViewBuilder
    var deleteAlertActions: some View {
        Button("キャンセル", role: .cancel) {
            transactionToDelete = nil
        }
        Button("削除", role: .destructive) {
            if let transaction = transactionToDelete {
                withAnimation {
                    dataStore.deleteTransaction(id: transaction.id)
                    transactionToDelete = nil
                }
            }
        }
    }
}

// MARK: - TransactionRow

private struct TransactionRow: View {
    let transaction: PPTransaction
    let projectId: UUID
    let onDelete: () -> Void

    @Environment(DataStore.self) private var dataStore

    private var isIncome: Bool {
        transaction.type == .income
    }

    private var allocationRatio: Int? {
        guard transaction.allocations.count > 1 else {
            return nil
        }
        return transaction.allocations
            .first(where: { $0.projectId == projectId })?
            .ratio
    }

    private var categoryName: String {
        dataStore.getCategory(id: transaction.categoryId)?.name ?? "未分類"
    }

    var body: some View {
        HStack(spacing: 12) {
            typeIndicator
            transactionDetails
            Spacer()
            amountAndDelete
        }
        .padding(.vertical, 10)
    }
}

// MARK: - TransactionRow Subviews

private extension TransactionRow {

    var typeIndicator: some View {
        Image(systemName: isIncome ? "arrow.down.left" : "arrow.up.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(isIncome ? AppColors.success : AppColors.error)
            .clipShape(Circle())
    }

    var transactionDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(categoryName)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(formatDate(transaction.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var amountAndDelete: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(transaction.amount))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isIncome ? AppColors.success : AppColors.error)

                if let ratio = allocationRatio {
                    Text("\(ratio)%配分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(AppColors.error.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProjectDetailView(
            project: PPProject(
                id: UUID(),
                name: "サンプルプロジェクト",
                projectDescription: "これはサンプルの説明です。",
                status: .active,
                createdAt: Date()
            )
        )
    }
    .environment(DataStore(modelContext: try! ModelContext(ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))))
}
