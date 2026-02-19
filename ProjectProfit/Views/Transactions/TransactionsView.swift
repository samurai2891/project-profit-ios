import SwiftData
import SwiftUI

// MARK: - ActivityViewController Wrapper

private struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - TransactionsView

struct TransactionsView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var viewModel: TransactionsViewModel?

    @State private var showAddSheet = false
    @State private var showFilterSheet = false
    @State private var editingTransaction: PPTransaction?
    @State private var deletingTransaction: PPTransaction?
    @State private var showShareSheet = false
    @State private var csvText = ""

    // MARK: - Body

    var body: some View {
        contentView
            .onAppear {
                if viewModel == nil {
                    viewModel = TransactionsViewModel(dataStore: dataStore)
                }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        if let viewModel {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    headerSection(viewModel: viewModel)
                    scrollContent(viewModel: viewModel)
                }
                .background(AppColors.surface)

                fabButton
            }
            .sheet(isPresented: $showAddSheet) {
                TransactionFormView(transaction: nil)
            }
            .sheet(item: $editingTransaction) { transaction in
                TransactionFormView(transaction: transaction)
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterView(filter: Binding(
                    get: { viewModel.filter },
                    set: { viewModel.filter = $0 }
                ))
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityViewControllerWrapper(items: [csvText])
            }
            .alert(
                "取引を削除",
                isPresented: .init(
                    get: { deletingTransaction != nil },
                    set: { if !$0 { deletingTransaction = nil } }
                )
            ) {
                Button("キャンセル", role: .cancel) {
                    deletingTransaction = nil
                }
                Button("削除", role: .destructive) {
                    if let transaction = deletingTransaction {
                        viewModel.deleteTransaction(id: transaction.id)
                        deletingTransaction = nil
                    }
                }
            } message: {
                Text("この取引を削除してもよろしいですか？")
            }
        }
    }

    // MARK: - Header

    private func headerSection(viewModel: TransactionsViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("取引履歴")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(viewModel.filteredTransactions.count)件")
                    .font(.caption)
                    .foregroundStyle(AppColors.muted)
            }

            Spacer()

            Button {
                csvText = viewModel.generateCSVText()
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundStyle(AppColors.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Scroll Content

    private func scrollContent(viewModel: TransactionsViewModel) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryBar(viewModel: viewModel)
                filterSortBar(viewModel: viewModel)

                if viewModel.filteredTransactions.isEmpty {
                    emptyState
                } else {
                    transactionList(viewModel: viewModel)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 80)
        }
    }

    // MARK: - Summary Bar

    private func summaryBar(viewModel: TransactionsViewModel) -> some View {
        let netColor = netColor(for: viewModel.netTotal)
        return HStack(spacing: 0) {
            summaryItem(label: "収益", amount: viewModel.incomeTotal, color: AppColors.success)
            Divider().frame(height: 36)
            summaryItem(label: "経費", amount: viewModel.expenseTotal, color: AppColors.error)
            Divider().frame(height: 36)
            summaryItem(label: "差引", amount: viewModel.netTotal, color: netColor)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func summaryItem(label: String, amount: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppColors.muted)
            Text(formatCurrency(amount))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func netColor(for netTotal: Int) -> Color {
        if netTotal > 0 { return AppColors.success }
        if netTotal < 0 { return AppColors.error }
        return AppColors.muted
    }

    // MARK: - Filter & Sort Bar

    private var filterSortBar: some View {
        HStack(spacing: 8) {
            filterButton
            Spacer()
            sortFieldMenu
            sortOrderToggle
        }
    }

    private var hasActiveFilter: Bool {
        filter.startDate != nil
            || filter.endDate != nil
            || filter.projectId != nil
            || filter.categoryId != nil
            || filter.type != nil
    }

    private var filterButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.subheadline)
                Text(hasActiveFilter ? "フィルター (適用中)" : "フィルター")
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(hasActiveFilter ? AppColors.primary.opacity(0.12) : Color.clear)
            .foregroundStyle(hasActiveFilter ? AppColors.primary : AppColors.muted)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(hasActiveFilter ? AppColors.primary : AppColors.border, lineWidth: 1)
            )
        }
    }

    private var sortFieldLabel: String {
        switch sort.field {
        case .date: return "日付"
        case .amount: return "金額"
        }
    }

    private var sortOrderLabel: String {
        switch sort.order {
        case .desc: return "降順"
        case .asc: return "昇順"
        }
    }

    private var sortFieldMenu: some View {
        Menu {
            Button {
                sort = TransactionSort(field: .date, order: sort.order)
            } label: {
                HStack {
                    Text("日付")
                    if sort.field == .date {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button {
                sort = TransactionSort(field: .amount, order: sort.order)
            } label: {
                HStack {
                    Text("金額")
                    if sort.field == .amount {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Text(sortFieldLabel)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(AppColors.primary)
                .background(AppColors.primary.opacity(0.08))
                .clipShape(Capsule())
        }
    }

    private var sortOrderToggle: some View {
        Button {
            let newOrder: TransactionSort.SortOrder = sort.order == .desc ? .asc : .desc
            sort = TransactionSort(field: sort.field, order: newOrder)
        } label: {
            Text(sortOrderLabel)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(AppColors.primary)
                .background(AppColors.primary.opacity(0.08))
                .clipShape(Capsule())
        }
    }

    // MARK: - Transaction List

    private var transactionList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredTransactions) { transaction in
                TransactionCardView(
                    transaction: transaction,
                    onEdit: { editingTransaction = transaction },
                    onDelete: { deletingTransaction = transaction }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.muted)

            Text("取引がありません")
                .font(.headline)
                .foregroundStyle(AppColors.muted)

            Button {
                showAddSheet = true
            } label: {
                Text("最初の取引を追加")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(AppColors.primary)
                .clipShape(Circle())
                .shadow(color: AppColors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }
}

// MARK: - TransactionCardView

private struct TransactionCardView: View {
    let transaction: PPTransaction
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(DataStore.self) private var dataStore

    private var isIncome: Bool {
        transaction.type == .income
    }

    private var categoryName: String {
        dataStore.getCategory(id: transaction.categoryId)?.name ?? "未分類"
    }

    private var projectNames: [String] {
        transaction.allocations.compactMap { alloc in
            dataStore.getProject(id: alloc.projectId)?.name
        }
    }

    private var formattedAmount: String {
        let prefix = isIncome ? "+" : "-"
        return "\(prefix)\(formatCurrency(transaction.amount))"
    }

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 12) {
                typeIndicator
                transactionDetails
                Spacer()
                amountAndActions
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Subviews

    private var typeIndicator: some View {
        Circle()
            .fill(isIncome ? AppColors.success.opacity(0.15) : AppColors.error.opacity(0.15))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: isIncome ? "arrow.up" : "arrow.down")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isIncome ? AppColors.success : AppColors.error)
            )
    }

    private var transactionDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(categoryName)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color(.label))

            Text(formatDate(transaction.date))
                .font(.caption)
                .foregroundStyle(AppColors.muted)

            if !transaction.memo.isEmpty {
                Text(transaction.memo)
                    .font(.caption)
                    .foregroundStyle(AppColors.muted)
                    .lineLimit(1)
            }

            if !projectNames.isEmpty {
                projectTags
            }
        }
    }

    private var projectTags: some View {
        HStack(spacing: 4) {
            let visibleProjects = Array(projectNames.prefix(2))
            let overflow = projectNames.count - 2

            ForEach(visibleProjects, id: \.self) { name in
                Text(name)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.warning.opacity(0.12))
                    .foregroundStyle(AppColors.warning)
                    .clipShape(Capsule())
            }

            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.muted.opacity(0.12))
                    .foregroundStyle(AppColors.muted)
                    .clipShape(Capsule())
            }
        }
    }

    private var amountAndActions: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(formattedAmount)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isIncome ? AppColors.success : AppColors.error)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(AppColors.error.opacity(0.7))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TransactionsView()
        .environment(DataStore(modelContext: try! ModelContext(ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))))
}
