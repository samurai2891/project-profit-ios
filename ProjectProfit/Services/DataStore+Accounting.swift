import SwiftData
import SwiftUI

enum ClosingEntryUseCaseError: LocalizedError {
    case ownerCapitalAccountMissing

    var errorDescription: String? {
        switch self {
        case .ownerCapitalAccountMissing:
            return "元入金の勘定科目が見つかりません"
        }
    }
}

@MainActor
struct ClosingEntryUseCase {
    private struct ClosingSourceEntry {
        enum EntryType {
            case normal
            case opening
            case closing
        }

        let id: UUID
        let date: Date
        let isPosted: Bool
        let entryType: EntryType
    }

    private struct ClosingSourceLine {
        let entryId: UUID
        let accountId: String
        let debit: Int
        let credit: Int
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func generate(
        businessId: UUID,
        taxYear: Int,
        startMonth: Int = FiscalYearSettings.startMonth
    ) throws -> CanonicalJournalEntry? {
        if let existing = try existingClosingEntry(businessId: businessId, taxYear: taxYear) {
            return existing
        }

        let accounts = try fetchCanonicalAccounts(businessId: businessId)
        let activeAccounts = accounts.filter { $0.archivedAt == nil }
        let yearLines = try projectedJournalLines(
            businessId: businessId,
            taxYear: taxYear,
            startMonth: startMonth
        )

        let revenueBalances = activeAccounts
            .filter { $0.accountType == .revenue }
            .compactMap { account -> (CanonicalAccount, Int)? in
                let balance = yearLines
                    .filter { $0.accountId == projectionAccountId(for: account) }
                    .reduce(0) { $0 + $1.credit - $1.debit }
                guard balance != 0 else { return nil }
                return (account, balance)
            }

        let expenseBalances = activeAccounts
            .filter { $0.accountType == .expense }
            .compactMap { account -> (CanonicalAccount, Int)? in
                let balance = yearLines
                    .filter { $0.accountId == projectionAccountId(for: account) }
                    .reduce(0) { $0 + $1.debit - $1.credit }
                guard balance != 0 else { return nil }
                return (account, balance)
            }

        guard !revenueBalances.isEmpty || !expenseBalances.isEmpty else {
            return nil
        }

        guard let ownerCapitalAccount = activeAccounts.first(where: {
            $0.legacyAccountId == AccountingConstants.ownerCapitalAccountId
        }) else {
            throw ClosingEntryUseCaseError.ownerCapitalAccountMissing
        }

        let (_, closingDate) = fiscalYearRange(year: taxYear, startMonth: startMonth)
        let voucherNumber = try nextVoucherNumber(
            businessId: businessId,
            taxYear: taxYear,
            month: Calendar(identifier: .gregorian).component(.month, from: closingDate)
        )

        let entryId = UUID()
        var journalLines: [JournalLine] = []
        var totalDebit = 0
        var totalCredit = 0
        var sortOrder = 0

        for (account, balance) in revenueBalances {
            journalLines.append(
                JournalLine(
                    journalId: entryId,
                    accountId: account.id,
                    debitAmount: Decimal(balance),
                    creditAmount: 0,
                    legalReportLineId: account.defaultLegalReportLineId,
                    sortOrder: sortOrder
                )
            )
            totalDebit += balance
            sortOrder += 1
        }

        for (account, balance) in expenseBalances {
            journalLines.append(
                JournalLine(
                    journalId: entryId,
                    accountId: account.id,
                    debitAmount: 0,
                    creditAmount: Decimal(balance),
                    legalReportLineId: account.defaultLegalReportLineId,
                    sortOrder: sortOrder
                )
            )
            totalCredit += balance
            sortOrder += 1
        }

        let netIncome = totalDebit - totalCredit
        if netIncome > 0 {
            journalLines.append(
                JournalLine(
                    journalId: entryId,
                    accountId: ownerCapitalAccount.id,
                    debitAmount: 0,
                    creditAmount: Decimal(netIncome),
                    legalReportLineId: ownerCapitalAccount.defaultLegalReportLineId,
                    sortOrder: sortOrder
                )
            )
        } else if netIncome < 0 {
            journalLines.append(
                JournalLine(
                    journalId: entryId,
                    accountId: ownerCapitalAccount.id,
                    debitAmount: Decimal(-netIncome),
                    creditAmount: 0,
                    legalReportLineId: ownerCapitalAccount.defaultLegalReportLineId,
                    sortOrder: sortOrder
                )
            )
        }

        let now = Date()
        let entry = CanonicalJournalEntry(
            id: entryId,
            businessId: businessId,
            taxYear: taxYear,
            journalDate: closingDate,
            voucherNo: voucherNumber.value,
            entryType: .closing,
            description: "\(taxYear)年 決算仕訳",
            lines: journalLines,
            approvedAt: now,
            createdAt: now,
            updatedAt: now
        )

        modelContext.insert(CanonicalJournalEntryEntityMapper.toEntity(entry))
        return entry
    }

    func delete(businessId: UUID, taxYear: Int) throws {
        let closingEntryTypeRaw = CanonicalJournalEntryType.closing.rawValue
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate {
                $0.businessId == businessId
                    && $0.taxYear == taxYear
                    && $0.entryTypeRaw == closingEntryTypeRaw
            }
        )
        let entries = try modelContext.fetch(descriptor)
        for entry in entries {
            modelContext.delete(entry)
        }
    }

    private func existingClosingEntry(businessId: UUID, taxYear: Int) throws -> CanonicalJournalEntry? {
        let closingEntryTypeRaw = CanonicalJournalEntryType.closing.rawValue
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate {
                $0.businessId == businessId
                    && $0.taxYear == taxYear
                    && $0.entryTypeRaw == closingEntryTypeRaw
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first.map(CanonicalJournalEntryEntityMapper.toDomain)
    }

    private func fetchCanonicalAccounts(businessId: UUID) throws -> [CanonicalAccount] {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(
            predicate: #Predicate { $0.businessId == businessId },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return try modelContext.fetch(descriptor).map(CanonicalAccountEntityMapper.toDomain)
    }

    private func projectedJournalLines(
        businessId: UUID,
        taxYear: Int,
        startMonth: Int
    ) throws -> [ClosingSourceLine] {
        let canonicalAccounts = try fetchCanonicalAccounts(businessId: businessId)
        let accountsById = Dictionary(uniqueKeysWithValues: canonicalAccounts.map { ($0.id, $0) })

        let journalDescriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == taxYear
            },
            sortBy: [
                SortDescriptor(\.journalDate, order: .reverse),
                SortDescriptor(\.voucherNo, order: .reverse)
            ]
        )
        let canonicalJournals = try modelContext.fetch(journalDescriptor)
            .map(CanonicalJournalEntryEntityMapper.toDomain)

        let projectedEntries: [ClosingSourceEntry] = canonicalJournals.map { journal in
            ClosingSourceEntry(
                id: journal.id,
                date: journal.journalDate,
                isPosted: journal.approvedAt != nil,
                entryType: projectedEntryType(for: journal)
            )
        }
        let projectedLines: [ClosingSourceLine] = canonicalJournals.flatMap { journal in
            journal.lines.sorted { $0.sortOrder < $1.sortOrder }.map { line in
                let legacyAccountId = accountsById[line.accountId]?.legacyAccountId ?? line.accountId.uuidString
                return ClosingSourceLine(
                    entryId: journal.id,
                    accountId: legacyAccountId,
                    debit: NSDecimalNumber(decimal: line.debitAmount).intValue,
                    credit: NSDecimalNumber(decimal: line.creditAmount).intValue
                )
            }
        }

        let (startDate, endDate) = fiscalYearRange(year: taxYear, startMonth: startMonth)
        let postedEntryIds = Set(
            projectedEntries
                .filter {
                    $0.isPosted && $0.date >= startDate && $0.date <= endDate
                        && $0.entryType != .closing
                }
                .map(\.id)
        )
        return projectedLines.filter { postedEntryIds.contains($0.entryId) }
    }

    private func projectionAccountId(for account: CanonicalAccount) -> String {
        account.legacyAccountId ?? account.id.uuidString
    }

    private func nextVoucherNumber(businessId: UUID, taxYear: Int, month: Int) throws -> VoucherNumber {
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == taxYear
            },
            sortBy: [SortDescriptor(\.voucherNo, order: .reverse)]
        )
        let sequence = try modelContext.fetch(descriptor)
            .compactMap { VoucherNumber(rawValue: $0.voucherNo) }
            .filter { $0.taxYear == taxYear && $0.month == month }
            .compactMap(\.sequence)
            .max() ?? 0
        return VoucherNumber(taxYear: taxYear, month: month, sequence: sequence + 1)
    }

    private func projectedEntryType(for entry: CanonicalJournalEntry) -> ClosingSourceEntry.EntryType {
        switch entry.entryType {
        case .opening:
            return .opening
        case .closing:
            return .closing
        case .normal, .depreciation, .inventoryAdjustment, .recurring, .taxAdjustment, .reversal:
            return .normal
        }
    }
    private func fiscalYearRange(year: Int, startMonth: Int) -> (start: Date, end: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1))!
        let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start)!
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end)!
        return (start, endOfDay)
    }
}

// MARK: - DataStore Accounting Extension

extension DataStore {
    // MARK: - Manual Journal Entry CRUD

#if DEBUG
    @discardableResult
    func addManualJournalEntry(
        date: Date,
        memo: String,
        lines: [(accountId: String, debit: Int, credit: Int, memo: String)],
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> PPJournalEntry? {
        guard !lines.isEmpty else { return nil }
        if mutationSource == .userInitiated, FeatureFlags.useCanonicalPosting {
            lastError = .legacyManualJournalMutationDisabled
            return nil
        }
        // T5: 年度ロックガード
        guard !isYearLocked(for: date) else { return nil }

        let entry = PPJournalEntry(
            sourceKey: "manual:\(UUID().uuidString)",
            date: date,
            entryType: .manual,
            memo: memo,
            isPosted: false
        )
        modelContext.insert(entry)

        for (index, line) in lines.enumerated() {
            let journalLine = PPJournalLine(
                entryId: entry.id,
                accountId: line.accountId,
                debit: line.debit,
                credit: line.credit,
                memo: line.memo,
                displayOrder: index
            )
            modelContext.insert(journalLine)
        }

        // バリデーション: 借方合計 == 貸方合計 かつ金額正常
        let debitTotal = lines.reduce(0) { $0 + $1.debit }
        let creditTotal = lines.reduce(0) { $0 + $1.credit }
        let allLinesValid = lines.allSatisfy { line in
            line.debit >= 0 && line.credit >= 0
                && !(line.debit > 0 && line.credit > 0)
                && (line.debit > 0 || line.credit > 0)
        }
        if debitTotal == creditTotal && debitTotal > 0 && allLinesValid {
            entry.isPosted = true
        }

        save()
        refreshJournalEntries()
        refreshJournalLines()
        return entry
    }

    func deleteManualJournalEntry(
        id: UUID,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) {
        guard let entry = journalEntries.first(where: { $0.id == id }) else { return }
        guard entry.entryType == .manual else { return }
        if mutationSource == .userInitiated, FeatureFlags.useCanonicalPosting {
            lastError = .legacyManualJournalMutationDisabled
            return
        }
        // T5: 年度ロックガード
        if isYearLocked(for: entry.date) { return }

        let linesToDelete = journalLines.filter { $0.entryId == id }
        for line in linesToDelete {
            modelContext.delete(line)
        }
        modelContext.delete(entry)

        save()
        refreshJournalEntries()
        refreshJournalLines()
    }
#endif

    @discardableResult
    func saveApprovedPostingSynchronously(
        _ posting: CanonicalTransactionPostingBridge.Posting,
        allocations: [(projectId: UUID, ratio: Int)],
        actor: String
    ) throws -> CanonicalJournalEntry {
        try canonicalPostingSupport.persistApprovedPosting(
            posting: posting,
            allocations: allocations,
            actor: actor,
            saveChanges: true
        )
    }

    @discardableResult
    func saveApprovedPostingSynchronously(
        _ posting: CanonicalTransactionPostingBridge.Posting,
        allocationAmounts: [Allocation],
        actor: String
    ) throws -> CanonicalJournalEntry {
        try canonicalPostingSupport.persistApprovedPosting(
            posting: posting,
            allocationAmounts: allocationAmounts,
            actor: actor,
            saveChanges: true
        )
    }

    // MARK: - Closing Entry (決算仕訳)

    /// 指定年度の決算仕訳を生成する
    @discardableResult
    func generateClosingEntry(for year: Int) -> CanonicalJournalEntry? {
        guard !isYearLocked(year) else { return nil }

        if FeatureFlags.useCanonicalPosting {
            runLegacyProfileMigrationIfNeeded()
            refreshCanonicalProfileCache()
            guard let businessId = businessProfile?.id else {
                lastError = .invalidInput(message: "申告者情報が未設定のため決算仕訳を生成できません")
                return nil
            }

            do {
                let useCase = ClosingEntryUseCase(modelContext: modelContext)
                let canonicalEntry = try useCase.generate(businessId: businessId, taxYear: year)
                deleteLegacyClosingEntryRecord(for: year)
                guard save() else { return nil }
                refreshJournalEntries()
                refreshJournalLines()
                lastError = nil
                return canonicalEntry
            } catch {
                lastError = .saveFailed(underlying: error)
                modelContext.rollback()
                refreshJournalEntries()
                refreshJournalLines()
                return nil
            }
        }

        return nil
    }

    /// 指定年度の決算仕訳を削除する
    func deleteClosingEntry(for year: Int) {
        guard !isYearLocked(year) else { return }
        if FeatureFlags.useCanonicalPosting {
            runLegacyProfileMigrationIfNeeded()
            refreshCanonicalProfileCache()
            guard let businessId = businessProfile?.id else {
                lastError = .invalidInput(message: "申告者情報が未設定のため決算仕訳を削除できません")
                return
            }

            do {
                try ClosingEntryUseCase(modelContext: modelContext).delete(businessId: businessId, taxYear: year)
                deleteLegacyClosingEntryRecord(for: year)
                guard save() else { return }
                refreshJournalEntries()
                refreshJournalLines()
                lastError = nil
            } catch {
                lastError = .saveFailed(underlying: error)
                modelContext.rollback()
                refreshJournalEntries()
                refreshJournalLines()
            }
        }
    }

    /// 指定年度の決算仕訳を再生成する（削除→生成）
    @discardableResult
    func regenerateClosingEntry(for year: Int) -> CanonicalJournalEntry? {
        guard !isYearLocked(year) else { return nil }
        if FeatureFlags.useCanonicalPosting {
            runLegacyProfileMigrationIfNeeded()
            refreshCanonicalProfileCache()
            guard let businessId = businessProfile?.id else {
                lastError = .invalidInput(message: "申告者情報が未設定のため決算仕訳を再生成できません")
                return nil
            }

            do {
                let useCase = ClosingEntryUseCase(modelContext: modelContext)
                try useCase.delete(businessId: businessId, taxYear: year)
                deleteLegacyClosingEntryRecord(for: year)
                let canonicalEntry = try useCase.generate(businessId: businessId, taxYear: year)
                guard save() else { return nil }
                refreshJournalEntries()
                refreshJournalLines()
                lastError = nil
                return canonicalEntry
            } catch {
                lastError = .saveFailed(underlying: error)
                modelContext.rollback()
                refreshJournalEntries()
                refreshJournalLines()
                return nil
            }
        }

        return nil
    }

    private func deleteLegacyClosingEntryRecord(for year: Int) {
        let sourceKey = PPJournalEntry.closingSourceKey(year: year)
        guard let entry = journalEntries.first(where: { $0.sourceKey == sourceKey }) else { return }

        let linesToDelete = journalLines.filter { $0.entryId == entry.id }
        for line in linesToDelete {
            modelContext.delete(line)
        }
        modelContext.delete(entry)
    }

    // MARK: - Account Balance

    func getAccountBalance(accountId: String, upTo date: Date? = nil) -> (debit: Int, credit: Int, balance: Int) {
        let projected = projectedCanonicalJournals(
            fiscalYear: date.map { fiscalYear(for: $0, startMonth: FiscalYearSettings.startMonth) }
        )
        let entryMap = Dictionary(uniqueKeysWithValues: projected.entries.map { ($0.id, $0) })
        let relevantLines: [PPJournalLine]
        if let date {
            let postedEntryIds = Set(
                projected.entries
                    .filter { $0.isPosted && $0.date <= date }
                    .map(\.id)
            )
            relevantLines = projected.lines.filter { line in
                guard postedEntryIds.contains(line.entryId),
                      line.accountId == accountId,
                      let entry = entryMap[line.entryId] else {
                    return false
                }
                return entry.date <= date
            }
        } else {
            let postedEntryIds = Set(projected.entries.filter(\.isPosted).map(\.id))
            relevantLines = projected.lines.filter { postedEntryIds.contains($0.entryId) && $0.accountId == accountId }
        }

        let debitTotal = relevantLines.reduce(0) { $0 + $1.debit }
        let creditTotal = relevantLines.reduce(0) { $0 + $1.credit }

        // 正常残高方向に応じた残高計算
        let account = accounts.first { $0.id == accountId }
        let balance: Int
        if account?.normalBalance == .debit {
            balance = debitTotal - creditTotal
        } else {
            balance = creditTotal - debitTotal
        }

        return (debit: debitTotal, credit: creditTotal, balance: balance)
    }

    // MARK: - Ledger Entries

    struct LedgerEntry: Identifiable {
        let id: UUID
        let date: Date
        let memo: String
        let entryType: JournalEntryType
        let debit: Int
        let credit: Int
        let runningBalance: Int
        let counterparty: String?
        let taxCategory: TaxCategory?

        init(
            id: UUID,
            date: Date,
            memo: String,
            entryType: JournalEntryType,
            debit: Int,
            credit: Int,
            runningBalance: Int,
            counterparty: String? = nil,
            taxCategory: TaxCategory? = nil
        ) {
            self.id = id
            self.date = date
            self.memo = memo
            self.entryType = entryType
            self.debit = debit
            self.credit = credit
            self.runningBalance = runningBalance
            self.counterparty = counterparty
            self.taxCategory = taxCategory
        }
    }

    func getLedgerEntries(
        accountId: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [LedgerEntry] {
        let requestedFiscalYear: Int?
        if let startDate {
            requestedFiscalYear = fiscalYear(for: startDate, startMonth: FiscalYearSettings.startMonth)
        } else if let endDate {
            requestedFiscalYear = fiscalYear(for: endDate, startMonth: FiscalYearSettings.startMonth)
        } else {
            requestedFiscalYear = nil
        }
        let projected = projectedCanonicalJournals(fiscalYear: requestedFiscalYear)
        let postedEntryIds = Set(projected.entries.filter(\.isPosted).map(\.id))
        let entryMap = Dictionary(uniqueKeysWithValues: projected.entries.map { ($0.id, $0) })
        let transactionMap = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        let transactionMapByJournalEntryId: [UUID: PPTransaction] = Dictionary(
            uniqueKeysWithValues: transactions.compactMap { transaction in
                guard let journalEntryId = transaction.journalEntryId else {
                    return nil
                }
                return (journalEntryId, transaction)
            }
        )
        let canonicalCounterpartyByEntryId: [UUID: UUID] = {
            guard let businessId = businessProfile?.id else { return [:] }
            return Dictionary(
                uniqueKeysWithValues: fetchCanonicalJournalEntries(businessId: businessId, taxYear: requestedFiscalYear).compactMap { journal in
                    guard let counterpartyId = journal.lines.compactMap(\.counterpartyId).first else {
                        return nil
                    }
                    return (journal.id, counterpartyId)
                }
            )
        }()

        let relevantLines = projected.lines
            .filter { $0.accountId == accountId && postedEntryIds.contains($0.entryId) }
            .compactMap { line -> (line: PPJournalLine, entry: PPJournalEntry)? in
                guard let entry = entryMap[line.entryId] else { return nil }
                if let start = startDate, entry.date < start { return nil }
                if let end = endDate, entry.date > end { return nil }
                return (line, entry)
            }
            .sorted { $0.entry.date < $1.entry.date }

        let account = accounts.first { $0.id == accountId }
        let isDebitNormal = account?.normalBalance == .debit

        var runningBalance = 0
        return relevantLines.map { pair in
            if isDebitNormal {
                runningBalance += pair.line.debit - pair.line.credit
            } else {
                runningBalance += pair.line.credit - pair.line.debit
            }

            let transaction = pair.entry.sourceTransactionId.flatMap { transactionMap[$0] }
                ?? transactionMapByJournalEntryId[pair.entry.id]
            let resolvedCounterparty = (transaction?.counterpartyId ?? canonicalCounterpartyByEntryId[pair.entry.id])
                .flatMap { canonicalCounterparty(id: $0)?.displayName }
                ?? transaction?.counterparty

            return LedgerEntry(
                id: pair.line.id,
                date: pair.entry.date,
                memo: pair.entry.memo,
                entryType: pair.entry.entryType,
                debit: pair.line.debit,
                credit: pair.line.credit,
                runningBalance: runningBalance,
                counterparty: resolvedCounterparty,
                taxCategory: transaction?.taxCategory
            )
        }
    }

}
