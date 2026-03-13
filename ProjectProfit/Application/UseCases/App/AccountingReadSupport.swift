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
    private let projectedJournalQuery: ProjectedJournalReadModelQuery

    init(modelContext: ModelContext) {
        let support = AccountingReadSupport(modelContext: modelContext)
        self.support = support
        self.projectedJournalQuery = ProjectedJournalReadModelQuery(support: support)
    }

    func reportBundle(fiscalYear: Int) -> AccountingReportBundle {
        let projected = projectedJournalQuery.snapshot(fiscalYear: fiscalYear)
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
    private let projectedJournalQuery: ProjectedJournalReadModelQuery

    init(modelContext: ModelContext) {
        let support = AccountingReadSupport(modelContext: modelContext)
        self.support = support
        self.projectedJournalQuery = ProjectedJournalReadModelQuery(support: support)
    }

    func listSnapshot(fiscalYear: Int? = nil) -> JournalListSnapshot {
        let projected = projectedJournalQuery.snapshot(fiscalYear: fiscalYear)
        let accountsById = Dictionary(uniqueKeysWithValues: support.fetchAccounts().map { ($0.id, $0.name) })
        let linesByEntryId = Dictionary(grouping: projected.lines, by: \.entryId)
        return JournalListSnapshot(
            businessId: projected.businessId,
            projects: support.fetchProjects(),
            entries: projected.entries.map { entry in
                listItem(
                    entry: entry,
                    lines: linesByEntryId[entry.id] ?? [],
                    accountNamesById: accountsById
                )
            },
            canCreateManualJournals: !FeatureFlags.useCanonicalPosting
        )
    }

    func detailSnapshot(entryId: UUID, fiscalYear: Int? = nil) -> JournalDetailSnapshot {
        let projected = projectedJournalQuery.snapshot(fiscalYear: fiscalYear)
        let accountsById = Dictionary(uniqueKeysWithValues: support.fetchAccounts().map { ($0.id, $0.name) })
        let lines = projected.lines
            .filter { $0.entryId == entryId }
            .sorted { $0.displayOrder < $1.displayOrder }
        let entry = projected.entries.first { $0.id == entryId }.map {
            listItem(
                entry: $0,
                lines: lines,
                accountNamesById: accountsById
            )
        }
        return JournalDetailSnapshot(
            entry: entry,
            lines: lines.map { line in
                JournalLineItem(
                    id: line.id,
                    entryId: line.entryId,
                    accountId: line.accountId,
                    accountName: accountsById[line.accountId] ?? line.accountId,
                    debit: line.debit,
                    credit: line.credit,
                    memo: line.memo,
                    displayOrder: line.displayOrder
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
        entry: PPJournalEntry,
        lines: [PPJournalLine],
        accountNamesById: [String: String]
    ) -> JournalListItem {
        let orderedLines = lines.sorted { $0.displayOrder < $1.displayOrder }
        let searchableText = SearchIndexNormalizer.normalizeText(
            ([entry.memo] + orderedLines.flatMap { line in
                [line.memo, accountNamesById[line.accountId] ?? line.accountId]
            }).joined(separator: " ")
        )
        return JournalListItem(
            id: entry.id,
            sourceKey: entry.sourceKey,
            date: entry.date,
            entryType: entry.entryType,
            memo: entry.memo,
            isPosted: entry.isPosted,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            debitTotal: orderedLines.reduce(0) { $0 + $1.debit },
            creditTotal: orderedLines.reduce(0) { $0 + $1.credit },
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
