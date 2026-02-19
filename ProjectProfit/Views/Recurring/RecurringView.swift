import SwiftData
import SwiftUI

struct RecurringView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: RecurringViewModel?
    @State private var showFormSheet = false
    @State private var editingRecurring: PPRecurringTransaction? = nil
    @State private var showSkipAlert = false
    @State private var skipTarget: PPRecurringTransaction? = nil
    @State private var showDeleteAlert = false
    @State private var deleteTarget: PPRecurringTransaction? = nil
    @State private var notificationTarget: PPRecurringTransaction? = nil
    @State private var historyTarget: PPRecurringTransaction? = nil

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.surface
                    .ignoresSafeArea()

                if let vm = viewModel {
                    if vm.hasRecurringTransactions {
                        contentView(vm)
                    } else {
                        emptyStateView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("定期取引")
                        .font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showFormSheet = true }) {
                        Image(systemName: "plus")
                            .foregroundStyle(AppColors.primary)
                    }
                }
            }
            .sheet(isPresented: $showFormSheet, onDismiss: { editingRecurring = nil }) {
                RecurringFormView(recurring: editingRecurring)
                    .environment(dataStore)
            }
            .alert("次回をスキップ", isPresented: $showSkipAlert) {
                Button("キャンセル", role: .cancel) {
                    skipTarget = nil
                }
                Button("スキップ", role: .destructive) {
                    if let target = skipTarget, let vm = viewModel {
                        vm.confirmSkip(target)
                    }
                    skipTarget = nil
                }
            } message: {
                if let target = skipTarget {
                    Text("\(target.name)の次回登録をスキップしますか？")
                }
            }
            .alert("削除の確認", isPresented: $showDeleteAlert) {
                Button("キャンセル", role: .cancel) {
                    deleteTarget = nil
                }
                Button("削除", role: .destructive) {
                    if let target = deleteTarget, let vm = viewModel {
                        vm.deleteRecurring(target)
                    }
                    deleteTarget = nil
                }
            } message: {
                if let target = deleteTarget {
                    Text("\(target.name)を削除しますか？この操作は取り消せません。")
                }
            }
            .sheet(item: $notificationTarget) { target in
                NotificationSettingsView(
                    currentTiming: target.notificationTiming,
                    onSave: { timing in
                        viewModel?.updateNotificationTiming(for: target, timing: timing)
                    }
                )
            }
            .sheet(item: $historyTarget) { target in
                RecurringHistoryView(recurringId: target.id)
                    .environment(dataStore)
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = RecurringViewModel(dataStore: dataStore)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("定期取引がありません")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("+ボタンから定期取引を追加できます")
                .font(.subheadline)
                .foregroundStyle(AppColors.muted)
        }
        .padding()
    }

    // MARK: - Content

    private func contentView(_ vm: RecurringViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard(vm)
                recurringList(vm)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Summary Card

    private func summaryCard(_ vm: RecurringViewModel) -> some View {
        HStack(spacing: 0) {
            summaryItem(label: "登録数", value: "\(vm.totalCount)")
            Divider()
                .frame(height: 40)
            summaryItem(label: "有効", value: "\(vm.activeCount)")
            Divider()
                .frame(height: 40)
            summaryItem(label: "月額合計", value: formatCurrency(vm.monthlyTotal))
        }
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func summaryItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recurring List

    private func recurringList(_ vm: RecurringViewModel) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(vm.recurringTransactions) { recurring in
                recurringCard(recurring, vm: vm)
            }
        }
    }

    // MARK: - Recurring Card

    private func recurringCard(_ recurring: PPRecurringTransaction, vm: RecurringViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: type indicator + name + amount + badge
            HStack(spacing: 10) {
                // Type indicator bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(recurring.type == .expense ? AppColors.error : AppColors.success)
                    .frame(width: 4, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(recurring.name)
                            .font(.subheadline.weight(.semibold))

                        if !recurring.isActive {
                            Text("停止中")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.muted.opacity(0.2))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Text(formatCurrency(recurring.amount))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(
                                recurring.type == .expense
                                    ? AppColors.error
                                    : AppColors.success
                            )
                    }

                    // Details row
                    HStack(spacing: 8) {
                        Text(vm.frequencyLabel(recurring))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let categoryName = vm.categoryName(for: recurring.categoryId) {
                            Text(categoryName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !recurring.allocations.isEmpty {
                            let names = vm.projectNamesText(recurring.allocations)
                            Text(names)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Next registration date banner
            if recurring.isActive {
                nextRegistrationBanner(recurring)
            }

            // Action buttons row
            actionButtonsRow(recurring, vm: vm)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            editingRecurring = recurring
            showFormSheet = true
        }
    }

    // MARK: - Next Registration Banner

    @ViewBuilder
    private func nextRegistrationBanner(_ recurring: PPRecurringTransaction) -> some View {
        if let info = getNextRegistrationDate(
            frequency: recurring.frequency,
            dayOfMonth: recurring.dayOfMonth,
            monthOfYear: recurring.monthOfYear,
            isActive: recurring.isActive,
            lastGeneratedDate: recurring.lastGeneratedDate
        ) {
            let isSkipped = recurring.skipDates.contains {
                Calendar.current.isDate($0, inSameDayAs: info.date)
            }
            let isWarning = info.daysUntil <= 3

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)

                if isSkipped {
                    Text("次回スキップ")
                        .font(.caption)
                        .strikethrough()
                } else {
                    Text("次回登録: \(formatDateShort(info.date))")
                        .font(.caption)

                    if info.daysUntil == 0 {
                        Text("（今日）")
                            .font(.caption)
                    } else if info.daysUntil == 1 {
                        Text("（明日）")
                            .font(.caption)
                    } else {
                        Text("（\(info.daysUntil)日後）")
                            .font(.caption)
                    }
                }

                Spacer()
            }
            .foregroundStyle(
                isSkipped
                    ? AppColors.muted
                    : (isWarning ? AppColors.warning : .secondary)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                (isWarning && !isSkipped ? AppColors.warning.opacity(0.08) : Color.clear)
            )
        }
    }

    // MARK: - Action Buttons Row

    private func actionButtonsRow(_ recurring: PPRecurringTransaction, vm: RecurringViewModel) -> some View {
        HStack(spacing: 0) {
            actionButton(
                icon: "forward.end",
                label: "スキップ",
                color: .secondary
            ) {
                skipTarget = recurring
                showSkipAlert = true
            }

            actionButton(
                icon: "bell",
                label: "通知",
                color: .secondary
            ) {
                notificationTarget = recurring
            }

            actionButton(
                icon: "clock.arrow.circlepath",
                label: "履歴",
                color: .secondary
            ) {
                historyTarget = recurring
            }

            actionButton(
                icon: recurring.isActive ? "pause.circle" : "play.circle",
                label: recurring.isActive ? "停止" : "再開",
                color: recurring.isActive ? AppColors.warning : AppColors.success
            ) {
                vm.toggleActive(recurring)
            }

            actionButton(
                icon: "trash",
                label: "削除",
                color: AppColors.error
            ) {
                deleteTarget = recurring
                showDeleteAlert = true
            }
        }
    }

    private func actionButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RecurringView()
        .environment(DataStore(modelContext: try! ModelContext(ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))))
}
