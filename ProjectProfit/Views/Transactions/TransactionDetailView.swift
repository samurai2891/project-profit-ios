import SwiftUI

struct TransactionDetailView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    let transaction: PPTransaction

    @State private var showReceiptPreview = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false
    @State private var showRecurringHistory = false

    private var typeColor: Color {
        switch transaction.type {
        case .income: AppColors.success
        case .expense: AppColors.error
        case .transfer: AppColors.warning
        }
    }

    private var typeIcon: String {
        switch transaction.type {
        case .income: "arrow.up.circle.fill"
        case .expense: "arrow.down.circle.fill"
        case .transfer: "arrow.left.arrow.right.circle.fill"
        }
    }

    private var amountPrefix: String {
        switch transaction.type {
        case .income: "+"
        case .expense: "-"
        case .transfer: ""
        }
    }

    private var categoryName: String {
        dataStore.getCategory(id: transaction.categoryId)?.name ?? "未分類"
    }

    private var categoryIcon: String {
        dataStore.getCategory(id: transaction.categoryId)?.icon ?? "ellipsis.circle"
    }

    private var projectAllocations: [(projectId: UUID, name: String, ratio: Int, amount: Int)] {
        transaction.allocations.compactMap { alloc in
            guard let project = dataStore.getProject(id: alloc.projectId) else { return nil }
            return (projectId: alloc.projectId, name: project.name, ratio: alloc.ratio, amount: alloc.amount)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    amountHeader
                    infoSection
                    if !transaction.lineItems.isEmpty {
                        lineItemsSection
                    }
                    if !projectAllocations.isEmpty {
                        allocationSection
                    }
                    if transaction.receiptImagePath != nil {
                        receiptImageSection
                    }
                    documentSection
                    if let cp = transaction.counterparty, !cp.isEmpty {
                        counterpartySection
                    }
                    if !transaction.memo.isEmpty {
                        memoSection
                    }
                    actionButtons
                }
                .padding(20)
            }
            .background(AppColors.surface)
            .navigationTitle("取引詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("編集") { showEditSheet = true }
                        .accessibilityLabel("編集")
                        .accessibilityHint("タップして取引を編集")
                }
            }
            .sheet(isPresented: $showEditSheet) {
                TransactionFormView(transaction: transaction)
            }
            .sheet(isPresented: $showReceiptPreview) {
                if let path = transaction.receiptImagePath,
                   let view = ReceiptImagePreviewView(fileName: path)
                {
                    view
                }
            }
            .navigationDestination(for: UUID.self) { projectId in
                ProjectDetailView(projectId: projectId)
            }
            .alert("取引を削除", isPresented: $showDeleteAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    dataStore.deleteTransaction(id: transaction.id)
                    dismiss()
                }
            } message: {
                Text("この取引を削除してもよろしいですか？")
            }
            .sheet(isPresented: $showRecurringHistory) {
                if let recurringId = transaction.recurringId {
                    RecurringHistoryView(recurringId: recurringId)
                }
            }
        }
    }

    // MARK: - Amount Header

    private var amountHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: typeIcon)
                    .font(.title3)
                    .foregroundStyle(typeColor)
                Text(transaction.type.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(typeColor)
            }

            Text("\(amountPrefix)\(formatCurrency(transaction.amount))")
                .font(.system(size: 32, weight: .bold).monospacedDigit())
                .foregroundStyle(typeColor)

            Text(formatDate(transaction.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(spacing: 0) {
            infoRow(label: "カテゴリ", icon: categoryIcon) {
                Text(categoryName)
                    .font(.subheadline.weight(.medium))
            }

            Divider().padding(.leading, 44)

            infoRow(label: "日付", icon: "calendar") {
                Text(formatDate(transaction.date))
                    .font(.subheadline)
            }

            if let recurringId = transaction.recurringId {
                Divider().padding(.leading, 44)
                recurringInfoRow(recurringId: recurringId)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func infoRow<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AppColors.primary)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func recurringInfoRow(recurringId: UUID) -> some View {
        let recurring = dataStore.getRecurring(id: recurringId)
        return Button {
            showRecurringHistory = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "repeat")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 24)
                Text("定期取引")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let recurring {
                    Text("\(recurring.name) (\(recurring.frequency.label))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.primary)
                } else {
                    Text("自動生成")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.primary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("定期取引: \(recurring?.name ?? "自動生成")")
        .accessibilityHint("タップして定期取引の履歴を表示")
    }

    // MARK: - Line Items Section

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .foregroundStyle(AppColors.primary)
                Text("明細 (\(transaction.lineItems.count)品目)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                let itemsTotal = transaction.lineItems.reduce(0) { $0 + $1.subtotal }
                Text(formatCurrency(itemsTotal))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(transaction.lineItems.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.name)
                        .font(.subheadline)

                    Spacer()

                    if item.quantity > 1 {
                        Text("\(item.quantity)×\(formatCurrency(item.unitPrice))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text(formatCurrency(item.subtotal))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Allocation Section

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.pie")
                    .foregroundStyle(AppColors.primary)
                Text("プロジェクト配分")
                    .font(.subheadline.weight(.medium))
            }

            ForEach(Array(projectAllocations.enumerated()), id: \.offset) { _, alloc in
                NavigationLink(value: alloc.projectId) {
                    HStack {
                        Text(alloc.name)
                            .font(.subheadline)
                            .foregroundStyle(Color(.label))
                        Spacer()
                        Text("\(alloc.ratio)%")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppColors.primary.opacity(0.1))
                            .foregroundStyle(AppColors.primary)
                            .clipShape(Capsule())
                        Text(formatCurrency(alloc.amount))
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(Color(.label))
                            .frame(width: 80, alignment: .trailing)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("\(alloc.name) \(alloc.ratio)パーセント \(formatCurrency(alloc.amount))")
                .accessibilityHint("タップしてプロジェクト詳細を表示")
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Receipt Image Section

    @ViewBuilder
    private var receiptImageSection: some View {
        if let path = transaction.receiptImagePath {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text.image")
                        .foregroundStyle(AppColors.primary)
                    Text("添付画像")
                        .font(.subheadline.weight(.medium))
                }

                Button {
                    showReceiptPreview = true
                } label: {
                    HStack(spacing: 12) {
                        if let image = ReceiptImageStore.loadImage(fileName: path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppColors.surface)
                                .frame(width: 60, height: 80)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundStyle(.tertiary)
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("タップして全画面表示")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.primary)
                            Text("ピンチで拡大・ダブルタップでズーム")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Legal Document Section

    private var documentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "archivebox")
                    .foregroundStyle(AppColors.primary)
                Text("書類管理")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(dataStore.documentCount(for: transaction.id))件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                TransactionDocumentsView(transaction: transaction)
            } label: {
                HStack {
                    Text("添付書類を管理")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Counterparty Section

    private var counterpartySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "building.2")
                    .foregroundStyle(AppColors.primary)
                Text("取引先")
                    .font(.subheadline.weight(.medium))
            }

            Text(transaction.counterparty ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Memo Section

    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(AppColors.primary)
                Text("メモ")
                    .font(.subheadline.weight(.medium))
            }

            Text(transaction.memo)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("この取引を削除")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppColors.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.error.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
