import SwiftUI

/// 定期取引の生成プレビュー+一括承認UI
struct RecurringPreviewView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var previewItems: [RecurringPreviewItem] = []
    @State private var selectedIds: Set<UUID> = []
    @State private var isProcessing = false
    @State private var processedCount: Int?

    private var recurringWorkflowUseCase: RecurringWorkflowUseCase {
        RecurringWorkflowUseCase(dataStore: dataStore)
    }

    var body: some View {
        NavigationStack {
            Group {
                if previewItems.isEmpty {
                    emptyState
                } else {
                    previewList
                }
            }
            .navigationTitle("定期取引プレビュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !previewItems.isEmpty {
                        Button("承認") { approveSelected() }
                            .disabled(selectedIds.isEmpty || isProcessing)
                    }
                }
            }
            .alert("処理完了", isPresented: .init(
                get: { processedCount != nil },
                set: { if !$0 { processedCount = nil } }
            )) {
                Button("OK") {
                    processedCount = nil
                    loadPreview()
                    if previewItems.isEmpty {
                        dismiss()
                    }
                }
            } message: {
                Text("\(processedCount ?? 0)件の取引を登録しました")
            }
        }
        .task {
            loadPreview()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("生成待ちの定期取引はありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Preview List

    private var previewList: some View {
        VStack(spacing: 0) {
            selectionControls
            List {
                ForEach(previewItems) { item in
                    previewRow(item)
                }
            }
            .listStyle(.plain)

            approvalBar
        }
    }

    private var selectionControls: some View {
        HStack {
            Button(selectedIds.count == previewItems.count ? "すべて解除" : "すべて選択") {
                if selectedIds.count == previewItems.count {
                    selectedIds.removeAll()
                } else {
                    selectedIds = Set(previewItems.map(\.id))
                }
            }
            .font(.subheadline)

            Spacer()

            Text("\(selectedIds.count)/\(previewItems.count)件選択中")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.surface)
    }

    private func previewRow(_ item: RecurringPreviewItem) -> some View {
        let isSelected = selectedIds.contains(item.id)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AppColors.primary : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.recurringName)
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 8) {
                    Label(formatDate(item.scheduledDate), systemImage: "calendar")
                    if item.isMonthlySpread {
                        Text("月次分割")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let projectName = item.projectName {
                    Label(projectName, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if item.allocationMode == .manual {
                    Text("手動配賦")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.warning.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            Text(formatCurrency(item.amount))
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(item.type == .income ? AppColors.success : AppColors.error)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedIds.remove(item.id)
            } else {
                selectedIds.insert(item.id)
            }
        }
    }

    private var approvalBar: some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    let selectedItems = previewItems.filter { selectedIds.contains($0.id) }
                    let totalIncome = selectedItems.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
                    let totalExpense = selectedItems.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }

                    if totalIncome > 0 {
                        Text("収入: \(formatCurrency(totalIncome))")
                            .font(.caption)
                            .foregroundStyle(AppColors.success)
                    }
                    if totalExpense > 0 {
                        Text("支出: \(formatCurrency(totalExpense))")
                            .font(.caption)
                            .foregroundStyle(AppColors.error)
                    }
                }

                Spacer()

                Button {
                    approveSelected()
                } label: {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("一括承認 (\(selectedIds.count)件)", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIds.isEmpty || isProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(AppColors.surface)
    }

    // MARK: - Actions

    private func loadPreview() {
        previewItems = recurringWorkflowUseCase.previewRecurringTransactions()
        selectedIds = Set(previewItems.map(\.id))
    }

    private func approveSelected() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            let count = await recurringWorkflowUseCase.approveRecurringItems(selectedIds, from: previewItems)
            isProcessing = false
            processedCount = count
        }
    }
}
