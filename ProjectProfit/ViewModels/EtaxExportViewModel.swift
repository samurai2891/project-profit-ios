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
        self.fiscalYear = currentFiscalYear(startMonth: FiscalYearSettings.startMonth) - 1
    }

    // MARK: - Generate Preview

    func generatePreview() {
        guard TaxYearDefinitionLoader.isSupported(year: fiscalYear, formType: formType) else {
            exportedForm = nil
            validationErrors = [.unsupportedTaxYear(year: fiscalYear)]
            return
        }

        let startMonth = FiscalYearSettings.startMonth
        let pl = AccountingReportService.generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines,
            startMonth: startMonth
        )
        let bs = AccountingReportService.generateBalanceSheet(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: dataStore.journalEntries,
            journalLines: dataStore.journalLines,
            startMonth: startMonth
        )

        let inventoryRecord = dataStore.getInventoryRecord(fiscalYear: fiscalYear)
        let profile = dataStore.accountingProfile

        let form: EtaxForm
        switch formType {
        case .blueReturn:
            form = EtaxFieldPopulator.populate(
                fiscalYear: fiscalYear,
                profitLoss: pl,
                balanceSheet: bs,
                formType: .blueReturn,
                accounts: dataStore.accounts,
                profile: profile,
                inventoryRecord: inventoryRecord
            )
        case .whiteReturn:
            form = ShushiNaiyakushoBuilder.build(
                fiscalYear: fiscalYear,
                profitLoss: pl,
                accounts: dataStore.accounts,
                profile: profile,
                fixedAssets: dataStore.fixedAssets,
                journalLines: dataStore.journalLines,
                journalEntries: dataStore.journalEntries
            )
        }

        validationErrors = EtaxCharacterValidator.validateForm(form)
        exportedForm = form
    }

    // MARK: - Export

    func exportXtx() {
        guard let form = exportedForm else { return }
        guard form.fiscalYear == fiscalYear else {
            exportResult = .failure(message: "年度を変更したため、プレビューを再生成してください")
            return
        }
        guard TaxYearDefinitionLoader.isSupported(year: form.fiscalYear, formType: form.formType) else {
            exportResult = .failure(message: EtaxExportError.unsupportedTaxYear(year: form.fiscalYear).description)
            return
        }
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
        guard form.fiscalYear == fiscalYear else {
            exportResult = .failure(message: "年度を変更したため、プレビューを再生成してください")
            return
        }
        guard TaxYearDefinitionLoader.isSupported(year: form.fiscalYear, formType: form.formType) else {
            exportResult = .failure(message: EtaxExportError.unsupportedTaxYear(year: form.fiscalYear).description)
            return
        }
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
