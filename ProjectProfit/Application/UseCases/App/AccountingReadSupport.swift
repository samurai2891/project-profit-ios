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

struct CanonicalReadContext {
    let businessId: UUID?
    let accounts: [CanonicalAccount]
    let journals: [CanonicalJournalEntry]
    let counterpartiesById: [UUID: String]
    let legacyAccountsById: [String: PPAccount]
    let canonicalAccountsById: [UUID: CanonicalAccount]
    let canonicalAccountsByLegacyId: [String: CanonicalAccount]

    func legacyAccountId(for canonicalAccountId: UUID) -> String {
        canonicalAccountsById[canonicalAccountId]?.legacyAccountId ?? canonicalAccountId.uuidString
    }

    func legacyAccount(for canonicalAccountId: UUID) -> PPAccount? {
        guard let legacyAccountId = canonicalAccountsById[canonicalAccountId]?.legacyAccountId else {
            return nil
        }
        return legacyAccountsById[legacyAccountId]
    }
}

struct ProjectedJournalSnapshot {
    let businessId: UUID?
    let entries: [PPJournalEntry]
    let lines: [PPJournalLine]
}

struct JournalListItem: Identifiable {
    let id: UUID
    let sourceKey: String
    let date: Date
    let entryType: JournalEntryType
    let memo: String
    let isPosted: Bool
    let createdAt: Date
    let updatedAt: Date
    let debitTotal: Int
    let creditTotal: Int
    let searchableText: String

    var isSupplemental: Bool {
        sourceKey.hasPrefix("manual:")
            || sourceKey.hasPrefix("opening:")
            || sourceKey.hasPrefix("closing:")
    }
}

struct JournalLineItem: Identifiable {
    let id: UUID
    let entryId: UUID
    let accountId: String
    let accountName: String
    let debit: Int
    let credit: Int
    let memo: String
    let displayOrder: Int
}

struct JournalListSnapshot {
    let businessId: UUID?
    let projects: [PPProject]
    let entries: [JournalListItem]
    let canCreateManualJournals: Bool
}

struct JournalDetailSnapshot {
    let entry: JournalListItem?
    let lines: [JournalLineItem]
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

struct CanonicalClassificationSuggestion {
    let result: ClassificationEngine.ClassificationResult
    let resolvedCategoryId: String
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

    func fetchUserRules() -> [PPUserRule] {
        fetch(
            FetchDescriptor<PPUserRule>(
                sortBy: [
                    SortDescriptor(\.priority, order: .reverse),
                    SortDescriptor(\.updatedAt, order: .reverse),
                ]
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

    func classificationSuggestion(
        memo: String,
        transactionType: TransactionType,
        categoryId: String
    ) -> CanonicalClassificationSuggestion? {
        guard transactionType != .transfer else {
            return nil
        }

        let transaction = PPTransaction(
            type: transactionType,
            amount: 0,
            date: Date(),
            categoryId: categoryId,
            memo: normalizedClassificationText(memo)
        )
        let result = ClassificationEngine.classify(
            transaction: transaction,
            categories: fetchCategories(),
            accounts: fetchAccounts(),
            userRules: fetchUserRules()
        )
        return CanonicalClassificationSuggestion(
            result: result,
            resolvedCategoryId: preferredCategoryId(
                for: result.taxLine,
                transactionType: transactionType,
                fallbackCategoryId: categoryId
            )
        )
    }

    func preferredCategoryId(
        for taxLine: TaxLine,
        transactionType: TransactionType,
        fallbackCategoryId: String
    ) -> String {
        guard transactionType != .transfer else {
            return fallbackCategoryId
        }
        let expectedCategoryType: CategoryType = transactionType == .income ? .income : .expense

        let categories = fetchCategories()
            .filter { $0.archivedAt == nil && $0.type == expectedCategoryType }
        let accountsById = Dictionary(uniqueKeysWithValues: fetchAccounts().map { ($0.id, $0) })

        if let currentCategory = categories.first(where: { $0.id == fallbackCategoryId }),
           let linkedAccountId = currentCategory.linkedAccountId,
           accountsById[linkedAccountId]?.subtype == taxLine.accountSubtype {
            return currentCategory.id
        }

        if let matchedCategory = categories.first(where: { category in
            guard let linkedAccountId = category.linkedAccountId else {
                return false
            }
            return accountsById[linkedAccountId]?.subtype == taxLine.accountSubtype
        }) {
            return matchedCategory.id
        }

        return fallbackCategoryId
    }

    func resolvedTaxLine(forApprovedCandidate candidate: PostingCandidate) -> TaxLine? {
        let canonicalAccountsById = Dictionary(
            uniqueKeysWithValues: fetchCanonicalAccounts(businessId: candidate.businessId).map { ($0.id, $0) }
        )
        let legacyAccountsById = Dictionary(uniqueKeysWithValues: fetchAccounts().map { ($0.id, $0) })

        for line in candidate.proposedLines {
            if let resolved = resolvedTaxLine(
                for: line,
                canonicalAccountsById: canonicalAccountsById,
                legacyAccountsById: legacyAccountsById
            ) {
                return resolved
            }
        }

        return nil
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

    func fetchCanonicalCounterparties() -> [Counterparty] {
        fetch(FetchDescriptor<CounterpartyEntity>()).map(CounterpartyEntityMapper.toDomain)
    }

    func canonicalReadContext(fiscalYear requestedFiscalYear: Int? = nil) -> CanonicalReadContext {
        let legacyAccounts = fetchAccounts()
        guard let businessId = fetchBusinessProfile()?.id else {
            return CanonicalReadContext(
                businessId: nil,
                accounts: [],
                journals: [],
                counterpartiesById: [:],
                legacyAccountsById: Dictionary(uniqueKeysWithValues: legacyAccounts.map { ($0.id, $0) }),
                canonicalAccountsById: [:],
                canonicalAccountsByLegacyId: [:]
            )
        }

        let accounts = fetchCanonicalAccounts(businessId: businessId)
        return CanonicalReadContext(
            businessId: businessId,
            accounts: accounts,
            journals: fetchCanonicalJournalEntries(businessId: businessId, taxYear: requestedFiscalYear),
            counterpartiesById: Dictionary(
                uniqueKeysWithValues: fetchCanonicalCounterparties().map { ($0.id, $0.displayName) }
            ),
            legacyAccountsById: Dictionary(uniqueKeysWithValues: legacyAccounts.map { ($0.id, $0) }),
            canonicalAccountsById: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) }),
            canonicalAccountsByLegacyId: Dictionary(
                uniqueKeysWithValues: accounts.compactMap { account in
                    guard let legacyAccountId = account.legacyAccountId else {
                        return nil
                    }
                    return (legacyAccountId, account)
                }
            )
        )
    }

    func projectedCanonicalJournals(fiscalYear requestedFiscalYear: Int? = nil) -> ProjectedJournalSnapshot {
        ProjectedJournalReadModelQuery(support: self).snapshot(fiscalYear: requestedFiscalYear)
    }

    func accountBalance(accountId: String, upTo date: Date? = nil) -> GeneralLedgerBalance {
        AccountingLedgerReadModelQuery(support: self).accountBalance(accountId: accountId, upTo: date)
    }

    func ledgerEntries(
        accountId: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [AccountingLedgerEntry] {
        AccountingLedgerReadModelQuery(support: self).entries(
            accountId: accountId,
            startDate: startDate,
            endDate: endDate
        )
    }

    func subLedgerEntries(
        type: SubLedgerType,
        startDate: Date? = nil,
        endDate: Date? = nil,
        accountFilter: String? = nil,
        counterpartyFilter: String? = nil
    ) -> [SubLedgerEntry] {
        SubLedgerReadModelQuery(support: self).entries(
            type: type,
            startDate: startDate,
            endDate: endDate,
            accountFilter: accountFilter,
            counterpartyFilter: counterpartyFilter
        )
    }

    func monthlySummaryRows(year: Int) -> [MonthlySummaryRow] {
        MonthlySummaryRowReadModelQuery(support: self).rows(year: year)
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

    private func fetch<T>(_ descriptor: FetchDescriptor<T>) -> [T] where T: PersistentModel {
        (try? modelContext.fetch(descriptor)) ?? []
    }
}

private extension AccountingReadSupport {
    func resolvedTaxLine(
        for line: PostingCandidateLine,
        canonicalAccountsById: [UUID: CanonicalAccount],
        legacyAccountsById: [String: PPAccount]
    ) -> TaxLine? {
        for accountId in [line.debitAccountId, line.creditAccountId].compactMap({ $0 }) {
            guard let canonicalAccount = canonicalAccountsById[accountId],
                  let legacyAccountId = canonicalAccount.legacyAccountId,
                  let subtype = legacyAccountsById[legacyAccountId]?.subtype,
                  let taxLine = TaxLine.allCases.first(where: { $0.accountSubtype == subtype }) else {
                continue
            }
            return taxLine
        }
        return nil
    }

    func normalizedClassificationText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let context = support.canonicalReadContext(fiscalYear: fiscalYear)
        let trialBalance = AccountingReportService.generateTrialBalance(
            fiscalYear: fiscalYear,
            accounts: context.accounts,
            journals: context.journals,
            startMonth: FiscalYearSettings.startMonth
        )
        let profitLoss = AccountingReportService.generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: context.accounts,
            journals: context.journals,
            startMonth: FiscalYearSettings.startMonth
        )
        let balanceSheet = AccountingReportService.generateBalanceSheet(
            fiscalYear: fiscalYear,
            accounts: context.accounts,
            journals: context.journals,
            startMonth: FiscalYearSettings.startMonth
        )

        return AccountingReportBundle(
            trialBalance: LegacyAccountingReportAdapter.trialBalance(trialBalance),
            profitLoss: LegacyAccountingReportAdapter.profitLoss(profitLoss),
            balanceSheet: LegacyAccountingReportAdapter.balanceSheet(balanceSheet)
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
        let context = support.canonicalReadContext(fiscalYear: fiscalYear)
        let journalsById = Dictionary(uniqueKeysWithValues: context.journals.map { ($0.id, $0) })
        let entries = CanonicalBookService.generateJournalBook(
            journals: context.journals,
            accounts: context.accounts,
            counterparties: context.counterpartiesById
        )
        return JournalListSnapshot(
            businessId: context.businessId,
            projects: support.fetchProjects(),
            entries: entries.compactMap { entry in
                guard let journal = journalsById[entry.id] else {
                    return nil
                }
                return listItem(journal: journal, bookEntry: entry)
            },
            canCreateManualJournals: !FeatureFlags.useCanonicalPosting
        )
    }

    func detailSnapshot(entryId: UUID, fiscalYear: Int? = nil) -> JournalDetailSnapshot {
        let context = support.canonicalReadContext(fiscalYear: fiscalYear)
        let journal = context.journals.first { $0.id == entryId }
        let bookEntry = CanonicalBookService.generateJournalBook(
            journals: context.journals,
            accounts: context.accounts,
            counterparties: context.counterpartiesById
        ).first { $0.id == entryId }
        let entry = journal.flatMap { journal in
            bookEntry.map { listItem(journal: journal, bookEntry: $0) }
        }
        return JournalDetailSnapshot(
            entry: entry,
            lines: (bookEntry?.lines ?? []).enumerated().map { index, line in
                JournalLineItem(
                    id: line.id,
                    entryId: entryId,
                    accountId: context.legacyAccountId(for: line.accountId),
                    accountName: line.accountName,
                    debit: decimalInt(line.debitAmount),
                    credit: decimalInt(line.creditAmount),
                    memo: "",
                    displayOrder: index
                )
            }
        )
    }

    func supplementalMatchIds(
        criteria: JournalSearchCriteria,
        snapshot: JournalListSnapshot
    ) -> Set<UUID> {
        let supplementalEntries = snapshot.entries.filter { entry in
            entry.isSupplemental
        }

        return Set(supplementalEntries.compactMap { entry in
            if let dateRange = criteria.dateRange, !dateRange.contains(entry.date) {
                return nil
            }

            let totalAmount = Decimal(max(entry.debitTotal, entry.creditTotal))
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
                if !entry.searchableText.contains(textQuery) {
                    return nil
                }
            }

            return entry.id
        })
    }

    private func listItem(
        journal: CanonicalJournalEntry,
        bookEntry: CanonicalJournalBookEntry
    ) -> JournalListItem {
        let searchableText = SearchIndexNormalizer.normalizeText(
            ([journal.description] + bookEntry.lines.flatMap { line in
                [line.accountName, line.counterpartyName ?? ""]
            }).joined(separator: " ")
        )
        return JournalListItem(
            id: journal.id,
            sourceKey: journalSourceKey(journal),
            date: journal.journalDate,
            entryType: legacyEntryType(for: journal.entryType),
            memo: journal.description,
            isPosted: journal.approvedAt != nil,
            createdAt: journal.createdAt,
            updatedAt: journal.updatedAt,
            debitTotal: bookEntry.lines.reduce(0) { $0 + decimalInt($1.debitAmount) },
            creditTotal: bookEntry.lines.reduce(0) { $0 + decimalInt($1.creditAmount) },
            searchableText: searchableText
        )
    }
}

@MainActor
struct LedgerQueryUseCase {
    private let support: AccountingReadSupport
    private let readModelQuery: AccountingLedgerReadModelQuery

    init(modelContext: ModelContext) {
        let support = AccountingReadSupport(modelContext: modelContext)
        self.support = support
        self.readModelQuery = AccountingLedgerReadModelQuery(support: support)
    }

    func activeAccounts() -> [PPAccount] {
        support.fetchAccounts()
            .filter(\.isActive)
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    func accountBalance(accountId: String, upTo date: Date? = nil) -> GeneralLedgerBalance {
        readModelQuery.accountBalance(accountId: accountId, upTo: date)
    }

    func snapshot(
        accountId: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> GeneralLedgerSnapshot {
        GeneralLedgerSnapshot(
            account: activeAccounts().first { $0.id == accountId },
            entries: readModelQuery.entries(accountId: accountId, startDate: startDate, endDate: endDate),
            balance: readModelQuery.accountBalance(accountId: accountId, upTo: endDate)
        )
    }
}

@MainActor
struct SubLedgerQueryUseCase {
    private let support: AccountingReadSupport
    private let readModelQuery: SubLedgerReadModelQuery

    init(modelContext: ModelContext) {
        let support = AccountingReadSupport(modelContext: modelContext)
        self.support = support
        self.readModelQuery = SubLedgerReadModelQuery(support: support)
    }

    func snapshot(
        type: SubLedgerType,
        year: Int,
        accountFilter: String? = nil,
        counterpartyFilter: String? = nil
    ) -> SubLedgerSnapshot {
        let startDate = startOfYear(year)
        let endDate = endOfYear(year)
        let allEntries = readModelQuery.entries(
            type: type,
            startDate: startDate,
            endDate: endDate
        )
        let filteredEntries = readModelQuery.entries(
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

private enum LegacyAccountingReportAdapter {
    static func trialBalance(_ report: CanonicalTrialBalanceReport) -> TrialBalanceReport {
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

    static func profitLoss(_ report: CanonicalProfitLossReport) -> ProfitLossReport {
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

    static func balanceSheet(_ report: CanonicalBalanceSheetReport) -> BalanceSheetReport {
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
}

private func legacyAccountType(for canonicalType: CanonicalAccountType) -> AccountType {
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

private func legacyEntryType(for entryType: CanonicalJournalEntryType) -> JournalEntryType {
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

private func journalSourceKey(_ journal: CanonicalJournalEntry) -> String {
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

private func decimalInt(_ value: Decimal) -> Int {
    NSDecimalNumber(decimal: value).intValue
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
