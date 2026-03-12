// ============================================================
// LedgerBookDetailView.swift
// 帳簿の詳細 - エントリ一覧と残高表示
// ============================================================

import SwiftUI

struct LedgerBookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LedgerDataStore.self) private var ledgerStore

    let bookId: UUID

    @State private var showAddEntry = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showCSVImport = false
    @State private var errorMessage: String?

    private var book: SDLedgerBook? {
        ledgerStore.book(for: bookId)
    }

    private var rawEntries: [SDLedgerEntry] {
        ledgerStore.fetchRawEntries(for: bookId)
    }

    private var balanceRows: [LedgerBalanceRow] {
        ledgerStore.balances(for: bookId)
    }

    private var balanceMap: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: balanceRows.map { ($0.id, $0.balance) })
    }

    private var legacyLedgerOptions: ExportCoordinator.LegacyLedgerExportOptions? {
        guard let book, let ledgerType = book.ledgerType else {
            return nil
        }
        return ExportCoordinator.LegacyLedgerExportOptions(
            bookId: book.id,
            bookTitle: book.title,
            ledgerType: ledgerType,
            metadataJSON: book.metadataJSON,
            includeInvoice: book.includeInvoice
        )
    }

    var body: some View {
        Group {
            if rawEntries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .navigationTitle(book?.title ?? "帳簿")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Menu {
                        if !rawEntries.isEmpty {
                            Button("CSV出力") { exportCSV() }
                            Button("Excel出力") { exportExcel() }
                            Button("PDF出力") { exportPDF() }
                        }
                        if !ledgerStore.isReadOnly {
                            if !rawEntries.isEmpty {
                                Divider()
                            }
                            Button("CSVインポート") { showCSVImport = true }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("出力・インポート")
                    if !ledgerStore.isReadOnly {
                        Button {
                            showAddEntry = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("エントリを追加")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddEntry) {
            NavigationStack {
                LedgerEntryFormView(bookId: bookId)
            }
        }
        .sheet(isPresented: $showCSVImport) {
            LedgerCSVImportView(bookId: bookId)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheetView(activityItems: [url])
            }
        }
        .alert("出力エラー", isPresented: Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("エントリがありません")
                .font(.headline)
            Text(ledgerStore.isReadOnly ? "旧台帳は読み取り専用です" : "＋ボタンからエントリを追加してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var entryList: some View {
        List {
            carryForwardRow

            if ledgerStore.isReadOnly {
                ForEach(Array(rawEntries.enumerated()), id: \.element.id) { index, sdEntry in
                    entryRow(sdEntry, index: index)
                }
            } else {
                ForEach(Array(rawEntries.enumerated()), id: \.element.id) { index, sdEntry in
                    entryRow(sdEntry, index: index)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let entry = rawEntries[index]
                        ledgerStore.deleteEntry(entry.id, bookId: bookId)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var carryForwardRow: some View {
        if let book, let ledgerType = book.ledgerType {
            let carryForward = carryForwardAmount(for: ledgerType, metadataJSON: book.metadataJSON)
            if let carryForward {
                HStack {
                    Text("前期より繰越")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatCurrency(carryForward))
                        .font(.caption.monospacedDigit().weight(.medium))
                }
                .listRowBackground(AppColors.surface.opacity(0.5))
            }
        }
    }

    private func entryRow(_ sdEntry: SDLedgerEntry, index: Int) -> some View {
        let decoded = decodeSummary(sdEntry)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(decoded.dateStr)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    Text(decoded.description)
                        .font(.caption)
                        .lineLimit(1)
                }
                if !decoded.account.isEmpty {
                    Text(decoded.account)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if decoded.income != 0 {
                    Text("+\(formatCurrency(decoded.income))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColors.success)
                }
                if decoded.expense != 0 {
                    Text("-\(formatCurrency(decoded.expense))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColors.error)
                }
            }

            if let balance = balanceMap[decoded.id] {
                Text(formatCurrency(balance))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Decode Summary

    private struct EntrySummary {
        let id: UUID
        let dateStr: String
        let description: String
        let account: String
        let income: Int
        let expense: Int
    }

    private func decodeSummary(_ sd: SDLedgerEntry) -> EntrySummary {
        guard let book, let ledgerType = book.ledgerType else {
            return EntrySummary(id: sd.id, dateStr: "", description: "?", account: "", income: 0, expense: 0)
        }

        switch ledgerType {
        case .cashBook, .cashBookInvoice:
            if let e = LedgerBridge.decodeCashBookEntry(from: sd) {
                return EntrySummary(
                    id: e.id, dateStr: "\(e.month)/\(e.day)",
                    description: e.description, account: e.account,
                    income: e.income ?? 0, expense: e.expense ?? 0
                )
            }

        case .bankAccountBook, .bankAccountBookInvoice:
            if let e = LedgerBridge.decodeBankAccountBookEntry(from: sd) {
                return EntrySummary(
                    id: e.id, dateStr: "\(e.month)/\(e.day)",
                    description: e.description, account: e.account,
                    income: e.deposit ?? 0, expense: e.withdrawal ?? 0
                )
            }

        case .accountsReceivable:
            if let e = LedgerBridge.decodeAccountsReceivableEntry(from: sd) {
                return EntrySummary(
                    id: e.id, dateStr: "\(e.month)/\(e.day)",
                    description: e.description, account: e.counterAccount,
                    income: e.salesAmount ?? 0, expense: e.receivedAmount ?? 0
                )
            }

        case .accountsPayable:
            if let e = LedgerBridge.decodeAccountsPayableEntry(from: sd) {
                return EntrySummary(
                    id: e.id, dateStr: "\(e.month)/\(e.day)",
                    description: e.description, account: e.counterAccount,
                    income: e.purchaseAmount ?? 0, expense: e.paymentAmount ?? 0
                )
            }

        case .expenseBook, .expenseBookInvoice:
            if let e = LedgerBridge.decodeExpenseBookEntry(from: sd) {
                return EntrySummary(
                    id: e.id, dateStr: "\(e.month)/\(e.day)",
                    description: e.description, account: e.counterAccount,
                    income: 0, expense: e.amount
                )
            }

        case .generalLedger, .generalLedgerInvoice:
            if let e = LedgerBridge.decodeGeneralLedgerEntry(from: sd) {
                return EntrySummary(
                    id: e.id, dateStr: "\(e.month)/\(e.day)",
                    description: e.description, account: e.counterAccount,
                    income: e.debit ?? 0, expense: e.credit ?? 0
                )
            }

        case .journal:
            if let e = LedgerBridge.decodeJournalEntry(from: sd) {
                return EntrySummary(
                    id: e.id, dateStr: "\(e.month)/\(e.day)",
                    description: e.description, account: e.debitAccount ?? "",
                    income: e.debitAmount ?? 0, expense: e.creditAmount ?? 0
                )
            }

        case .transportationExpense:
            if let e = LedgerBridge.decodeTransportationExpenseEntry(from: sd) {
                return EntrySummary(
                    id: e.id, dateStr: e.date,
                    description: e.destination, account: e.transportMethod,
                    income: 0, expense: e.amount
                )
            }

        case .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            if let e = LedgerBridge.decodeWhiteTaxBookkeepingEntry(from: sd) {
                let totalExpense = [
                    e.purchases, e.salaries, e.outsourcing, e.depreciation, e.badDebts,
                    e.rent, e.interestDiscount, e.taxesDuties, e.packingShipping,
                    e.utilities, e.travelTransport, e.communication, e.advertising,
                    e.entertainment, e.insurance, e.repairs, e.supplies, e.welfare,
                    e.miscellaneous
                ].compactMap { $0 }.reduce(0, +)
                let totalIncome = (e.salesAmount ?? 0) + (e.miscIncome ?? 0)
                return EntrySummary(
                    id: e.id, dateStr: "\(e.month)/\(e.day)",
                    description: e.description, account: "",
                    income: totalIncome, expense: totalExpense
                )
            }

        case .fixedAssetDepreciation:
            if let e = LedgerBridge.decodeFixedAssetDepreciationEntry(from: sd) {
                let depExp = Int(Double(e.openingBookValue) * e.depreciationRate)
                return EntrySummary(
                    id: e.id, dateStr: e.acquisitionDate,
                    description: e.assetName, account: e.account,
                    income: e.acquisitionCost, expense: depExp
                )
            }

        case .fixedAssetRegister:
            if let e = LedgerBridge.decodeFixedAssetRegisterEntry(from: sd) {
                return EntrySummary(
                    id: e.id, dateStr: e.date,
                    description: e.description, account: "",
                    income: e.acquiredAmount ?? 0, expense: e.depreciationAmount ?? 0
                )
            }
        }

        return EntrySummary(id: sd.id, dateStr: "", description: "?", account: "", income: 0, expense: 0)
    }

    // MARK: - Carry Forward

    private func carryForwardAmount(for type: LedgerType, metadataJSON: String) -> Int? {
        switch type {
        case .cashBook, .cashBookInvoice:
            return LedgerBridge.decodeCashBookMetadata(from: metadataJSON).carryForward
        case .bankAccountBook, .bankAccountBookInvoice:
            return LedgerBridge.decodeBankAccountBookMetadata(from: metadataJSON).carryForward
        case .accountsReceivable:
            return LedgerBridge.decodeAccountsReceivableMetadata(from: metadataJSON).carryForward
        case .accountsPayable:
            return LedgerBridge.decodeAccountsPayableMetadata(from: metadataJSON).carryForward
        case .generalLedger, .generalLedgerInvoice:
            return LedgerBridge.decodeGeneralLedgerMetadata(from: metadataJSON).carryForward
        default:
            return nil
        }
    }

    // MARK: - CSV Export

    private func exportCSV() {
        exportAndShare(format: .csv)
    }

    // MARK: - Excel Export

    private func exportExcel() {
        exportAndShare(format: .xlsx)
    }

    // MARK: - PDF Export

    private func exportPDF() {
        exportAndShare(format: .pdf)
    }

    private func exportAndShare(format: ExportCoordinator.ExportFormat) {
        guard let legacyLedgerOptions else {
            return
        }
        do {
            shareURL = try ExportCoordinator.export(
                format: format,
                modelContext: modelContext,
                legacyLedgerOptions: legacyLedgerOptions
            )
            showShareSheet = true
        } catch {
            shareURL = nil
            showShareSheet = false
            errorMessage = error.localizedDescription
        }
    }
}
