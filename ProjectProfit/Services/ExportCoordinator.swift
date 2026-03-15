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
        case journal
        case ledger
        case transactions
        case subLedger
        case etax
        case withholdingStatement
        case fixedAssets
        case legacyLedgerBook

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
            case .withholdingStatement: "支払調書"
            case .fixedAssets: "固定資産台帳"
            case .legacyLedgerBook: "旧台帳（互換）"
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
            case .withholdingStatement: "withholding_statement"
            case .fixedAssets: "fixed_assets"
            case .legacyLedgerBook: "legacy_ledger"
            }
        }

        /// 現在のアプリ導線で許可する target/format 組み合わせ。
        /// ExportMenuButton / EtaxExportView / 旧台帳詳細画面の実使用範囲を正本として管理する。
        var supportedFormats: Set<ExportFormat> {
            switch self {
            case .profitLoss, .balanceSheet, .trialBalance, .journal, .ledger, .fixedAssets, .withholdingStatement:
                return [.csv, .pdf]
            case .transactions, .subLedger:
                return [.csv]
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
            case .profitLoss, .balanceSheet, .trialBalance, .journal, .ledger, .fixedAssets, .etax, .withholdingStatement:
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
            .context(fiscalYear: fiscalYear)
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

    private static func legacyJournalProjection(
        from context: CanonicalReadContext
    ) -> (entries: [PPJournalEntry], lines: [PPJournalLine]) {
        let books = CanonicalBookService.generateJournalBook(
            journals: context.journals,
            accounts: context.accounts,
            counterparties: context.counterpartiesById
        )
        let journalsById = Dictionary(uniqueKeysWithValues: context.journals.map { ($0.id, $0) })
        let entries = books.compactMap { book -> PPJournalEntry? in
            guard let journal = journalsById[book.id] else {
                return nil
            }
            return PPJournalEntry(
                id: journal.id,
                sourceKey: journalSourceKey(journal),
                date: journal.journalDate,
                entryType: exportJournalEntryType(for: journal.entryType),
                memo: journal.description,
                isPosted: journal.approvedAt != nil,
                createdAt: journal.createdAt,
                updatedAt: journal.updatedAt
            )
        }
        let lines = books.flatMap { book in
            book.lines.enumerated().map { index, line in
                PPJournalLine(
                    id: line.id,
                    entryId: book.id,
                    accountId: context.legacyAccountId(for: line.accountId),
                    debit: decimalInt(line.debitAmount),
                    credit: decimalInt(line.creditAmount),
                    memo: "",
                    displayOrder: index,
                    createdAt: journalsById[book.id]?.createdAt ?? Date(),
                    updatedAt: journalsById[book.id]?.updatedAt ?? Date()
                )
            }
        }
        return (entries, lines)
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

        let support = AccountingReadSupport(modelContext: modelContext)
        let context = support.canonicalReadContext(fiscalYear: fiscalYear)
        let startMonth = FiscalYearSettings.startMonth

        switch (target, format) {
        case (.journal, .csv):
            let projected = legacyJournalProjection(from: context)
            let csv = ReportCSVExportService.exportJournalCSV(
                entries: projected.entries,
                lines: projected.lines,
                accounts: legacyAccounts(for: context)
            )
            return .text(csv)

        case (.journal, .pdf):
            let projected = legacyJournalProjection(from: context)
            let pdf = PDFExportService.exportJournalPDF(
                entries: projected.entries,
                lines: projected.lines,
                accounts: legacyAccounts(for: context),
                fiscalYear: fiscalYear
            )
            return .data(pdf)

        case (.profitLoss, .csv):
            let report = AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: startMonth
            )
            return .text(ReportCSVExportService.exportProfitLossCSV(report: legacyProfitLossReport(from: report)))

        case (.profitLoss, .pdf):
            let report = AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: startMonth
            )
            return .data(PDFExportService.exportProfitLossPDF(report: legacyProfitLossReport(from: report)))

        case (.balanceSheet, .csv):
            let report = AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: startMonth
            )
            return .text(ReportCSVExportService.exportBalanceSheetCSV(report: legacyBalanceSheetReport(from: report)))

        case (.balanceSheet, .pdf):
            let report = AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: startMonth
            )
            return .data(PDFExportService.exportBalanceSheetPDF(report: legacyBalanceSheetReport(from: report)))

        case (.trialBalance, .csv):
            let report = AccountingReportService.generateTrialBalance(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: startMonth
            )
            return .text(ReportCSVExportService.exportTrialBalanceCSV(rows: legacyTrialBalanceReport(from: report).rows))

        case (.trialBalance, .pdf):
            let report = AccountingReportService.generateTrialBalance(
                fiscalYear: fiscalYear,
                accounts: context.accounts,
                journals: context.journals,
                startMonth: startMonth
            )
            return .data(PDFExportService.exportTrialBalancePDF(report: legacyTrialBalanceReport(from: report)))

        case (.ledger, .csv):
            guard let opts = ledgerOptions else { throw ExportError.ledgerAccountRequired }
            let entries = legacyLedgerEntries(
                from: LedgerQueryUseCase(modelContext: modelContext).snapshot(accountId: opts.accountId).entries
            )
            return .text(ReportCSVExportService.exportLedgerCSV(
                accountName: opts.accountName,
                accountCode: opts.accountCode,
                entries: entries
            ))

        case (.ledger, .pdf):
            guard let opts = ledgerOptions else { throw ExportError.ledgerAccountRequired }
            let entries = legacyLedgerEntries(
                from: LedgerQueryUseCase(modelContext: modelContext).snapshot(accountId: opts.accountId).entries
            )
            return .data(PDFExportService.exportLedgerPDF(
                accountName: opts.accountName,
                accountCode: opts.accountCode,
                entries: entries,
                fiscalYear: fiscalYear
            ))

        case (.transactions, .csv):
            guard let opts = transactionOptions else {
                throw ExportError.transactionsRequired
            }
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
            let year = opts.startDate.map { Calendar.current.component(.year, from: $0) } ?? fiscalYear
            let entries = SubLedgerQueryUseCase(modelContext: modelContext).snapshot(
                type: opts.type,
                year: year,
                accountFilter: opts.accountFilter,
                counterpartyFilter: opts.counterpartyFilter
            ).entries
            return .text(exportSubLedgerCSV(entries: entries))

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

        case (.fixedAssets, .csv):
            let assets = FixedAssetQueryUseCase(modelContext: modelContext).listSnapshot(currentYear: fiscalYear).assets
            return .text(ReportCSVExportService.exportFixedAssetsCSV(
                assets: assets,
                calculateAccumulated: { asset in
                    let prior = support.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
                    guard let calc = DepreciationEngine.calculate(
                        asset: asset,
                        fiscalYear: fiscalYear,
                        priorAccumulatedDepreciation: prior
                    ) else {
                        return prior
                    }
                    return calc.accumulatedDepreciation
                },
                calculateCurrentYear: { asset in
                    let prior = support.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
                    return DepreciationEngine.calculate(
                        asset: asset,
                        fiscalYear: fiscalYear,
                        priorAccumulatedDepreciation: prior
                    )?.annualAmount ?? 0
                }
            ))

        case (.fixedAssets, .pdf):
            let assets = FixedAssetQueryUseCase(modelContext: modelContext).listSnapshot(currentYear: fiscalYear).assets
            return .data(PDFExportService.exportFixedAssetsPDF(
                assets: assets,
                fiscalYear: fiscalYear,
                calculateAccumulated: { asset in
                    let prior = support.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
                    guard let calc = DepreciationEngine.calculate(
                        asset: asset,
                        fiscalYear: fiscalYear,
                        priorAccumulatedDepreciation: prior
                    ) else {
                        return prior
                    }
                    return calc.accumulatedDepreciation
                },
                calculateCurrentYear: { asset in
                    let prior = support.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
                    return DepreciationEngine.calculate(
                        asset: asset,
                        fiscalYear: fiscalYear,
                        priorAccumulatedDepreciation: prior
                    )?.annualAmount ?? 0
                }
            ))

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

    private static func exportJournalEntryType(for entryType: CanonicalJournalEntryType) -> JournalEntryType {
        switch entryType {
        case .normal:
            return .auto
        case .opening:
            return .opening
        case .closing:
            return .closing
        case .depreciation, .inventoryAdjustment, .recurring, .taxAdjustment, .reversal:
            return .auto
        }
    }

    private static func journalSourceKey(_ journal: CanonicalJournalEntry) -> String {
        switch journal.entryType {
        case .opening:
            return "opening:\(journal.id.uuidString)"
        case .closing:
            return "closing:\(journal.id.uuidString)"
        case .normal, .depreciation, .inventoryAdjustment, .recurring, .taxAdjustment, .reversal:
            if journal.sourceCandidateId != nil && journal.sourceEvidenceId == nil {
                return "manual:\(journal.id.uuidString)"
            }
            return "canonical:\(journal.id.uuidString)"
        }
    }

    private static func decimalInt(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).intValue
    }
}
