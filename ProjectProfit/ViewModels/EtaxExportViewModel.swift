import Foundation
import os
import SwiftUI

@Observable
@MainActor
final class EtaxExportViewModel {
    let dataStore: DataStore

    var fiscalYear: Int
    var formType: EtaxFormType = .blueReturn
    var validationErrors: [EtaxExportError] = []
    var exportedForm: EtaxForm?
    var isExporting = false
    var exportResult: ExportResult?

    enum ExportResult: Identifiable {
        case success(url: URL)
        case failure(message: String)

        var id: String {
            switch self {
            case .success(let url): "success-\(url.absoluteString)"
            case .failure(let msg): "failure-\(msg)"
            }
        }
    }

    init(dataStore: DataStore) {
        self.dataStore = dataStore
        self.fiscalYear = Calendar.current.component(.year, from: Date()) - 1
    }

    // MARK: - Generate Preview

    func generatePreview() {
        let pl = AccountingReportService.generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines
        )
        let bs = AccountingReportService.generateBalanceSheet(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines
        )

        let form: EtaxForm
        switch formType {
        case .blueReturn:
            form = EtaxFieldPopulator.populate(
                fiscalYear: fiscalYear,
                profitLoss: pl,
                balanceSheet: bs,
                formType: .blueReturn,
                accounts: dataStore.accounts
            )
        case .whiteReturn:
            form = ShushiNaiyakushoBuilder.build(
                fiscalYear: fiscalYear,
                profitLoss: pl,
                accounts: dataStore.accounts
            )
        }

        validationErrors = EtaxCharacterValidator.validateForm(form)
        exportedForm = form
    }

    // MARK: - Export

    func exportXtx() {
        guard let form = exportedForm else { return }
        isExporting = true

        let result = EtaxXtxExporter.generateXtx(form: form)
        switch result {
        case .success(let data):
            if let url = saveToTempFile(data: data, extension: "xtx") {
                exportResult = .success(url: url)
            } else {
                exportResult = .failure(message: "ファイルの保存に失敗しました")
            }
        case .failure(let error):
            exportResult = .failure(message: error.description)
        }

        isExporting = false
    }

    func exportCsv() {
        guard let form = exportedForm else { return }
        isExporting = true

        let result = EtaxXtxExporter.generateCsv(form: form)
        switch result {
        case .success(let data):
            if let url = saveToTempFile(data: data, extension: "csv") {
                exportResult = .success(url: url)
            } else {
                exportResult = .failure(message: "ファイルの保存に失敗しました")
            }
        case .failure(let error):
            exportResult = .failure(message: error.description)
        }

        isExporting = false
    }

    // MARK: - File Handling

    private static let logger = Logger(subsystem: "com.projectprofit", category: "EtaxExport")

    private func saveToTempFile(data: Data, extension ext: String) -> URL? {
        let fileName = "etax_\(fiscalYear)_\(formType.rawValue).\(ext)"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            Self.logger.error("ファイル保存失敗: \(fileURL.path), error: \(error.localizedDescription)")
            return nil
        }
    }
}
