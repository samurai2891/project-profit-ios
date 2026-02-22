import SwiftData
import SwiftUI

// MARK: - Filter Status

enum FilterStatus: String, CaseIterable, Identifiable {
    case all = "すべて"
    case active = "進行中"
    case completed = "完了"
    case paused = "保留"

    var id: String { rawValue }
}

// MARK: - ProjectsView

struct ProjectsView: View {
    @Environment(DataStore.self) private var dataStore

    @State private var viewModel: ProjectsViewModel?
    @State private var showAddSheet = false
    @State private var projectToDelete: PPProject?
    @State private var showDeleteConfirmation = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedProjectIds: Set<UUID> = []
    @State private var showBatchDeleteConfirmation = false

    private var resolvedViewModel: ProjectsViewModel {
        viewModel ?? ProjectsViewModel(dataStore: dataStore)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if !resolvedViewModel.hasProjects {
                emptyStateView
            } else {
                projectListContent
            }

            if editMode == .active && !selectedProjectIds.isEmpty {
                batchDeleteBar
            } else if editMode == .inactive {
                fabButton
            }
        }
        .navigationTitle("プロジェクト")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editMode == .active {
                    Button("完了") {
                        withAnimation {
                            editMode = .inactive
                            selectedProjectIds.removeAll()
                        }
                    }
                } else {
                    Button("選択") {
                        withAnimation {
                            selectedProjectIds.removeAll()
                            editMode = .active
                        }
                    }
                    .disabled(!resolvedViewModel.hasProjects)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ProjectFormView(project: nil)
        }
        .alert("プロジェクトを削除", isPresented: $showDeleteConfirmation) {
            deleteAlertActions
        } message: {
            Text("「\(projectToDelete?.name ?? "")」を削除しますか？関連する取引も削除されます。この操作は取り消せません。")
        }
        .alert("プロジェクトを削除", isPresented: $showBatchDeleteConfirmation) {
            batchDeleteAlertActions
        } message: {
            Text("\(selectedProjectIds.count)件のプロジェクトを削除しますか？関連する取引も削除されます。この操作は取り消せません。")
        }
        .task {
            if viewModel == nil {
                viewModel = ProjectsViewModel(dataStore: dataStore)
            }
        }
    }
}

// MARK: - Subviews

private extension ProjectsView {

    var filterTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterStatus.allCases) { status in
                    filterChip(for: status)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    func filterChip(for status: FilterStatus) -> some View {
        let isSelected = resolvedViewModel.filterStatus == status
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel?.filterStatus = status
            }
        } label: {
            Text(status.rawValue)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? AppColors.primary.opacity(0.15)
                        : Color(.systemGray6)
                )
                .foregroundStyle(isSelected ? AppColors.primary : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? AppColors.primary : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("フィルター: \(status.rawValue)")
        .accessibilityHint("タップして\(status.rawValue)のプロジェクトを表示")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    var projectListContent: some View {
        VStack(spacing: 0) {
            filterTabsView

            if resolvedViewModel.filteredProjects.isEmpty {
                filteredEmptyView
            } else {
                List(selection: $selectedProjectIds) {
                    ForEach(resolvedViewModel.filteredProjects) { project in
                        NavigationLink(destination: ProjectDetailView(projectId: project.id)) {
                            ProjectCardView(project: project)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                projectToDelete = project
                                showDeleteConfirmation = true
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .environment(\.editMode, $editMode)
            }
        }
    }

    var filteredEmptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("該当するプロジェクトがありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(AppColors.primary.opacity(0.6))

            Text("プロジェクトがありません")
                .font(.title3)
                .fontWeight(.semibold)

            Text("プロジェクトを追加して収支を管理しましょう")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showAddSheet = true
            } label: {
                Label("プロジェクトを追加", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppColors.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .accessibilityLabel("プロジェクトを追加")
            .accessibilityHint("タップして新しいプロジェクトを作成")
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    var fabButton: some View {
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
                .shadow(color: AppColors.primary.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("新規追加")
        .accessibilityHint("タップして新しいプロジェクトを作成")
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    var batchDeleteBar: some View {
        Button(role: .destructive) {
            showBatchDeleteConfirmation = true
        } label: {
            Label("\(selectedProjectIds.count)件を削除", systemImage: "trash")
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppColors.error)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(color: AppColors.error.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .accessibilityLabel("\(selectedProjectIds.count)件のプロジェクトを削除")
    }

    @ViewBuilder
    var batchDeleteAlertActions: some View {
        Button("キャンセル", role: .cancel) {}
        Button("\(selectedProjectIds.count)件を削除", role: .destructive) {
            withAnimation {
                viewModel?.deleteProjects(ids: selectedProjectIds)
                selectedProjectIds.removeAll()
                editMode = .inactive
            }
        }
    }

    @ViewBuilder
    var deleteAlertActions: some View {
        Button("キャンセル", role: .cancel) {
            projectToDelete = nil
        }
        Button("削除", role: .destructive) {
            if let project = projectToDelete {
                withAnimation {
                    viewModel?.deleteProject(id: project.id)
                }
            }
            projectToDelete = nil
        }
    }
}

// MARK: - ProjectCardView

private struct ProjectCardView: View {
    let project: PPProject

    @Environment(DataStore.self) private var dataStore

    private var summary: ProjectSummary? {
        dataStore.getProjectSummary(projectId: project.id)
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

    private var profitMargin: Double {
        summary?.profitMargin ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            descriptionRow
            financialSummaryRow
            profitMarginBar
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name) \(statusLabel(project.status)) 収入 \(formatCurrency(projectIncome)) 支出 \(formatCurrency(projectExpense)) 利益 \(formatCurrency(projectProfit)) 利益率 \(Int(profitMargin))%")
        .accessibilityHint("タップしてプロジェクト詳細を表示")
    }

    private func statusLabel(_ status: ProjectStatus) -> String {
        switch status {
        case .active: return "進行中"
        case .completed: return "完了"
        case .paused: return "保留"
        }
    }
}

// MARK: - ProjectCardView Subviews

private extension ProjectCardView {

    var headerRow: some View {
        HStack(alignment: .center) {
            Text(project.name)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            StatusBadge(status: project.status)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    var descriptionRow: some View {
        if !project.projectDescription.isEmpty {
            Text(project.projectDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    var financialSummaryRow: some View {
        HStack(spacing: 16) {
            financialItem(label: "収入", amount: projectIncome, color: AppColors.success)
            financialItem(label: "支出", amount: projectExpense, color: AppColors.error)
            financialItem(
                label: "利益",
                amount: projectProfit,
                color: projectProfit >= 0 ? AppColors.success : AppColors.error
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("収入 \(formatCurrency(projectIncome)) 支出 \(formatCurrency(projectExpense)) 利益 \(formatCurrency(projectProfit))")
    }

    func financialItem(label: String, amount: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatCurrency(amount))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var profitMarginBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("利益率")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(profitMargin))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(profitMargin >= 0 ? AppColors.success : AppColors.error)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(profitMargin >= 0 ? AppColors.success : AppColors.error)
                        .frame(
                            width: max(
                                0,
                                min(geometry.size.width, geometry.size.width * abs(profitMargin) / 100)
                            ),
                            height: 6
                        )
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("利益率")
        .accessibilityValue("\(Int(profitMargin))%")
    }

}

// MARK: - StatusBadge

struct StatusBadge: View {
    let status: ProjectStatus

    private var label: String {
        switch status {
        case .active: return "進行中"
        case .completed: return "完了"
        case .paused: return "保留"
        }
    }

    private var color: Color {
        switch status {
        case .active: return AppColors.success
        case .completed: return .blue
        case .paused: return AppColors.warning
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("ステータス: \(label)")
    }
}

// MARK: - Preview

#Preview {
    ProjectsView()
        .environment(DataStore(modelContext: try! ModelContext(ModelContainer(for: PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self))))
}
