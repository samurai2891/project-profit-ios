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
    @State private var viewMode: ViewMode = .monthly

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }

    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        if viewMode == .monthly {
            let start = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: 1)) ?? Date()
            let end = endOfMonth(start)
            return (start, end)
        } else {
            return (startOfYear(currentYear), endOfYear(currentYear))
        }
    }

    private var summary: OverallSummary {
        dataStore.getOverallSummary(startDate: dateRange.start, endDate: dateRange.end)
    }

    private var topProjects: [ProjectSummary] {
        dataStore.getAllProjectSummaries()
            .sorted { $0.profit > $1.profit }
            .prefix(3)
            .map { $0 }
    }

    private var expenseCategories: [CategorySummary] {
        Array(dataStore.getCategorySummaries(type: .expense, startDate: dateRange.start, endDate: dateRange.end).prefix(5))
    }

    private var monthlySummaries: [MonthlySummary] {
        dataStore.getMonthlySummaries(year: currentYear)
    }

    private var periodLabel: String {
        viewMode == .monthly
            ? "\(currentYear)年\(currentMonth)月の収支状況"
            : "\(currentYear)年の収支状況"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                viewModeToggle
                summaryCards
                if viewMode == .yearly { monthlyChart }
                topProjectsSection
                expenseCategoriesSection
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("ダッシュボード")
        .refreshable {
            dataStore.loadData()
        }
        .navigationDestination(for: UUID.self) { projectId in
            if let project = dataStore.getProject(id: projectId) {
                ProjectDetailView(project: project)
            } else {
                ContentUnavailableView("プロジェクトが見つかりません", systemImage: "folder.badge.questionmark")
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(periodLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Toggle
    private var viewModeToggle: some View {
        Picker("表示", selection: $viewMode) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .accessibilityLabel("表示期間の切り替え")
        .accessibilityHint("月次または年次の表示を切り替えます")
    }

    // MARK: - Summary Cards
    private var summaryCards: some View {
        VStack(spacing: 12) {
            // Net Profit Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: summary.netProfit >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    Text("純利益")
                        .font(.subheadline)
                }
                .foregroundStyle(.white.opacity(0.8))

                Text(formatCurrency(summary.netProfit))
                    .font(.system(size: 32, weight: .bold))
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
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(formatCurrency(amount))")
    }

    // MARK: - Monthly Chart
    private var monthlyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    // MARK: - Top Projects
    private var topProjectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("利益トップ3")
                .font(.headline)
                .padding(.horizontal, 20)

            if topProjects.isEmpty {
                emptyCard(icon: "folder.fill", message: "プロジェクトがありません")
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(topProjects) { p in
                        NavigationLink(value: p.projectId) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.projectName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("収益 \(formatCurrency(p.totalIncome)) / 経費 \(formatCurrency(p.totalExpense))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(formatCurrency(p.profit))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(p.profit >= 0 ? AppColors.success : AppColors.error)
                                    Text("\(String(format: "%.1f", p.profitMargin))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(16)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(p.projectName) 利益 \(formatCurrency(p.profit)) 利益率 \(String(format: "%.1f", p.profitMargin))%")
                        .accessibilityHint("タップしてプロジェクト詳細を表示")
                        .accessibilityAddTraits(.isButton)
                        Divider()
                    }
                }
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Expense Categories
    private var expenseCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                                    .font(.subheadline)
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
