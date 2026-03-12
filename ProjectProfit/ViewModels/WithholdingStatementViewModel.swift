import Foundation
import SwiftData

@Observable
@MainActor
final class WithholdingStatementViewModel {
    enum ExportResult: Identifiable {
        case success(url: URL)
        case failure(message: String)

        var id: String {
            switch self {
            case .success(let url):
                return "success-\(url.absoluteString)"
            case .failure(let message):
                return "failure-\(message)"
            }
        }
    }

    private let queryUseCase: WithholdingStatementQueryUseCase
    private let exporter: @MainActor (ExportCoordinator.ExportFormat, ExportCoordinator.WithholdingStatementExportOptions) throws -> URL

    var fiscalYear: Int
    var annualSummary: WithholdingStatementAnnualSummary?
    var isLoading = false
    var errorMessage: String?
    var exportResult: ExportResult?

    init(
        modelContext: ModelContext,
        exporter: @escaping @MainActor (ExportCoordinator.ExportFormat, ExportCoordinator.WithholdingStatementExportOptions) throws -> URL
    ) {
        self.queryUseCase = WithholdingStatementQueryUseCase(modelContext: modelContext)
        self.exporter = exporter
        self.fiscalYear = currentFiscalYear(startMonth: FiscalYearSettings.startMonth) - 1
    }

    func generatePreview() {
        isLoading = true
        defer { isLoading = false }

        do {
            annualSummary = try queryUseCase.summary(fiscalYear: fiscalYear)
            errorMessage = nil
        } catch {
            annualSummary = nil
            errorMessage = error.localizedDescription
        }
    }

    func exportAnnual(format: ExportCoordinator.ExportFormat) {
        guard let annualSummary else { return }
        export(
            format: format,
            options: ExportCoordinator.WithholdingStatementExportOptions(
                scope: .annualSummary,
                annualSummary: annualSummary,
                document: nil
            )
        )
    }

    func exportPayee(_ document: WithholdingStatementDocument, format: ExportCoordinator.ExportFormat) {
        guard let annualSummary else { return }
        export(
            format: format,
            options: ExportCoordinator.WithholdingStatementExportOptions(
                scope: .payee(document.counterpartyId),
                annualSummary: annualSummary,
                document: document
            )
        )
    }

    private func export(
        format: ExportCoordinator.ExportFormat,
        options: ExportCoordinator.WithholdingStatementExportOptions
    ) {
        do {
            let url = try exporter(format, options)
            exportResult = .success(url: url)
        } catch {
            exportResult = .failure(message: error.localizedDescription)
        }
    }
}
