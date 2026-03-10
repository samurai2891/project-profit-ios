import Foundation

/// 全 export サービスを統合するコーディネーター
@MainActor
enum ExportCoordinator {

    // MARK: - Types

    enum ExportFormat: String, CaseIterable, Sendable {
        case csv
        case pdf
        case xtx

        var label: String {
            switch self {
            case .csv: "CSV"
            case .pdf: "PDF"
            case .xtx: "XTX"
            }
        }

        var fileExtension: String { rawValue }
    }

    enum ExportTarget: String, CaseIterable, Sendable {
        case profitLoss
        case balanceSheet
        case trialBalance
        case journal
        case ledger
        case transactions
        case subLedger
        case etax
        case fixedAssets

        var label: String {
            switch self {
            case .profitLoss: "損益計算書"
            case .balanceSheet: "貸借対照表"
            case .trialBalance: "残高試算表"
            case .journal: "仕訳帳"
            case .ledger: "総勘定元帳"
            case .transactions: "取引履歴"
            case .subLedger: "補助簿"
            case .etax: "e-Tax"
            case .fixedAssets: "固定資産台帳"
            }
        }

        var filePrefix: String {
            switch self {
            case .profitLoss: "profit_loss"
            case .balanceSheet: "balance_sheet"
            case .trialBalance: "trial_balance"
            case .journal: "journal"
            case .ledger: "ledger"
            case .transactions: "transactions"
            case .subLedger: "sub_ledger"
            case .etax: "etax"
            case .fixedAssets: "fixed_assets"
            }
        }

        var requiresPreflight: Bool {
            switch self {
            case .profitLoss, .balanceSheet, .trialBalance, .journal, .ledger, .fixedAssets, .etax:
                return true
            case .transactions, .subLedger:
                return false
            }
        }
    }

    enum ExportError: LocalizedError {
        case dataUnavailable
        case ledgerAccountRequired
        case transactionsRequired
        case subLedgerConfigurationRequired
        case etaxFormRequired
        case preflightBlocked([String])
        case unsupportedFormat(ExportTarget, ExportFormat)
        case etaxGenerationFailed(String)
        case fileWriteFailed

        var errorDescription: String? {
            switch self {
            case .dataUnavailable:
                return "出力データが取得できません"
            case .ledgerAccountRequired:
                return "元帳出力には勘定科目の指定が必要です"
            case .transactionsRequired:
                return "取引履歴出力に必要な対象データがありません"
            case .subLedgerConfigurationRequired:
                return "補助簿出力に必要な設定が不足しています"
            case .etaxFormRequired:
                return "e-Tax出力用のフォームが未生成です"
            case .preflightBlocked(let messages):
                return messages.joined(separator: "\n")
            case .unsupportedFormat(let target, let format):
                return "\(target.label)の\(format.label)出力は未対応です"
            case .etaxGenerationFailed(let message):
                return message
            case .fileWriteFailed:
                return "ファイルの書き込みに失敗しました"
            }
        }
    }

    struct LedgerExportOptions {
        let accountId: String
        let accountName: String
        let accountCode: String
    }

    struct TransactionExportOptions {
        let transactions: [PPTransaction]
    }

    struct SubLedgerExportOptions {
        let type: SubLedgerType
        let startDate: Date?
        let endDate: Date?
        let accountFilter: String?
        let counterpartyFilter: String?
    }

    struct EtaxExportOptions {
        let form: EtaxForm
    }

    // MARK: - Export

    /// 指定の帳票をフォーマットでエクスポートし、一時ファイルのURLを返す
    static func export(
        target: ExportTarget,
        format: ExportFormat,
        fiscalYear: Int,
        dataStore: DataStore,
        ledgerOptions: LedgerExportOptions? = nil,
        transactionOptions: TransactionExportOptions? = nil,
        subLedgerOptions: SubLedgerExportOptions? = nil,
        etaxOptions: EtaxExportOptions? = nil
    ) throws -> URL {
        if target.requiresPreflight {
            try validatePreflight(fiscalYear: fiscalYear, dataStore: dataStore)
        }

        let content: ExportContent = try generateContent(
            target: target,
            format: format,
            fiscalYear: fiscalYear,
            dataStore: dataStore,
            ledgerOptions: ledgerOptions,
            transactionOptions: transactionOptions,
            subLedgerOptions: subLedgerOptions,
            etaxOptions: etaxOptions
        )

        let fileName = makeFileName(target: target, fiscalYear: fiscalYear, format: format)
        return try writeToTempFile(content: content, fileName: fileName)
    }

    private static func validatePreflight(
        fiscalYear: Int,
        dataStore: DataStore
    ) throws {
        guard let businessId = dataStore.businessProfile?.id else {
            return
        }

        let report = try FilingPreflightUseCase(modelContext: dataStore.modelContext).preflightReport(
            businessId: businessId,
            taxYear: fiscalYear,
            context: .export
        )

        let blockingMessages = report.blockingIssues.map(\.message)
        guard blockingMessages.isEmpty else {
            throw ExportError.preflightBlocked(blockingMessages)
        }
    }

    // MARK: - Content Generation

    private enum ExportContent {
        case text(String)
        case data(Data)
    }

    private static func generateContent(
        target: ExportTarget,
        format: ExportFormat,
        fiscalYear: Int,
        dataStore: DataStore,
        ledgerOptions: LedgerExportOptions?,
        transactionOptions: TransactionExportOptions?,
        subLedgerOptions: SubLedgerExportOptions?,
        etaxOptions: EtaxExportOptions?
    ) throws -> ExportContent {
        let projected = dataStore.projectedCanonicalJournals(fiscalYear: fiscalYear)
        let accounts = dataStore.accounts
        let startMonth = FiscalYearSettings.startMonth

        switch (target, format) {
        // MARK: Journal
        case (.journal, .csv):
            let csv = ReportCSVExportService.exportJournalCSV(
                entries: projected.entries,
                lines: projected.lines,
                accounts: accounts
            )
            return .text(csv)

        case (.journal, .pdf):
            let pdf = PDFExportService.exportJournalPDF(
                entries: projected.entries,
                lines: projected.lines,
                accounts: accounts,
                fiscalYear: fiscalYear
            )
            return .data(pdf)

        // MARK: Profit & Loss
        case (.profitLoss, .csv):
            let report = AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            )
            return .text(ReportCSVExportService.exportProfitLossCSV(report: report))

        case (.profitLoss, .pdf):
            let report = AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            )
            return .data(PDFExportService.exportProfitLossPDF(report: report))

        // MARK: Balance Sheet
        case (.balanceSheet, .csv):
            let report = AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            )
            return .text(ReportCSVExportService.exportBalanceSheetCSV(report: report))

        case (.balanceSheet, .pdf):
            let report = AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            )
            return .data(PDFExportService.exportBalanceSheetPDF(report: report))

        // MARK: Trial Balance
        case (.trialBalance, .csv):
            let report = AccountingReportService.generateTrialBalance(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            )
            return .text(ReportCSVExportService.exportTrialBalanceCSV(rows: report.rows))

        case (.trialBalance, .pdf):
            let report = AccountingReportService.generateTrialBalance(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            )
            return .data(PDFExportService.exportTrialBalancePDF(report: report))

        // MARK: Ledger
        case (.ledger, .csv):
            guard let opts = ledgerOptions else { throw ExportError.ledgerAccountRequired }
            let entries = dataStore.getLedgerEntries(accountId: opts.accountId)
            return .text(ReportCSVExportService.exportLedgerCSV(
                accountName: opts.accountName,
                accountCode: opts.accountCode,
                entries: entries
            ))

        case (.ledger, .pdf):
            guard let opts = ledgerOptions else { throw ExportError.ledgerAccountRequired }
            let entries = dataStore.getLedgerEntries(accountId: opts.accountId)
            return .data(PDFExportService.exportLedgerPDF(
                accountName: opts.accountName,
                accountCode: opts.accountCode,
                entries: entries,
                fiscalYear: fiscalYear
            ))

        case (.profitLoss, .xtx),
             (.balanceSheet, .xtx),
             (.trialBalance, .xtx),
             (.journal, .xtx),
             (.ledger, .xtx):
            throw ExportError.unsupportedFormat(target, format)

        // MARK: Transactions
        case (.transactions, .csv):
            guard let opts = transactionOptions else {
                throw ExportError.transactionsRequired
            }
            return .text(generateCSV(
                transactions: opts.transactions,
                getCategory: { dataStore.getCategory(id: $0) },
                getProject: { dataStore.getProject(id: $0) }
            ))

        case (.transactions, _):
            throw ExportError.unsupportedFormat(target, format)

        // MARK: Sub Ledger
        case (.subLedger, .csv):
            guard let opts = subLedgerOptions else {
                throw ExportError.subLedgerConfigurationRequired
            }
            return .text(dataStore.exportSubLedgerCSV(
                type: opts.type,
                startDate: opts.startDate,
                endDate: opts.endDate,
                accountFilter: opts.accountFilter,
                counterpartyFilter: opts.counterpartyFilter
            ))

        case (.subLedger, _):
            throw ExportError.unsupportedFormat(target, format)

        // MARK: e-Tax
        case (.etax, .xtx):
            guard let opts = etaxOptions else {
                throw ExportError.etaxFormRequired
            }
            switch EtaxXtxExporter.generateXtx(form: opts.form) {
            case .success(let data):
                return .data(data)
            case .failure(let error):
                throw ExportError.etaxGenerationFailed(error.description)
            }

        case (.etax, .csv):
            guard let opts = etaxOptions else {
                throw ExportError.etaxFormRequired
            }
            switch EtaxXtxExporter.generateCsv(form: opts.form) {
            case .success(let data):
                return .data(data)
            case .failure(let error):
                throw ExportError.etaxGenerationFailed(error.description)
            }

        case (.etax, _):
            throw ExportError.unsupportedFormat(target, format)

        // MARK: Fixed Assets
        case (.fixedAssets, .csv):
            let assets = dataStore.fixedAssets
            return .text(ReportCSVExportService.exportFixedAssetsCSV(
                assets: assets,
                calculateAccumulated: { asset in
                    let prior = dataStore.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
                    guard let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: fiscalYear, priorAccumulatedDepreciation: prior) else { return prior }
                    return calc.accumulatedDepreciation
                },
                calculateCurrentYear: { asset in
                    let prior = dataStore.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
                    return DepreciationEngine.calculate(asset: asset, fiscalYear: fiscalYear, priorAccumulatedDepreciation: prior)?.annualAmount ?? 0
                }
            ))

        case (.fixedAssets, .pdf):
            let assets = dataStore.fixedAssets
            return .data(PDFExportService.exportFixedAssetsPDF(
                assets: assets,
                fiscalYear: fiscalYear,
                calculateAccumulated: { asset in
                    let prior = dataStore.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
                    guard let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: fiscalYear, priorAccumulatedDepreciation: prior) else { return prior }
                    return calc.accumulatedDepreciation
                },
                calculateCurrentYear: { asset in
                    let prior = dataStore.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
                    return DepreciationEngine.calculate(asset: asset, fiscalYear: fiscalYear, priorAccumulatedDepreciation: prior)?.annualAmount ?? 0
                }
            ))

        case (.fixedAssets, .xtx):
            throw ExportError.unsupportedFormat(target, format)
        }
    }

    // MARK: - File Naming

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return formatter
    }()

    static func makeFileName(target: ExportTarget, fiscalYear: Int, format: ExportFormat) -> String {
        let dateStr = dateFormatter.string(from: Date())
        return "\(target.filePrefix)_\(fiscalYear)_\(dateStr).\(format.fileExtension)"
    }

    // MARK: - File I/O

    private static func writeToTempFile(content: ExportContent, fileName: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        switch content {
        case .text(let text):
            guard let data = text.data(using: .utf8) else {
                throw ExportError.fileWriteFailed
            }
            try data.write(to: fileURL, options: .atomic)
        case .data(let data):
            try data.write(to: fileURL, options: .atomic)
        }

        return fileURL
    }
}
