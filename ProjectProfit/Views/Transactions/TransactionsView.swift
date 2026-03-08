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

// MARK: - Display Mode

enum TransactionDisplayMode: String, CaseIterable {
    case card
    case ledger

    var label: String {
        switch self {
        case .card: "カード"
        case .ledger: "帳簿"
        }
    }
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
    @AppStorage("transactionDisplayMode") private var displayMode: String = TransactionDisplayMode.card.rawValue

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
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    EvidenceInboxView()
                } label: {
                    Image(systemName: "tray.full")
                }
                .accessibilityLabel("証憑Inbox")
                .accessibilityHint("登録済みの証憑を確認します")
            }

            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    ApprovalQueueView()
                } label: {
                    Image(systemName: "checklist")
                }
                .accessibilityLabel("Approval Queue")
                .accessibilityHint("承認待ちの仕訳候補を確認します")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showReceiptScanner = true
                } label: {
                    Image(systemName: "doc.text.viewfinder")
                }
                .accessibilityLabel("書類読取")
                .accessibilityHint("タップして書類を読み取り証憑を取り込みます")
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
        .searchable(
            text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ),
            prompt: "メモを検索"
        )
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

    private var currentDisplayMode: TransactionDisplayMode {
        TransactionDisplayMode(rawValue: displayMode) ?? .card
    }

    private func scrollContent(viewModel: TransactionsViewModel) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if !viewModel.canMutateLegacyTransactions {
                    canonicalCutoverNotice
                }
                HStack {
                    Text("\(viewModel.filteredTransactions.count)件")
                        .font(.caption)
                        .foregroundStyle(AppColors.muted)
                    Spacer()
                }
                .padding(.top, 4)

                summaryBar(viewModel: viewModel)
                typeSegmentControl(viewModel: viewModel)
                displayModeToggle
                filterSortBar(viewModel: viewModel)

                if viewModel.filteredTransactions.isEmpty {
                    emptyState
                } else if currentDisplayMode == .ledger {
                    ledgerTable(viewModel: viewModel)
                } else {
                    groupedTransactionList(viewModel: viewModel)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 80)
        }
    }

    // MARK: - Display Mode Toggle

    private var displayModeToggle: some View {
        Picker("表示モード", selection: $displayMode) {
            ForEach(TransactionDisplayMode.allCases, id: \.rawValue) { mode in
                Text(mode.label).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("表示モード切替")
    }

    // MARK: - Ledger Table

    private func ledgerTable(viewModel: TransactionsViewModel) -> some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("日付")
                    .frame(width: 56, alignment: .leading)
                Text("摘要")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("カテゴリ")
                    .frame(width: 64, alignment: .leading)
                Text("借方")
                    .frame(width: 72, alignment: .trailing)
                Text("貸方")
                    .frame(width: 72, alignment: .trailing)
                Text("残高")
                    .frame(width: 76, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(AppColors.surface)

            Divider()

            // Data rows
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.ledgerRows.enumerated()), id: \.element.id) { index, row in
                    Button {
                        selectedTransaction = row.transaction
                    } label: {
                        ledgerRowView(row: row)
                            .background(
                                index.isMultiple(of: 2)
                                    ? Color(.systemBackground)
                                    : AppColors.surface.opacity(0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Divider()
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func ledgerRowView(row: LedgerRow) -> some View {
        HStack(spacing: 0) {
            Text(formatDateShort(row.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            Text(row.memo.isEmpty ? row.categoryName : row.memo)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.categoryName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)

            CurrencyText(
                amount: row.debit,
                font: .caption.weight(.medium),
                color: AppColors.error,
                emptyWhenZero: true
            )
            .frame(width: 72, alignment: .trailing)

            CurrencyText(
                amount: row.credit,
                font: .caption.weight(.medium),
                color: AppColors.success,
                emptyWhenZero: true
            )
            .frame(width: 72, alignment: .trailing)

            CurrencyText(
                amount: row.runningBalance,
                font: .caption.weight(.semibold),
                color: row.runningBalance >= 0 ? .primary : AppColors.error
            )
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(formatDateShort(row.date)) \(row.categoryName) 借方\(formatCurrency(row.debit)) 貸方\(formatCurrency(row.credit)) 残高\(formatCurrency(row.runningBalance))")
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
            Text("振替").tag(TransactionType?.some(.transfer))
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("取引種別フィルター")
    }

    // MARK: - Summary Bar

    @ViewBuilder
    private func summaryBar(viewModel: TransactionsViewModel) -> some View {
        if viewModel.isTransferFilter {
            HStack(spacing: 0) {
                summaryItem(label: "振替合計", amount: viewModel.transferTotal, color: AppColors.warning)
            }
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("振替合計 \(formatCurrency(viewModel.transferTotal))")
        } else {
            let netColor = netColor(for: viewModel.netTotal)
            HStack(spacing: 0) {
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
    }

    private func summaryItem(label: String, amount: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppColors.muted)
            Text(formatCurrency(amount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
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
                    sectionHeader(group: group, isTransferFilter: viewModel.isTransferFilter)

                    ForEach(group.transactions) { transaction in
                        TransactionCardView(
                            transaction: transaction,
                            onTap: { selectedTransaction = transaction },
                            onDelete: { deletingTransaction = transaction },
                            showDeleteButton: viewModel.canMutateLegacyTransactions
                        )
                    }
                }
            }
        }
    }

    private func sectionHeader(group: TransactionGroup, isTransferFilter: Bool) -> some View {
        HStack {
            Text(group.displayLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color(.label))

            Spacer()

            if isTransferFilter {
                Text("振替: \(formatCurrency(group.transfer))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppColors.warning)
            } else {
                HStack(spacing: 12) {
                    Text("収益: \(formatCurrency(group.income))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColors.success)
                    Text("経費: \(formatCurrency(group.expense))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColors.error)
                }
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
                Text(dataStore.isLegacyTransactionEditingEnabled ? "最初の取引を追加" : "最初の候補を作成")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
            .accessibilityLabel(dataStore.isLegacyTransactionEditingEnabled ? "最初の取引を追加" : "最初の候補を作成")
            .accessibilityHint(dataStore.isLegacyTransactionEditingEnabled ? "タップして新しい取引を作成" : "タップして承認待ち候補を手入力します")

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - FAB

    private var canonicalCutoverNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.doc")
                .foregroundStyle(AppColors.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("既存取引の編集・削除は停止中")
                    .font(.subheadline.weight(.semibold))
                Text("新規の手入力は承認待ち候補として保存されます。証憑取込は右上の書類読取から行えます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(AppColors.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

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
        .accessibilityLabel(dataStore.isLegacyTransactionEditingEnabled ? "新規追加" : "候補を手入力")
        .accessibilityHint(dataStore.isLegacyTransactionEditingEnabled ? "タップして新しい取引を作成" : "タップして承認待ち候補を手入力します")
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }
}

// MARK: - TransactionCardView

private struct TransactionCardView: View {
    let transaction: PPTransaction
    let onTap: () -> Void
    let onDelete: () -> Void
    let showDeleteButton: Bool

    @Environment(DataStore.self) private var dataStore

    private var typeColor: Color {
        switch transaction.type {
        case .income: AppColors.success
        case .expense: AppColors.error
        case .transfer: AppColors.warning
        }
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
        switch transaction.type {
        case .income: return "+\(formatCurrency(transaction.amount))"
        case .expense: return "-\(formatCurrency(transaction.amount))"
        case .transfer: return formatCurrency(transaction.amount)
        }
    }

    private var accessibilityDescription: String {
        let typeLabel = transaction.type.label
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

    private var typeIcon: String {
        switch transaction.type {
        case .income: "arrow.up"
        case .expense: "arrow.down"
        case .transfer: "arrow.left.arrow.right"
        }
    }

    private var typeIndicator: some View {
        Circle()
            .fill(typeColor.opacity(0.15))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: typeIcon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(typeColor)
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
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(typeColor)
                .accessibilityHidden(true)

            if showDeleteButton {
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
}

// MARK: - Preview

#Preview {
    TransactionsView()
        .environment(DataStore(modelContext: try! ModelContext(ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))))
}
