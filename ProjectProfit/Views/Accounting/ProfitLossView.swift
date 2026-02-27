import SwiftUI

struct ProfitLossView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var viewModel: AccountingReportViewModel?

    var body: some View {
        Group {
            if let viewModel, let report = viewModel.profitLoss {
                plContent(viewModel: viewModel, report: report)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("損益計算書")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let viewModel, let report = viewModel.profitLoss {
                ToolbarItem(placement: .primaryAction) {
                    ExportMenuButton(
                        csvGenerator: {
                            CSVExportService.exportProfitLossCSV(report: report)
                        },
                        pdfGenerator: {
                            PDFExportService.exportProfitLossPDF(report: report)
                        },
                        fileNamePrefix: "損益計算書"
                    )
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = AccountingReportViewModel(dataStore: dataStore)
            }
        }
    }

    private func plContent(viewModel: AccountingReportViewModel, report: ProfitLossReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearHeader(viewModel: viewModel)
                netIncomeCard(report: report)
                revenueSection(report: report)
                expenseSection(report: report)
            }
            .padding(16)
        }
        .onAppear { viewModel.refresh() }
    }

    private func yearHeader(viewModel: AccountingReportViewModel) -> some View {
        HStack {
            Button { viewModel.navigatePreviousYear() } label: {
                Image(systemName: "chevron.left").foregroundStyle(AppColors.primary)
            }
            Spacer()
            Text("\(String(viewModel.fiscalYear))年度")
                .font(.headline)
            Spacer()
            Button { viewModel.navigateNextYear() } label: {
                Image(systemName: "chevron.right").foregroundStyle(AppColors.primary)
            }
        }
    }

    private func netIncomeCard(report: ProfitLossReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("所得金額（事業所得）")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Text(formatCurrency(report.netIncome))
                .font(.system(size: 28, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
            HStack(spacing: 16) {
                Text("収入: \(formatCurrency(report.totalRevenue))")
                Text("経費: \(formatCurrency(report.totalExpenses))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(report.netIncome >= 0 ? AppColors.success : AppColors.error)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func revenueSection(report: ProfitLossReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "収入", total: report.totalRevenue, icon: "arrow.up.circle.fill", color: AppColors.success)
            ForEach(report.revenueItems) { item in
                itemRow(item: item)
            }
        }
    }

    private func expenseSection(report: ProfitLossReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "経費", total: report.totalExpenses, icon: "arrow.down.circle.fill", color: AppColors.error)
            ForEach(report.expenseItems) { item in
                itemRow(item: item)
            }
        }
    }

    private func sectionHeader(title: String, total: Int, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(formatCurrency(total))
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private func itemRow(item: ProfitLossItem) -> some View {
        HStack {
            Text(item.name)
                .font(.subheadline)
            Spacer()
            Text(formatCurrency(item.amount))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
