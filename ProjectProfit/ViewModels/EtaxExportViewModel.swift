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
        let preferredYear = currentFiscalYear(startMonth: FiscalYearSettings.startMonth) - 1
        self.fiscalYear = Self.resolveSupportedFiscalYear(formType: .blueReturn, preferredYear: preferredYear)
    }

    private var taxYearStateUseCase: TaxYearStateUseCase {
        TaxYearStateUseCase(modelContext: dataStore.modelContext)
    }

    private var filingPreflightUseCase: FilingPreflightUseCase {
        FilingPreflightUseCase(modelContext: dataStore.modelContext)
    }

    // MARK: - Generate Preview

    func generatePreview() {
        guard TaxYearDefinitionLoader.isSupported(year: fiscalYear, formType: formType) else {
            exportedForm = nil
            validationErrors = [.unsupportedTaxYear(year: fiscalYear)]
            return
        }

        let preflightErrors = preflightErrors(context: .export)
        guard preflightErrors.isEmpty else {
            exportedForm = nil
            validationErrors = preflightErrors
            return
        }

        let startMonth = FiscalYearSettings.startMonth
        let projected = dataStore.projectedCanonicalJournals(fiscalYear: fiscalYear)
        let pl = AccountingReportService.generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines,
            startMonth: startMonth
        )
        let bs = AccountingReportService.generateBalanceSheet(
            fiscalYear: fiscalYear,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines,
            startMonth: startMonth
        )

        let inventoryRecord = dataStore.getInventoryRecord(fiscalYear: fiscalYear)
        let profile = dataStore.etaxExportProfile(for: fiscalYear)

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
                journalLines: projected.lines,
                journalEntries: projected.entries
            )
        }

        validationErrors = EtaxCharacterValidator.validateForm(Self.exportableForm(from: form))
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
        let preflightErrors = preflightErrors(context: .export)
        guard preflightErrors.isEmpty else {
            validationErrors = preflightErrors
            exportResult = .failure(message: preflightErrors.map(\.description).joined(separator: "\n"))
            return
        }
        isExporting = true

        let result = EtaxXtxExporter.generateXtx(form: Self.exportableForm(from: form))
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
        let preflightErrors = preflightErrors(context: .export)
        guard preflightErrors.isEmpty else {
            validationErrors = preflightErrors
            exportResult = .failure(message: preflightErrors.map(\.description).joined(separator: "\n"))
            return
        }
        isExporting = true

        let result = EtaxXtxExporter.generateCsv(form: Self.exportableForm(from: form))
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

    private static func resolveSupportedFiscalYear(formType: EtaxFormType, preferredYear: Int) -> Int {
        let years = TaxYearDefinitionLoader.supportedYears(formType: formType)
        if years.contains(preferredYear) {
            return preferredYear
        }
        return years.last ?? preferredYear
    }

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

    private func preflightErrors(context: FilingPreflightContext) -> [EtaxExportError] {
        var errors = taxStatePreflightErrors()
        errors.append(contentsOf: accountingPreflightErrors(context: context))
        return errors
    }

    static func exportableForm(from form: EtaxForm) -> EtaxForm {
        let exportableKeys: Set<String> = Set(
            TaxYearDefinitionLoader.fieldDefinitions(for: form.formType, fiscalYear: form.fiscalYear)
                .compactMap { definition in
                    guard let xmlTag = definition.xmlTag?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !xmlTag.isEmpty
                    else {
                        return nil
                    }
                    return definition.internalKey
                }
        )

        return EtaxForm(
            fiscalYear: form.fiscalYear,
            formType: form.formType,
            fields: form.fields.filter { exportableKeys.contains($0.id) },
            generatedAt: form.generatedAt
        )
    }

    private func taxStatePreflightErrors() -> [EtaxExportError] {
        guard let businessId = dataStore.businessProfile?.id else {
            return []
        }

        do {
            let fallbackProfile = dataStore.currentTaxYearProfile?.taxYear == fiscalYear
                ? dataStore.currentTaxYearProfile
                : nil
            let issues = try taxYearStateUseCase.filingPreflightIssues(
                businessId: businessId,
                taxYear: fiscalYear,
                fallbackProfile: fallbackProfile
            )
            let errors = issues
                .filter { $0.severity == .error }
                .map(\.message)
            guard !errors.isEmpty else {
                return []
            }
            return [.validationFailed(reasons: errors)]
        } catch {
            return [.validationFailed(reasons: [error.localizedDescription])]
        }
    }

    private func accountingPreflightErrors(context: FilingPreflightContext) -> [EtaxExportError] {
        guard let businessId = dataStore.businessProfile?.id else {
            return []
        }

        do {
            let report = try filingPreflightUseCase.preflightReport(
                businessId: businessId,
                taxYear: fiscalYear,
                context: context
            )
            guard !report.blockingIssues.isEmpty else {
                return []
            }
            return report.blockingIssues.map { issue in
                .validationFailed(reasons: [issue.message])
            }
        } catch {
            return [.validationFailed(reasons: [error.localizedDescription])]
        }
    }
}
