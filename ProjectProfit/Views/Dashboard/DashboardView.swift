import SwiftData
import SwiftUI

enum ViewMode: String, CaseIterable {
    case monthly
    case yearly

    var label: String {
        switch self {
        case .monthly: "月次"
        case .yearly: "年次"
        }
    }
}

struct DashboardView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: DashboardViewModel?
    @State private var showAddProjectSheet = false

    var body: some View {
        Group {
            if let viewModel {
                dashboardContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task(id: dataRevisionKey) {
            if viewModel == nil {
                viewModel = DashboardViewModel(modelContext: modelContext)
            } else {
                viewModel?.refresh()
            }
        }
    }

    private var dataRevisionKey: String {
        let transactionStamp = dataStore.transactions.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let projectStamp = dataStore.projects.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let journalStamp = dataStore.journalEntries.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let categorySignature = dataStore.categories
            .map { "\($0.id):\($0.name):\($0.archivedAt?.timeIntervalSince1970 ?? 0):\($0.linkedAccountId ?? "")" }
            .sorted()
            .joined(separator: "|")
        return [
            String(dataStore.transactions.count),
            String(dataStore.projects.count),
            String(dataStore.categories.count),
            String(dataStore.journalEntries.count),
            String(transactionStamp),
            String(projectStamp),
            categorySignature,
            String(journalStamp),
        ].joined(separator: ":")
    }

    private func dashboardContent(viewModel: DashboardViewModel) -> some View {
        @Bindable var vm = viewModel
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(viewModel: viewModel)
                yearNavigator(viewModel: viewModel)
                viewModeToggle(viewModel: viewModel)
                if viewModel.viewMode == .monthly {
                    monthSelector(viewModel: viewModel)
                }
                summaryCards(viewModel: viewModel)
                if viewModel.viewMode == .yearly { monthlyChart(viewModel: viewModel) }
                activeProjectsSection(viewModel: viewModel)
                expenseCategoriesSection(viewModel: viewModel)
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("ダッシュボード")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            viewModel.reloadStartMonth()
        }
        .refreshable {
            viewModel.refresh()
        }
        .navigationDestination(for: UUID.self) { projectId in
            ProjectDetailView(projectId: projectId)
        }
        .sheet(isPresented: $showAddProjectSheet) {
            ProjectFormView(project: nil)
        }
    }

    // MARK: - Header
    private func headerSection(viewModel: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.periodLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Year Navigator
    private func yearNavigator(viewModel: DashboardViewModel) -> some View {
        HStack {
            Button {
                viewModel.navigatePreviousYear()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
            }
            .accessibilityLabel("前の年度")
            .accessibilityHint("タップして前の年度を表示")

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.fiscalYearLabelText)
                    .font(.headline)
                Text(viewModel.fiscalYearPeriodText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.navigateNextYear()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(viewModel.canNavigateNext ? AppColors.primary : AppColors.muted)
            }
            .disabled(!viewModel.canNavigateNext)
            .accessibilityLabel("次の年度")
            .accessibilityHint(viewModel.canNavigateNext ? "タップして次の年度を表示" : "現在の年度です")
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("年度切替 \(viewModel.fiscalYearLabelText)")
    }

    // MARK: - Toggle
    private func viewModeToggle(viewModel: DashboardViewModel) -> some View {
        @Bindable var vm = viewModel
        return Picker("表示", selection: $vm.viewMode) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .accessibilityLabel("表示期間の切り替え")
        .accessibilityHint("月次または年次の表示を切り替えます")
    }

    // MARK: - Month Selector
    private func monthSelector(viewModel: DashboardViewModel) -> some View {
        let months = viewModel.fiscalYearMonths
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(months, id: \.month) { pair in
                        let isSelected = pair.month == viewModel.selectedMonth
                        Button {
                            viewModel.selectedMonth = pair.month
                        } label: {
                            Text("\(pair.month)月")
                                .font(.subheadline.weight(isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? AppColors.primary : AppColors.surface)
                                .clipShape(Capsule())
                        }
                        .id(pair.month)
                        .accessibilityLabel("\(pair.month)月")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                proxy.scrollTo(viewModel.selectedMonth, anchor: .center)
            }
        }
    }

    // MARK: - Summary Cards
    private func summaryCards(viewModel: DashboardViewModel) -> some View {
        let summary = viewModel.summary
        return VStack(spacing: 12) {
            // Net Profit Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: summary.netProfit >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    Text("純利益")
                        .font(.subheadline)
                }
                .foregroundStyle(.white.opacity(0.8))

                Text(formatCurrency(summary.netProfit))
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)

                Text("利益率: \(String(format: "%.1f", summary.profitMargin))%")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(summary.netProfit >= 0 ? AppColors.success : AppColors.error)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("純利益 \(formatCurrency(summary.netProfit)) 利益率 \(String(format: "%.1f", summary.profitMargin))%")
            .accessibilityValue(summary.netProfit >= 0 ? "黒字" : "赤字")

            // Income & Expense
            HStack(spacing: 12) {
                summaryCard(title: "収益", amount: summary.totalIncome, color: AppColors.success, icon: "arrow.up.circle.fill")
                summaryCard(title: "経費", amount: summary.totalExpense, color: AppColors.error, icon: "arrow.down.circle.fill")
            }
        }
        .padding(.horizontal, 20)
    }

    private func summaryCard(title: String, amount: Int, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(formatCurrency(amount))
                .font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(formatCurrency(amount))")
    }

    // MARK: - Monthly Chart
    private func monthlyChart(viewModel: DashboardViewModel) -> some View {
        let monthlySummaries = viewModel.monthlySummaries
        return VStack(alignment: .leading, spacing: 12) {
            Text("月別推移")
                .font(.headline)
                .padding(.horizontal, 20)

            VStack(spacing: 6) {
                let maxValue = max(monthlySummaries.map { max($0.income, $0.expense) }.max() ?? 1, 1)

                ForEach(monthlySummaries) { m in
                    let monthNum = Int(m.month.suffix(2)) ?? 0
                    HStack(spacing: 8) {
                        Text("\(monthNum)月")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .trailing)

                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                Rectangle()
                                    .fill(AppColors.success)
                                    .frame(width: geo.size.width * CGFloat(m.income) / CGFloat(maxValue))
                                Rectangle()
                                    .fill(AppColors.error)
                                    .frame(width: geo.size.width * CGFloat(m.expense) / CGFloat(maxValue))
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(height: 12)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(monthNum)月 収益 \(formatCurrency(m.income)) 経費 \(formatCurrency(m.expense))")
                }

                // Legend
                HStack(spacing: 16) {
                    legendItem(color: AppColors.success, label: "収益")
                    legendItem(color: AppColors.error, label: "経費")
                }
                .padding(.top, 8)
            }
            .padding(16)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Active Projects
    private func activeProjectsSection(viewModel: DashboardViewModel) -> some View {
        let activeProjects = viewModel.activeProjects
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("進行中のプロジェクト")
                    .font(.headline)
                Text("\(activeProjects.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { showAddProjectSheet = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppColors.primary)
                }
                .accessibilityLabel("新規プロジェクト")
                .accessibilityHint("タップして新しいプロジェクトを作成")
            }
            .padding(.horizontal, 20)

            if activeProjects.isEmpty {
                emptyCard(icon: "folder.badge.plus", message: "進行中のプロジェクトがありません")
                    .padding(.horizontal, 20)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(activeProjects.enumerated()), id: \.element.id) { index, project in
                        NavigationLink(value: project.projectId) {
                            activeProjectRow(project: project)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(project.projectName) 利益 \(formatCurrency(project.profit))")
                        .accessibilityHint("タップしてプロジェクト詳細を表示")
                        .accessibilityAddTraits(.isButton)
                        if index < activeProjects.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            }
        }
    }

    private func activeProjectRow(project: ProjectSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.projectName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("収益 \(formatCurrency(project.totalIncome)) / 経費 \(formatCurrency(project.totalExpense))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(project.profit))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(project.profit >= 0 ? AppColors.success : AppColors.error)
                Text("\(String(format: "%.1f", project.profitMargin))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    // MARK: - Expense Categories
    private func expenseCategoriesSection(viewModel: DashboardViewModel) -> some View {
        let expenseCategories = viewModel.expenseCategories
        return VStack(alignment: .leading, spacing: 12) {
            Text("経費カテゴリ")
                .font(.headline)
                .padding(.horizontal, 20)

            if expenseCategories.isEmpty {
                emptyCard(icon: "chart.pie.fill", message: "経費データがありません")
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(expenseCategories) { cat in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(cat.categoryName)
                                    .font(.subheadline)
                                Spacer()
                                Text(formatCurrency(cat.total))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: cat.percentage, total: 100)
                                .tint(AppColors.primary)
                            Text("\(String(format: "%.1f", cat.percentage))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(cat.categoryName) \(formatCurrency(cat.total))")
                        .accessibilityValue("経費全体の\(String(format: "%.1f", cat.percentage))%")
                    }
                }
                .padding(16)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            }
        }
    }

    private func emptyCard(icon: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
