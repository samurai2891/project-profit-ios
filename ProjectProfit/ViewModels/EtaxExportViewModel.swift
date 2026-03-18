import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class EtaxExportViewModel {
    private struct PreviewState {
        let fiscalYear: Int
        let formType: EtaxFormType
        let dataRevision: Int
    }

    private let contextProvider: @MainActor (Int) -> EtaxExportContext
    private let snapshotProvider: @MainActor (Int) -> EtaxFormBuildSnapshot
    private let taxYearStateUseCase: TaxYearStateUseCase
    private let filingPreflightUseCase: FilingPreflightUseCase
    private let formBuilder: @MainActor (FilingStyle, EtaxFormBuildSnapshot) throws -> EtaxForm
    private let exporter: @MainActor (ExportCoordinator.ExportFormat, EtaxForm) throws -> URL

    var fiscalYear: Int
    var formType: EtaxFormType = .blueReturn
    var validationErrors: [EtaxExportError] = []
    var exportedForm: EtaxForm?
    var isExporting = false
    var exportResult: ExportResult?
    private var previewState: PreviewState?

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

    init(
        modelContext: ModelContext,
        contextProvider: @escaping @MainActor (Int) -> EtaxExportContext,
        snapshotProvider: @escaping @MainActor (Int) -> EtaxFormBuildSnapshot,
        formBuilder: @escaping @MainActor (FilingStyle, EtaxFormBuildSnapshot) throws -> EtaxForm,
        exporter: @escaping @MainActor (ExportCoordinator.ExportFormat, EtaxForm) throws -> URL
    ) {
        self.contextProvider = contextProvider
        self.snapshotProvider = snapshotProvider
        self.taxYearStateUseCase = TaxYearStateUseCase(modelContext: modelContext)
        self.filingPreflightUseCase = FilingPreflightUseCase(modelContext: modelContext)
        self.formBuilder = formBuilder
        self.exporter = exporter
        let preferredYear = currentFiscalYear(startMonth: FiscalYearSettings.startMonth) - 1
        self.fiscalYear = Self.resolveSupportedFiscalYear(formType: .blueReturn, preferredYear: preferredYear)
    }

    // MARK: - Generate Preview

    func generatePreview() {
        guard TaxYearDefinitionLoader.isSupported(year: fiscalYear, formType: formType) else {
            exportedForm = nil
            validationErrors = [.unsupportedTaxYear(year: fiscalYear)]
            previewState = nil
            return
        }

        let preflightErrors = preflightErrors(context: .export)
        guard preflightErrors.isEmpty else {
            exportedForm = nil
            validationErrors = preflightErrors
            previewState = nil
            return
        }

        do {
            let snapshot = snapshotProvider(fiscalYear)
            let revision = dataRevision(for: snapshot)
            let form = try buildExportParityForm(snapshot: snapshot)
            validationErrors = EtaxCharacterValidator.validateForm(form)
            exportedForm = form
            previewState = PreviewState(
                fiscalYear: fiscalYear,
                formType: formType,
                dataRevision: revision
            )
        } catch {
            exportedForm = nil
            validationErrors = [.validationFailed(reasons: [error.localizedDescription])]
            previewState = nil
            return
        }
    }

    // MARK: - Export

    func exportXtx() {
        export(format: .xtx)
    }

    func exportCsv() {
        export(format: .csv)
    }

    private func export(format: ExportCoordinator.ExportFormat) {
        guard exportedForm != nil else { return }
        guard exportedForm?.fiscalYear == fiscalYear else {
            exportResult = .failure(message: "年度を変更したため、プレビューを再生成してください")
            return
        }
        guard TaxYearDefinitionLoader.isSupported(year: fiscalYear, formType: formType) else {
            exportResult = .failure(message: EtaxExportError.unsupportedTaxYear(year: fiscalYear).description)
            return
        }

        let preflightErrors = preflightErrors(context: .export)
        guard preflightErrors.isEmpty else {
            validationErrors = preflightErrors
            exportResult = .failure(message: preflightErrors.map(\.description).joined(separator: "\n"))
            return
        }

        let snapshot = snapshotProvider(fiscalYear)
        let currentRevision = dataRevision(for: snapshot)
        let shouldRebuild = previewState?.fiscalYear != fiscalYear
            || previewState?.formType != formType
            || previewState?.dataRevision != currentRevision

        let currentForm: EtaxForm
        do {
            if shouldRebuild {
                currentForm = try buildExportParityForm(snapshot: snapshot)
                exportedForm = currentForm
                previewState = PreviewState(
                    fiscalYear: fiscalYear,
                    formType: formType,
                    dataRevision: currentRevision
                )
            } else if let exportedForm {
                currentForm = exportedForm
            } else {
                currentForm = try buildExportParityForm(snapshot: snapshot)
                exportedForm = currentForm
                previewState = PreviewState(
                    fiscalYear: fiscalYear,
                    formType: formType,
                    dataRevision: currentRevision
                )
            }
        } catch {
            validationErrors = [.validationFailed(reasons: [error.localizedDescription])]
            exportResult = .failure(message: error.localizedDescription)
            return
        }

        let exportValidationErrors = EtaxCharacterValidator.validateForm(currentForm)
        validationErrors = exportValidationErrors
        guard exportValidationErrors.isEmpty else {
            exportResult = .failure(message: exportValidationErrors.map(\.description).joined(separator: "\n"))
            return
        }

        isExporting = true

        do {
            let url = try exporter(format, currentForm)
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

    private func filingStyle(for formType: EtaxFormType) -> FilingStyle {
        switch formType {
        case .blueReturn:
            return .blueGeneral
        case .blueCashBasis:
            return .blueCashBasis
        case .whiteReturn:
            return .white
        }
    }

    private func buildExportParityForm(snapshot: EtaxFormBuildSnapshot) throws -> EtaxForm {
        let rawForm = try formBuilder(filingStyle(for: formType), snapshot)
        return Self.exportableForm(from: rawForm)
    }

    private func dataRevision(for snapshot: EtaxFormBuildSnapshot) -> Int {
        var hasher = Hasher()
        hasher.combine(snapshot.fiscalYear)
        hasher.combine(snapshot.startMonth)

        if let businessProfile = snapshot.businessProfile {
            hasher.combine(businessProfile.id)
            hasher.combine(businessProfile.ownerName)
            hasher.combine(businessProfile.businessName)
            hasher.combine(businessProfile.businessAddress)
            hasher.combine(businessProfile.postalCode)
            hasher.combine(businessProfile.phoneNumber)
            hasher.combine(businessProfile.updatedAt.timeIntervalSinceReferenceDate)
        } else {
            hasher.combine("businessProfile:nil")
        }

        if let taxYearProfile = snapshot.taxYearProfile {
            hasher.combine(taxYearProfile.id)
            hasher.combine(taxYearProfile.taxYear)
            hasher.combine(taxYearProfile.filingStyle.rawValue)
            hasher.combine(taxYearProfile.yearLockState.rawValue)
            hasher.combine(taxYearProfile.taxPackVersion)
            hasher.combine(taxYearProfile.updatedAt.timeIntervalSinceReferenceDate)
        } else {
            hasher.combine("taxYearProfile:nil")
        }

        hasher.combine(snapshot.canonicalAccounts.count)
        for account in snapshot.canonicalAccounts.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(account.id)
            hasher.combine(account.code)
            hasher.combine(account.name)
            hasher.combine(account.updatedAt.timeIntervalSinceReferenceDate)
        }

        let sortedCategoryNames = snapshot.categoryNamesById.sorted { lhs, rhs in
            lhs.key < rhs.key
        }
        hasher.combine(sortedCategoryNames.count)
        for entry in sortedCategoryNames {
            hasher.combine(entry.key)
            hasher.combine(entry.value)
        }

        hasher.combine(snapshot.fixedAssets.count)
        for asset in snapshot.fixedAssets.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(asset.id)
            hasher.combine(asset.name)
            hasher.combine(asset.acquisitionCost)
            hasher.combine(asset.businessUsePercent)
            hasher.combine(asset.updatedAt.timeIntervalSinceReferenceDate)
        }

        if let inventoryRecord = snapshot.inventoryRecord {
            hasher.combine(inventoryRecord.id)
            hasher.combine(inventoryRecord.fiscalYear)
            hasher.combine(inventoryRecord.openingInventory)
            hasher.combine(inventoryRecord.purchases)
            hasher.combine(inventoryRecord.closingInventory)
            hasher.combine(inventoryRecord.updatedAt.timeIntervalSinceReferenceDate)
        } else {
            hasher.combine("inventoryRecord:nil")
        }

        hasher.combine(decimalString(snapshot.canonicalProfitLoss.totalRevenue))
        hasher.combine(decimalString(snapshot.canonicalProfitLoss.totalExpenses))
        hasher.combine(decimalString(snapshot.canonicalProfitLoss.netIncome))
        hasher.combine(decimalString(snapshot.canonicalBalanceSheet.totalAssets))
        hasher.combine(decimalString(snapshot.canonicalBalanceSheet.totalLiabilities))
        hasher.combine(decimalString(snapshot.canonicalBalanceSheet.totalEquity))

        hasher.combine(snapshot.canonicalJournals.count)
        for journal in snapshot.canonicalJournals.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(journal.id)
            hasher.combine(journal.voucherNo)
            hasher.combine(journal.updatedAt.timeIntervalSinceReferenceDate)
            hasher.combine(decimalString(journal.totalDebit))
            hasher.combine(decimalString(journal.totalCredit))
        }

        let sortedCandidateSummaries = snapshot.candidateSummariesById.sorted { lhs, rhs in
            lhs.key.uuidString < rhs.key.uuidString
        }
        hasher.combine(sortedCandidateSummaries.count)
        for entry in sortedCandidateSummaries {
            hasher.combine(entry.key)
            hasher.combine(entry.value.transactionType.rawValue)
            hasher.combine(entry.value.resolvedCategoryId)
        }

        return hasher.finalize()
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
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

        let allowCashBasisDynamicExpenses = form.formType == .blueCashBasis

        return EtaxForm(
            fiscalYear: form.fiscalYear,
            formType: form.formType,
            fields: form.fields.filter {
                exportableKeys.contains($0.id)
                    || (allowCashBasisDynamicExpenses && $0.id.hasPrefix("cash_basis_expense_") && $0.id != "cash_basis_expense_total")
            },
            generatedAt: form.generatedAt
        )
    }

    private func taxStatePreflightErrors() -> [EtaxExportError] {
        let context = contextProvider(fiscalYear)
        guard let businessId = context.businessId else {
            return []
        }

        do {
            let issues = try taxYearStateUseCase.filingPreflightIssues(
                businessId: businessId,
                taxYear: fiscalYear,
                fallbackProfile: context.fallbackTaxYearProfile
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
        guard let businessId = contextProvider(fiscalYear).businessId else {
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
