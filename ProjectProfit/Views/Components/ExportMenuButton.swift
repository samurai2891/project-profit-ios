import SwiftData
import SwiftUI

struct ExportMenuButton: View {
    @Environment(\.modelContext) private var modelContext

    let target: ExportCoordinator.ExportTarget
    let fiscalYear: Int
    let ledgerOptions: ExportCoordinator.LedgerExportOptions?
    let ledgerBookSelectionOptions: ExportCoordinator.LedgerBookSelectionOptions?

    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    /// ExportCoordinator 経由でエクスポートするコンビニエンスイニシャライザ
    @MainActor
    init(
        target: ExportCoordinator.ExportTarget,
        fiscalYear: Int,
        ledgerOptions: ExportCoordinator.LedgerExportOptions? = nil,
        ledgerBookSelectionOptions: ExportCoordinator.LedgerBookSelectionOptions? = nil
    ) {
        self.target = target
        self.fiscalYear = fiscalYear
        self.ledgerOptions = ledgerOptions
        self.ledgerBookSelectionOptions = ledgerBookSelectionOptions
    }

    var body: some View {
        Menu {
            ForEach(Array(supportedFormats).sorted(by: formatSortOrder), id: \.self) { format in
                Button {
                    exportAndShare(format: format)
                } label: {
                    Label("\(format.label)で共有", systemImage: iconName(for: format))
                }
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

    private var supportedFormats: Set<ExportCoordinator.ExportFormat> {
        target.supportedFormats
    }

    private func formatSortOrder(_ lhs: ExportCoordinator.ExportFormat, _ rhs: ExportCoordinator.ExportFormat) -> Bool {
        sortPriority(lhs) < sortPriority(rhs)
    }

    private func sortPriority(_ format: ExportCoordinator.ExportFormat) -> Int {
        switch format {
        case .csv:
            return 0
        case .pdf:
            return 1
        case .xlsx:
            return 2
        case .xtx:
            return 3
        }
    }

    private func iconName(for format: ExportCoordinator.ExportFormat) -> String {
        switch format {
        case .csv:
            return "tablecells"
        case .pdf:
            return "doc.richtext"
        case .xlsx:
            return "tablecells.badge.ellipsis"
        case .xtx:
            return "doc.badge.gearshape"
        }
    }

    private func exportAndShare(format: ExportCoordinator.ExportFormat) {
        do {
            shareURL = try ExportCoordinator.export(
                target: target,
                format: format,
                fiscalYear: fiscalYear,
                modelContext: modelContext,
                ledgerOptions: ledgerOptions,
                ledgerBookSelectionOptions: ledgerBookSelectionOptions
            )
            showShareSheet = true
        } catch {
            shareURL = nil
            showShareSheet = false
            errorMessage = error.localizedDescription
        }
    }
}
