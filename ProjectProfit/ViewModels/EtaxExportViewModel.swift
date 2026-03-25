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
    private let modelContext: ModelContext
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
        self.modelContext = modelContext
        self.contextProvider = contextProvider
        self.snapshotProvider = snapshotProvider
        self.taxYearStateUseCase = TaxYearStateUseCase(modelContext: modelContext)
        self.filingPreflightUseCase = FilingPreflightUseCase(modelContext: modelContext)
        self.formBuilder = formBuilder
        self.exporter = exporter
        let preferredYear = currentTaxYear() - 1
        self.fiscalYear = Self.resolveSupportedFiscalYear(formType: .blueReturn, preferredYear: preferredYear)
    }

    // MARK: - Generate Preview

    func generatePreview() {
        let exportContext = contextProvider(fiscalYear)
        guard TaxYearDefinitionLoader.isSupported(year: fiscalYear, formType: formType) else {
            exportedForm = nil
            validationErrors = [.unsupportedTaxYear(year: fiscalYear)]
            previewState = nil
            return
        }

        let preflightErrors = preflightErrors(context: .export, exportContext: exportContext)
        guard preflightErrors.isEmpty else {
            exportedForm = nil
            validationErrors = preflightErrors
            previewState = nil
            return
        }

        do {
            let snapshot = snapshotProvider(fiscalYear)
            let revision = currentDataRevision(
                businessId: exportContext.businessId,
                fiscalYear: fiscalYear,
                fallbackSnapshot: snapshot
            )
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

        let exportContext = contextProvider(fiscalYear)
        let currentRevision = currentDataRevision(
            businessId: exportContext.businessId,
            fiscalYear: fiscalYear,
            fallbackSnapshot: nil
        )
        let shouldRebuild = previewState?.fiscalYear != fiscalYear
            || previewState?.formType != formType
            || previewState?.dataRevision != currentRevision

        let currentForm: EtaxForm
        do {
            if shouldRebuild {
                let preflightErrors = preflightErrors(context: .export, exportContext: exportContext)
                guard preflightErrors.isEmpty else {
                    validationErrors = preflightErrors
                    exportResult = .failure(message: preflightErrors.map(\.description).joined(separator: "\n"))
                    return
                }

                let snapshot = snapshotProvider(fiscalYear)
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
                let snapshot = snapshotProvider(fiscalYear)
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

        let exportValidationErrors = if shouldRebuild || previewState == nil {
            EtaxCharacterValidator.validateForm(currentForm)
        } else {
            validationErrors
        }
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
        let exportContext = contextProvider(fiscalYear)
        return preflightErrors(context: context, exportContext: exportContext)
    }

    private func preflightErrors(
        context: FilingPreflightContext,
        exportContext: EtaxExportContext
    ) -> [EtaxExportError] {
        var errors = taxStatePreflightErrors(context: exportContext)
        errors.append(contentsOf: accountingPreflightErrors(context: context, exportContext: exportContext))
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

    private func currentDataRevision(
        businessId: UUID?,
        fiscalYear: Int,
        fallbackSnapshot: EtaxFormBuildSnapshot?
    ) -> Int {
        do {
            var hasher = Hasher()
            hasher.combine(fiscalYear)

            if let businessId {
                if let businessProfile = try modelContext.fetch(
                    FetchDescriptor<BusinessProfileEntity>(
                        predicate: #Predicate { $0.businessId == businessId },
                        sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                    )
                ).first {
                    hasher.combine(businessProfile.businessId)
                    hasher.combine(businessProfile.updatedAt.timeIntervalSinceReferenceDate)
                } else {
                    hasher.combine("businessProfile:nil")
                }

                if let taxYearProfile = try modelContext.fetch(
                    FetchDescriptor<TaxYearProfileEntity>(
                        predicate: #Predicate {
                            $0.businessId == businessId && $0.taxYear == fiscalYear
                        },
                        sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                    )
                ).first {
                    hasher.combine(taxYearProfile.profileId)
                    hasher.combine(taxYearProfile.updatedAt.timeIntervalSinceReferenceDate)
                    hasher.combine(taxYearProfile.taxPackVersion)
                    hasher.combine(taxYearProfile.yearLockStateRaw)
                } else {
                    hasher.combine("taxYearProfile:nil")
                }

                let accounts = try modelContext.fetch(
                    FetchDescriptor<CanonicalAccountEntity>(
                        predicate: #Predicate { $0.businessId == businessId },
                        sortBy: [SortDescriptor(\.accountId)]
                    )
                )
                hasher.combine(accounts.count)
                for account in accounts {
                    hasher.combine(account.accountId)
                    hasher.combine(account.code)
                    hasher.combine(account.name)
                    hasher.combine(account.updatedAt.timeIntervalSinceReferenceDate)
                }

                let journals = try modelContext.fetch(
                    FetchDescriptor<JournalEntryEntity>(
                        predicate: #Predicate {
                            $0.businessId == businessId && $0.taxYear == fiscalYear
                        },
                        sortBy: [SortDescriptor(\.journalId)]
                    )
                )
                hasher.combine(journals.count)
                for journal in journals {
                    hasher.combine(journal.journalId)
                    hasher.combine(journal.voucherNo)
                    hasher.combine(journal.updatedAt.timeIntervalSinceReferenceDate)
                    hasher.combine(journal.approvedAt?.timeIntervalSinceReferenceDate ?? 0)
                }

                let candidates = try modelContext.fetch(
                    FetchDescriptor<PostingCandidateEntity>(
                        predicate: #Predicate {
                            $0.businessId == businessId && $0.taxYear == fiscalYear
                        },
                        sortBy: [SortDescriptor(\.candidateId)]
                    )
                )
                hasher.combine(candidates.count)
                for candidate in candidates {
                    hasher.combine(candidate.candidateId)
                    hasher.combine(candidate.statusRaw)
                    hasher.combine(candidate.updatedAt.timeIntervalSinceReferenceDate)
                }
            }

            let categories = try modelContext.fetch(
                FetchDescriptor<PPCategory>(
                    sortBy: [SortDescriptor(\.id)]
                )
            )
            hasher.combine(categories.count)
            for category in categories {
                hasher.combine(category.id)
                hasher.combine(category.name)
                hasher.combine(category.archivedAt?.timeIntervalSinceReferenceDate ?? 0)
                hasher.combine(category.linkedAccountId ?? "")
            }

            let fixedAssets = try modelContext.fetch(
                FetchDescriptor<PPFixedAsset>(
                    sortBy: [SortDescriptor(\.id)]
                )
            )
            hasher.combine(fixedAssets.count)
            for asset in fixedAssets {
                hasher.combine(asset.id)
                hasher.combine(asset.updatedAt.timeIntervalSinceReferenceDate)
                hasher.combine(asset.name)
                hasher.combine(asset.acquisitionCost)
                hasher.combine(asset.businessUsePercent)
            }

            let inventoryRecords = try modelContext.fetch(
                FetchDescriptor<PPInventoryRecord>(
                    predicate: #Predicate { $0.fiscalYear == fiscalYear },
                    sortBy: [SortDescriptor(\.id)]
                )
            )
            hasher.combine(inventoryRecords.count)
            for record in inventoryRecords {
                hasher.combine(record.id)
                hasher.combine(record.updatedAt.timeIntervalSinceReferenceDate)
                hasher.combine(record.openingInventory)
                hasher.combine(record.purchases)
                hasher.combine(record.closingInventory)
            }

            return hasher.finalize()
        } catch {
            if let fallbackSnapshot {
                return dataRevision(for: fallbackSnapshot)
            }
            let fallbackSnapshot = snapshotProvider(fiscalYear)
            return dataRevision(for: fallbackSnapshot)
        }
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

    private func taxStatePreflightErrors(context: EtaxExportContext) -> [EtaxExportError] {
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

    private func accountingPreflightErrors(
        context: FilingPreflightContext,
        exportContext: EtaxExportContext
    ) -> [EtaxExportError] {
        guard let businessId = exportContext.businessId else {
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
