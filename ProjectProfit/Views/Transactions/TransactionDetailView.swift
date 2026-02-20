import SwiftUI

struct TransactionDetailView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    let transaction: PPTransaction

    @State private var showReceiptPreview = false
    @State private var showEditSheet = false
    @State private var showDeleteAlert = false

    private var isIncome: Bool { transaction.type == .income }

    private var categoryName: String {
        dataStore.getCategory(id: transaction.categoryId)?.name ?? "未分類"
    }

    private var categoryIcon: String {
        dataStore.getCategory(id: transaction.categoryId)?.icon ?? "ellipsis.circle"
    }

    private var projectAllocations: [(name: String, ratio: Int, amount: Int)] {
        transaction.allocations.compactMap { alloc in
            guard let project = dataStore.getProject(id: alloc.projectId) else { return nil }
            return (name: project.name, ratio: alloc.ratio, amount: alloc.amount)
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
            .alert("取引を削除", isPresented: $showDeleteAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    dataStore.deleteTransaction(id: transaction.id)
                    dismiss()
                }
            } message: {
                Text("この取引を削除してもよろしいですか？")
            }
        }
    }

    // MARK: - Amount Header

    private var amountHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isIncome ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isIncome ? AppColors.success : AppColors.error)
                Text(isIncome ? "収益" : "経費")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isIncome ? AppColors.success : AppColors.error)
            }

            Text("\(isIncome ? "+" : "-")\(formatCurrency(transaction.amount))")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(isIncome ? AppColors.success : AppColors.error)

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

            if transaction.recurringId != nil {
                Divider().padding(.leading, 44)
                infoRow(label: "定期取引", icon: "repeat") {
                    Text("自動生成")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColors.primary.opacity(0.1))
                        .foregroundStyle(AppColors.primary)
                        .clipShape(Capsule())
                }
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
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(transaction.lineItems.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.name)
                        .font(.subheadline)

                    Spacer()

                    if item.quantity > 1 {
                        Text("\(item.quantity)×\(formatCurrency(item.unitPrice))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(formatCurrency(item.subtotal))
                        .font(.subheadline.weight(.medium))
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
                HStack {
                    Text(alloc.name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(alloc.ratio)%")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColors.primary.opacity(0.1))
                        .foregroundStyle(AppColors.primary)
                        .clipShape(Capsule())
                    Text(formatCurrency(alloc.amount))
                        .font(.subheadline.weight(.medium))
                        .frame(width: 80, alignment: .trailing)
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

    // MARK: - Receipt Image Section

    @ViewBuilder
    private var receiptImageSection: some View {
        if let path = transaction.receiptImagePath {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.text.image")
                        .foregroundStyle(AppColors.primary)
                    Text("レシート画像")
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
