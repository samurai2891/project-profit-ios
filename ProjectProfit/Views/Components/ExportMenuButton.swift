import SwiftUI

struct ExportMenuButton: View {
    let csvGenerator: () -> String
    let pdfGenerator: () -> Data
    let fileNamePrefix: String

    @State private var showShareSheet = false
    @State private var shareURL: URL?

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
    }

    private func shareCSV() {
        let csv = csvGenerator()
        let fileName = "\(fileNamePrefix)_\(formattedDate()).csv"
        guard let data = csv.data(using: .utf8) else { return }
        guard let url = writeTempFile(content: data, fileName: fileName) else { return }
        shareURL = url
        showShareSheet = true
    }

    private func sharePDF() {
        let data = pdfGenerator()
        let fileName = "\(fileNamePrefix)_\(formattedDate()).pdf"
        guard let url = writeTempFile(content: data, fileName: fileName) else { return }
        shareURL = url
        showShareSheet = true
    }

    private func writeTempFile(content: Data, fileName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try content.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
}
