import SwiftUI

struct BalanceSheetView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var viewModel: AccountingReportViewModel?

    var body: some View {
        Group {
            if let viewModel, let report = viewModel.balanceSheet {
                bsContent(viewModel: viewModel, report: report)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("貸借対照表")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = AccountingReportViewModel(dataStore: dataStore)
            }
        }
    }

    private func bsContent(viewModel: AccountingReportViewModel, report: BalanceSheetReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearHeader(viewModel: viewModel)
                balanceCheck(report: report)
                assetSection(report: report)
                liabilitySection(report: report)
                equitySection(report: report)
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

    private func balanceCheck(report: BalanceSheetReport) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: report.isBalanced ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(report.isBalanced ? AppColors.success : AppColors.error)
                Text(report.isBalanced ? "資産 = 負債 + 資本" : "資産 ≠ 負債 + 資本")
                    .font(.subheadline.weight(.medium))
            }

            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("資産合計")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(report.totalAssets))
                        .font(.subheadline.weight(.semibold))
                }
                Text("=")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    Text("負債+資本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(report.liabilitiesAndEquity))
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background((report.isBalanced ? AppColors.success : AppColors.error).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func assetSection(report: BalanceSheetReport) -> some View {
        bsSection(title: "資産の部", items: report.assetItems, total: report.totalAssets, color: AppColors.primary)
    }

    private func liabilitySection(report: BalanceSheetReport) -> some View {
        bsSection(title: "負債の部", items: report.liabilityItems, total: report.totalLiabilities, color: AppColors.warning)
    }

    private func equitySection(report: BalanceSheetReport) -> some View {
        bsSection(title: "資本の部", items: report.equityItems, total: report.totalEquity, color: AppColors.success)
    }

    private func bsSection(title: String, items: [BalanceSheetItem], total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(formatCurrency(total))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }

            if items.isEmpty {
                Text("データなし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(items) { item in
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text(formatCurrency(item.balance))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
