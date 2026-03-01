// ============================================================
// LedgerDataStore+Export.swift
// 納品CSVExportServiceへのブリッジ
// ============================================================

import Foundation

extension LedgerDataStore {

    /// 台帳のCSV出力文字列を生成する
    func exportCSV(for bookId: UUID) -> String? {
        guard let book = book(for: bookId),
              let ledgerType = book.ledgerType else { return nil }

        let service = CSVExportService.shared
        let includeInvoice = book.includeInvoice

        switch ledgerType {
        case .cashBook, .cashBookInvoice:
            let metadata = LedgerBridge.decodeCashBookMetadata(from: book.metadataJSON)
            let entries = cashBookEntries(for: bookId)
            return service.exportCashBook(
                metadata: metadata, entries: entries,
                includeInvoice: includeInvoice
            )

        case .bankAccountBook, .bankAccountBookInvoice:
            let metadata = LedgerBridge.decodeBankAccountBookMetadata(from: book.metadataJSON)
            let entries = bankAccountBookEntries(for: bookId)
            return service.exportBankAccountBook(
                metadata: metadata, entries: entries,
                includeInvoice: includeInvoice
            )

        case .accountsReceivable:
            let metadata = LedgerBridge.decodeAccountsReceivableMetadata(from: book.metadataJSON)
            let entries = accountsReceivableEntries(for: bookId)
            return service.exportAccountsReceivable(
                metadata: metadata, entries: entries
            )

        case .accountsPayable:
            let metadata = LedgerBridge.decodeAccountsPayableMetadata(from: book.metadataJSON)
            let entries = accountsPayableEntries(for: bookId)
            return service.exportAccountsPayable(
                metadata: metadata, entries: entries
            )

        case .expenseBook, .expenseBookInvoice:
            let metadata = LedgerBridge.decodeExpenseBookMetadata(from: book.metadataJSON)
            let entries = expenseBookEntries(for: bookId)
            return service.exportExpenseBook(
                metadata: metadata, entries: entries,
                includeInvoice: includeInvoice
            )

        case .generalLedger, .generalLedgerInvoice:
            let metadata = LedgerBridge.decodeGeneralLedgerMetadata(from: book.metadataJSON)
            let entries = generalLedgerEntries(for: bookId)
            return service.exportGeneralLedger(
                metadata: metadata, entries: entries,
                includeInvoice: includeInvoice
            )

        case .journal:
            let entries = journalEntries(for: bookId)
            return service.exportJournal(entries: entries)

        case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            let metadata = LedgerBridge.decodeWhiteTaxBookkeepingMetadata(from: book.metadataJSON)
            let entries = whiteTaxBookkeepingEntries(for: bookId)
            return service.exportWhiteTaxBookkeeping(
                metadata: metadata, entries: entries,
                includeInvoice: includeInvoice
            )

        case .fixedAssetDepreciation, .fixedAssetRegister, .transportationExpense:
            return nil
        }
    }

    // MARK: - Excel Export

    /// 台帳のExcel(.xlsx)ファイルを指定パスに出力する
    func exportExcel(for bookId: UUID, to path: String) -> Bool {
        guard let book = book(for: bookId),
              let ledgerType = book.ledgerType else { return false }

        let service = LedgerExcelExportService.shared
        let includeInvoice = book.includeInvoice

        switch ledgerType {
        case .cashBook, .cashBookInvoice:
            let metadata = LedgerBridge.decodeCashBookMetadata(from: book.metadataJSON)
            let entries = cashBookEntries(for: bookId)
            service.exportCashBook(
                metadata: metadata, entries: entries,
                includeInvoice: includeInvoice, to: path
            )

        case .bankAccountBook, .bankAccountBookInvoice:
            let metadata = LedgerBridge.decodeBankAccountBookMetadata(from: book.metadataJSON)
            let entries = bankAccountBookEntries(for: bookId)
            service.exportBankAccountBook(
                metadata: metadata, entries: entries,
                includeInvoice: includeInvoice, to: path
            )

        case .accountsReceivable:
            let metadata = LedgerBridge.decodeAccountsReceivableMetadata(from: book.metadataJSON)
            let entries = accountsReceivableEntries(for: bookId)
            service.exportAccountsReceivable(
                metadata: metadata, entries: entries, to: path
            )

        case .accountsPayable:
            let metadata = LedgerBridge.decodeAccountsPayableMetadata(from: book.metadataJSON)
            let entries = accountsPayableEntries(for: bookId)
            service.exportAccountsPayable(
                metadata: metadata, entries: entries, to: path
            )

        case .generalLedger, .generalLedgerInvoice:
            let metadata = LedgerBridge.decodeGeneralLedgerMetadata(from: book.metadataJSON)
            let entries = generalLedgerEntries(for: bookId)
            service.exportGeneralLedger(
                metadata: metadata, entries: entries,
                includeInvoice: includeInvoice, to: path
            )

        case .journal:
            let entries = journalEntries(for: bookId)
            service.exportJournal(entries: entries, to: path)

        default:
            return false
        }

        return true
    }

    // MARK: - PDF Export

    /// 台帳のPDF(.pdf)ファイルを指定パスに出力する
    func exportPDF(for bookId: UUID) -> Data? {
        guard let book = book(for: bookId),
              let ledgerType = book.ledgerType else { return nil }

        let service = LedgerPDFExportService.shared

        switch ledgerType {
        case .cashBook, .cashBookInvoice:
            let metadata = LedgerBridge.decodeCashBookMetadata(from: book.metadataJSON)
            let entries = cashBookEntries(for: bookId)
            return service.exportCashBook(metadata: metadata, entries: entries, includeInvoice: book.includeInvoice)

        case .bankAccountBook, .bankAccountBookInvoice:
            let metadata = LedgerBridge.decodeBankAccountBookMetadata(from: book.metadataJSON)
            let entries = bankAccountBookEntries(for: bookId)
            return service.exportBankAccountBook(metadata: metadata, entries: entries, includeInvoice: book.includeInvoice)

        case .accountsReceivable:
            let metadata = LedgerBridge.decodeAccountsReceivableMetadata(from: book.metadataJSON)
            let entries = accountsReceivableEntries(for: bookId)
            return service.exportAccountsReceivable(metadata: metadata, entries: entries)

        case .accountsPayable:
            let metadata = LedgerBridge.decodeAccountsPayableMetadata(from: book.metadataJSON)
            let entries = accountsPayableEntries(for: bookId)
            return service.exportAccountsPayable(metadata: metadata, entries: entries)

        case .expenseBook, .expenseBookInvoice:
            let metadata = LedgerBridge.decodeExpenseBookMetadata(from: book.metadataJSON)
            let entries = expenseBookEntries(for: bookId)
            return service.exportExpenseBook(metadata: metadata, entries: entries, includeInvoice: book.includeInvoice)

        case .generalLedger, .generalLedgerInvoice:
            let metadata = LedgerBridge.decodeGeneralLedgerMetadata(from: book.metadataJSON)
            let entries = generalLedgerEntries(for: bookId)
            return service.exportGeneralLedger(metadata: metadata, entries: entries, includeInvoice: book.includeInvoice)

        case .journal:
            let entries = journalEntries(for: bookId)
            return service.exportJournal(entries: entries)

        case .transportationExpense:
            let metadata = LedgerBridge.decodeTransportationExpenseMetadata(from: book.metadataJSON)
            let entries = transportationExpenseEntries(for: bookId)
            return service.exportTransportationExpense(metadata: metadata, entries: entries)

        case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            let metadata = LedgerBridge.decodeWhiteTaxBookkeepingMetadata(from: book.metadataJSON)
            let entries = whiteTaxBookkeepingEntries(for: bookId)
            return service.exportWhiteTaxBookkeeping(metadata: metadata, entries: entries, includeInvoice: book.includeInvoice)

        case .fixedAssetDepreciation:
            let entries = fixedAssetDepreciationEntries(for: bookId)
            return service.exportFixedAssetDepreciation(entries: entries)

        case .fixedAssetRegister:
            let metadata = LedgerBridge.decodeFixedAssetRegisterMetadata(from: book.metadataJSON)
            let entries = fixedAssetRegisterEntries(for: bookId)
            return service.exportFixedAssetRegister(metadata: metadata, entries: entries)
        }
    }
}
