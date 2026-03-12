import Foundation
import SwiftData

struct AccountingHomeSnapshot {
    let unpostedJournalCount: Int
    let suspenseBalance: Int
    let totalAccounts: Int
    let totalJournalEntries: Int
    let isBootstrapped: Bool
}

struct AccountingReportBundle {
    let trialBalance: TrialBalanceReport
    let profitLoss: ProfitLossReport
    let balanceSheet: BalanceSheetReport
}

struct ProjectedJournalSnapshot {
    let businessId: UUID?
    let entries: [PPJournalEntry]
    let lines: [PPJournalLine]
}

struct JournalListSnapshot {
    let businessId: UUID?
    let projects: [PPProject]
    let entries: [PPJournalEntry]
    let lines: [PPJournalLine]
    let canCreateManualJournals: Bool
}

struct JournalDetailSnapshot {
    let lines: [PPJournalLine]
    let accountNamesById: [String: String]
}

struct GeneralLedgerBalance {
    let debit: Int
    let credit: Int
    let balance: Int
}

struct AccountingLedgerEntry: Identifiable {
    let id: UUID
    let date: Date
    let memo: String
    let entryType: JournalEntryType
    let debit: Int
    let credit: Int
    let runningBalance: Int
    let counterparty: String?
    let taxCategory: TaxCategory?
}

struct GeneralLedgerSnapshot {
    let account: PPAccount?
    let entries: [AccountingLedgerEntry]
    let balance: GeneralLedgerBalance
}

struct SubLedgerSnapshot {
    let entries: [SubLedgerEntry]
    let summary: SubLedgerSummary
    let expenseAccounts: [PPAccount]
}

struct ClosingEntryDisplayLine: Identifiable {
    let id: UUID
    let accountName: String
    let debit: Int
    let credit: Int
}

struct ClosingEntrySnapshot {
    let businessId: UUID?
    let closingEntry: CanonicalJournalEntry?
    let displayLines: [ClosingEntryDisplayLine]
    let yearState: YearLockState
}

struct FixedAssetListSnapshot {
    let assets: [PPFixedAsset]
    let bookValueByAssetId: [UUID: Int]
}

struct FixedAssetDetailSnapshot {
    let asset: PPFixedAsset?
    let isAssetFiscalYearLocked: Bool
    let isCurrentYearLocked: Bool
    let schedule: [DepreciationCalculation]
    let relatedEntries: [PPJournalEntry]
}

struct InventoryYearSnapshot {
    let record: PPInventoryRecord?
}

struct ClassificationResultItem {
    let transaction: PPTransaction
    let result: ClassificationEngine.ClassificationResult
}

struct ClassificationSnapshot {
    let results: [ClassificationResultItem]
    let userRules: [PPUserRule]
}

struct EtaxExportContext {
    let businessId: UUID?
    let fallbackTaxYearProfile: TaxYearProfile?
}

@MainActor
struct AccountingReadSupport {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchProjects() -> [PPProject] {
        fetch(
            FetchDescriptor<PPProject>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }

    func fetchTransactions() -> [PPTransaction] {
        fetch(
            FetchDescriptor<PPTransaction>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )
    }

    func fetchCategories() -> [PPCategory] {
        fetch(
            FetchDescriptor<PPCategory>(
                sortBy: [SortDescriptor(\.name)]
            )
        )
    }

    func fetchAccounts() -> [PPAccount] {
        fetch(
            FetchDescriptor<PPAccount>(
                sortBy: [SortDescriptor(\.displayOrder)]
            )
        )
    }

    func fetchJournalEntries() -> [PPJournalEntry] {
        fetch(
            FetchDescriptor<PPJournalEntry>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        )
    }

    func fetchJournalLines() -> [PPJournalLine] {
        fetch(
            FetchDescriptor<PPJournalLine>(
                sortBy: [SortDescriptor(\.displayOrder)]
            )
        )
    }

    func fetchInventoryRecord(fiscalYear: Int) -> PPInventoryRecord? {
        let descriptor = FetchDescriptor<PPInventoryRecord>(
            predicate: #Predicate { $0.fiscalYear == fiscalYear }
        )
        return fetch(descriptor).first
    }

    func fetchBusinessProfile() -> BusinessProfile? {
        let descriptor = FetchDescriptor<BusinessProfileEntity>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return fetch(descriptor).first.map(BusinessProfileEntityMapper.toDomain)
    }

    func fetchTaxYearProfile(businessId: UUID, taxYear: Int) -> TaxYearProfile? {
        let descriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == taxYear
            }
        )
        return fetch(descriptor).first.map(TaxYearProfileEntityMapper.toDomain)
    }

    func fetchCanonicalAccounts(businessId: UUID) -> [CanonicalAccount] {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(
            predicate: #Predicate { $0.businessId == businessId },
            sortBy: [
                SortDescriptor(\.displayOrder),
                SortDescriptor(\.code)
            ]
        )
        return fetch(descriptor).map(CanonicalAccountEntityMapper.toDomain)
    }

    func fetchCanonicalJournalEntries(
        businessId: UUID,
        taxYear: Int? = nil
    ) -> [CanonicalJournalEntry] {
        let descriptor: FetchDescriptor<JournalEntryEntity>
        if let taxYear {
            descriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                },
                sortBy: [
                    SortDescriptor(\.journalDate, order: .reverse),
                    SortDescriptor(\.voucherNo, order: .reverse)
                ]
            )
        } else {
            descriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [
                    SortDescriptor(\.journalDate, order: .reverse),
                    SortDescriptor(\.voucherNo, order: .reverse)
                ]
            )
        }
        return fetch(descriptor).map(CanonicalJournalEntryEntityMapper.toDomain)
    }

    func fetchCanonicalCounterparty(id: UUID) -> Counterparty? {
        let descriptor = FetchDescriptor<CounterpartyEntity>(
            predicate: #Predicate { $0.counterpartyId == id }
        )
        return fetch(descriptor).first.map(CounterpartyEntityMapper.toDomain)
    }

    func projectedCanonicalJournals(fiscalYear requestedFiscalYear: Int? = nil) -> ProjectedJournalSnapshot {
        guard let businessProfile = fetchBusinessProfile() else {
            return ProjectedJournalSnapshot(businessId: nil, entries: [], lines: [])
        }

        let canonicalAccounts = fetchCanonicalAccounts(businessId: businessProfile.id)
        let accountsById = Dictionary(uniqueKeysWithValues: canonicalAccounts.map { ($0.id, $0) })
        let journals = fetchCanonicalJournalEntries(
            businessId: businessProfile.id,
            taxYear: requestedFiscalYear
        )

        let projectedEntries = journals.map { entry in
            PPJournalEntry(
                id: entry.id,
                sourceKey: "canonical:\(entry.id.uuidString)",
                date: entry.journalDate,
                entryType: projectedLegacyEntryType(for: entry),
                memo: entry.description,
                isPosted: entry.approvedAt != nil,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt
            )
        }

        let projectedLines = journals.flatMap { entry in
            entry.lines.sorted { $0.sortOrder < $1.sortOrder }.map { line in
                let legacyAccountId = accountsById[line.accountId]?.legacyAccountId ?? line.accountId.uuidString
                return PPJournalLine(
                    id: line.id,
                    entryId: entry.id,
                    accountId: legacyAccountId,
                    debit: NSDecimalNumber(decimal: line.debitAmount).intValue,
                    credit: NSDecimalNumber(decimal: line.creditAmount).intValue,
                    memo: "",
                    displayOrder: line.sortOrder,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt
                )
            }
        }

        let legacyEntries = fetchJournalEntries().filter { entry in
            guard !projectedEntries.contains(where: { $0.id == entry.id }) else {
                return false
            }
            let isSupplemental = entry.sourceKey.hasPrefix("manual:")
                || entry.sourceKey.hasPrefix("opening:")
                || entry.sourceKey.hasPrefix("closing:")
            guard isSupplemental else {
                return false
            }
            guard let requestedFiscalYear else {
                return true
            }
            return fiscalYear(for: entry.date, startMonth: FiscalYearSettings.startMonth) == requestedFiscalYear
        }
        let supplementalIds = Set(legacyEntries.map(\.id))
        let legacyLines = fetchJournalLines().filter { supplementalIds.contains($0.entryId) }

        let mergedEntries = (projectedEntries + legacyEntries).sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.date > rhs.date
        }
        return ProjectedJournalSnapshot(
            businessId: businessProfile.id,
            entries: mergedEntries,
            lines: projectedLines + legacyLines
        )
    }

    func accountBalance(accountId: String, upTo date: Date? = nil) -> GeneralLedgerBalance {
        let requestedFiscalYear = date.map { fiscalYear(for: $0, startMonth: FiscalYearSettings.startMonth) }
        let projected = projectedCanonicalJournals(fiscalYear: requestedFiscalYear)
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
                      let entry = entryMap[line.entryId]
                else {
                    return false
                }
                return entry.date <= date
            }
        } else {
            let postedEntryIds = Set(projected.entries.filter(\.isPosted).map(\.id))
            relevantLines = projected.lines.filter {
                postedEntryIds.contains($0.entryId) && $0.accountId == accountId
            }
        }

        let debitTotal = relevantLines.reduce(0) { $0 + $1.debit }
        let creditTotal = relevantLines.reduce(0) { $0 + $1.credit }
        let account = fetchAccounts().first { $0.id == accountId }
        let balance = account?.normalBalance == .debit
            ? debitTotal - creditTotal
            : creditTotal - debitTotal

        return GeneralLedgerBalance(
            debit: debitTotal,
            credit: creditTotal,
            balance: balance
        )
    }

    func ledgerEntries(
        accountId: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [AccountingLedgerEntry] {
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
        let transactionMap = Dictionary(uniqueKeysWithValues: fetchTransactions().map { ($0.id, $0) })
        let transactionMapByJournalEntryId: [UUID: PPTransaction] = Dictionary(
            uniqueKeysWithValues: fetchTransactions().compactMap { transaction in
                guard let journalEntryId = transaction.journalEntryId else {
                    return nil
                }
                return (journalEntryId, transaction)
            }
        )
        let canonicalCounterpartyByEntryId: [UUID: UUID] = {
            guard let businessId = projected.businessId else { return [:] }
            return Dictionary(
                uniqueKeysWithValues: fetchCanonicalJournalEntries(
                    businessId: businessId,
                    taxYear: requestedFiscalYear
                ).compactMap { journal in
                    guard let counterpartyId = journal.lines.compactMap(\.counterpartyId).first else {
                        return nil
                    }
                    return (journal.id, counterpartyId)
                }
            )
        }()

        let relevantLines = projected.lines
            .filter { $0.accountId == accountId && postedEntryIds.contains($0.entryId) }
            .compactMap { line -> (PPJournalLine, PPJournalEntry)? in
                guard let entry = entryMap[line.entryId] else { return nil }
                if let startDate, entry.date < startDate { return nil }
                if let endDate, entry.date > endDate { return nil }
                return (line, entry)
            }
            .sorted { $0.1.date < $1.1.date }

        let account = fetchAccounts().first { $0.id == accountId }
        let isDebitNormal = account?.normalBalance == .debit
        var runningBalance = 0

        return relevantLines.map { line, entry in
            if isDebitNormal {
                runningBalance += line.debit - line.credit
            } else {
                runningBalance += line.credit - line.debit
            }

            let transaction = entry.sourceTransactionId.flatMap { transactionMap[$0] }
                ?? transactionMapByJournalEntryId[entry.id]
            let resolvedCounterparty = (transaction?.counterpartyId ?? canonicalCounterpartyByEntryId[entry.id])
                .flatMap { fetchCanonicalCounterparty(id: $0)?.displayName }
                ?? transaction?.counterparty

            return AccountingLedgerEntry(
                id: line.id,
                date: entry.date,
                memo: entry.memo,
                entryType: entry.entryType,
                debit: line.debit,
                credit: line.credit,
                runningBalance: runningBalance,
                counterparty: resolvedCounterparty,
                taxCategory: transaction?.taxCategory
            )
        }
    }

    func subLedgerEntries(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil,
        accountFilter: String? = nil,
        counterpartyFilter: String? = nil
    ) -> [SubLedgerEntry] {
        let accounts = fetchAccounts()
        let targetAccountIds: [String]
        if let accountFilter {
            targetAccountIds = [accountFilter]
        } else {
            targetAccountIds = subLedgerAccountIds(for: type, accounts: accounts)
        }
        guard !targetAccountIds.isEmpty else { return [] }

        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
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
        let transactionMap = Dictionary(uniqueKeysWithValues: fetchTransactions().map { ($0.id, $0) })
        let transactionMapByJournalEntryId: [UUID: PPTransaction] = Dictionary(
            uniqueKeysWithValues: fetchTransactions().compactMap { transaction in
                guard let journalEntryId = transaction.journalEntryId else {
                    return nil
                }
                return (journalEntryId, transaction)
            }
        )
        let linesByEntry = Dictionary(grouping: projected.lines) { $0.entryId }
        let targetAccountIdSet = Set(targetAccountIds)
        let canonicalCounterpartyByEntryId: [UUID: UUID] = {
            guard let businessId = projected.businessId else { return [:] }
            return Dictionary(
                uniqueKeysWithValues: fetchCanonicalJournalEntries(
                    businessId: businessId,
                    taxYear: requestedFiscalYear
                ).compactMap { journal in
                    guard let counterpartyId = journal.lines.compactMap(\.counterpartyId).first else {
                        return nil
                    }
                    return (journal.id, counterpartyId)
                }
            )
        }()

        var enrichedLines: [(
            lineId: UUID,
            entryDate: Date,
            accountId: String,
            accountCode: String,
            accountName: String,
            memo: String,
            debit: Int,
            credit: Int,
            counterAccountId: String?,
            counterparty: String?,
            taxCategory: TaxCategory?
        )] = []

        for journalLine in projected.lines {
            guard targetAccountIdSet.contains(journalLine.accountId),
                  postedEntryIds.contains(journalLine.entryId),
                  let entry = entryMap[journalLine.entryId]
            else {
                continue
            }
            if let startDate, entry.date < startDate { continue }
            if let endDate, entry.date > endDate { continue }

            let account = accountMap[journalLine.accountId]
            let siblingLines = linesByEntry[entry.id]?.filter { $0.id != journalLine.id } ?? []
            let transaction = entry.sourceTransactionId.flatMap { transactionMap[$0] }
                ?? transactionMapByJournalEntryId[entry.id]
            let resolvedCounterparty = (transaction?.counterpartyId ?? canonicalCounterpartyByEntryId[entry.id])
                .flatMap { fetchCanonicalCounterparty(id: $0)?.displayName }
                ?? transaction?.counterparty

            enrichedLines.append((
                lineId: journalLine.id,
                entryDate: entry.date,
                accountId: journalLine.accountId,
                accountCode: account?.code ?? journalLine.accountId,
                accountName: account?.name ?? journalLine.accountId,
                memo: entry.memo,
                debit: journalLine.debit,
                credit: journalLine.credit,
                counterAccountId: siblingLines.max(by: { $0.amount < $1.amount })?.accountId,
                counterparty: resolvedCounterparty,
                taxCategory: transaction?.taxCategory
            ))
        }

        enrichedLines.sort {
            if $0.entryDate != $1.entryDate { return $0.entryDate < $1.entryDate }
            if $0.accountCode != $1.accountCode { return $0.accountCode < $1.accountCode }
            return $0.lineId.uuidString < $1.lineId.uuidString
        }

        if let counterpartyFilter {
            enrichedLines = enrichedLines.filter { line in
                let counterparty = line.counterparty ?? ""
                return counterpartyFilter.isEmpty ? counterparty.isEmpty : counterparty == counterpartyFilter
            }
        }

        var runningBalances: [String: Int] = [:]
        return enrichedLines.map { line in
            let account = accountMap[line.accountId]
            let isDebitNormal = account?.normalBalance == .debit
            let balanceKey: String
            switch type {
            case .accountsReceivableBook, .accountsPayableBook:
                balanceKey = line.counterparty ?? ""
            case .cashBook, .expenseBook:
                balanceKey = line.accountId
            }

            let previousBalance = runningBalances[balanceKey, default: 0]
            let newBalance = isDebitNormal
                ? previousBalance + line.debit - line.credit
                : previousBalance + line.credit - line.debit
            runningBalances[balanceKey] = newBalance

            return SubLedgerEntry(
                id: line.lineId,
                date: line.entryDate,
                accountId: line.accountId,
                accountCode: line.accountCode,
                accountName: line.accountName,
                memo: line.memo,
                debit: line.debit,
                credit: line.credit,
                runningBalance: newBalance,
                counterAccountId: line.counterAccountId,
                counterparty: line.counterparty,
                taxCategory: line.taxCategory
            )
        }
    }

    func monthlySummaryRows(year: Int) -> [MonthlySummaryRow] {
        let start = startOfYear(year)
        let end = endOfYear(year)
        let journalEntries = fetchJournalEntries()
        let journalLines = fetchJournalLines()
        let postedEntryIds = Set(journalEntries.filter(\.isPosted).map(\.id))
        let entryMap = Dictionary(uniqueKeysWithValues: journalEntries.map { ($0.id, $0) })
        let linesByEntry = Dictionary(grouping: journalLines) { $0.entryId }
        let calendar = Calendar.current

        var monthlyTotals: [String: [(debit: Int, credit: Int)]] = [:]
        var lineContexts: [JournalLineContext] = []

        for journalLine in journalLines {
            guard postedEntryIds.contains(journalLine.entryId),
                  let entry = entryMap[journalLine.entryId],
                  entry.date >= start,
                  entry.date <= end
            else {
                continue
            }

            let month = calendar.component(.month, from: entry.date)
            let siblings = linesByEntry[entry.id]?.filter { $0.id != journalLine.id } ?? []
            lineContexts.append(
                JournalLineContext(
                    accountId: journalLine.accountId,
                    debit: journalLine.debit,
                    credit: journalLine.credit,
                    month: month,
                    counterAccountIds: siblings.map(\.accountId)
                )
            )

            let index = month - 1
            guard (0..<12).contains(index) else { continue }
            if monthlyTotals[journalLine.accountId] == nil {
                monthlyTotals[journalLine.accountId] = Array(repeating: (0, 0), count: 12)
            }
            monthlyTotals[journalLine.accountId]?[index].debit += journalLine.debit
            monthlyTotals[journalLine.accountId]?[index].credit += journalLine.credit
        }

        var rows: [MonthlySummaryRow] = []
        let salesLines = lineContexts.filter { $0.accountId == AccountingConstants.salesAccountId }
        let cashSales = aggregateMonthly(salesLines, counter: AccountingConstants.cashAccountId, useCredit: true)
        let creditSales = aggregateMonthly(salesLines, counter: AccountingConstants.accountsReceivableAccountId, useCredit: true)
        let otherSalesLines = salesLines.filter {
            !$0.counterAccountIds.contains(AccountingConstants.cashAccountId)
                && !$0.counterAccountIds.contains(AccountingConstants.accountsReceivableAccountId)
        }
        let otherSales = monthlySum(otherSalesLines, useCredit: true)
        let totalSales = addMonthlyArrays(cashSales, addMonthlyArrays(creditSales, otherSales))

        rows.append(makeMonthlySummaryRow(id: "sales-cash", label: "  現金売上", amounts: cashSales))
        rows.append(makeMonthlySummaryRow(id: "sales-credit", label: "  掛売上", amounts: creditSales))
        if otherSales.contains(where: { $0 > 0 }) {
            rows.append(makeMonthlySummaryRow(id: "sales-other", label: "  その他売上", amounts: otherSales))
        }
        rows.append(makeMonthlySummaryRow(id: "sales-total", label: "売上（収入）金額 計", amounts: totalSales, isSubtotal: true))

        let otherIncome = extractCredit(monthlyTotals[AccountingConstants.otherIncomeAccountId])
        rows.append(makeMonthlySummaryRow(id: "other-income", label: "雑収入", amounts: otherIncome))

        let purchaseLines = lineContexts.filter { $0.accountId == AccountingConstants.purchasesAccountId }
        let cashPurchases = aggregateMonthly(purchaseLines, counter: AccountingConstants.cashAccountId, useCredit: false)
        let creditPurchases = aggregateMonthly(purchaseLines, counter: AccountingConstants.accountsPayableAccountId, useCredit: false)
        let totalPurchases = addMonthlyArrays(cashPurchases, creditPurchases)

        rows.append(makeMonthlySummaryRow(id: "purchases-cash", label: "  現金仕入", amounts: cashPurchases))
        rows.append(makeMonthlySummaryRow(id: "purchases-credit", label: "  掛仕入", amounts: creditPurchases))
        rows.append(makeMonthlySummaryRow(id: "purchases-total", label: "仕入金額 計", amounts: totalPurchases, isSubtotal: true))

        let skippedAccountIds: Set<String> = [
            AccountingConstants.purchasesAccountId,
            AccountingConstants.openingInventoryAccountId,
            AccountingConstants.closingInventoryAccountId,
            AccountingConstants.cogsAccountId,
        ]
        let expenseAccounts = fetchAccounts()
            .filter { $0.isActive && $0.accountType == .expense && !skippedAccountIds.contains($0.id) }
            .sorted { $0.displayOrder < $1.displayOrder }

        var expenseTotal = Array(repeating: 0, count: 12)
        for account in expenseAccounts {
            let amounts = extractDebit(monthlyTotals[account.id])
            if amounts.contains(where: { $0 > 0 }) {
                rows.append(makeMonthlySummaryRow(id: "expense-\(account.id)", label: "  \(account.name)", amounts: amounts))
                expenseTotal = addMonthlyArrays(expenseTotal, amounts)
            }
        }
        rows.append(makeMonthlySummaryRow(id: "expense-total", label: "経費 計", amounts: expenseTotal, isSubtotal: true))
        return rows
    }

    func calculatePriorAccumulatedDepreciation(asset: PPFixedAsset, beforeYear: Int) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
        var accumulated = 0

        for year in acquisitionYear..<beforeYear {
            guard let calc = DepreciationEngine.calculate(
                asset: asset,
                fiscalYear: year,
                priorAccumulatedDepreciation: accumulated
            ) else {
                continue
            }
            accumulated = calc.accumulatedDepreciation
        }
        return accumulated
    }

    func previewDepreciationSchedule(asset: PPFixedAsset) -> [DepreciationCalculation] {
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
        let currentYear = calendar.component(.year, from: Date())
        let endYear = acquisitionYear + asset.usefulLifeYears + 1

        var schedule: [DepreciationCalculation] = []
        var accumulated = 0
        for year in acquisitionYear...max(currentYear, endYear) {
            guard let calc = DepreciationEngine.calculate(
                asset: asset,
                fiscalYear: year,
                priorAccumulatedDepreciation: accumulated
            ) else {
                continue
            }
            schedule.append(calc)
            accumulated = calc.accumulatedDepreciation
        }
        return schedule
    }

    func yearLockState(for year: Int) -> YearLockState {
        WorkflowPersistenceSupport.yearLockState(modelContext: modelContext, year: year)
    }

    func isYearLocked(_ year: Int) -> Bool {
        WorkflowPersistenceSupport.isYearLocked(modelContext: modelContext, year: year)
    }

    private func projectedLegacyEntryType(for entry: CanonicalJournalEntry) -> JournalEntryType {
        switch entry.entryType {
        case .opening:
            return .opening
        case .closing:
            return .closing
        case .normal, .depreciation, .inventoryAdjustment, .recurring, .taxAdjustment, .reversal:
            return .auto
        }
    }

    private func subLedgerAccountIds(for type: SubLedgerType, accounts: [PPAccount]) -> [String] {
        switch type {
        case .cashBook:
            return [AccountingConstants.cashAccountId]
        case .accountsReceivableBook:
            return [AccountingConstants.accountsReceivableAccountId]
        case .accountsPayableBook:
            return [AccountingConstants.accountsPayableAccountId]
        case .expenseBook:
            return accounts
                .filter {
                    $0.isActive
                        && $0.accountType == .expense
                        && !expenseBookExcludedAccountIds.contains($0.id)
                }
                .map(\.id)
        }
    }

    private var expenseBookExcludedAccountIds: Set<String> {
        [
            AccountingConstants.purchasesAccountId,
            AccountingConstants.openingInventoryAccountId,
            AccountingConstants.cogsAccountId,
        ]
    }

    private func fetch<T>(_ descriptor: FetchDescriptor<T>) -> [T] where T: PersistentModel {
        (try? modelContext.fetch(descriptor)) ?? []
    }
}

@MainActor
struct AccountingHomeQueryUseCase {
    private let support: AccountingReadSupport

    init(modelContext: ModelContext) {
        self.support = AccountingReadSupport(modelContext: modelContext)
    }

    func snapshot() -> AccountingHomeSnapshot {
        let entries = support.fetchJournalEntries()
        let lines = support.fetchJournalLines()
        let suspenseLines = lines.filter { $0.accountId == AccountingConstants.suspenseAccountId }

        return AccountingHomeSnapshot(
            unpostedJournalCount: entries.filter { !$0.isPosted }.count,
            suspenseBalance: suspenseLines.reduce(0) { $0 + $1.debit } - suspenseLines.reduce(0) { $0 + $1.credit },
            totalAccounts: support.fetchAccounts().filter(\.isActive).count,
            totalJournalEntries: entries.count,
            isBootstrapped: support.fetchBusinessProfile() != nil
        )
    }
}

@MainActor
struct AccountingReportQueryUseCase {
    private let support: AccountingReadSupport

    init(modelContext: ModelContext) {
        self.support = AccountingReadSupport(modelContext: modelContext)
    }

    func reportBundle(fiscalYear: Int) -> AccountingReportBundle {
        let projected = support.projectedCanonicalJournals(fiscalYear: fiscalYear)
        let accounts = support.fetchAccounts()
        let startMonth = FiscalYearSettings.startMonth

        return AccountingReportBundle(
            trialBalance: AccountingReportService.generateTrialBalance(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            ),
            profitLoss: AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            ),
            balanceSheet: AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            )
        )
    }
}

@MainActor
struct JournalReadQueryUseCase {
    private let support: AccountingReadSupport

    init(modelContext: ModelContext) {
        self.support = AccountingReadSupport(modelContext: modelContext)
    }

    func listSnapshot(fiscalYear: Int? = nil) -> JournalListSnapshot {
        let projected = support.projectedCanonicalJournals(fiscalYear: fiscalYear)
        return JournalListSnapshot(
            businessId: projected.businessId,
            projects: support.fetchProjects(),
            entries: projected.entries,
            lines: projected.lines,
            canCreateManualJournals: !FeatureFlags.useCanonicalPosting
        )
    }

    func detailSnapshot(entryId: UUID, fiscalYear: Int? = nil) -> JournalDetailSnapshot {
        let projected = support.projectedCanonicalJournals(fiscalYear: fiscalYear)
        let lines = projected.lines
            .filter { $0.entryId == entryId }
            .sorted { $0.displayOrder < $1.displayOrder }
        let accountNamesById = Dictionary(uniqueKeysWithValues: support.fetchAccounts().map { ($0.id, $0.name) })
        return JournalDetailSnapshot(lines: lines, accountNamesById: accountNamesById)
    }

    func supplementalMatchIds(
        criteria: JournalSearchCriteria,
        snapshot: JournalListSnapshot
    ) -> Set<UUID> {
        let supplementalEntries = snapshot.entries.filter { entry in
            entry.sourceKey.hasPrefix("manual:")
                || entry.sourceKey.hasPrefix("opening:")
                || entry.sourceKey.hasPrefix("closing:")
        }

        return Set(supplementalEntries.compactMap { entry in
            if let dateRange = criteria.dateRange, !dateRange.contains(entry.date) {
                return nil
            }

            let lines = snapshot.lines.filter { $0.entryId == entry.id }
            let totalAmount = Decimal(lines.reduce(0) { $0 + max($1.debit, $1.credit) })
            if let amountRange = criteria.amountRange, !amountRange.contains(totalAmount) {
                return nil
            }

            if criteria.counterpartyText != nil
                || criteria.registrationNumber != nil
                || criteria.projectId != nil
                || criteria.fileHash != nil {
                return nil
            }

            if let textQuery = SearchIndexNormalizer.normalizeOptionalText(criteria.textQuery) {
                let searchText = SearchIndexNormalizer.normalizeText(
                    ([entry.memo] + lines.map(\.memo)).joined(separator: " ")
                )
                if !searchText.contains(textQuery) {
                    return nil
                }
            }

            return entry.id
        })
    }
}

@MainActor
struct LedgerQueryUseCase {
    private let support: AccountingReadSupport

    init(modelContext: ModelContext) {
        self.support = AccountingReadSupport(modelContext: modelContext)
    }

    func activeAccounts() -> [PPAccount] {
        support.fetchAccounts()
            .filter(\.isActive)
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    func accountBalance(accountId: String, upTo date: Date? = nil) -> GeneralLedgerBalance {
        support.accountBalance(accountId: accountId, upTo: date)
    }

    func snapshot(
        accountId: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> GeneralLedgerSnapshot {
        GeneralLedgerSnapshot(
            account: activeAccounts().first { $0.id == accountId },
            entries: support.ledgerEntries(accountId: accountId, startDate: startDate, endDate: endDate),
            balance: support.accountBalance(accountId: accountId, upTo: endDate)
        )
    }
}

@MainActor
struct SubLedgerQueryUseCase {
    private let support: AccountingReadSupport

    init(modelContext: ModelContext) {
        self.support = AccountingReadSupport(modelContext: modelContext)
    }

    func snapshot(
        type: SubLedgerType,
        year: Int,
        accountFilter: String? = nil,
        counterpartyFilter: String? = nil
    ) -> SubLedgerSnapshot {
        let startDate = startOfYear(year)
        let endDate = endOfYear(year)
        let allEntries = support.subLedgerEntries(
            type: type,
            startDate: startDate,
            endDate: endDate
        )
        let filteredEntries = support.subLedgerEntries(
            type: type,
            startDate: startDate,
            endDate: endDate,
            accountFilter: accountFilter,
            counterpartyFilter: counterpartyFilter
        )
        let expenseAccounts = support.fetchAccounts()
            .filter { $0.isActive && $0.accountType == .expense }
            .sorted { $0.displayOrder < $1.displayOrder }

        return SubLedgerSnapshot(
            entries: filteredEntries,
            summary: SubLedgerSummary(
                count: allEntries.count,
                debitTotal: allEntries.reduce(0) { $0 + $1.debit },
                creditTotal: allEntries.reduce(0) { $0 + $1.credit },
                periodStart: startDate,
                periodEnd: endDate
            ),
            expenseAccounts: expenseAccounts
        )
    }
}

@MainActor
struct ClosingQueryUseCase {
    private let support: AccountingReadSupport

    init(modelContext: ModelContext) {
        self.support = AccountingReadSupport(modelContext: modelContext)
    }

    func snapshot(year: Int) -> ClosingEntrySnapshot {
        let businessId = support.fetchBusinessProfile()?.id
        let closingEntry = businessId.flatMap { businessId in
            support.fetchCanonicalJournalEntries(businessId: businessId, taxYear: year)
                .first { $0.entryType == .closing }
        }
        let accountsById = businessId.map { businessId in
            Dictionary(uniqueKeysWithValues: support.fetchCanonicalAccounts(businessId: businessId).map { ($0.id, $0) })
        } ?? [:]
        let displayLines = closingEntry?.lines
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { line in
                ClosingEntryDisplayLine(
                    id: line.id,
                    accountName: accountsById[line.accountId]?.name ?? line.accountId.uuidString,
                    debit: NSDecimalNumber(decimal: line.debitAmount).intValue,
                    credit: NSDecimalNumber(decimal: line.creditAmount).intValue
                )
            } ?? []

        return ClosingEntrySnapshot(
            businessId: businessId,
            closingEntry: closingEntry,
            displayLines: displayLines,
            yearState: support.yearLockState(for: year)
        )
    }
}

@MainActor
struct FixedAssetQueryUseCase {
    private let support: AccountingReadSupport
    private let fixedAssetRepository: any FixedAssetRepository

    init(
        modelContext: ModelContext,
        fixedAssetRepository: (any FixedAssetRepository)? = nil
    ) {
        self.support = AccountingReadSupport(modelContext: modelContext)
        self.fixedAssetRepository = fixedAssetRepository ?? SwiftDataFixedAssetRepository(modelContext: modelContext)
    }

    func listSnapshot(currentYear: Int) -> FixedAssetListSnapshot {
        let assets = (try? fixedAssetRepository.allFixedAssets()) ?? []
        let bookValueByAssetId = Dictionary(uniqueKeysWithValues: assets.map {
            ($0.id, $0.acquisitionCost - support.calculatePriorAccumulatedDepreciation(asset: $0, beforeYear: currentYear + 1))
        })
        return FixedAssetListSnapshot(assets: assets, bookValueByAssetId: bookValueByAssetId)
    }

    func detailSnapshot(assetId: UUID, currentYear: Int) -> FixedAssetDetailSnapshot {
        let asset = try? fixedAssetRepository.fixedAsset(id: assetId)
        let journalEntries = support.fetchJournalEntries()
        let isAssetFiscalYearLocked = asset.map {
            support.isYearLocked(fiscalYear(for: $0.acquisitionDate, startMonth: FiscalYearSettings.startMonth))
        } ?? false
        let relatedEntries: [PPJournalEntry]
        if let asset {
            let calendar = Calendar(identifier: .gregorian)
            let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
            relatedEntries = (acquisitionYear...currentYear).compactMap { year in
                let sourceKey = PPFixedAsset.depreciationSourceKey(assetId: assetId, year: year)
                return journalEntries.first { $0.sourceKey == sourceKey }
            }
        } else {
            relatedEntries = []
        }

        return FixedAssetDetailSnapshot(
            asset: asset ?? nil,
            isAssetFiscalYearLocked: isAssetFiscalYearLocked,
            isCurrentYearLocked: support.isYearLocked(currentYear),
            schedule: asset.map { support.previewDepreciationSchedule(asset: $0) } ?? [],
            relatedEntries: relatedEntries
        )
    }
}

@MainActor
struct InventoryQueryUseCase {
    private let support: AccountingReadSupport
    private let inventoryRepository: any InventoryRepository

    init(
        modelContext: ModelContext,
        inventoryRepository: (any InventoryRepository)? = nil
    ) {
        self.support = AccountingReadSupport(modelContext: modelContext)
        self.inventoryRepository = inventoryRepository ?? SwiftDataInventoryRepository(modelContext: modelContext)
    }

    func snapshot(fiscalYear: Int) -> InventoryYearSnapshot {
        InventoryYearSnapshot(
            record: (try? inventoryRepository.inventoryRecord(fiscalYear: fiscalYear))
                ?? support.fetchInventoryRecord(fiscalYear: fiscalYear)
        )
    }
}

@MainActor
struct ClassificationQueryUseCase {
    private let support: AccountingReadSupport
    private let userRuleRepository: any UserRuleRepository

    init(
        modelContext: ModelContext,
        userRuleRepository: (any UserRuleRepository)? = nil
    ) {
        self.support = AccountingReadSupport(modelContext: modelContext)
        self.userRuleRepository = userRuleRepository ?? SwiftDataUserRuleRepository(modelContext: modelContext)
    }

    func snapshot() -> ClassificationSnapshot {
        let userRules = (try? userRuleRepository.allRules()) ?? []
        let results = ClassificationEngine.classifyBatch(
            transactions: support.fetchTransactions(),
            categories: support.fetchCategories(),
            accounts: support.fetchAccounts(),
            userRules: userRules
        ).map { ClassificationResultItem(transaction: $0.transaction, result: $0.result) }
        return ClassificationSnapshot(results: results, userRules: userRules)
    }
}

@MainActor
struct EtaxExportContextQueryUseCase {
    private let support: AccountingReadSupport

    init(modelContext: ModelContext) {
        self.support = AccountingReadSupport(modelContext: modelContext)
    }

    func context(fiscalYear: Int) -> EtaxExportContext {
        let businessId = support.fetchBusinessProfile()?.id
        let fallbackTaxYearProfile = businessId.flatMap {
            support.fetchTaxYearProfile(businessId: $0, taxYear: fiscalYear)
        }
        return EtaxExportContext(
            businessId: businessId,
            fallbackTaxYearProfile: fallbackTaxYearProfile
        )
    }
}

private struct JournalLineContext {
    let accountId: String
    let debit: Int
    let credit: Int
    let month: Int
    let counterAccountIds: [String]
}

private func makeMonthlySummaryRow(
    id: String,
    label: String,
    amounts: [Int],
    isSubtotal: Bool = false
) -> MonthlySummaryRow {
    MonthlySummaryRow(
        id: id,
        label: label,
        isSubtotal: isSubtotal,
        amounts: amounts,
        total: amounts.reduce(0, +)
    )
}

private func extractCredit(_ totals: [(debit: Int, credit: Int)]?) -> [Int] {
    totals?.map(\.credit) ?? Array(repeating: 0, count: 12)
}

private func extractDebit(_ totals: [(debit: Int, credit: Int)]?) -> [Int] {
    totals?.map(\.debit) ?? Array(repeating: 0, count: 12)
}

private func aggregateMonthly(
    _ lines: [JournalLineContext],
    counter: String,
    useCredit: Bool
) -> [Int] {
    monthlySum(lines.filter { $0.counterAccountIds.contains(counter) }, useCredit: useCredit)
}

private func monthlySum(_ lines: [JournalLineContext], useCredit: Bool) -> [Int] {
    var result = Array(repeating: 0, count: 12)
    for line in lines where (1...12).contains(line.month) {
        result[line.month - 1] += useCredit ? line.credit : line.debit
    }
    return result
}

private func addMonthlyArrays(_ lhs: [Int], _ rhs: [Int]) -> [Int] {
    (0..<12).map { index in
        (lhs.indices.contains(index) ? lhs[index] : 0)
            + (rhs.indices.contains(index) ? rhs[index] : 0)
    }
}
