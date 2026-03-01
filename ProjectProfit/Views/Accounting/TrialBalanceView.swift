import SwiftUI

struct TrialBalanceView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var viewModel: AccountingReportViewModel?

    var body: some View {
        Group {
            if let viewModel, let report = viewModel.trialBalance {
                trialBalanceContent(viewModel: viewModel, report: report)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("試算表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let viewModel, let report = viewModel.trialBalance {
                ToolbarItem(placement: .primaryAction) {
                    ExportMenuButton(
                        csvGenerator: {
                            ReportCSVExportService.exportTrialBalanceCSV(rows: report.rows)
                        },
                        pdfGenerator: {
                            PDFExportService.exportTrialBalancePDF(report: report)
                        },
                        fileNamePrefix: "試算表"
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

    private func trialBalanceContent(viewModel: AccountingReportViewModel, report: TrialBalanceReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                yearHeader(viewModel: viewModel)
                balanceStatus(report: report)
                reportTable(report: report)
                totalsRow(report: report)
            }
            .padding(16)
        }
        .onAppear { viewModel.refresh() }
    }

    private func yearHeader(viewModel: AccountingReportViewModel) -> some View {
        HStack {
            Button { viewModel.navigatePreviousYear() } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(AppColors.primary)
            }
            Spacer()
            Text("\(String(viewModel.fiscalYear))年度")
                .font(.headline)
            Spacer()
            Button { viewModel.navigateNextYear() } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.primary)
            }
        }
    }

    private func balanceStatus(report: TrialBalanceReport) -> some View {
        HStack(spacing: 8) {
            Image(systemName: report.isBalanced ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(report.isBalanced ? AppColors.success : AppColors.error)
            Text(report.isBalanced ? "貸借一致" : "貸借不一致")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(report.isBalanced ? AppColors.success : AppColors.error)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(12)
        .background((report.isBalanced ? AppColors.success : AppColors.error).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func reportTable(report: TrialBalanceReport) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("科目")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("借方")
                    .frame(width: 80, alignment: .trailing)
                Text("貸方")
                    .frame(width: 80, alignment: .trailing)
                Text("残高")
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.surface)

            ForEach(report.rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.caption)
                        Text(row.code)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(row.debit > 0 ? formatCurrency(row.debit) : "")
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Text(row.credit > 0 ? formatCurrency(row.credit) : "")
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                    Text(formatCurrency(row.balance))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider().padding(.horizontal, 12)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func totalsRow(report: TrialBalanceReport) -> some View {
        HStack {
            Text("合計")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatCurrency(report.debitTotal))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Text(formatCurrency(report.creditTotal))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 80, alignment: .trailing)
            Spacer()
                .frame(width: 80)
        }
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
