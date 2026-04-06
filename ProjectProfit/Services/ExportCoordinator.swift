import Foundation
import SwiftData

/// 全 export サービスを統合するコーディネーター
@MainActor
enum ExportCoordinator {

    // MARK: - Types

    enum ExportFormat: String, CaseIterable, Sendable {
        case csv
        case pdf
        case xtx
        case xlsx

        var label: String {
            switch self {
            case .csv: "CSV"
            case .pdf: "PDF"
            case .xtx: "XTX"
            case .xlsx: "Excel"
            }
        }

        var fileExtension: String { rawValue }
    }

    enum ExportTarget: String, CaseIterable, Sendable {
        case profitLoss
        case balanceSheet
        case trialBalance
        case cashBook
        case bankAccountBook
        case accountsReceivableBook
        case accountsPayableBook
        case expenseBook
        case generalLedger
        case journalBook
        case transportationExpense
        case whiteTaxBookkeeping
        case journal
        case ledger
        case transactions
        case subLedger
        case etax
        case withholdingStatement
        case fixedAssetRegister
        case fixedAssetDepreciation
        case legacyLedgerBook

        var label: String {
            switch self {
            case .profitLoss: "損益計算書"
            case .balanceSheet: "貸借対照表"
            case .trialBalance: "残高試算表"
            case .cashBook: "現金出納帳"
            case .bankAccountBook: "預金出納帳"
            case .accountsReceivableBook: "売掛帳"
            case .accountsPayableBook: "買掛帳"
            case .expenseBook: "経費帳"
            case .generalLedger: "総勘定元帳"
            case .journalBook: "仕訳帳"
            case .transportationExpense: "交通費精算書"
            case .whiteTaxBookkeeping: "白色申告用 簡易帳簿"
            case .journal: "仕訳帳"
            case .ledger: "総勘定元帳"
            case .transactions: "取引履歴"
            case .subLedger: "補助簿"
            case .etax: "e-Tax"
            case .withholdingStatement: "支払調書"
            case .fixedAssetRegister: "固定資産台帳"
            case .fixedAssetDepreciation: "減価償却明細表"
            case .legacyLedgerBook: "旧台帳（互換）"
            }
        }

        var filePrefix: String {
            switch self {
            case .profitLoss: "profit_loss"
            case .balanceSheet: "balance_sheet"
            case .trialBalance: "trial_balance"
            case .cashBook: "cash_book"
            case .bankAccountBook: "bank_account_book"
            case .accountsReceivableBook: "accounts_receivable_book"
            case .accountsPayableBook: "accounts_payable_book"
            case .expenseBook: "expense_book"
            case .generalLedger: "general_ledger"
            case .journalBook: "journal_book"
            case .transportationExpense: "transportation_expense"
            case .whiteTaxBookkeeping: "white_tax_bookkeeping"
            case .journal: "journal"
            case .ledger: "ledger"
            case .transactions: "transactions"
            case .subLedger: "sub_ledger"
            case .etax: "etax"
            case .withholdingStatement: "withholding_statement"
            case .fixedAssetRegister: "fixed_asset_register"
            case .fixedAssetDepreciation: "fixed_asset_depreciation"
            case .legacyLedgerBook: "legacy_ledger"
            }
        }

        /// 現在のアプリ導線で許可する target/format 組み合わせ。
        /// ExportMenuButton / EtaxExportView / 旧台帳詳細画面の実使用範囲を正本として管理する。
        var supportedFormats: Set<ExportFormat> {
            switch self {
            case .profitLoss, .balanceSheet, .trialBalance,
                 .cashBook, .bankAccountBook, .accountsReceivableBook, .accountsPayableBook,
                 .expenseBook, .generalLedger, .journalBook, .transportationExpense,
                 .whiteTaxBookkeeping,
                 .fixedAssetRegister, .fixedAssetDepreciation:
                return [.csv, .pdf, .xlsx]
            case .withholdingStatement:
                return [.csv, .pdf]
            case .transactions:
                return [.csv]
            case .subLedger:
                return [.csv, .pdf]
            case .journal, .ledger:
                return [.csv, .pdf, .xlsx]
            case .etax:
                return [.csv, .xtx]
            case .legacyLedgerBook:
                // 旧台帳は compat export target としてだけ残す。
                return [.csv, .pdf, .xlsx]
            }
        }

        /// 申告前チェックが必要な出力だけ true。
        /// 旧台帳/汎用CSV（取引履歴/補助簿）は日常運用で使うため preflight を要求しない。
        var requiresPreflight: Bool {
            switch self {
            case .profitLoss, .balanceSheet, .trialBalance,
                 .cashBook, .bankAccountBook, .accountsReceivableBook, .accountsPayableBook,
                 .expenseBook, .generalLedger, .journalBook, .transportationExpense,
                 .whiteTaxBookkeeping, .journal, .ledger,
                 .fixedAssetRegister, .fixedAssetDepreciation, .etax, .withholdingStatement:
                return true
            case .transactions, .subLedger, .legacyLedgerBook:
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

    struct LegacyLedgerExportOptions {
        let bookId: UUID
        let bookTitle: String
        let ledgerType: LedgerType
        let metadataJSON: String
        let includeInvoice: Bool
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

    struct WithholdingStatementExportOptions {
        enum Scope: Sendable, Equatable {
            case annualSummary
            case payee(UUID)
        }

        let scope: Scope
        let annualSummary: WithholdingStatementAnnualSummary
        let document: WithholdingStatementDocument?
    }

    struct LedgerBookSelectionOptions {
        let bookId: UUID?
        let ledgerType: LedgerType

        init(bookId: UUID? = nil, ledgerType: LedgerType) {
            self.bookId = bookId
            self.ledgerType = ledgerType
        }
    }

    @MainActor
    private struct AccountingBookExportSource {
        let fiscalYear: Int
        private let support: AccountingReadSupport
        private let projectedJournalQuery: ProjectedJournalReadModelQuery
        private let ledgerQueryUseCase: LedgerQueryUseCase
        private let subLedgerQueryUseCase: SubLedgerQueryUseCase
        let modelContext: ModelContext

        init(modelContext: ModelContext, fiscalYear: Int) {
            let support = AccountingReadSupport(modelContext: modelContext)
            self.modelContext = modelContext
            self.fiscalYear = fiscalYear
            self.support = support
            self.projectedJournalQuery = ProjectedJournalReadModelQuery(support: support)
            self.ledgerQueryUseCase = LedgerQueryUseCase(modelContext: modelContext)
            self.subLedgerQueryUseCase = SubLedgerQueryUseCase(modelContext: modelContext)
        }

        func journalPayload() -> (entries: [PPJournalEntry], lines: [PPJournalLine], accounts: [PPAccount]) {
            let context = support.canonicalReadContext(fiscalYear: fiscalYear)
            let projected = projectedJournalQuery.snapshot(fiscalYear: fiscalYear)
            return (
                entries: projected.entries,
                lines: projected.lines,
                accounts: legacyAccounts(for: context)
            )
        }

        func ledgerEntries(options: LedgerExportOptions) -> [AccountingLedgerEntry] {
            ledgerQueryUseCase.snapshot(accountId: options.accountId).entries
        }

        func subLedgerSnapshot(options: SubLedgerExportOptions) -> SubLedgerSnapshot {
            let year = options.startDate.map { Calendar.current.component(.year, from: $0) } ?? fiscalYear
            return subLedgerQueryUseCase.snapshot(
                type: options.type,
                year: year,
                accountFilter: options.accountFilter,
                counterpartyFilter: options.counterpartyFilter
            )
        }

        func account(id: String) -> PPAccount? {
            support.fetchAccounts().first { $0.id == id }
        }

        func latestLegacyBook(type: LedgerType) -> SDLedgerBook? {
            LedgerDataStore(modelContext: modelContext)
                .books(ofType: type)
                .sorted { $0.updatedAt > $1.updatedAt }
                .first
        }
    }

    // MARK: - Export

    /// 指定の帳票をフォーマットでエクスポートし、一時ファイルのURLを返す
    static func export(
        target: ExportTarget,
        format: ExportFormat,
        fiscalYear: Int,
        modelContext: ModelContext,
        skipPreflightValidation: Bool = false,
        ledgerOptions: LedgerExportOptions? = nil,
        transactionOptions: TransactionExportOptions? = nil,
        subLedgerOptions: SubLedgerExportOptions? = nil,
        etaxOptions: EtaxExportOptions? = nil,
        withholdingStatementOptions: WithholdingStatementExportOptions? = nil,
        ledgerBookSelectionOptions: LedgerBookSelectionOptions? = nil,
        legacyLedgerOptions: LegacyLedgerExportOptions? = nil
    ) throws -> URL {
        try exportInternal(
            target: target,
            format: format,
            fiscalYear: fiscalYear,
            modelContext: modelContext,
            skipPreflightValidation: skipPreflightValidation,
            ledgerOptions: ledgerOptions,
            transactionOptions: transactionOptions,
            subLedgerOptions: subLedgerOptions,
            etaxOptions: etaxOptions,
            withholdingStatementOptions: withholdingStatementOptions,
            ledgerBookSelectionOptions: ledgerBookSelectionOptions,
            legacyLedgerOptions: legacyLedgerOptions
        )
    }

    /// fiscalYear を持たない旧台帳出力用のコンビニエンス API。
    static func export(
        format: ExportFormat,
        modelContext: ModelContext,
        legacyLedgerOptions: LegacyLedgerExportOptions
    ) throws -> URL {
        try exportInternal(
            target: .legacyLedgerBook,
            format: format,
            fiscalYear: nil,
            modelContext: modelContext,
            skipPreflightValidation: true,
            ledgerOptions: nil,
            transactionOptions: nil,
            subLedgerOptions: nil,
            etaxOptions: nil,
            withholdingStatementOptions: nil,
            ledgerBookSelectionOptions: nil,
            legacyLedgerOptions: legacyLedgerOptions
        )
    }

    private static func exportInternal(
        target: ExportTarget,
        format: ExportFormat,
        fiscalYear: Int?,
        modelContext: ModelContext,
        skipPreflightValidation: Bool,
        ledgerOptions: LedgerExportOptions?,
        transactionOptions: TransactionExportOptions?,
        subLedgerOptions: SubLedgerExportOptions?,
        etaxOptions: EtaxExportOptions?,
        withholdingStatementOptions: WithholdingStatementExportOptions?,
        ledgerBookSelectionOptions: LedgerBookSelectionOptions?,
        legacyLedgerOptions: LegacyLedgerExportOptions?
    ) throws -> URL {
        let supportedFormats = supportedFormats(for: target, legacyLedgerOptions: legacyLedgerOptions)
        guard supportedFormats.contains(format) else {
            throw ExportError.unsupportedFormat(target, format)
        }

        if target.requiresPreflight && !skipPreflightValidation {
            guard let fiscalYear else {
                throw ExportError.dataUnavailable
            }
            try validatePreflight(fiscalYear: fiscalYear, modelContext: modelContext)
        }

        let content = try generateContent(
            target: target,
            format: format,
            fiscalYear: fiscalYear,
            modelContext: modelContext,
            ledgerOptions: ledgerOptions,
            transactionOptions: transactionOptions,
            subLedgerOptions: subLedgerOptions,
            etaxOptions: etaxOptions,
            withholdingStatementOptions: withholdingStatementOptions,
            ledgerBookSelectionOptions: ledgerBookSelectionOptions,
            legacyLedgerOptions: legacyLedgerOptions
        )

        let fileName: String
        if let legacyLedgerOptions {
            fileName = makeLegacyLedgerFileName(options: legacyLedgerOptions, format: format)
        } else if let fiscalYear {
            fileName = makeFileName(target: target, fiscalYear: fiscalYear, format: format)
        } else {
            throw ExportError.dataUnavailable
        }
        return try writeToTempFile(content: content, fileName: fileName)
    }

    private static func supportedFormats(
        for target: ExportTarget,
        legacyLedgerOptions: LegacyLedgerExportOptions?
    ) -> Set<ExportFormat> {
        guard target == .legacyLedgerBook, let legacyLedgerOptions else {
            return target.supportedFormats
        }
        return LegacyLedgerExportAdapter.supportedFormats(for: legacyLedgerOptions.ledgerType)
    }

    private static func validatePreflight(
        fiscalYear: Int,
        modelContext: ModelContext
    ) throws {
        let businessId = EtaxExportContextQueryUseCase(modelContext: modelContext)
            .context(taxYear: fiscalYear)
            .businessId
        guard let businessId else {
            return
        }

        let report = try FilingPreflightUseCase(modelContext: modelContext).preflightReport(
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
        case fileWriter((URL) throws -> Void)
    }

    @MainActor
    private enum LegacyLedgerExportAdapter {
        static func supportedFormats(for ledgerType: LedgerType) -> Set<ExportFormat> {
            switch ledgerType {
            case .cashBook, .cashBookInvoice,
                 .bankAccountBook, .bankAccountBookInvoice,
                 .accountsReceivable, .accountsPayable,
                 .generalLedger, .generalLedgerInvoice,
                 .journal:
                return [.csv, .pdf, .xlsx]
            case .expenseBook, .expenseBookInvoice,
                 .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
                return [.csv, .pdf]
            case .fixedAssetDepreciation, .fixedAssetRegister, .transportationExpense:
                return [.pdf]
            }
        }

        static func generateContent(
            format: ExportFormat,
            modelContext: ModelContext,
            options: LegacyLedgerExportOptions
        ) throws -> ExportContent {
            let store = LedgerDataStore(modelContext: modelContext)

            switch format {
            case .csv:
                return .text(try csv(store: store, options: options))
            case .pdf:
                return .data(try pdf(store: store, options: options))
            case .xlsx:
                return .fileWriter { url in
                    try writeXLSX(store: store, options: options, to: url)
                }
            case .xtx:
                throw ExportError.unsupportedFormat(.legacyLedgerBook, .xtx)
            }
        }

        private static func csv(
            store: LedgerDataStore,
            options: LegacyLedgerExportOptions
        ) throws -> String {
            let service = CSVExportService.shared

            switch options.ledgerType {
            case .cashBook, .cashBookInvoice:
                return service.exportCashBook(
                    metadata: LedgerBridge.decodeCashBookMetadata(from: options.metadataJSON),
                    entries: store.cashBookEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice
                )

            case .bankAccountBook, .bankAccountBookInvoice:
                return service.exportBankAccountBook(
                    metadata: LedgerBridge.decodeBankAccountBookMetadata(from: options.metadataJSON),
                    entries: store.bankAccountBookEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice
                )

            case .accountsReceivable:
                return service.exportAccountsReceivable(
                    metadata: LedgerBridge.decodeAccountsReceivableMetadata(from: options.metadataJSON),
                    entries: store.accountsReceivableEntries(for: options.bookId)
                )

            case .accountsPayable:
                return service.exportAccountsPayable(
                    metadata: LedgerBridge.decodeAccountsPayableMetadata(from: options.metadataJSON),
                    entries: store.accountsPayableEntries(for: options.bookId)
                )

            case .expenseBook, .expenseBookInvoice:
                return service.exportExpenseBook(
                    metadata: LedgerBridge.decodeExpenseBookMetadata(from: options.metadataJSON),
                    entries: store.expenseBookEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice
                )

            case .generalLedger, .generalLedgerInvoice:
                return service.exportGeneralLedger(
                    metadata: LedgerBridge.decodeGeneralLedgerMetadata(from: options.metadataJSON),
                    entries: store.generalLedgerEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice
                )

            case .journal:
                return service.exportJournal(entries: store.journalEntries(for: options.bookId))

            case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
                return service.exportWhiteTaxBookkeeping(
                    metadata: LedgerBridge.decodeWhiteTaxBookkeepingMetadata(from: options.metadataJSON),
                    entries: store.whiteTaxBookkeepingEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice
                )

            case .fixedAssetDepreciation, .fixedAssetRegister, .transportationExpense:
                throw ExportError.unsupportedFormat(.legacyLedgerBook, .csv)
            }
        }

        private static func pdf(
            store: LedgerDataStore,
            options: LegacyLedgerExportOptions
        ) throws -> Data {
            let service = LedgerPDFExportService.shared

            switch options.ledgerType {
            case .cashBook, .cashBookInvoice:
                return service.exportCashBook(
                    metadata: LedgerBridge.decodeCashBookMetadata(from: options.metadataJSON),
                    entries: store.cashBookEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice
                )

            case .bankAccountBook, .bankAccountBookInvoice:
                return service.exportBankAccountBook(
                    metadata: LedgerBridge.decodeBankAccountBookMetadata(from: options.metadataJSON),
                    entries: store.bankAccountBookEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice
                )

            case .accountsReceivable:
                return service.exportAccountsReceivable(
                    metadata: LedgerBridge.decodeAccountsReceivableMetadata(from: options.metadataJSON),
                    entries: store.accountsReceivableEntries(for: options.bookId)
                )

            case .accountsPayable:
                return service.exportAccountsPayable(
                    metadata: LedgerBridge.decodeAccountsPayableMetadata(from: options.metadataJSON),
                    entries: store.accountsPayableEntries(for: options.bookId)
                )

            case .expenseBook, .expenseBookInvoice:
                return service.exportExpenseBook(
                    metadata: LedgerBridge.decodeExpenseBookMetadata(from: options.metadataJSON),
                    entries: store.expenseBookEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice
                )

            case .generalLedger, .generalLedgerInvoice:
                return service.exportGeneralLedger(
                    metadata: LedgerBridge.decodeGeneralLedgerMetadata(from: options.metadataJSON),
                    entries: store.generalLedgerEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice
                )

            case .journal:
                return service.exportJournal(entries: store.journalEntries(for: options.bookId))

            case .transportationExpense:
                return service.exportTransportationExpense(
                    metadata: LedgerBridge.decodeTransportationExpenseMetadata(from: options.metadataJSON),
                    entries: store.transportationExpenseEntries(for: options.bookId)
                )

            case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
                return service.exportWhiteTaxBookkeeping(
                    metadata: LedgerBridge.decodeWhiteTaxBookkeepingMetadata(from: options.metadataJSON),
                    entries: store.whiteTaxBookkeepingEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice
                )

            case .fixedAssetDepreciation:
                return service.exportFixedAssetDepreciation(
                    metadata: LedgerBridge.decodeFixedAssetDepreciationMetadata(from: options.metadataJSON),
                    entries: store.fixedAssetDepreciationEntries(for: options.bookId)
                )

            case .fixedAssetRegister:
                return service.exportFixedAssetRegister(
                    metadata: LedgerBridge.decodeFixedAssetRegisterMetadata(from: options.metadataJSON),
                    entries: store.fixedAssetRegisterEntries(for: options.bookId)
                )
            }
        }

        private static func writeXLSX(
            store: LedgerDataStore,
            options: LegacyLedgerExportOptions,
            to url: URL
        ) throws {
            let service = LedgerExcelExportService.shared
            let path = url.path

            switch options.ledgerType {
            case .cashBook, .cashBookInvoice:
                service.exportCashBook(
                    metadata: LedgerBridge.decodeCashBookMetadata(from: options.metadataJSON),
                    entries: store.cashBookEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice,
                    to: path
                )

            case .bankAccountBook, .bankAccountBookInvoice:
                service.exportBankAccountBook(
                    metadata: LedgerBridge.decodeBankAccountBookMetadata(from: options.metadataJSON),
                    entries: store.bankAccountBookEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice,
                    to: path
                )

            case .accountsReceivable:
                service.exportAccountsReceivable(
                    metadata: LedgerBridge.decodeAccountsReceivableMetadata(from: options.metadataJSON),
                    entries: store.accountsReceivableEntries(for: options.bookId),
                    to: path
                )

            case .accountsPayable:
                service.exportAccountsPayable(
                    metadata: LedgerBridge.decodeAccountsPayableMetadata(from: options.metadataJSON),
                    entries: store.accountsPayableEntries(for: options.bookId),
                    to: path
                )

            case .generalLedger, .generalLedgerInvoice:
                service.exportGeneralLedger(
                    metadata: LedgerBridge.decodeGeneralLedgerMetadata(from: options.metadataJSON),
                    entries: store.generalLedgerEntries(for: options.bookId),
                    includeInvoice: options.includeInvoice,
                    to: path
                )

            case .journal:
                service.exportJournal(entries: store.journalEntries(for: options.bookId), to: path)

            case .expenseBook, .expenseBookInvoice,
                 .fixedAssetDepreciation, .fixedAssetRegister,
                 .transportationExpense,
                 .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
                throw ExportError.unsupportedFormat(.legacyLedgerBook, .xlsx)
            }
        }
    }

    private static func exportSubLedgerCSV(entries: [SubLedgerEntry]) -> String {
        var lines: [String] = [
            "date,accountCode,accountName,memo,counterparty,debit,credit,runningBalance,counterAccountId,taxCategory"
        ]
        let formatter = ISO8601DateFormatter()
        for row in entries {
            let dateText = formatter.string(from: row.date)
            let memo = row.memo.replacingOccurrences(of: "\"", with: "\"\"")
            let accountName = row.accountName.replacingOccurrences(of: "\"", with: "\"\"")
            let counterparty = (row.counterparty ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let taxCategory = row.taxCategory?.rawValue ?? ""
            lines.append(
                "\(dateText),\(row.accountCode),\"\(accountName)\",\"\(memo)\",\"\(counterparty)\","
                + "\(row.debit),\(row.credit),\(row.runningBalance),"
                + "\(row.counterAccountId ?? ""),\(taxCategory)"
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func legacyLedgerOptions(
        from book: SDLedgerBook
    ) -> LegacyLedgerExportOptions? {
        guard let ledgerType = book.ledgerType else {
            return nil
        }
        return LegacyLedgerExportOptions(
            bookId: book.id,
            bookTitle: book.title,
            ledgerType: ledgerType,
            metadataJSON: book.metadataJSON,
            includeInvoice: book.includeInvoice
        )
    }

    private static func resolveLegacyLedgerOptions(
        selection: LedgerBookSelectionOptions?,
        source: AccountingBookExportSource
    ) -> LegacyLedgerExportOptions? {
        if let bookId = selection?.bookId {
            let store = LedgerDataStore(modelContext: source.modelContext)
            if let book = store.book(for: bookId) {
                return legacyLedgerOptions(from: book)
            }
        }
        guard let ledgerType = selection?.ledgerType,
              let book = source.latestLegacyBook(type: ledgerType) else {
            return nil
        }
        return legacyLedgerOptions(from: book)
    }

    private static func dateComponents(from date: Date) -> DateComponents {
        Calendar(identifier: .gregorian).dateComponents([.month, .day], from: date)
    }

    private static func shortDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    private static func invoiceType(for taxCategory: TaxCategory?) -> InvoiceType? {
        guard let taxCategory else { return nil }
        switch taxCategory {
        case .standardRate, .reducedRate:
            return .applicable
        default:
            return nil
        }
    }

    private static func includeInvoice(for entries: [SubLedgerEntry]) -> Bool {
        entries.contains { $0.taxCategory != nil }
    }

    private static func subLedgerEntries(
        source: AccountingBookExportSource,
        options: SubLedgerExportOptions?,
        fallbackType: SubLedgerType
    ) throws -> [SubLedgerEntry] {
        let effectiveOptions = options ?? SubLedgerExportOptions(
            type: fallbackType,
            startDate: nil,
            endDate: nil,
            accountFilter: nil,
            counterpartyFilter: nil
        )
        guard effectiveOptions.type == fallbackType else {
            throw ExportError.subLedgerConfigurationRequired
        }
        return source.subLedgerSnapshot(options: effectiveOptions).entries
    }

    private static func cashBookContent(
        entries: [SubLedgerEntry]
    ) -> (metadata: CashBookMetadata, entries: [CashBookEntry], includeInvoice: Bool) {
        let includeInvoice = includeInvoice(for: entries)
        return (
            metadata: CashBookMetadata(),
            entries: entries.map { row in
                let parts = dateComponents(from: row.date)
                return CashBookEntry(
                    month: parts.month ?? 0,
                    day: parts.day ?? 0,
                    description: row.memo,
                    account: row.counterAccountId ?? "",
                    income: row.debit > 0 ? row.debit : nil,
                    expense: row.credit > 0 ? row.credit : nil,
                    reducedTax: row.taxCategory == .reducedRate,
                    invoiceType: invoiceType(for: row.taxCategory)
                )
            },
            includeInvoice: includeInvoice
        )
    }

    private static func bankAccountBookContent(
        entries: [SubLedgerEntry]
    ) -> (metadata: BankAccountBookMetadata, entries: [BankAccountBookEntry], includeInvoice: Bool) {
        let includeInvoice = includeInvoice(for: entries)
        return (
            metadata: BankAccountBookMetadata(),
            entries: entries.map { row in
                let parts = dateComponents(from: row.date)
                return BankAccountBookEntry(
                    month: parts.month ?? 0,
                    day: parts.day ?? 0,
                    description: row.memo,
                    account: row.counterAccountId ?? "",
                    deposit: row.debit > 0 ? row.debit : nil,
                    withdrawal: row.credit > 0 ? row.credit : nil,
                    reducedTax: row.taxCategory == .reducedRate,
                    invoiceType: invoiceType(for: row.taxCategory)
                )
            },
            includeInvoice: includeInvoice
        )
    }

    private static func accountsReceivableContent(
        entries: [SubLedgerEntry]
    ) -> (metadata: AccountsReceivableMetadata, entries: [AccountsReceivableEntry]) {
        let clientName = entries.compactMap(\.counterparty).first ?? ""
        return (
            metadata: AccountsReceivableMetadata(clientName: clientName, carryForward: 0),
            entries: entries.map { row in
                let parts = dateComponents(from: row.date)
                return AccountsReceivableEntry(
                    month: parts.month ?? 0,
                    day: parts.day ?? 0,
                    counterAccount: row.counterAccountId ?? "",
                    description: row.memo,
                    salesAmount: row.debit > 0 ? row.debit : nil,
                    receivedAmount: row.credit > 0 ? row.credit : nil
                )
            }
        )
    }

    private static func accountsPayableContent(
        entries: [SubLedgerEntry]
    ) -> (metadata: AccountsPayableMetadata, entries: [AccountsPayableEntry]) {
        let supplierName = entries.compactMap(\.counterparty).first ?? ""
        return (
            metadata: AccountsPayableMetadata(supplierName: supplierName, carryForward: 0),
            entries: entries.map { row in
                let parts = dateComponents(from: row.date)
                return AccountsPayableEntry(
                    month: parts.month ?? 0,
                    day: parts.day ?? 0,
                    counterAccount: row.counterAccountId ?? "",
                    description: row.memo,
                    purchaseAmount: row.credit > 0 ? row.credit : nil,
                    paymentAmount: row.debit > 0 ? row.debit : nil
                )
            }
        )
    }

    private static func expenseBookContent(
        entries: [SubLedgerEntry],
        source: AccountingBookExportSource,
        accountId: String?
    ) -> (metadata: ExpenseBookMetadata, entries: [ExpenseBookEntry], includeInvoice: Bool) {
        let includeInvoice = includeInvoice(for: entries)
        let accountName = accountId.flatMap { source.account(id: $0)?.name } ?? entries.first?.accountName ?? ""
        return (
            metadata: ExpenseBookMetadata(accountName: accountName),
            entries: entries.map { row in
                let parts = dateComponents(from: row.date)
                return ExpenseBookEntry(
                    month: parts.month ?? 0,
                    day: parts.day ?? 0,
                    counterAccount: row.counterAccountId ?? "",
                    description: row.memo,
                    amount: max(row.debit, row.credit),
                    reducedTax: row.taxCategory == .reducedRate,
                    invoiceType: invoiceType(for: row.taxCategory)
                )
            },
            includeInvoice: includeInvoice
        )
    }

    private static func generalLedgerContent(
        source: AccountingBookExportSource,
        options: LedgerExportOptions
    ) -> (metadata: GeneralLedgerMetadata, entries: [GeneralLedgerEntry], includeInvoice: Bool) {
        let rawEntries = source.ledgerEntries(options: options)
        let includeInvoice = rawEntries.contains { $0.taxCategory != nil }
        let accountAttribute = source.account(id: options.accountId).map(accountCategory(for:))
        return (
            metadata: GeneralLedgerMetadata(
                accountName: options.accountName,
                accountAttribute: accountAttribute,
                carryForward: 0
            ),
            entries: rawEntries.map { row in
                let parts = dateComponents(from: row.date)
                return GeneralLedgerEntry(
                    month: parts.month ?? 0,
                    day: parts.day ?? 0,
                    counterAccount: row.counterparty ?? "",
                    description: row.memo,
                    debit: row.debit > 0 ? row.debit : nil,
                    credit: row.credit > 0 ? row.credit : nil,
                    reducedTax: row.taxCategory == .reducedRate,
                    invoiceType: invoiceType(for: row.taxCategory)
                )
            },
            includeInvoice: includeInvoice
        )
    }

    private static func journalEntriesContent(
        source: AccountingBookExportSource
    ) -> [JournalEntry] {
        let projected = source.journalPayload()
        let groupedLines = Dictionary(grouping: projected.lines, by: \.entryId)
        let accountsById = Dictionary(uniqueKeysWithValues: projected.accounts.map { ($0.id, $0.name) })

        return projected.entries.flatMap { entry in
            let lines = (groupedLines[entry.id] ?? []).sorted { $0.displayOrder < $1.displayOrder }
            guard !lines.isEmpty else { return [JournalEntry]() }
            return lines.enumerated().map { index, line in
                JournalEntry(
                    month: index == 0 ? Calendar.current.component(.month, from: entry.date) : 0,
                    day: index == 0 ? Calendar.current.component(.day, from: entry.date) : 0,
                    description: entry.memo,
                    debitAccount: line.debit > 0 ? accountsById[line.accountId] : nil,
                    debitAmount: line.debit > 0 ? line.debit : nil,
                    creditAccount: line.credit > 0 ? accountsById[line.accountId] : nil,
                    creditAmount: line.credit > 0 ? line.credit : nil,
                    isCompoundContinuation: index > 0
                )
            }
        }
    }

    private static func accountCategory(for account: PPAccount) -> AccountCategory {
        switch account.accountType {
        case .asset: return .asset
        case .liability: return .liability
        case .equity: return .capital
        case .revenue: return .sales
        case .expense: return .expense
        }
    }

    private static func whiteTaxBookkeepingContent(
        snapshot: WhiteTaxBookkeepingSnapshot
    ) -> (metadata: WhiteTaxBookkeepingMetadata, entries: [WhiteTaxBookkeepingEntry], includeInvoice: Bool) {
        let revenueAmount = snapshot.revenueRows.first(where: { $0.id == "shushi_revenue_sales" })?.amount
        let miscIncome = snapshot.revenueRows.first(where: { $0.id == "shushi_revenue_other" })?.amount
        let purchases = snapshot.inventoryRows.first(where: { $0.id == "shushi_inventory_purchases" })?.amount
        let expenseById = Dictionary(uniqueKeysWithValues: snapshot.expenseRows.map { ($0.id, $0.amount) })
        let entry = WhiteTaxBookkeepingEntry(
            id: UUID(),
            month: 12,
            day: 31,
            description: "\(snapshot.fiscalYear)年分",
            salesAmount: revenueAmount,
            miscIncome: miscIncome,
            purchases: purchases,
            salaries: expenseById["shushi_expense_salary"],
            outsourcing: expenseById["shushi_expense_outsourcing"],
            depreciation: expenseById["shushi_expense_depreciation"],
            badDebts: expenseById["shushi_expense_bad_debt"],
            rent: expenseById["shushi_expense_rent"],
            interestDiscount: expenseById["shushi_expense_interest"],
            taxesDuties: expenseById["shushi_expense_taxes"],
            packingShipping: expenseById["shushi_expense_shipping"],
            utilities: expenseById["shushi_expense_utilities"],
            travelTransport: expenseById["shushi_expense_travel"],
            communication: expenseById["shushi_expense_communication"],
            advertising: expenseById["shushi_expense_advertising"],
            entertainment: expenseById["shushi_expense_entertainment"],
            insurance: expenseById["shushi_expense_insurance"],
            repairs: expenseById["shushi_expense_repairs"],
            supplies: expenseById["shushi_expense_supplies"],
            welfare: expenseById["shushi_expense_welfare"],
            miscellaneous: expenseById["shushi_expense_misc"]
        )
        return (
            metadata: WhiteTaxBookkeepingMetadata(fiscalYear: snapshot.fiscalYear),
            entries: [entry],
            includeInvoice: false
        )
    }

    private static func fixedAssetRegisterContent(
        modelContext: ModelContext,
        fiscalYear: Int
    ) -> (metadata: FixedAssetRegisterMetadata, entries: [FixedAssetRegisterEntry]) {
        let assets = FixedAssetQueryUseCase(modelContext: modelContext)
            .listSnapshot(currentYear: fiscalYear)
            .assets
            .sorted { $0.acquisitionDate < $1.acquisitionDate }
        let support = AccountingReadSupport(modelContext: modelContext)
        let entries = assets.map { asset in
            let prior = support.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
            let calculation = DepreciationEngine.calculate(
                asset: asset,
                fiscalYear: fiscalYear,
                priorAccumulatedDepreciation: prior
            )
            return FixedAssetRegisterEntry(
                id: asset.id,
                date: shortDateString(asset.acquisitionDate),
                description: asset.name,
                acquiredQuantity: 1,
                acquiredUnitPrice: asset.acquisitionCost,
                acquiredAmount: asset.acquisitionCost,
                depreciationAmount: calculation?.annualAmount,
                disposalQuantity: asset.assetStatus == .disposed || asset.assetStatus == .sold ? 1 : nil,
                disposalAmount: asset.disposalAmount,
                businessUseRatio: exportBusinessUseRatio(for: asset),
                remarks: asset.memo
            )
        }
        let metadata: FixedAssetRegisterMetadata
        if let firstAsset = assets.first {
            metadata = FixedAssetRegisterMetadata(
                assetName: firstAsset.name,
                assetNumber: firstAsset.id.uuidString,
                assetType: exportAssetType(for: firstAsset),
                acquisitionDate: shortDateString(firstAsset.acquisitionDate),
                location: "",
                usefulLife: firstAsset.usefulLifeYears,
                depreciationMethod: exportDepreciationMethodLabel(for: firstAsset.depreciationMethod),
                depreciationRate: exportDepreciationRate(
                    for: firstAsset.depreciationMethod,
                    usefulLifeYears: firstAsset.usefulLifeYears
                )
            )
        } else {
            metadata = FixedAssetRegisterMetadata()
        }
        return (metadata: metadata, entries: entries)
    }

    private static func fixedAssetDepreciationContent(
        modelContext: ModelContext,
        fiscalYear: Int
    ) -> (metadata: FixedAssetDepreciationMetadata, entries: [FixedAssetDepreciationEntry]) {
        let assets = FixedAssetQueryUseCase(modelContext: modelContext)
            .listSnapshot(currentYear: fiscalYear)
            .assets
            .sorted { $0.acquisitionDate < $1.acquisitionDate }
        let support = AccountingReadSupport(modelContext: modelContext)
        let calendar = Calendar(identifier: .gregorian)
        let entries = assets.compactMap { asset -> FixedAssetDepreciationEntry? in
            let prior = support.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
            guard let calc = DepreciationEngine.calculate(
                asset: asset,
                fiscalYear: fiscalYear,
                priorAccumulatedDepreciation: prior
            ) else {
                return nil
            }
            let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
            let acquisitionMonth = calendar.component(.month, from: asset.acquisitionDate)
            let months: Int
            if let disposalDate = asset.disposalDate,
               calendar.component(.year, from: disposalDate) == fiscalYear {
                months = calendar.component(.month, from: disposalDate)
            } else if fiscalYear == acquisitionYear,
                      [.straightLine, .decliningBalance].contains(asset.depreciationMethod) {
                months = 13 - acquisitionMonth
            } else if calc.annualAmount > 0 {
                months = 12
            } else {
                months = 0
            }
            let rate = exportDepreciationRate(
                for: asset.depreciationMethod,
                usefulLifeYears: asset.usefulLifeYears
            )
            return FixedAssetDepreciationEntry(
                account: "減価償却費",
                assetCode: asset.id.uuidString,
                assetName: asset.name,
                assetType: exportAssetType(for: asset),
                status: asset.assetStatus.label,
                acquisitionDate: shortDateString(asset.acquisitionDate),
                acquisitionCost: asset.acquisitionCost,
                depreciationMethod: legacyLedgerDepreciationMethod(for: asset.depreciationMethod),
                usefulLife: asset.usefulLifeYears,
                depreciationRate: rate,
                depreciationMonths: months,
                openingBookValue: asset.acquisitionCost - prior,
                businessUseRatio: exportBusinessUseRatio(for: asset),
                quantity: 1,
                midYearChange: 0,
                depreciationMethodLabel: exportDepreciationMethodLabel(for: asset.depreciationMethod),
                depreciationExpense: calc.annualAmount,
                specialDepreciation: 0,
                totalDepreciation: calc.annualAmount,
                deductibleAmount: calc.businessAmount,
                yearEndBalance: calc.bookValueAfter,
                remarks: asset.memo
            )
        }
        return (
            metadata: FixedAssetDepreciationMetadata(fiscalYear: "\(fiscalYear)年分"),
            entries: entries
        )
    }

    private static func exportAssetType(for asset: PPFixedAsset) -> String {
        switch asset.depreciationMethod {
        case .threeYearEqual:
            return "一括償却資産"
        case .smallBusiness:
            return "少額減価償却資産"
        default:
            return "固定資産"
        }
    }

    private static func exportDepreciationMethodLabel(for method: PPDepreciationMethod) -> String {
        method.label
    }

    private static func legacyLedgerDepreciationMethod(for method: PPDepreciationMethod) -> DepreciationMethod {
        switch method {
        case .decliningBalance:
            return .decliningBalance
        case .straightLine, .immediateExpense, .threeYearEqual, .smallBusiness:
            return .straightLine
        }
    }

    private static func exportDepreciationRate(for method: PPDepreciationMethod, usefulLifeYears: Int) -> Double {
        guard usefulLifeYears > 0 else { return 0 }
        switch method {
        case .straightLine:
            return 1.0 / Double(usefulLifeYears)
        case .decliningBalance:
            return 2.0 / Double(usefulLifeYears)
        case .immediateExpense, .smallBusiness:
            return 1.0
        case .threeYearEqual:
            return 1.0 / 3.0
        }
    }

    private static func exportBusinessUseRatio(for asset: PPFixedAsset) -> Double {
        Double(asset.businessUsePercent) / 100.0
    }

    private static func legacyLedgerEntries(from entries: [AccountingLedgerEntry]) -> [DataStore.LedgerEntry] {
        entries.map { entry in
            DataStore.LedgerEntry(
                id: entry.id,
                date: entry.date,
                memo: entry.memo,
                entryType: entry.entryType,
                debit: entry.debit,
                credit: entry.credit,
                runningBalance: entry.runningBalance,
                counterparty: entry.counterparty,
                taxCategory: entry.taxCategory
            )
        }
    }

    private static func legacyAccounts(for context: CanonicalReadContext) -> [PPAccount] {
        context.accounts.compactMap { account in
            if let legacyAccountId = account.legacyAccountId,
               let legacyAccount = context.legacyAccountsById[legacyAccountId] {
                return legacyAccount
            }

            return PPAccount(
                id: account.legacyAccountId ?? account.id.uuidString,
                code: account.code,
                name: account.name,
                accountType: legacyAccountType(for: account.accountType),
                normalBalance: account.normalBalance,
                subtype: nil,
                parentAccountId: nil,
                isSystem: false,
                isActive: account.archivedAt == nil,
                displayOrder: account.displayOrder
            )
        }
    }

    private static func legacyTrialBalanceReport(from report: CanonicalTrialBalanceReport) -> TrialBalanceReport {
        TrialBalanceReport(
            fiscalYear: report.fiscalYear,
            generatedAt: report.generatedAt,
            rows: report.rows.map { row in
                TrialBalanceRow(
                    id: row.id.uuidString,
                    code: row.code,
                    name: row.name,
                    accountType: legacyAccountType(for: row.accountType),
                    debit: decimalInt(row.debit),
                    credit: decimalInt(row.credit),
                    balance: decimalInt(row.balance)
                )
            }
        )
    }

    private static func legacyProfitLossReport(from report: CanonicalProfitLossReport) -> ProfitLossReport {
        ProfitLossReport(
            fiscalYear: report.fiscalYear,
            generatedAt: report.generatedAt,
            revenueItems: report.revenueItems.map { item in
                ProfitLossItem(
                    id: item.id.uuidString,
                    code: item.code,
                    name: item.name,
                    amount: decimalInt(item.amount),
                    deductibleAmount: decimalInt(item.amount)
                )
            },
            expenseItems: report.expenseItems.map { item in
                ProfitLossItem(
                    id: item.id.uuidString,
                    code: item.code,
                    name: item.name,
                    amount: decimalInt(item.amount),
                    deductibleAmount: decimalInt(item.amount)
                )
            }
        )
    }

    private static func legacyBalanceSheetReport(from report: CanonicalBalanceSheetReport) -> BalanceSheetReport {
        BalanceSheetReport(
            fiscalYear: report.fiscalYear,
            generatedAt: report.generatedAt,
            assetItems: report.assetItems.map(legacyBalanceSheetItem),
            liabilityItems: report.liabilityItems.map(legacyBalanceSheetItem),
            equityItems: report.equityItems.map(legacyBalanceSheetItem)
        )
    }

    private static func legacyBalanceSheetItem(_ item: CanonicalBalanceSheetItem) -> BalanceSheetItem {
        BalanceSheetItem(
            id: item.id.uuidString,
            code: item.code,
            name: item.name,
            balance: decimalInt(item.balance)
        )
    }

    private static func generateContent(
        target: ExportTarget,
        format: ExportFormat,
        fiscalYear: Int?,
        modelContext: ModelContext,
        ledgerOptions: LedgerExportOptions?,
        transactionOptions: TransactionExportOptions?,
        subLedgerOptions: SubLedgerExportOptions?,
        etaxOptions: EtaxExportOptions?,
        withholdingStatementOptions: WithholdingStatementExportOptions?,
        ledgerBookSelectionOptions: LedgerBookSelectionOptions?,
        legacyLedgerOptions: LegacyLedgerExportOptions?
    ) throws -> ExportContent {
        if target == .legacyLedgerBook {
            guard let legacyLedgerOptions else {
                throw ExportError.dataUnavailable
            }
            return try LegacyLedgerExportAdapter.generateContent(
                format: format,
                modelContext: modelContext,
                options: legacyLedgerOptions
            )
        }

        guard let fiscalYear else {
            throw ExportError.dataUnavailable
        }
        let bookExportSource = AccountingBookExportSource(modelContext: modelContext, fiscalYear: fiscalYear)
        let dataStore = DataStore(modelContext: modelContext)
        dataStore.loadData()

        switch (target, format) {
        case (.cashBook, .csv):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .cashBook)
            let payload = cashBookContent(entries: entries)
            return .text(CSVExportService.shared.exportCashBook(
                metadata: payload.metadata,
                entries: payload.entries,
                includeInvoice: payload.includeInvoice
            ))

        case (.cashBook, .pdf):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .cashBook)
            let payload = cashBookContent(entries: entries)
            return .data(LedgerPDFExportService.shared.exportCashBook(
                metadata: payload.metadata,
                entries: payload.entries,
                includeInvoice: payload.includeInvoice
            ))

        case (.cashBook, .xlsx):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .cashBook)
            let payload = cashBookContent(entries: entries)
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportCashBook(
                    metadata: payload.metadata,
                    entries: payload.entries,
                    includeInvoice: payload.includeInvoice,
                    to: path
                )
            })

        case (.bankAccountBook, .csv):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .depositBook)
            let payload = bankAccountBookContent(entries: entries)
            return .text(CSVExportService.shared.exportBankAccountBook(
                metadata: payload.metadata,
                entries: payload.entries,
                includeInvoice: payload.includeInvoice
            ))

        case (.bankAccountBook, .pdf):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .depositBook)
            let payload = bankAccountBookContent(entries: entries)
            return .data(LedgerPDFExportService.shared.exportBankAccountBook(
                metadata: payload.metadata,
                entries: payload.entries,
                includeInvoice: payload.includeInvoice
            ))

        case (.bankAccountBook, .xlsx):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .depositBook)
            let payload = bankAccountBookContent(entries: entries)
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportBankAccountBook(
                    metadata: payload.metadata,
                    entries: payload.entries,
                    includeInvoice: payload.includeInvoice,
                    to: path
                )
            })

        case (.accountsReceivableBook, .csv):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .accountsReceivableBook)
            let payload = accountsReceivableContent(entries: entries)
            return .text(CSVExportService.shared.exportAccountsReceivable(
                metadata: payload.metadata,
                entries: payload.entries
            ))

        case (.accountsReceivableBook, .pdf):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .accountsReceivableBook)
            let payload = accountsReceivableContent(entries: entries)
            return .data(LedgerPDFExportService.shared.exportAccountsReceivable(
                metadata: payload.metadata,
                entries: payload.entries
            ))

        case (.accountsReceivableBook, .xlsx):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .accountsReceivableBook)
            let payload = accountsReceivableContent(entries: entries)
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportAccountsReceivable(
                    metadata: payload.metadata,
                    entries: payload.entries,
                    to: path
                )
            })

        case (.accountsPayableBook, .csv):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .accountsPayableBook)
            let payload = accountsPayableContent(entries: entries)
            return .text(CSVExportService.shared.exportAccountsPayable(
                metadata: payload.metadata,
                entries: payload.entries
            ))

        case (.accountsPayableBook, .pdf):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .accountsPayableBook)
            let payload = accountsPayableContent(entries: entries)
            return .data(LedgerPDFExportService.shared.exportAccountsPayable(
                metadata: payload.metadata,
                entries: payload.entries
            ))

        case (.accountsPayableBook, .xlsx):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .accountsPayableBook)
            let payload = accountsPayableContent(entries: entries)
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportAccountsPayable(
                    metadata: payload.metadata,
                    entries: payload.entries,
                    to: path
                )
            })

        case (.expenseBook, .csv):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .expenseBook)
            let payload = expenseBookContent(entries: entries, source: bookExportSource, accountId: subLedgerOptions?.accountFilter)
            return .text(CSVExportService.shared.exportExpenseBook(
                metadata: payload.metadata,
                entries: payload.entries,
                includeInvoice: payload.includeInvoice
            ))

        case (.expenseBook, .pdf):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .expenseBook)
            let payload = expenseBookContent(entries: entries, source: bookExportSource, accountId: subLedgerOptions?.accountFilter)
            return .data(LedgerPDFExportService.shared.exportExpenseBook(
                metadata: payload.metadata,
                entries: payload.entries,
                includeInvoice: payload.includeInvoice
            ))

        case (.expenseBook, .xlsx):
            let entries = try subLedgerEntries(source: bookExportSource, options: subLedgerOptions, fallbackType: .expenseBook)
            let payload = expenseBookContent(entries: entries, source: bookExportSource, accountId: subLedgerOptions?.accountFilter)
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportExpenseBook(
                    metadata: payload.metadata,
                    entries: payload.entries,
                    includeInvoice: payload.includeInvoice,
                    to: path
                )
            })

        case (.generalLedger, .csv):
            guard let opts = ledgerOptions else { throw ExportError.ledgerAccountRequired }
            let payload = generalLedgerContent(source: bookExportSource, options: opts)
            return .text(CSVExportService.shared.exportGeneralLedger(
                metadata: payload.metadata,
                entries: payload.entries,
                includeInvoice: payload.includeInvoice
            ))

        case (.generalLedger, .pdf):
            guard let opts = ledgerOptions else { throw ExportError.ledgerAccountRequired }
            let payload = generalLedgerContent(source: bookExportSource, options: opts)
            return .data(LedgerPDFExportService.shared.exportGeneralLedger(
                metadata: payload.metadata,
                entries: payload.entries,
                includeInvoice: payload.includeInvoice
            ))

        case (.generalLedger, .xlsx):
            guard let opts = ledgerOptions else { throw ExportError.ledgerAccountRequired }
            let payload = generalLedgerContent(source: bookExportSource, options: opts)
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportGeneralLedger(
                    metadata: payload.metadata,
                    entries: payload.entries,
                    includeInvoice: payload.includeInvoice,
                    to: path
                )
            })

        case (.journalBook, .csv):
            return .text(CSVExportService.shared.exportJournal(entries: journalEntriesContent(source: bookExportSource)))

        case (.journalBook, .pdf):
            return .data(LedgerPDFExportService.shared.exportJournal(entries: journalEntriesContent(source: bookExportSource)))

        case (.journalBook, .xlsx):
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportJournal(
                    entries: journalEntriesContent(source: bookExportSource),
                    to: path
                )
            })

        case (.whiteTaxBookkeeping, .csv):
            let snapshot = WhiteTaxBookkeepingQueryUseCase(modelContext: modelContext).snapshot(taxYear: fiscalYear)
            let payload = whiteTaxBookkeepingContent(snapshot: snapshot)
            return .text(CSVExportService.shared.exportWhiteTaxBookkeeping(
                metadata: payload.metadata,
                entries: payload.entries,
                includeInvoice: payload.includeInvoice
            ))

        case (.whiteTaxBookkeeping, .pdf):
            let snapshot = WhiteTaxBookkeepingQueryUseCase(modelContext: modelContext).snapshot(taxYear: fiscalYear)
            let payload = whiteTaxBookkeepingContent(snapshot: snapshot)
            return .data(LedgerPDFExportService.shared.exportWhiteTaxBookkeeping(
                metadata: payload.metadata,
                entries: payload.entries,
                includeInvoice: payload.includeInvoice
            ))

        case (.whiteTaxBookkeeping, .xlsx):
            let snapshot = WhiteTaxBookkeepingQueryUseCase(modelContext: modelContext).snapshot(taxYear: fiscalYear)
            let payload = whiteTaxBookkeepingContent(snapshot: snapshot)
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportWhiteTaxBookkeeping(
                    metadata: payload.metadata,
                    entries: payload.entries,
                    includeInvoice: payload.includeInvoice,
                    to: path
                )
            })

        case (.transportationExpense, .csv):
            guard let legacyOptions = resolveLegacyLedgerOptions(
                selection: ledgerBookSelectionOptions ?? .init(ledgerType: .transportationExpense),
                source: bookExportSource
            ) else {
                throw ExportError.dataUnavailable
            }
            let store = LedgerDataStore(modelContext: modelContext)
            return .text(CSVExportService.shared.exportTransportationExpense(
                metadata: LedgerBridge.decodeTransportationExpenseMetadata(from: legacyOptions.metadataJSON),
                entries: store.transportationExpenseEntries(for: legacyOptions.bookId)
            ))

        case (.transportationExpense, .pdf):
            guard let legacyOptions = resolveLegacyLedgerOptions(
                selection: ledgerBookSelectionOptions ?? .init(ledgerType: .transportationExpense),
                source: bookExportSource
            ) else {
                throw ExportError.dataUnavailable
            }
            let store = LedgerDataStore(modelContext: modelContext)
            return .data(LedgerPDFExportService.shared.exportTransportationExpense(
                metadata: LedgerBridge.decodeTransportationExpenseMetadata(from: legacyOptions.metadataJSON),
                entries: store.transportationExpenseEntries(for: legacyOptions.bookId)
            ))

        case (.transportationExpense, .xlsx):
            guard let legacyOptions = resolveLegacyLedgerOptions(
                selection: ledgerBookSelectionOptions ?? .init(ledgerType: .transportationExpense),
                source: bookExportSource
            ) else {
                throw ExportError.dataUnavailable
            }
            let store = LedgerDataStore(modelContext: modelContext)
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportTransportationExpense(
                    metadata: LedgerBridge.decodeTransportationExpenseMetadata(from: legacyOptions.metadataJSON),
                    entries: store.transportationExpenseEntries(for: legacyOptions.bookId),
                    to: path
                )
            })

        case (.journal, .csv):
            let projected = bookExportSource.journalPayload()
            let csv = ReportCSVExportService.exportJournalCSV(
                entries: projected.entries,
                lines: projected.lines,
                accounts: projected.accounts
            )
            return .text(csv)

        case (.journal, .pdf):
            let projected = bookExportSource.journalPayload()
            let pdf = PDFExportService.exportJournalPDF(
                entries: projected.entries,
                lines: projected.lines,
                accounts: projected.accounts,
                fiscalYear: fiscalYear
            )
            return .data(pdf)

        case (.journal, .xlsx):
            let projected = bookExportSource.journalPayload()
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportJournalReport(
                    entries: projected.entries,
                    lines: projected.lines,
                    accounts: projected.accounts,
                    fiscalYear: fiscalYear,
                    to: path
                )
            })

        case (.profitLoss, .csv):
            let context = AccountingReadSupport(modelContext: modelContext)
                .canonicalReadContext(fiscalYear: fiscalYear)
            let report = AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: FiscalYearSettings.startMonth
            )
            return .text(ReportCSVExportService.exportProfitLossCSV(report: legacyProfitLossReport(from: report)))

        case (.profitLoss, .pdf):
            let context = AccountingReadSupport(modelContext: modelContext)
                .canonicalReadContext(fiscalYear: fiscalYear)
            let report = AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: FiscalYearSettings.startMonth
            )
            return .data(PDFExportService.exportProfitLossPDF(report: legacyProfitLossReport(from: report)))

        case (.profitLoss, .xlsx):
            let projected = bookExportSource.journalPayload()
            let report = AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: projected.accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: FiscalYearSettings.startMonth
            )
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportProfitLossReport(report: report, to: path)
            })

        case (.balanceSheet, .csv):
            let context = AccountingReadSupport(modelContext: modelContext)
                .canonicalReadContext(fiscalYear: fiscalYear)
            let report = AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: FiscalYearSettings.startMonth
            )
            return .text(ReportCSVExportService.exportBalanceSheetCSV(report: legacyBalanceSheetReport(from: report)))

        case (.balanceSheet, .pdf):
            let context = AccountingReadSupport(modelContext: modelContext)
                .canonicalReadContext(fiscalYear: fiscalYear)
            let report = AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: FiscalYearSettings.startMonth
            )
            return .data(PDFExportService.exportBalanceSheetPDF(report: legacyBalanceSheetReport(from: report)))

        case (.balanceSheet, .xlsx):
            let projected = bookExportSource.journalPayload()
            let report = AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: projected.accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: FiscalYearSettings.startMonth
            )
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportBalanceSheetReport(report: report, to: path)
            })

        case (.trialBalance, .csv):
            let context = AccountingReadSupport(modelContext: modelContext)
                .canonicalReadContext(fiscalYear: fiscalYear)
            let report = AccountingReportService.generateTrialBalance(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: FiscalYearSettings.startMonth
            )
            return .text(ReportCSVExportService.exportTrialBalanceCSV(rows: legacyTrialBalanceReport(from: report).rows))

        case (.trialBalance, .pdf):
            let context = AccountingReadSupport(modelContext: modelContext)
                .canonicalReadContext(fiscalYear: fiscalYear)
            let report = AccountingReportService.generateTrialBalance(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: FiscalYearSettings.startMonth
            )
            return .data(PDFExportService.exportTrialBalancePDF(report: legacyTrialBalanceReport(from: report)))

        case (.trialBalance, .xlsx):
            let projected = bookExportSource.journalPayload()
            let report = AccountingReportService.generateTrialBalance(
                fiscalYear: fiscalYear,
                accounts: projected.accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: FiscalYearSettings.startMonth
            )
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportTrialBalanceReport(report: report, to: path)
            })

        case (.ledger, .csv):
            guard let opts = ledgerOptions else { throw ExportError.ledgerAccountRequired }
            let entries = legacyLedgerEntries(from: bookExportSource.ledgerEntries(options: opts))
            return .text(ReportCSVExportService.exportLedgerCSV(
                accountName: opts.accountName,
                accountCode: opts.accountCode,
                entries: entries
            ))

        case (.ledger, .pdf):
            guard let opts = ledgerOptions else { throw ExportError.ledgerAccountRequired }
            let entries = legacyLedgerEntries(from: bookExportSource.ledgerEntries(options: opts))
            return .data(PDFExportService.exportLedgerPDF(
                accountName: opts.accountName,
                accountCode: opts.accountCode,
                entries: entries,
                fiscalYear: fiscalYear
            ))

        case (.ledger, .xlsx):
            guard let opts = ledgerOptions else { throw ExportError.ledgerAccountRequired }
            let entries = dataStore.getLedgerEntries(accountId: opts.accountId)
            let account = dataStore.accounts.first { $0.id == opts.accountId }
            let isDebitNormal = account?.normalBalance == .debit
            let openingBalance: Int
            if let first = entries.first {
                if isDebitNormal {
                    openingBalance = first.runningBalance - first.debit + first.credit
                } else {
                    openingBalance = first.runningBalance - first.credit + first.debit
                }
            } else {
                openingBalance = 0
            }

            let accountNames = Dictionary(uniqueKeysWithValues: dataStore.accounts.map { ($0.id, $0.name) })
            let linesByEntry = Dictionary(grouping: dataStore.journalLines, by: \.entryId)
            let counterpartyNames = Dictionary(uniqueKeysWithValues: entries.map { entry in
                let counterpartNames = (linesByEntry[entry.id] ?? [])
                    .filter { $0.accountId != opts.accountId }
                    .compactMap { accountNames[$0.accountId] }
                var seen = Set<String>()
                let counterpart = counterpartNames.filter { seen.insert($0).inserted }.joined(separator: " / ")
                return (entry.id, counterpart.isEmpty ? (entry.counterparty ?? "") : counterpart)
            })

            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportLedgerReport(
                    accountName: opts.accountName,
                    accountCode: opts.accountCode,
                    accountTypeLabel: account?.accountType.label ?? "",
                    openingBalance: openingBalance,
                    entries: entries,
                    counterpartyNames: counterpartyNames,
                    fiscalYear: fiscalYear,
                    to: path
                )
            })

        case (.transactions, .csv):
            guard let opts = transactionOptions else {
                throw ExportError.transactionsRequired
            }
            let support = AccountingReadSupport(modelContext: modelContext)
            let categoriesById = Dictionary(uniqueKeysWithValues: support.fetchCategories().map { ($0.id, $0) })
            let projectsById = Dictionary(uniqueKeysWithValues: support.fetchProjects().map { ($0.id, $0) })
            return .text(generateCSV(
                transactions: opts.transactions,
                getCategory: { categoriesById[$0] },
                getProject: { projectsById[$0] }
            ))

        case (.subLedger, .csv):
            guard let opts = subLedgerOptions else {
                throw ExportError.subLedgerConfigurationRequired
            }
            let snapshot = bookExportSource.subLedgerSnapshot(options: opts)
            return .text(exportSubLedgerCSV(entries: snapshot.entries))

        case (.subLedger, .pdf):
            guard let opts = subLedgerOptions else {
                throw ExportError.subLedgerConfigurationRequired
            }
            let snapshot = bookExportSource.subLedgerSnapshot(options: opts)
            return .data(PDFExportService.exportSubLedgerPDF(
                entries: snapshot.entries,
                fiscalYear: snapshot.summary.periodStart.map { Calendar.current.component(.year, from: $0) } ?? fiscalYear,
                title: opts.type.title
            ))

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

        case (.withholdingStatement, .csv):
            guard let opts = withholdingStatementOptions else {
                throw ExportError.dataUnavailable
            }
            switch opts.scope {
            case .annualSummary:
                return .text(ReportCSVExportService.exportWithholdingStatementAnnualCSV(summary: opts.annualSummary))
            case .payee:
                guard let document = opts.document else {
                    throw ExportError.dataUnavailable
                }
                return .text(ReportCSVExportService.exportWithholdingStatementPayeeCSV(document: document))
            }

        case (.withholdingStatement, .pdf):
            guard let opts = withholdingStatementOptions else {
                throw ExportError.dataUnavailable
            }
            switch opts.scope {
            case .annualSummary:
                return .data(PDFExportService.exportWithholdingStatementAnnualPDF(summary: opts.annualSummary))
            case .payee:
                guard let document = opts.document else {
                    throw ExportError.dataUnavailable
                }
                return .data(PDFExportService.exportWithholdingStatementPayeePDF(document: document))
            }

        case (.fixedAssetRegister, .csv):
            let payload = fixedAssetRegisterContent(modelContext: modelContext, fiscalYear: fiscalYear)
            return .text(CSVExportService.shared.exportFixedAssetRegister(
                metadata: payload.metadata,
                entries: payload.entries
            ))

        case (.fixedAssetRegister, .pdf):
            let payload = fixedAssetRegisterContent(modelContext: modelContext, fiscalYear: fiscalYear)
            return .data(LedgerPDFExportService.shared.exportFixedAssetRegister(
                metadata: payload.metadata,
                entries: payload.entries
            ))

        case (.fixedAssetRegister, .xlsx):
            let payload = fixedAssetRegisterContent(modelContext: modelContext, fiscalYear: fiscalYear)
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportFixedAssetRegister(
                    metadata: payload.metadata,
                    entries: payload.entries,
                    to: path
                )
            })

        case (.fixedAssetDepreciation, .csv):
            let payload = fixedAssetDepreciationContent(modelContext: modelContext, fiscalYear: fiscalYear)
            return .text(CSVExportService.shared.exportFixedAssetDepreciation(
                metadata: payload.metadata,
                entries: payload.entries
            ))

        case (.fixedAssetDepreciation, .pdf):
            let payload = fixedAssetDepreciationContent(modelContext: modelContext, fiscalYear: fiscalYear)
            return .data(LedgerPDFExportService.shared.exportFixedAssetDepreciation(
                metadata: payload.metadata,
                entries: payload.entries
            ))

        case (.fixedAssetDepreciation, .xlsx):
            let payload = fixedAssetDepreciationContent(modelContext: modelContext, fiscalYear: fiscalYear)
            return .data(try generateSpreadsheetData(fileExtension: "xlsx") { path in
                LedgerExcelExportService.shared.exportFixedAssetDepreciation(
                    entries: payload.entries,
                    to: path
                )
            })

        default:
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

    private static func makeLegacyLedgerFileName(
        options: LegacyLedgerExportOptions,
        format: ExportFormat
    ) -> String {
        let dateStr = dateFormatter.string(from: Date())
        return "legacy_ledger_\(options.ledgerType.rawValue)_\(dateStr).\(format.fileExtension)"
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
        case .fileWriter(let writer):
            try writer(fileURL)
        }

        return fileURL
    }

    private static func legacyAccountType(for canonicalType: CanonicalAccountType) -> AccountType {
        switch canonicalType {
        case .asset:
            return .asset
        case .liability:
            return .liability
        case .equity:
            return .equity
        case .revenue:
            return .revenue
        case .expense:
            return .expense
        }
    }

    private static func decimalInt(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).intValue
    }

    private static func generateSpreadsheetData(
        fileExtension: String,
        builder: (String) -> Void
    ) throws -> Data {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        builder(tempURL.path)

        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw ExportError.fileWriteFailed
        }
        return try Data(contentsOf: tempURL)
    }
}
