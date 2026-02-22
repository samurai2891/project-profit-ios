import SwiftData
import SwiftUI

// MARK: - ProjectDetailView

struct ProjectDetailView: View {
    let projectId: UUID

    @Environment(DataStore.self) private var dataStore
    @State private var viewModel: ProjectDetailViewModel?
    @State private var showEditSheet = false
    @State private var showAddTransactionSheet = false
    @State private var showReceiptScanner = false
    @State private var selectedTransaction: PPTransaction?
    @State private var transactionToDelete: PPTransaction?
    @State private var showDeleteConfirmation = false

    private var resolvedViewModel: ProjectDetailViewModel {
        viewModel ?? ProjectDetailViewModel(dataStore: dataStore, projectId: projectId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let project = resolvedViewModel.currentProject {
                    headerCard(project: project)
                    descriptionSection(project: project)
                }
                profitCard
                incomeExpenseCards
                recentTransactionsSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(resolvedViewModel.currentProject?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                receiptScanButton
                addTransactionButton
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let project = resolvedViewModel.currentProject {
                ProjectFormView(project: project)
            }
        }
        .sheet(isPresented: $showAddTransactionSheet) {
            TransactionFormView(defaultProjectId: projectId)
        }
        .sheet(isPresented: $showReceiptScanner) {
            ReceiptScannerView(defaultProjectId: projectId)
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailView(transaction: transaction)
        }
        .alert("取引を削除", isPresented: $showDeleteConfirmation) {
            deleteAlertActions
        } message: {
            Text("この取引を削除しますか？この操作は取り消せません。")
        }
        .task {
            if viewModel == nil {
                viewModel = ProjectDetailViewModel(dataStore: dataStore, projectId: projectId)
            }
        }
    }
}

// MARK: - Header Card

private extension ProjectDetailView {

    func headerCard(project: PPProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    StatusBadge(status: project.status)

                    if let startDate = project.startDate {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                                .font(.caption)
                                .foregroundStyle(AppColors.primary)
                            Text("開始日: \(formatDate(startDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("開始日 \(formatDate(startDate))")
                    }

                    if project.status == .completed, let completedAt = project.completedAt {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(AppColors.success)
                            Text("完了日: \(formatDate(completedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("完了日 \(formatDate(completedAt))")
                    }
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
        .accessibilityElement(children: .contain)
    }

    var editButton: some View {
        Button {
            showEditSheet = true
        } label: {
            Image(systemName: "pencil.circle.fill")
                .font(.title2)
                .foregroundStyle(AppColors.primary)
        }
        .accessibilityLabel("編集")
        .accessibilityHint("タップしてプロジェクトを編集")
    }
}

// MARK: - Description Section

private extension ProjectDetailView {

    @ViewBuilder
    func descriptionSection(project: PPProject) -> some View {
        if !project.projectDescription.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("説明")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(project.projectDescription)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("説明 \(project.projectDescription)")
        }
    }
}

// MARK: - Profit Card

private extension ProjectDetailView {

    var profitCard: some View {
        let profit = resolvedViewModel.projectProfit
        let income = resolvedViewModel.projectIncome
        let isPositive = profit >= 0

        return VStack(spacing: 8) {
            Text("利益")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.8))

            Text(formatCurrency(profit))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            if income > 0 {
                let margin = Double(profit) / Double(income) * 100
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("利益 \(formatCurrency(profit))")
        .accessibilityValue(isPositive ? "黒字" : "赤字")
    }
}

// MARK: - Income / Expense Cards

private extension ProjectDetailView {

    var incomeExpenseCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: "収入",
                amount: resolvedViewModel.projectIncome,
                icon: "arrow.up.circle.fill",
                color: AppColors.success
            )

            summaryCard(
                title: "支出",
                amount: resolvedViewModel.projectExpense,
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(formatCurrency(amount))")
    }
}

// MARK: - Recent Transactions

private extension ProjectDetailView {

    var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            if resolvedViewModel.recentTransactions.isEmpty {
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
            Text("取引一覧")
                .font(.headline)

            Spacer()

            Text("\(resolvedViewModel.recentTransactions.count)件")
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

            HStack(spacing: 12) {
                Button {
                    showReceiptScanner = true
                } label: {
                    Label("レシート読取", systemImage: "doc.text.viewfinder")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .accessibilityLabel("レシート読取")
                .accessibilityHint("タップしてレシートを読み取り経費を自動登録")

                Button {
                    showAddTransactionSheet = true
                } label: {
                    Label("手動で追加", systemImage: "plus")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .accessibilityLabel("取引を追加")
                .accessibilityHint("タップして新しい取引を作成")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    var transactionsList: some View {
        let transactions = resolvedViewModel.recentTransactions
        return LazyVStack(spacing: 0) {
            ForEach(transactions) { transaction in
                Button {
                    selectedTransaction = transaction
                } label: {
                    TransactionRow(
                        transaction: transaction,
                        projectId: projectId,
                        viewModel: resolvedViewModel,
                        onDelete: {
                            transactionToDelete = transaction
                            showDeleteConfirmation = true
                        }
                    )
                }
                .buttonStyle(.plain)

                if transaction.id != transactions.last?.id {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
    }

    var receiptScanButton: some View {
        Button {
            showReceiptScanner = true
        } label: {
            Image(systemName: "doc.text.viewfinder")
                .font(.title3)
                .foregroundStyle(AppColors.primary)
        }
        .accessibilityLabel("レシート読取")
        .accessibilityHint("タップしてレシートを読み取り経費を自動登録")
    }

    var addTransactionButton: some View {
        Button {
            showAddTransactionSheet = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(AppColors.primary)
        }
        .accessibilityLabel("取引を追加")
        .accessibilityHint("タップして新しい取引を作成")
    }

    @ViewBuilder
    var deleteAlertActions: some View {
        Button("キャンセル", role: .cancel) {
            transactionToDelete = nil
        }
        Button("削除", role: .destructive) {
            if let transaction = transactionToDelete {
                withAnimation {
                    viewModel?.deleteTransaction(id: transaction.id)
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
    let viewModel: ProjectDetailViewModel
    let onDelete: () -> Void

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

    private var allocationAmount: Int? {
        transaction.allocations
            .first(where: { $0.projectId == projectId })?
            .amount
    }

    private var categoryName: String {
        viewModel.getCategoryName(for: transaction.categoryId)
    }

    var body: some View {
        HStack(spacing: 12) {
            typeIndicator
            transactionDetails
            Spacer()
            amountAndDelete
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(isIncome ? "収益" : "経費") \(categoryName) \(formatCurrency(allocationAmount ?? transaction.amount)) \(formatDate(transaction.date))")
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
            .accessibilityHidden(true)
    }

    var transactionDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(categoryName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if transaction.receiptImagePath != nil {
                    Image(systemName: "doc.text.image")
                        .font(.caption2)
                        .foregroundStyle(AppColors.primary)
                }
            }

            Text(formatDate(transaction.date))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !transaction.memo.isEmpty {
                Text(transaction.memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !transaction.lineItems.isEmpty {
                Text("\(transaction.lineItems.count)品目")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.primary.opacity(0.1))
                    .foregroundStyle(AppColors.primary)
                    .clipShape(Capsule())
            }
        }
        .accessibilityHidden(true)
    }

    var amountAndDelete: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(allocationAmount ?? transaction.amount))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isIncome ? AppColors.success : AppColors.error)

                if let ratio = allocationRatio {
                    Text("\(ratio)%配分")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if allocationAmount != nil {
                    Text("全体: \(formatCurrency(transaction.amount))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHidden(true)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(AppColors.error.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("削除")
            .accessibilityHint("タップして取引を削除")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ProjectDetailView(
            projectId: UUID()
        )
    }
    .environment(DataStore(modelContext: try! ModelContext(ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))))
}
