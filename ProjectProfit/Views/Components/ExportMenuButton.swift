import SwiftUI

struct ExportMenuButton: View {
    let target: ExportCoordinator.ExportTarget
    let fiscalYear: Int
    let dataStore: DataStore
    let ledgerOptions: ExportCoordinator.LedgerExportOptions?

    @State private var showShareSheet = false
    @State private var shareURL: URL?

    @MainActor
    init(
        target: ExportCoordinator.ExportTarget,
        fiscalYear: Int,
        dataStore: DataStore,
        ledgerOptions: ExportCoordinator.LedgerExportOptions? = nil
    ) {
        self.target = target
        self.fiscalYear = fiscalYear
        self.dataStore = dataStore
        self.ledgerOptions = ledgerOptions
    }

    var body: some View {
        Menu {
            ForEach(ExportCoordinator.ExportFormat.allCases, id: \.self) { format in
                Button {
                    share(format: format)
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
    }

    private func share(format: ExportCoordinator.ExportFormat) {
        guard let url = try? ExportCoordinator.export(
            target: target,
            format: format,
            fiscalYear: fiscalYear,
            dataStore: dataStore,
            ledgerOptions: ledgerOptions
        ) else { return }
        shareURL = url
        showShareSheet = true
    }

    private func iconName(for format: ExportCoordinator.ExportFormat) -> String {
        switch format {
        case .csv:
            return "tablecells"
        case .pdf:
            return "doc.richtext"
        case .xlsx:
            return "tablecells.badge.ellipsis"
        }
    }
}
