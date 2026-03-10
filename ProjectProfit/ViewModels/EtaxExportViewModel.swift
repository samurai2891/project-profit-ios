import Foundation
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

        let filingStyle: FilingStyle
        switch formType {
        case .blueReturn:
            filingStyle = .blueGeneral
        case .blueCashBasis:
            filingStyle = .blueCashBasis
        case .whiteReturn:
            filingStyle = .white
        }

        let form: EtaxForm
        do {
            form = try FormEngine.build(
                filingStyle: filingStyle,
                dataStore: dataStore,
                fiscalYear: fiscalYear
            )
        } catch {
            exportedForm = nil
            validationErrors = [.validationFailed(reasons: [error.localizedDescription])]
            return
        }

        validationErrors = EtaxCharacterValidator.validateForm(Self.exportableForm(from: form))
        exportedForm = form
    }

    // MARK: - Export

    func exportXtx() {
        export(format: .xtx)
    }

    func exportCsv() {
        export(format: .csv)
    }

    private func export(format: ExportCoordinator.ExportFormat) {
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

        do {
            let url = try ExportCoordinator.export(
                target: .etax,
                format: format,
                fiscalYear: form.fiscalYear,
                dataStore: dataStore,
                etaxOptions: .init(form: Self.exportableForm(from: form))
            )
            exportResult = .success(url: url)
        } catch {
            exportResult = .failure(message: error.localizedDescription)
        }

        isExporting = false
    }

    // MARK: - File Handling

    private static func resolveSupportedFiscalYear(formType: EtaxFormType, preferredYear: Int) -> Int {
        let years = TaxYearDefinitionLoader.supportedYears(formType: formType)
        if years.contains(preferredYear) {
            return preferredYear
        }
        return years.last ?? preferredYear
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
