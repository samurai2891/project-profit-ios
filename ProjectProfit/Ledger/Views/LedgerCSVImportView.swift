// ============================================================
// LedgerCSVImportView.swift
// CSVファイルインポートUI
// ============================================================

import SwiftUI
import UniformTypeIdentifiers

struct LedgerCSVImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LedgerDataStore.self) private var ledgerStore
    @Environment(\.dismiss) private var dismiss

    let bookId: UUID

    @State private var showFilePicker = false
    @State private var importResult: CSVImportResult?
    @State private var isImporting = false
    @State private var previewRows: [[String]] = []
    @State private var selectedURL: URL?
    @State private var errorMessage: String?

    private var book: SDLedgerBook? {
        ledgerStore.book(for: bookId)
    }

    private var postingIntakeUseCase: PostingIntakeUseCase {
        PostingIntakeUseCase(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            List {
                if ledgerStore.isReadOnly {
                    Section {
                        Text("旧台帳は読み取り専用です。CSVインポートは無効です。")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("CSVファイルを選択", systemImage: "doc.badge.plus")
                    }
                    .disabled(ledgerStore.isReadOnly)

                    if let url = selectedURL {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }

                if !previewRows.isEmpty {
                    Section("プレビュー（先頭5行）") {
                        ForEach(Array(previewRows.prefix(6).enumerated()), id: \.offset) { idx, row in
                            HStack {
                                if idx == 0 {
                                    ForEach(row, id: \.self) { cell in
                                        Text(cell)
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                } else {
                                    ForEach(row, id: \.self) { cell in
                                        Text(cell)
                                            .font(.caption2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            Task { await performImport() }
                        } label: {
                            HStack {
                                Spacer()
                                if isImporting {
                                    ProgressView()
                                } else {
                                    Text("インポート実行")
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isImporting || ledgerStore.isReadOnly)
                    }
                }

                if let result = importResult {
                    Section("結果") {
                        HStack {
                            Label("成功", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Text("\(result.successCount)件")
                                .font(.headline)
                        }
                        if result.errorCount > 0 {
                            HStack {
                                Label("エラー", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Spacer()
                                Text("\(result.errorCount)件")
                                    .font(.headline)
                            }
                            ForEach(result.lineErrors.prefix(10)) { error in
                                Text("行\(error.line): \(error.reason)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("CSVインポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }

    // MARK: - File Handling

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        guard !ledgerStore.isReadOnly else {
            errorMessage = "旧台帳は読み取り専用です"
            return
        }
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedURL = url
            errorMessage = nil
            importResult = nil
            loadPreview(from: url)
        case .failure(let error):
            errorMessage = "ファイル選択エラー: \(error.localizedDescription)"
        }
    }

    private func loadPreview(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "ファイルへのアクセスが拒否されました"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let cleaned = content.replacingOccurrences(of: "\u{FEFF}", with: "")
            previewRows = CSVImportService.shared.parseCSV(cleaned)
        } catch {
            errorMessage = "ファイル読み込みエラー: \(error.localizedDescription)"
        }
    }

    private func performImport() async {
        guard !ledgerStore.isReadOnly else {
            errorMessage = "旧台帳は読み取り専用です"
            return
        }
        guard let url = selectedURL,
              let ledgerType = book?.ledgerType else { return }

        isImporting = true
        try? await Task.sleep(nanoseconds: 50_000_000)

        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "ファイルへのアクセスが拒否されました"
            isImporting = false
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let fileData = try Data(contentsOf: url)
            guard let content = String(data: fileData, encoding: .utf8) else {
                throw AppError.invalidInput(message: "CSV の文字コードを UTF-8 として読み取れません")
            }
            let result = await postingIntakeUseCase.importTransactions(
                request: CSVImportRequest(
                    csvString: content,
                    originalFileName: url.lastPathComponent,
                    fileData: fileData,
                    mimeType: "text/csv",
                    channel: .ledgerBook(
                        ledgerType: ledgerType,
                        metadataJSON: book?.metadataJSON
                    )
                )
            )
            importResult = result
            errorMessage = nil
        } catch {
            errorMessage = "インポートエラー: \(error.localizedDescription)"
        }

        isImporting = false
    }
}
