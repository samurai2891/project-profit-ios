import SwiftUI

struct EtaxExportView: View {
    private static let selectableFormTypes: [EtaxFormType] = [
        .blueReturn,
        .blueCashBasis,
        .whiteReturn,
    ]
    private static let supportMatrixColumns: [(formType: EtaxFormType?, title: String)] = [
        (nil, "年分"),
        (.blueReturn, "青色"),
        (.blueCashBasis, "現金"),
        (.whiteReturn, "白色"),
    ]

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: EtaxExportViewModel?
    @State private var showShareSheet = false
    @State private var shareURL: URL?

    var body: some View {
        Group {
            if let viewModel {
                exportContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("e-Tax出力")
        .task {
            if viewModel == nil {
                let contextQueryUseCase = EtaxExportContextQueryUseCase(modelContext: modelContext)
                let formBuildQueryUseCase = EtaxFormBuildQueryUseCase(modelContext: modelContext)
                viewModel = EtaxExportViewModel(
                    modelContext: modelContext,
                    contextProvider: { taxYear in
                        contextQueryUseCase.context(taxYear: taxYear)
                    },
                    snapshotProvider: { taxYear in
                        formBuildQueryUseCase.snapshot(taxYear: taxYear)
                    },
                    formBuilder: { filingStyle, snapshot in
                        try FormEngine.build(
                            filingStyle: filingStyle,
                            input: FormEngine.BuildInput(
                                snapshot: snapshot
                            )
                        )
                    },
                    exporter: { format, form in
                        try ExportCoordinator.export(
                            target: .etax,
                            format: format,
                            fiscalYear: form.fiscalYear,
                            modelContext: modelContext,
                            skipPreflightValidation: true,
                            etaxOptions: .init(form: EtaxExportViewModel.exportableForm(from: form))
                        )
                    }
                )
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheetView(activityItems: [url])
            }
        }
    }

    @ViewBuilder
    private func exportContent(viewModel: EtaxExportViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection(viewModel: viewModel)
                previewButton(viewModel: viewModel)

                if !viewModel.validationErrors.isEmpty {
                    validationSection(viewModel: viewModel)
                }

                if let form = viewModel.exportedForm {
                    EtaxFormPreviewView(form: form)
                    exportButtons(viewModel: viewModel)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .alert(item: alertBinding(viewModel: viewModel)) { result in
            switch result {
            case .success(let url):
                Alert(
                    title: Text("エクスポート完了"),
                    message: Text("ファイルを保存しました"),
                    primaryButton: .default(Text("共有")) {
                        shareURL = url
                        showShareSheet = true
                    },
                    secondaryButton: .cancel(Text("閉じる"))
                )
            case .failure(let message):
                Alert(
                    title: Text("エクスポートエラー"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .accessibilityIdentifier("screen.etax.export")
    }

    // MARK: - Settings

    @MainActor
    private func settingsSection(viewModel: EtaxExportViewModel) -> some View {
        let supportedYears = TaxYearDefinitionLoader.supportedYears(formType: viewModel.formType)
        let yearOptions = supportedYears.isEmpty ? [viewModel.taxYear] : supportedYears

        return VStack(alignment: .leading, spacing: 12) {
            Text("設定")
                .font(.headline)

            HStack {
                Text("申告年分")
                Spacer()
                Picker("申告年分", selection: Binding(
                    get: { viewModel.taxYear },
                    set: {
                        viewModel.taxYear = $0
                        viewModel.exportedForm = nil
                        viewModel.validationErrors = []
                    }
                )) {
                    ForEach(yearOptions, id: \.self) { year in
                        Text("\(year)年").tag(year)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text("申告種類")
                Spacer()
                Picker("種類", selection: Binding(
                    get: { viewModel.formType },
                    set: {
                        viewModel.formType = $0
                        let years = TaxYearDefinitionLoader.supportedYears(formType: $0)
                        if !years.isEmpty,
                           !years.contains(viewModel.taxYear),
                           let latest = years.last
                        {
                            viewModel.taxYear = latest
                        }
                        viewModel.exportedForm = nil
                        viewModel.validationErrors = []
                    }
                )) {
                    ForEach(Self.selectableFormTypes, id: \.self) { formType in
                        Text(formType.exportSelectionLabel).tag(formType)
                    }
                }
                .pickerStyle(.menu)
            }

            Text("申告年分は暦年（1月〜12月）基準で判定します。会計年度設定とは別管理です。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(viewModel.selectedFormTypeSupportDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("etax.support.selectedFormDescription")

            supportStatusSection(viewModel: viewModel)
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func supportStatusSection(viewModel: EtaxExportViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("対応状況")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                supportMatrixHeader

                ForEach(viewModel.supportStatusRows, id: \.fiscalYear) { row in
                    supportMatrixRow(row)
                        .accessibilityIdentifier("etax.support.row.\(row.fiscalYear)")

                    if row.fiscalYear != viewModel.supportStatusRows.last?.fiscalYear {
                        Divider()
                    }
                }
            }
            .background(Color.white.opacity(0.001))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("etax.support.matrix")

            Text(viewModel.unsupportedYearReasonDescription)
                .font(.caption)
                .foregroundStyle(AppColors.warning)
                .accessibilityIdentifier("etax.support.note")
        }
    }

    private var supportMatrixHeader: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.supportMatrixColumns.enumerated()), id: \.offset) { _, column in
                Text(column.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: column.formType == nil ? .leading : .center)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
    }

    private func supportMatrixRow(_ row: TaxYearDefinitionLoader.EtaxSupportStatusRow) -> some View {
        HStack(spacing: 8) {
            Text("\(row.fiscalYear)年")
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("etax.support.row.\(row.fiscalYear)")

            supportStatusBadge(isSupported: row.isSupported(for: .blueReturn))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("etax.support.row.\(row.fiscalYear).blueReturn")

            supportStatusBadge(isSupported: row.isSupported(for: .blueCashBasis))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("etax.support.row.\(row.fiscalYear).blueCashBasis")

            supportStatusBadge(isSupported: row.isSupported(for: .whiteReturn))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("etax.support.row.\(row.fiscalYear).whiteReturn")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func supportStatusBadge(isSupported: Bool) -> some View {
        Text(isSupported ? "対応済み" : "未対応")
            .font(.caption.weight(.medium))
            .foregroundStyle(isSupported ? AppColors.success : AppColors.warning)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Preview Button

    private func previewButton(viewModel: EtaxExportViewModel) -> some View {
        Button {
            viewModel.generatePreview()
        } label: {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                Text("プレビュー生成")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Validation

    @ViewBuilder
    private func validationSection(viewModel: EtaxExportViewModel) -> some View {
        if !viewModel.validationErrors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.warning)
                    Text("バリデーションエラー")
                        .font(.headline)
                }
                ForEach(Array(viewModel.validationErrors.enumerated()), id: \.offset) { _, error in
                    Text(error.description)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Export Buttons

    private func exportButtons(viewModel: EtaxExportViewModel) -> some View {
        VStack(spacing: 8) {
            Button {
                viewModel.exportXtx()
            } label: {
                HStack {
                    Image(systemName: "doc.richtext")
                    Text(".xtx エクスポート")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isExporting || !viewModel.validationErrors.isEmpty)

            Button {
                viewModel.exportCsv()
            } label: {
                HStack {
                    Image(systemName: "tablecells")
                    Text(".csv エクスポート")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isExporting || !viewModel.validationErrors.isEmpty)
        }
    }

    // MARK: - Alert Binding

    private func alertBinding(viewModel: EtaxExportViewModel) -> Binding<EtaxExportViewModel.ExportResult?> {
        Binding(
            get: { viewModel.exportResult },
            set: { viewModel.exportResult = $0 }
        )
    }
}
