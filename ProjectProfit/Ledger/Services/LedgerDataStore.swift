// ============================================================
// LedgerDataStore.swift
// 帳簿データの CRUD と残高計算
// ============================================================

import Foundation
import os
import SwiftData

@MainActor
@Observable
final class LedgerDataStore {
    enum AccessMode: Sendable {
        case readOnly
        case readWrite
    }

    private static let logger = Logger(subsystem: "com.projectprofit", category: "LedgerDataStore")

    private let modelContext: ModelContext
    private let accessMode: AccessMode

    var books: [SDLedgerBook] = []
    var lastError: AppError?

    var isReadOnly: Bool {
        accessMode == .readOnly
    }

    init(modelContext: ModelContext, accessMode: AccessMode = .readOnly) {
        self.modelContext = modelContext
        self.accessMode = accessMode
        loadBooks()
    }

    // MARK: - Load

    func loadBooks() {
        let descriptor = FetchDescriptor<SDLedgerBook>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        books = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Book CRUD

    @discardableResult
    func createBook(
        ledgerType: LedgerType,
        title: String,
        metadataJSON: String = "{}",
        includeInvoice: Bool = false
    ) -> SDLedgerBook? {
        guard ensureWriteAccess() else {
            return nil
        }
        let book = SDLedgerBook(
            ledgerType: ledgerType,
            title: title,
            metadataJSON: metadataJSON,
            includeInvoice: includeInvoice
        )
        modelContext.insert(book)
        save()
        loadBooks()
        return book
    }

    func updateBookTitle(_ bookId: UUID, title: String) {
        guard ensureWriteAccess() else { return }
        guard let book = books.first(where: { $0.id == bookId }) else { return }
        book.title = title
        book.updatedAt = Date()
        save()
        loadBooks()
    }

    func updateBookMetadata(_ bookId: UUID, metadataJSON: String) {
        guard ensureWriteAccess() else { return }
        guard let book = books.first(where: { $0.id == bookId }) else { return }
        book.metadataJSON = metadataJSON
        book.updatedAt = Date()
        save()
        loadBooks()
    }

    func deleteBook(_ bookId: UUID) {
        guard ensureWriteAccess() else { return }
        guard let book = books.first(where: { $0.id == bookId }) else { return }
        // Delete all entries first
        let entries = fetchRawEntries(for: bookId)
        for entry in entries {
            modelContext.delete(entry)
        }
        modelContext.delete(book)
        save()
        loadBooks()
    }

    func book(for id: UUID) -> SDLedgerBook? {
        books.first { $0.id == id }
    }

    func books(ofType type: LedgerType) -> [SDLedgerBook] {
        books.filter { $0.ledgerTypeRaw == type.rawValue }
    }

    // MARK: - Entry CRUD

    @discardableResult
    func addEntry<T: Encodable>(
        to bookId: UUID,
        entry: T,
        sortOrder: Int? = nil
    ) -> SDLedgerEntry? {
        guard ensureWriteAccess() else { return nil }
        let order = sortOrder ?? (fetchRawEntries(for: bookId).count)
        guard let sdEntry = LedgerBridge.encodeEntry(entry, bookId: bookId, sortOrder: order) else {
            return nil
        }
        modelContext.insert(sdEntry)
        updateBookTimestamp(bookId)
        save()
        return sdEntry
    }

    func updateEntry<T: Encodable>(_ entryId: UUID, bookId: UUID, newEntry: T) {
        guard ensureWriteAccess() else { return }
        guard let sdEntry = fetchRawEntry(id: entryId) else { return }
        guard let json = LedgerBridge.encode(newEntry) else { return }
        sdEntry.entryJSON = json
        sdEntry.updatedAt = Date()
        updateBookTimestamp(bookId)
        save()
    }

    func deleteEntry(_ entryId: UUID, bookId: UUID) {
        guard ensureWriteAccess() else { return }
        guard let sdEntry = fetchRawEntry(id: entryId) else { return }
        modelContext.delete(sdEntry)
        updateBookTimestamp(bookId)
        save()
    }

    func reorderEntries(bookId: UUID, orderedIds: [UUID]) {
        guard ensureWriteAccess() else { return }
        let entries = fetchRawEntries(for: bookId)
        let entryMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for (index, id) in orderedIds.enumerated() {
            entryMap[id]?.sortOrder = index
        }
        save()
    }

    // MARK: - Raw Entry Fetch

    func fetchRawEntries(for bookId: UUID) -> [SDLedgerEntry] {
        let descriptor = FetchDescriptor<SDLedgerEntry>(
            predicate: #Predicate<SDLedgerEntry> { $0.bookId == bookId },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchRawEntry(id: UUID) -> SDLedgerEntry? {
        let descriptor = FetchDescriptor<SDLedgerEntry>(
            predicate: #Predicate<SDLedgerEntry> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Type-Safe Entry Decode

    func cashBookEntries(for bookId: UUID) -> [CashBookEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeCashBookEntry(from: $0) }
    }

    func bankAccountBookEntries(for bookId: UUID) -> [BankAccountBookEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeBankAccountBookEntry(from: $0) }
    }

    func accountsReceivableEntries(for bookId: UUID) -> [AccountsReceivableEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeAccountsReceivableEntry(from: $0) }
    }

    func accountsPayableEntries(for bookId: UUID) -> [AccountsPayableEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeAccountsPayableEntry(from: $0) }
    }

    func expenseBookEntries(for bookId: UUID) -> [ExpenseBookEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeExpenseBookEntry(from: $0) }
    }

    func generalLedgerEntries(for bookId: UUID) -> [GeneralLedgerEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeGeneralLedgerEntry(from: $0) }
    }

    func journalEntries(for bookId: UUID) -> [JournalEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeJournalEntry(from: $0) }
    }

    func fixedAssetDepreciationEntries(for bookId: UUID) -> [FixedAssetDepreciationEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeFixedAssetDepreciationEntry(from: $0) }
    }

    func fixedAssetRegisterEntries(for bookId: UUID) -> [FixedAssetRegisterEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeFixedAssetRegisterEntry(from: $0) }
    }

    func transportationExpenseEntries(for bookId: UUID) -> [TransportationExpenseEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeTransportationExpenseEntry(from: $0) }
    }

    func whiteTaxBookkeepingEntries(for bookId: UUID) -> [WhiteTaxBookkeepingEntry] {
        fetchRawEntries(for: bookId).compactMap { LedgerBridge.decodeWhiteTaxBookkeepingEntry(from: $0) }
    }

    // MARK: - Persistence Helpers

    private func ensureWriteAccess() -> Bool {
        // REL-P0-01: canonical正本モード時は旧台帳への書き込みを拒否
        guard FeatureFlags.useLegacyLedger else {
            Self.logger.warning("Write access denied: legacy ledger is disabled (useLegacyLedger=false)")
            lastError = .invalidInput(message: "旧台帳は読み取り専用です")
            return false
        }
        guard !isReadOnly else {
            Self.logger.warning("Write access denied: LedgerDataStore is read-only")
            lastError = .invalidInput(message: "旧台帳は読み取り専用です")
            return false
        }
        return true
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            lastError = .saveFailed(underlying: error)
            loadBooks()
        }
    }

    private func updateBookTimestamp(_ bookId: UUID) {
        if let book = books.first(where: { $0.id == bookId }) {
            book.updatedAt = Date()
        }
    }
}
