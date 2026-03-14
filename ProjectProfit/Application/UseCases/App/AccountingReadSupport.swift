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
    let candidate: PostingCandidate
    let evidence: EvidenceDocument?
    let result: ClassificationEngine.ClassificationResult
    let suggestedCategoryId: String
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

struct EtaxCandidateSummary {
    let transactionType: TransactionType
    let resolvedCategoryId: String
}

struct EtaxFormBuildSnapshot {
    let fiscalYear: Int
    let startMonth: Int
    let canonicalAccounts: [CanonicalAccount]
    let canonicalAccountsById: [UUID: CanonicalAccount]
    let categoryNamesById: [String: String]
    let fixedAssets: [PPFixedAsset]
    let inventoryRecord: PPInventoryRecord?
    let businessProfile: BusinessProfile?
    let taxYearProfile: TaxYearProfile?
    let sensitivePayload: ProfileSensitivePayload?
    let canonicalProfitLoss: CanonicalProfitLossReport
    let canonicalBalanceSheet: CanonicalBalanceSheetReport
    let canonicalJournals: [CanonicalJournalEntry]
    let candidateSummariesById: [UUID: EtaxCandidateSummary]
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

    func fetchFixedAssets() -> [PPFixedAsset] {
        fetch(
            FetchDescriptor<PPFixedAsset>(
                sortBy: [
                    SortDescriptor(\.acquisitionDate, order: .reverse),
                    SortDescriptor(\.name)
                ]
            )
        )
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

    func etaxTaxLine(for canonicalAccount: CanonicalAccount) -> TaxLine? {
        TaxLine(legalReportLineId: canonicalAccount.defaultLegalReportLineId)
    }

    func etaxTaxLine(for line: JournalLine, canonicalAccountsById: [UUID: CanonicalAccount]) -> TaxLine? {
        if let taxLine = TaxLine(legalReportLineId: line.legalReportLineId) {
            return taxLine
        }
        guard let account = canonicalAccountsById[line.accountId] else {
            return nil
        }
        return etaxTaxLine(for: account)
    }

    func etaxCandidateSummaries(
        candidatesById: [UUID: PostingCandidate]
    ) -> [UUID: EtaxCandidateSummary] {
        let categories = fetchCategories()
        let activeCategories = categories.filter { $0.archivedAt == nil }
        let expenseCategories = activeCategories.filter { $0.type == .expense }
        let incomeCategories = activeCategories.filter { $0.type == .income }
        let categoriesById = Dictionary(uniqueKeysWithValues: activeCategories.map { ($0.id, $0) })
        let legacyAccountsById = Dictionary(uniqueKeysWithValues: fetchAccounts().map { ($0.id, $0) })
        let canonicalAccountsById = Dictionary(
            uniqueKeysWithValues: candidatesById.values
                .flatMap(\.proposedLines)
                .flatMap { [$0.debitAccountId, $0.creditAccountId].compactMap { $0 } }
                .compactMap { accountId in
                    fetchCanonicalAccount(accountId: accountId).map { (accountId, $0) }
                }
        )

        return candidatesById.reduce(into: [UUID: EtaxCandidateSummary]()) { result, entry in
            let candidate = entry.value
            let transactionType = resolvedEtaxTransactionType(
                candidate: candidate,
                categoriesById: categoriesById,
                legacyAccountsById: legacyAccountsById,
                canonicalAccountsById: canonicalAccountsById
            )
            let resolvedCategoryId = resolvedEtaxCategoryId(
                candidate: candidate,
                transactionType: transactionType,
                expenseCategories: expenseCategories,
                incomeCategories: incomeCategories,
                categoriesById: categoriesById,
                legacyAccountsById: legacyAccountsById,
                canonicalAccountsById: canonicalAccountsById
            )
            result[entry.key] = EtaxCandidateSummary(
                transactionType: transactionType,
                resolvedCategoryId: resolvedCategoryId
            )
        }
    }

    func classificationSuggestion(
        candidate: PostingCandidate,
        evidence: EvidenceDocument? = nil,
        fallbackCategoryId: String? = nil
    ) -> CanonicalClassificationSuggestion? {
        let transactionType = classificationTransactionType(for: candidate)
        guard transactionType != .transfer else {
            return nil
        }

        let categoryId = fallbackCategoryId ?? candidate.legacySnapshot?.categoryId ?? ""
        let result = ClassificationEngine.classify(
            candidate: candidate.updated(
                memo: normalizedClassificationText(candidate.memo ?? classificationTextFallback(evidence: evidence))
            ),
            evidence: evidence,
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

    func fetchPostingCandidates(ids: Set<UUID>) -> [UUID: PostingCandidate] {
        guard !ids.isEmpty else {
            return [:]
        }

        let descriptor = FetchDescriptor<PostingCandidateEntity>()
        return fetch(descriptor).reduce(into: [UUID: PostingCandidate]()) { result, entity in
            guard ids.contains(entity.candidateId) else {
                return
            }
            result[entity.candidateId] = PostingCandidateEntityMapper.toDomain(entity)
        }
    }

    func fetchPostingCandidates(statuses: Set<CandidateStatus>) -> [PostingCandidate] {
        guard let businessId = fetchBusinessProfile()?.id else {
            return []
        }

        let descriptor = FetchDescriptor<PostingCandidateEntity>(
            sortBy: [
                SortDescriptor(\.candidateDate, order: .reverse),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        return fetch(descriptor)
            .map(PostingCandidateEntityMapper.toDomain)
            .filter {
                $0.businessId == businessId && statuses.contains($0.status)
            }
    }

    func fetchEvidence(ids: Set<UUID>) -> [UUID: EvidenceDocument] {
        guard !ids.isEmpty else {
            return [:]
        }

        let descriptor = FetchDescriptor<EvidenceRecordEntity>(
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        return fetch(descriptor).reduce(into: [UUID: EvidenceDocument]()) { result, entity in
            guard ids.contains(entity.evidenceId) else {
                return
            }
            result[entity.evidenceId] = EvidenceRecordEntityMapper.toDomain(entity)
        }
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

    private func fetchCanonicalAccount(accountId: UUID) -> CanonicalAccount? {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(
            predicate: #Predicate { $0.accountId == accountId }
        )
        return fetch(descriptor).first.map(CanonicalAccountEntityMapper.toDomain)
    }
}

private extension AccountingReadSupport {
    func classificationTransactionType(for candidate: PostingCandidate) -> TransactionType {
        candidate.legacySnapshot?.type ?? .expense
    }

    func classificationTextFallback(evidence: EvidenceDocument?) -> String {
        normalizedClassificationText(
            evidence?.structuredFields?.counterpartyName
                ?? evidence?.ocrText
                ?? evidence?.searchTokens.first
                ?? ""
        )
    }

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

    func resolvedEtaxTransactionType(
        candidate: PostingCandidate,
        categoriesById: [String: PPCategory],
        legacyAccountsById: [String: PPAccount],
        canonicalAccountsById: [UUID: CanonicalAccount]
    ) -> TransactionType {
        if let explicit = candidate.legacySnapshot?.type {
            return explicit
        }

        for line in candidate.proposedLines {
            if let categoryId = resolvedEtaxCategoryId(
                for: line,
                categoriesById: categoriesById,
                legacyAccountsById: legacyAccountsById,
                canonicalAccountsById: canonicalAccountsById
            ) {
                return categoriesById[categoryId]?.type == .income ? .income : .expense
            }
        }

        let hasDebit = candidate.proposedLines.contains { $0.debitAccountId != nil }
        let hasCredit = candidate.proposedLines.contains { $0.creditAccountId != nil }
        if hasDebit && hasCredit {
            return .transfer
        }
        return .expense
    }

    func resolvedEtaxCategoryId(
        candidate: PostingCandidate,
        transactionType: TransactionType,
        expenseCategories: [PPCategory],
        incomeCategories: [PPCategory],
        categoriesById: [String: PPCategory],
        legacyAccountsById: [String: PPAccount],
        canonicalAccountsById: [UUID: CanonicalAccount]
    ) -> String {
        for line in candidate.proposedLines {
            if let categoryId = resolvedEtaxCategoryId(
                for: line,
                categoriesById: categoriesById,
                legacyAccountsById: legacyAccountsById,
                canonicalAccountsById: canonicalAccountsById
            ) {
                return categoryId
            }
        }

        let fallbackCategoryId = candidate.legacySnapshot?.categoryId ?? ""
        if categoriesById[fallbackCategoryId] != nil || fallbackCategoryId.isEmpty {
            return fallbackCategoryId
        }

        let categories = transactionType == .income ? incomeCategories : expenseCategories
        if let taxLine = candidate.proposedLines.compactMap({
            resolvedEtaxTaxLine(
                for: $0,
                canonicalAccountsById: canonicalAccountsById
            )
        }).first,
           let matchedCategory = preferredCategory(
                for: taxLine,
                categories: categories,
                legacyAccountsById: legacyAccountsById
           ) {
            return matchedCategory.id
        }

        return fallbackCategoryId
    }

    func resolvedEtaxCategoryId(
        for line: PostingCandidateLine,
        categoriesById: [String: PPCategory],
        legacyAccountsById: [String: PPAccount],
        canonicalAccountsById: [UUID: CanonicalAccount]
    ) -> String? {
        if let taxLine = resolvedEtaxTaxLine(for: line, canonicalAccountsById: canonicalAccountsById),
           let category = preferredCategory(
                for: taxLine,
                categories: Array(categoriesById.values),
                legacyAccountsById: legacyAccountsById
           ) {
            return category.id
        }
        return nil
    }

    func resolvedEtaxTaxLine(
        for line: PostingCandidateLine,
        canonicalAccountsById: [UUID: CanonicalAccount]
    ) -> TaxLine? {
        if let taxLine = TaxLine(legalReportLineId: line.legalReportLineId) {
            return taxLine
        }

        for accountId in [line.debitAccountId, line.creditAccountId].compactMap({ $0 }) {
            guard let account = canonicalAccountsById[accountId],
                  let taxLine = etaxTaxLine(for: account)
            else {
                continue
            }
            return taxLine
        }

        return nil
    }

    func preferredCategory(
        for taxLine: TaxLine,
        categories: [PPCategory],
        legacyAccountsById: [String: PPAccount]
    ) -> PPCategory? {
        let matching = categories.filter { category in
            guard let linkedAccountId = category.linkedAccountId,
                  let subtype = legacyAccountsById[linkedAccountId]?.subtype
            else {
                return false
            }
            return TaxLine.allCases.first { $0.accountSubtype == subtype } == taxLine
        }

        if matching.count == 1 {
            return matching.first
        }
        return nil
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
        let candidates = support.fetchPostingCandidates(statuses: [.draft, .needsReview])
        let evidenceById = support.fetchEvidence(ids: Set(candidates.compactMap(\.evidenceId)))
        let results = ClassificationEngine.classifyBatch(
            candidates: candidates,
            evidencesById: evidenceById,
            categories: support.fetchCategories(),
            accounts: support.fetchAccounts(),
            userRules: userRules
        ).map {
            ClassificationResultItem(
                candidate: $0.candidate,
                evidence: $0.evidence,
                result: $0.result,
                suggestedCategoryId: support.preferredCategoryId(
                    for: $0.result.taxLine,
                    transactionType: $0.candidate.legacySnapshot?.type ?? .expense,
                    fallbackCategoryId: $0.candidate.legacySnapshot?.categoryId ?? ""
                )
            )
        }
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

@MainActor
struct EtaxFormBuildQueryUseCase {
    private let support: AccountingReadSupport

    init(modelContext: ModelContext) {
        self.support = AccountingReadSupport(modelContext: modelContext)
    }

    func snapshot(fiscalYear: Int) -> EtaxFormBuildSnapshot {
        let readContext = support.canonicalReadContext(fiscalYear: fiscalYear)
        let startMonth = FiscalYearSettings.startMonth
        let businessProfile = support.fetchBusinessProfile()
        let taxYearProfile = readContext.businessId.flatMap {
            support.fetchTaxYearProfile(businessId: $0, taxYear: fiscalYear)
        }
        let candidateIds = Set(readContext.journals.compactMap(\.sourceCandidateId))
        let candidatesById = support.fetchPostingCandidates(ids: candidateIds)

        return EtaxFormBuildSnapshot(
            fiscalYear: fiscalYear,
            startMonth: startMonth,
            canonicalAccounts: readContext.accounts,
            canonicalAccountsById: readContext.canonicalAccountsById,
            categoryNamesById: Dictionary(
                uniqueKeysWithValues: support.fetchCategories().map { ($0.id, $0.name) }
            ),
            fixedAssets: support.fetchFixedAssets(),
            inventoryRecord: support.fetchInventoryRecord(fiscalYear: fiscalYear),
            businessProfile: businessProfile,
            taxYearProfile: taxYearProfile,
            sensitivePayload: businessProfile.flatMap { ProfileSecureStore.load(profileId: $0.id.uuidString) },
            canonicalProfitLoss: AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: readContext.accounts,
                journals: readContext.journals,
                startMonth: startMonth
            ),
            canonicalBalanceSheet: AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: readContext.accounts,
                journals: readContext.journals,
                startMonth: startMonth
            ),
            canonicalJournals: readContext.journals,
            candidateSummariesById: support.etaxCandidateSummaries(candidatesById: candidatesById)
        )
    }
}
