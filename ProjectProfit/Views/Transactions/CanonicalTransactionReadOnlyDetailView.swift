import SwiftData
import SwiftUI

struct CanonicalTransactionReadOnlyDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let transaction: CanonicalTransactionListItem

    @State private var showReceiptPreview = false

    private var transactionHistoryUseCase: TransactionHistoryUseCase {
        TransactionHistoryUseCase(modelContext: modelContext)
    }

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
        transactionHistoryUseCase.categoryName(for: transaction.categoryId)
    }

    private var categoryIcon: String {
        transactionHistoryUseCase.categoryIcon(for: transaction.categoryId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if transaction.isCanonicalOnly {
                        canonicalBadge
                    }
                    amountHeader
                    infoSection
                    if !transaction.projectAllocations.isEmpty {
                        allocationSection
                    }
                    if !transaction.lineItems.isEmpty {
                        lineItemsSection
                    }
                    if transaction.receiptImagePath != nil {
                        receiptImageSection
                    }
                    sourceSection
                    if let counterparty = transaction.counterpartyName, !counterparty.isEmpty {
                        counterpartySection(counterparty: counterparty)
                    }
                    if !transaction.memo.isEmpty {
                        memoSection
                    }
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
            }
            .sheet(isPresented: $showReceiptPreview) {
                if let path = transaction.receiptImagePath,
                   let view = ReceiptImagePreviewView(fileName: path)
                {
                    view
                }
            }
        }
    }

    private var canonicalBadge: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checklist.checked")
                .foregroundStyle(AppColors.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("canonical 正本データ")
                    .font(.subheadline.weight(.semibold))
                Text("この取引は読み取り専用です。編集・削除はできません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(AppColors.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

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
                infoRow(label: "定期取引", icon: "repeat") {
                    Text(transactionHistoryUseCase.recurringDisplayName(for: recurringId) ?? "未設定")
                        .font(.subheadline)
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

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("案件配分")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(transaction.projectAllocations) { allocation in
                    HStack {
                        Text(allocation.projectName ?? allocation.projectId.uuidString)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(formatCurrency(allocation.amount))
                            .font(.subheadline.monospacedDigit())
                        if let ratio = allocation.ratio {
                            Text("\(ratio)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("明細")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(Array(transaction.lineItems.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.quantity) x \(formatCurrency(item.unitPrice))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(item.subtotal))
                            .font(.subheadline.monospacedDigit())
                    }
                    .padding(.vertical, 2)
                }
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

    private var receiptImageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("添付画像")
                .font(.headline)
            Button("画像を表示") {
                showReceiptPreview = true
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppColors.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("参照元")
                .font(.headline)

            sourceRow(label: "仕訳ID", value: transaction.journalId)
            sourceRow(label: "候補ID", value: transaction.sourceCandidateId)
            sourceRow(label: "証憑ID", value: transaction.sourceEvidenceId)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func sourceRow(label: String, value: UUID?) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value?.uuidString ?? "-")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func counterpartySection(counterparty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("取引先")
                .font(.headline)
            Text(counterparty)
                .font(.subheadline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private var memoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("メモ")
                .font(.headline)
            Text(transaction.memo)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
}
