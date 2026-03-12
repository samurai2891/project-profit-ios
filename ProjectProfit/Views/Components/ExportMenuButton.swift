import SwiftData
import SwiftUI

struct ExportMenuButton: View {
    @Environment(\.modelContext) private var modelContext

    let target: ExportCoordinator.ExportTarget
    let fiscalYear: Int
    let ledgerOptions: ExportCoordinator.LedgerExportOptions?

    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    /// ExportCoordinator 経由でエクスポートするコンビニエンスイニシャライザ
    @MainActor
    init(
        target: ExportCoordinator.ExportTarget,
        fiscalYear: Int,
        ledgerOptions: ExportCoordinator.LedgerExportOptions? = nil
    ) {
        self.target = target
        self.fiscalYear = fiscalYear
        self.ledgerOptions = ledgerOptions
    }

    var body: some View {
        Menu {
            Button {
                shareCSV()
            } label: {
                Label("CSVで共有", systemImage: "tablecells")
            }
            Button {
                sharePDF()
            } label: {
                Label("PDFで共有", systemImage: "doc.richtext")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheetView(activityItems: [url])
            }
        }
        .alert("出力エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func shareCSV() {
        exportAndShare(format: .csv)
    }

    private func sharePDF() {
        exportAndShare(format: .pdf)
    }

    private func exportAndShare(format: ExportCoordinator.ExportFormat) {
        do {
            shareURL = try ExportCoordinator.export(
                target: target,
                format: format,
                fiscalYear: fiscalYear,
                modelContext: modelContext,
                ledgerOptions: ledgerOptions
            )
            showShareSheet = true
        } catch {
            shareURL = nil
            showShareSheet = false
            errorMessage = error.localizedDescription
        }
    }
}
