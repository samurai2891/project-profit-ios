import SwiftUI

enum ReportSegment: String, CaseIterable {
    case annual = "年次レポート"
    case taxFiling = "確定申告"
}

struct ReportView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var viewModel: ReportViewModel?
    @State private var selectedSegment: ReportSegment = .annual

    var body: some View {
        VStack(spacing: 0) {
            Picker("レポート種別", selection: $selectedSegment) {
                ForEach(ReportSegment.allCases, id: \.self) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Group {
                switch selectedSegment {
                case .annual:
                    if let viewModel {
                        reportContent(viewModel: viewModel)
                    } else {
                        ProgressView()
                    }
                case .taxFiling:
                    AccountingHomeView()
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = ReportViewModel(dataStore: dataStore)
            }
        }
    }

    private func reportContent(viewModel: ReportViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                yearNavigator(viewModel: viewModel)
                overallSummaryCards(viewModel: viewModel)
                yoyComparisonSection(viewModel: viewModel)
                monthlyChartSection(viewModel: viewModel)
                expenseCategoriesSection(viewModel: viewModel)
                incomeCategoriesSection(viewModel: viewModel)
                projectRankingSection(viewModel: viewModel)
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("レポート")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            viewModel.reloadStartMonth()
        }
        .refreshable {
            viewModel.refresh()
        }
    }

    // MARK: - Year Navigator

    private func yearNavigator(viewModel: ReportViewModel) -> some View {
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
    }

    // MARK: - Overall Summary Cards

    private func overallSummaryCards(viewModel: ReportViewModel) -> some View {
        let summary = viewModel.overallSummary
        return VStack(spacing: 12) {
            // Net Profit
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: summary.netProfit >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    Text("年間純利益")
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
            .accessibilityLabel("年間純利益 \(formatCurrency(summary.netProfit))")

            HStack(spacing: 12) {
                metricCard(title: "収益合計", amount: summary.totalIncome, color: AppColors.success, icon: "arrow.up.circle.fill")
                metricCard(title: "経費合計", amount: summary.totalExpense, color: AppColors.error, icon: "arrow.down.circle.fill")
            }
        }
        .padding(.horizontal, 20)
    }

    private func metricCard(title: String, amount: Int, color: Color, icon: String) -> some View {
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

    // MARK: - YoY Comparison

    private func yoyComparisonSection(viewModel: ReportViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("前年比較")
                .font(.headline)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                yoyRow(label: "収益", change: viewModel.yoyIncomeChange)
                yoyRow(label: "経費", change: viewModel.yoyExpenseChange)
                yoyRow(label: "利益", change: viewModel.yoyProfitChange)
            }
            .padding(16)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 20)
        }
    }

    private func yoyRow(label: String, change: Int) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption)
                Text(formatCurrency(change))
                    .font(.subheadline.bold().monospacedDigit())
            }
            .foregroundStyle(changeColor(for: change, label: label))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) 前年比 \(formatCurrency(change))")
    }

    private func changeColor(for change: Int, label: String) -> Color {
        if change == 0 { return AppColors.muted }
        // For expenses, increase is bad (red), decrease is good (green)
        if label == "経費" {
            return change > 0 ? AppColors.error : AppColors.success
        }
        return change > 0 ? AppColors.success : AppColors.error
    }

    // MARK: - Monthly Chart

    private func monthlyChartSection(viewModel: ReportViewModel) -> some View {
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

                        Text(formatCurrency(m.profit))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(m.profit >= 0 ? AppColors.success : AppColors.error)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(monthNum)月 収益 \(formatCurrency(m.income)) 経費 \(formatCurrency(m.expense)) 利益 \(formatCurrency(m.profit))")
                }

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

    // MARK: - Expense Categories

    private func expenseCategoriesSection(viewModel: ReportViewModel) -> some View {
        let categories = viewModel.expenseCategories
        return VStack(alignment: .leading, spacing: 12) {
            Text("経費カテゴリ内訳")
                .font(.headline)
                .padding(.horizontal, 20)

            if categories.isEmpty {
                emptyCard(message: "経費データがありません")
                    .padding(.horizontal, 20)
            } else {
                categoryList(categories: categories)
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Income Categories

    private func incomeCategoriesSection(viewModel: ReportViewModel) -> some View {
        let categories = viewModel.incomeCategories
        return VStack(alignment: .leading, spacing: 12) {
            Text("収益カテゴリ内訳")
                .font(.headline)
                .padding(.horizontal, 20)

            if categories.isEmpty {
                emptyCard(message: "収益データがありません")
                    .padding(.horizontal, 20)
            } else {
                categoryList(categories: categories)
                    .padding(.horizontal, 20)
            }
        }
    }

    private func categoryList(categories: [CategorySummary]) -> some View {
        VStack(spacing: 10) {
            ForEach(categories) { cat in
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
                .accessibilityLabel("\(cat.categoryName) \(formatCurrency(cat.total)) \(String(format: "%.1f", cat.percentage))%")
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Project Ranking

    private func projectRankingSection(viewModel: ReportViewModel) -> some View {
        let projects = viewModel.projectRanking
        return VStack(alignment: .leading, spacing: 12) {
            Text("プロジェクト別損益")
                .font(.headline)
                .padding(.horizontal, 20)

            if projects.isEmpty {
                emptyCard(message: "プロジェクトデータがありません")
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.projectName)
                                    .font(.subheadline.weight(.medium))
                                HStack(spacing: 8) {
                                    Text("収益 \(formatCurrency(project.totalIncome))")
                                    Text("経費 \(formatCurrency(project.totalExpense))")
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(formatCurrency(project.profit))
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(project.profit >= 0 ? AppColors.success : AppColors.error)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(index + 1)位 \(project.projectName) 利益 \(formatCurrency(project.profit))")

                        if index < projects.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Empty Card

    private func emptyCard(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
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
