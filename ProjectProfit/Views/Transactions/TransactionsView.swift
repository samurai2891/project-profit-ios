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
    @State private var showReceiptScanner = false
    @State private var selectedTransaction: PPTransaction?
    @State private var deletingTransaction: PPTransaction?
    @State private var showShareSheet = false
    @State private var csvText = ""

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel {
                mainContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = TransactionsViewModel(dataStore: dataStore)
            }
        }
    }

    private func mainContent(viewModel: TransactionsViewModel) -> some View {
        ZStack(alignment: .bottomTrailing) {
            scrollContent(viewModel: viewModel)
                .background(AppColors.surface)

            fabButton
        }
        .navigationTitle("取引履歴")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showReceiptScanner = true
                } label: {
                    Image(systemName: "doc.text.viewfinder")
                }
                .accessibilityLabel("書類読取")
                .accessibilityHint("タップして書類を読み取り取引を自動入力")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        csvText = viewModel.generateCSVText(exportAll: false)
                        showShareSheet = true
                    } label: {
                        Label("フィルタ中のデータ", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    Button {
                        csvText = viewModel.generateCSVText(exportAll: true)
                        showShareSheet = true
                    } label: {
                        Label("全データ", systemImage: "tray.full")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("CSV出力")
                .accessibilityHint("タップしてCSVエクスポートオプションを表示")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            TransactionFormView(transaction: nil)
        }
        .sheet(isPresented: $showReceiptScanner) {
            ReceiptScannerView()
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailView(transaction: transaction)
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

    // MARK: - Scroll Content

    private func scrollContent(viewModel: TransactionsViewModel) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Text("\(viewModel.filteredTransactions.count)件")
                        .font(.caption)
                        .foregroundStyle(AppColors.muted)
                    Spacer()
                }
                .padding(.top, 4)

                summaryBar(viewModel: viewModel)
                typeSegmentControl(viewModel: viewModel)
                filterSortBar(viewModel: viewModel)

                if viewModel.filteredTransactions.isEmpty {
                    emptyState
                } else {
                    groupedTransactionList(viewModel: viewModel)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 80)
        }
    }

    // MARK: - Type Segment Control

    private func typeSegmentControl(viewModel: TransactionsViewModel) -> some View {
        Picker("取引種別", selection: Binding(
            get: { viewModel.selectedType },
            set: { viewModel.selectedType = $0 }
        )) {
            Text("全て").tag(TransactionType?.none)
            Text("収益").tag(TransactionType?.some(.income))
            Text("経費").tag(TransactionType?.some(.expense))
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("取引種別フィルター")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("収益 \(formatCurrency(viewModel.incomeTotal)) 経費 \(formatCurrency(viewModel.expenseTotal)) 差引 \(formatCurrency(viewModel.netTotal))")
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

    private func filterSortBar(viewModel: TransactionsViewModel) -> some View {
        HStack(spacing: 8) {
            filterButton(viewModel: viewModel)
            Spacer()
            sortFieldMenu(viewModel: viewModel)
            sortOrderToggle(viewModel: viewModel)
        }
    }

    private func filterButton(viewModel: TransactionsViewModel) -> some View {
        let isActive = viewModel.hasActiveFilter
        return Button {
            showFilterSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.subheadline)
                Text(isActive ? "フィルター (適用中)" : "フィルター")
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? AppColors.primary.opacity(0.12) : Color.clear)
            .foregroundStyle(isActive ? AppColors.primary : AppColors.muted)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isActive ? AppColors.primary : AppColors.border, lineWidth: 1)
            )
        }
        .accessibilityLabel(isActive ? "フィルター適用中" : "フィルター")
        .accessibilityHint("タップしてフィルター条件を設定")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func sortFieldLabel(for sort: TransactionSort) -> String {
        switch sort.field {
        case .date: return "日付"
        case .amount: return "金額"
        }
    }

    private func sortOrderLabel(for sort: TransactionSort) -> String {
        switch sort.order {
        case .desc: return "降順"
        case .asc: return "昇順"
        }
    }

    private func sortFieldMenu(viewModel: TransactionsViewModel) -> some View {
        Menu {
            Button {
                viewModel.sort = TransactionSort(field: .date, order: viewModel.sort.order)
            } label: {
                HStack {
                    Text("日付")
                    if viewModel.sort.field == .date {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button {
                viewModel.sort = TransactionSort(field: .amount, order: viewModel.sort.order)
            } label: {
                HStack {
                    Text("金額")
                    if viewModel.sort.field == .amount {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Text(sortFieldLabel(for: viewModel.sort))
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(AppColors.primary)
                .background(AppColors.primary.opacity(0.08))
                .clipShape(Capsule())
        }
        .accessibilityLabel("並び替え: \(sortFieldLabel(for: viewModel.sort))")
        .accessibilityHint("タップして並び替えの基準を変更")
    }

    private func sortOrderToggle(viewModel: TransactionsViewModel) -> some View {
        Button {
            let newOrder: TransactionSort.SortOrder = viewModel.sort.order == .desc ? .asc : .desc
            viewModel.sort = TransactionSort(field: viewModel.sort.field, order: newOrder)
        } label: {
            Text(sortOrderLabel(for: viewModel.sort))
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(AppColors.primary)
                .background(AppColors.primary.opacity(0.08))
                .clipShape(Capsule())
        }
        .accessibilityLabel("並び順: \(sortOrderLabel(for: viewModel.sort))")
        .accessibilityHint("タップして昇順と降順を切り替え")
    }

    // MARK: - Grouped Transaction List

    private func groupedTransactionList(viewModel: TransactionsViewModel) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.groupedTransactions) { group in
                VStack(spacing: 8) {
                    sectionHeader(group: group)

                    ForEach(group.transactions) { transaction in
                        TransactionCardView(
                            transaction: transaction,
                            onTap: { selectedTransaction = transaction },
                            onDelete: { deletingTransaction = transaction }
                        )
                    }
                }
            }
        }
    }

    private func sectionHeader(group: TransactionGroup) -> some View {
        HStack {
            Text(group.displayLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color(.label))

            Spacer()

            HStack(spacing: 12) {
                Text("収益: \(formatCurrency(group.income))")
                    .font(.caption)
                    .foregroundStyle(AppColors.success)
                Text("経費: \(formatCurrency(group.expense))")
                    .font(.caption)
                    .foregroundStyle(AppColors.error)
            }
        }
        .padding(.vertical, 4)
        .accessibilityAddTraits(.isHeader)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.displayLabel) 収益 \(formatCurrency(group.income)) 経費 \(formatCurrency(group.expense))")
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
            .accessibilityLabel("最初の取引を追加")
            .accessibilityHint("タップして新しい取引を作成")

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
        .accessibilityLabel("新規追加")
        .accessibilityHint("タップして新しい取引を作成")
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }
}

// MARK: - TransactionCardView

private struct TransactionCardView: View {
    let transaction: PPTransaction
    let onTap: () -> Void
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

    private var hasReceipt: Bool {
        transaction.receiptImagePath != nil
    }

    private var formattedAmount: String {
        let prefix = isIncome ? "+" : "-"
        return "\(prefix)\(formatCurrency(transaction.amount))"
    }

    private var accessibilityDescription: String {
        let typeLabel = isIncome ? "収益" : "経費"
        let receiptInfo = hasReceipt ? " 添付画像あり" : ""
        let projectInfo = projectNames.isEmpty ? "" : " \(projectNames.joined(separator: ", "))"
        let memoInfo = transaction.memo.isEmpty ? "" : " \(transaction.memo)"
        return "\(typeLabel) \(categoryName) \(formattedAmount) \(formatDate(transaction.date))\(receiptInfo)\(projectInfo)\(memoInfo)"
    }

    var body: some View {
        Button(action: onTap) {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("タップして取引の詳細を表示")
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
            .accessibilityHidden(true)
    }

    private var transactionDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(categoryName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color(.label))

                if hasReceipt {
                    Image(systemName: "doc.text.image")
                        .font(.caption2)
                        .foregroundStyle(AppColors.primary)
                        .accessibilityLabel("添付画像あり")
                }
            }

            Text(formatDateShort(transaction.date))
                .font(.caption)
                .foregroundStyle(AppColors.muted)

            if !transaction.memo.isEmpty {
                Text(transaction.memo)
                    .font(.caption)
                    .foregroundStyle(AppColors.muted)
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

            if !projectNames.isEmpty {
                projectTags
            }
        }
        .accessibilityHidden(true)
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
                .accessibilityHidden(true)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(AppColors.error.opacity(0.7))
            }
            .accessibilityLabel("削除")
            .accessibilityHint("タップして削除確認画面を表示")
        }
    }
}

// MARK: - Preview

#Preview {
    TransactionsView()
        .environment(DataStore(modelContext: try! ModelContext(ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))))
}
