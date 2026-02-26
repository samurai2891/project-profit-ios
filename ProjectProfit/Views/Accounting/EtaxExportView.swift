import SwiftUI

struct EtaxExportView: View {
    @Environment(DataStore.self) private var dataStore
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
                viewModel = EtaxExportViewModel(dataStore: dataStore)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
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
    }

    // MARK: - Settings

    @MainActor
    private func settingsSection(viewModel: EtaxExportViewModel) -> some View {
        let supportedYears = TaxYearDefinitionLoader.supportedYears(formType: viewModel.formType)
        let yearOptions = supportedYears.isEmpty ? [viewModel.fiscalYear] : supportedYears

        return VStack(alignment: .leading, spacing: 12) {
            Text("設定")
                .font(.headline)

            HStack {
                Text("年度")
                Spacer()
                Picker("年度", selection: Binding(
                    get: { viewModel.fiscalYear },
                    set: {
                        viewModel.fiscalYear = $0
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
                           !years.contains(viewModel.fiscalYear),
                           let latest = years.last
                        {
                            viewModel.fiscalYear = latest
                        }
                        viewModel.exportedForm = nil
                        viewModel.validationErrors = []
                    }
                )) {
                    Text("青色申告").tag(EtaxFormType.blueReturn)
                    Text("白色申告").tag(EtaxFormType.whiteReturn)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    Text(".xtx (XML) エクスポート")
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

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
