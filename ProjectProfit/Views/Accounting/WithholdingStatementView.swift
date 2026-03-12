import SwiftData
import SwiftUI

struct WithholdingStatementView: View {
    fileprivate static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    @Environment(\.modelContext) private var modelContext
    private let initialFiscalYear: Int?
    @State private var viewModel: WithholdingStatementViewModel?
    @State private var shareURL: URL?
    @State private var showShareSheet = false

    init(initialFiscalYear: Int? = nil) {
        self.initialFiscalYear = initialFiscalYear
    }

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("支払調書")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                let createdViewModel = WithholdingStatementViewModel(
                    modelContext: modelContext,
                    exporter: { format, options in
                        try ExportCoordinator.export(
                            target: .withholdingStatement,
                            format: format,
                            fiscalYear: options.annualSummary.fiscalYear,
                            modelContext: modelContext,
                            withholdingStatementOptions: options
                        )
                    }
                )
                if let initialFiscalYear {
                    createdViewModel.fiscalYear = initialFiscalYear
                }
                createdViewModel.generatePreview()
                viewModel = createdViewModel
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ShareSheetView(activityItems: [shareURL])
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: WithholdingStatementViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection(viewModel: viewModel)
                Button("集計プレビュー生成") {
                    viewModel.generatePreview()
                }
                .buttonStyle(.borderedProminent)

                if let summary = viewModel.annualSummary {
                    summarySection(summary)
                    annualExportButtons(viewModel: viewModel)
                    documentList(summary.documents, viewModel: viewModel)
                } else if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppColors.error)
                }
            }
            .padding(20)
        }
        .alert(item: Binding(
            get: { viewModel.exportResult },
            set: { viewModel.exportResult = $0 }
        )) { result in
            switch result {
            case .success(let url):
                return Alert(
                    title: Text("エクスポート完了"),
                    message: Text("ファイルを保存しました"),
                    primaryButton: .default(Text("共有")) {
                        shareURL = url
                        showShareSheet = true
                    },
                    secondaryButton: .cancel(Text("閉じる"))
                )
            case .failure(let message):
                return Alert(
                    title: Text("エクスポートエラー"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func settingsSection(viewModel: WithholdingStatementViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("設定")
                .font(.headline)

            HStack {
                Text("年度")
                Spacer()
                Picker("年度", selection: Binding(
                    get: { viewModel.fiscalYear },
                    set: { viewModel.fiscalYear = $0 }
                )) {
                    ForEach((2020...currentFiscalYear(startMonth: FiscalYearSettings.startMonth)).reversed(), id: \.self) { year in
                        Text("\(year)年").tag(year)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func summarySection(_ summary: WithholdingStatementAnnualSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("年次一覧")
                .font(.headline)
            summaryRow("支払先", "\(summary.documentCount)件")
            summaryRow("支払件数", "\(summary.paymentCount)件")
            summaryRow("支払総額", formatCurrency(summary.totalGrossAmount))
            summaryRow("源泉徴収税額", formatCurrency(summary.totalWithholdingTaxAmount))
            summaryRow("実支払額", formatCurrency(summary.totalNetAmount))
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func annualExportButtons(viewModel: WithholdingStatementViewModel) -> some View {
        VStack(spacing: 8) {
            Button("年次一覧をCSV出力") {
                viewModel.exportAnnual(format: .csv)
            }
            .buttonStyle(.bordered)

            Button("年次一覧をPDF出力") {
                viewModel.exportAnnual(format: .pdf)
            }
            .buttonStyle(.bordered)
        }
    }

    private func documentList(
        _ documents: [WithholdingStatementDocument],
        viewModel: WithholdingStatementViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("支払先別")
                .font(.headline)

            ForEach(documents) { document in
                NavigationLink {
                    WithholdingStatementDetailView(
                        document: document,
                        viewModel: viewModel
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(document.counterpartyName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(document.withholdingTaxCode.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("支払総額 \(formatCurrency(document.totalGrossAmount))")
                            Spacer()
                            Text("源泉 \(formatCurrency(document.totalWithholdingTaxAmount))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        return Self.currencyFormatter.string(from: number) ?? number.stringValue
    }
}

struct WithholdingStatementDetailView: View {
    let document: WithholdingStatementDocument
    let viewModel: WithholdingStatementViewModel

    @State private var shareURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.counterpartyName)
                        .font(.headline)
                    Text(document.withholdingTaxCode.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let address = document.payeeAddress {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("集計")
                        .font(.headline)
                    detailRow("支払件数", "\(document.paymentCount)件")
                    detailRow("支払総額", formatCurrency(document.totalGrossAmount))
                    detailRow("源泉徴収税額", formatCurrency(document.totalWithholdingTaxAmount))
                    detailRow("実支払額", formatCurrency(document.totalNetAmount))
                }
                .padding(16)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 8) {
                    Button("この支払調書をCSV出力") {
                        viewModel.exportPayee(document, format: .csv)
                    }
                    .buttonStyle(.bordered)

                    Button("この支払調書をPDF出力") {
                        viewModel.exportPayee(document, format: .pdf)
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("明細")
                        .font(.headline)
                    ForEach(document.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDate(row.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(row.description)
                                .font(.subheadline)
                            HStack {
                                Text("総額 \(formatCurrency(row.grossAmount))")
                                Spacer()
                                Text("源泉 \(formatCurrency(row.withholdingTaxAmount))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("支払先単票")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ShareSheetView(activityItems: [shareURL])
            }
        }
        .alert(item: Binding(
            get: { viewModel.exportResult },
            set: { viewModel.exportResult = $0 }
        )) { result in
            switch result {
            case .success(let url):
                return Alert(
                    title: Text("エクスポート完了"),
                    message: Text("ファイルを保存しました"),
                    primaryButton: .default(Text("共有")) {
                        shareURL = url
                        showShareSheet = true
                    },
                    secondaryButton: .cancel(Text("閉じる"))
                )
            case .failure(let message):
                return Alert(
                    title: Text("エクスポートエラー"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        return WithholdingStatementView.currencyFormatter.string(from: number) ?? number.stringValue
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
