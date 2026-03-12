import CryptoKit
import os
import SwiftData
import SwiftUI

enum LegacyTransactionMutationSource: Sendable, Equatable {
    case systemGenerated
    case userInitiated
}

@MainActor
@Observable
class DataStore {
    struct LegacyLedgerDiagnostics: Equatable, Sendable {
        let legacyBookCount: Int
        let legacyEntryCount: Int
        let legacyJournalBookCount: Int
        let legacyJournalEntryCount: Int
        let canonicalJournalEntryCount: Int

        var hasLegacyData: Bool {
            legacyBookCount > 0 || legacyEntryCount > 0
        }

        var journalEntryDelta: Int {
            canonicalJournalEntryCount - legacyJournalEntryCount
        }
    }

    enum CanonicalCounterpartySyncStatus: Equatable, Sendable {
        case synced(UUID)
        case skippedSourceNotFound
        case skippedBusinessProfileUnavailable
        case skippedBlankName
        case failed(String)
    }

    enum CanonicalPostingSyncStatus: Equatable, Sendable {
        case synced(candidateId: UUID, journalId: UUID)
        case skippedSourceNotFound
        case skippedBusinessProfileUnavailable
        case skippedLegacyJournalUnavailable
        case skippedUnmappableAccountIds([String])
        case failed(String)
    }

    struct CanonicalTransactionSyncResult: Equatable, Sendable {
        let counterpartyStatus: CanonicalCounterpartySyncStatus
        let postingStatus: CanonicalPostingSyncStatus
    }

    var modelContext: ModelContext

    var projects: [PPProject] = []
    var allTransactions: [PPTransaction] = []
    var categories: [PPCategory] = []
    var recurringTransactions: [PPRecurringTransaction] = []
    var accounts: [PPAccount] = []
    var journalEntries: [PPJournalEntry] = []
    var journalLines: [PPJournalLine] = []
    var businessProfile: BusinessProfile?
    var currentTaxYearProfile: TaxYearProfile?
    var fixedAssets: [PPFixedAsset] = []
    var inventoryRecords: [PPInventoryRecord] = []
    var isLoading = true
    var lastError: AppError?

    /// ソフトデリートされていない有効な取引のみ
    var transactions: [PPTransaction] {
        allTransactions.filter { $0.deletedAt == nil }
    }

    /// アーカイブされていない有効なカテゴリのみ
    var activeCategories: [PPCategory] {
        categories.filter { $0.archivedAt == nil }
    }

    /// H2: 定期取引の追加/更新/削除時に通知スケジュールを再構成するためのコールバック
    var onRecurringScheduleChanged: (([PPRecurringTransaction]) -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    private var counterpartyMasterUseCase: CounterpartyMasterUseCase {
        CounterpartyMasterUseCase(modelContext: modelContext)
    }

    private var postingWorkflowUseCase: PostingWorkflowUseCase {
        PostingWorkflowUseCase(modelContext: modelContext)
    }

    private var postingIntakeUseCase: PostingIntakeUseCase {
        PostingIntakeUseCase(modelContext: modelContext)
    }

    var canonicalPostingSupport: CanonicalPostingSupport {
        CanonicalPostingSupport(modelContext: modelContext)
    }

    private var projectWorkflowUseCase: ProjectWorkflowUseCase {
        ProjectWorkflowUseCase(modelContext: modelContext)
    }

    private var bundledTaxYearPackProvider: BundledTaxYearPackProvider {
        BundledTaxYearPackProvider(bundle: .main)
    }

    var profileSensitivePayload: ProfileSensitivePayload? {
        loadSensitivePayload()
    }

    private var canonicalProfileSecureStoreId: String? {
        businessProfile?.id.uuidString
    }

    var isAccountingBootstrapped: Bool {
        businessProfile != nil
    }

    var defaultPaymentAccountPreference: String? {
        businessProfile?.defaultPaymentAccountId
    }

    var profileOpeningDate: Date? {
        businessProfile?.openingDate
    }

    var isLegacyTransactionEditingEnabled: Bool {
        !FeatureFlags.useCanonicalPosting
    }

    var legacyTransactionMutationDisabledMessage: String {
        AppError.legacyTransactionMutationDisabled.errorDescription ?? "この操作は現在利用できません"
    }

    private func canonicalTaxCodeId(
        explicitTaxCodeId: String?,
        legacyCategory: TaxCategory? = nil,
        taxRate: Int? = nil
    ) -> String? {
        if let resolved = TaxCode.resolve(id: explicitTaxCodeId) {
            return resolved.rawValue
        }
        return TaxCode.resolve(
            legacyCategory: legacyCategory,
            taxRate: taxRate
        )?.rawValue
    }

    private func syncCanonicalAccountsFromLegacyAccountsIfNeeded() {
        guard let businessId = businessProfile?.id else {
            return
        }

        do {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.businessId == businessId }
            )
            let existingEntities = try modelContext.fetch(descriptor)
            var entitiesByLegacyId: [String: CanonicalAccountEntity] = [:]
            var entitiesByAccountId: [UUID: CanonicalAccountEntity] = [:]
            var entitiesByCode: [String: CanonicalAccountEntity] = [:]

            for entity in existingEntities {
                entitiesByAccountId[entity.accountId] = entity
                if let legacyAccountId = entity.legacyAccountId {
                    entitiesByLegacyId[legacyAccountId] = entity
                }
                entitiesByCode[entity.code] = entitiesByCode[entity.code] ?? entity
            }

            var changed = false
            for legacyAccount in accounts {
                let canonicalId = LegacyAccountCanonicalMapper.canonicalAccountId(
                    businessId: businessId,
                    legacyAccountId: legacyAccount.id
                )
                let existingEntity = entitiesByLegacyId[legacyAccount.id]
                    ?? entitiesByAccountId[canonicalId]
                    ?? entitiesByCode[legacyAccount.code]
                let existingAccount = existingEntity.map(CanonicalAccountEntityMapper.toDomain)
                let canonicalAccount = LegacyAccountCanonicalMapper.canonicalAccount(
                    from: legacyAccount,
                    businessId: businessId,
                    existing: existingAccount
                )

                if let existingEntity {
                    if CanonicalAccountEntityMapper.toDomain(existingEntity) != canonicalAccount {
                        CanonicalAccountEntityMapper.update(existingEntity, from: canonicalAccount)
                        changed = true
                    }
                } else {
                    modelContext.insert(CanonicalAccountEntityMapper.toEntity(canonicalAccount))
                    changed = true
                }
            }

            if changed {
                try modelContext.save()
            }
        } catch {
            AppLogger.dataStore.warning("Canonical account sync failed: \(error.localizedDescription)")
        }
    }

    private func canonicalAccountIdsByLegacyId(businessId: UUID) -> [String: UUID] {
        do {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.businessId == businessId }
            )
            let entities = try modelContext.fetch(descriptor)
            return Dictionary(
                uniqueKeysWithValues: entities.compactMap { entity in
                    guard let legacyAccountId = entity.legacyAccountId else {
                        return nil
                    }
                    return (legacyAccountId, entity.accountId)
                }
            )
        } catch {
            AppLogger.dataStore.warning("Canonical account lookup failed: \(error.localizedDescription)")
            return [:]
        }
    }

    private func canonicalAccountsByLegacyId(businessId: UUID) -> [String: CanonicalAccount] {
        do {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.businessId == businessId }
            )
            let entities = try modelContext.fetch(descriptor)
            return Dictionary(
                uniqueKeysWithValues: entities.compactMap { entity in
                    guard let legacyAccountId = entity.legacyAccountId else {
                        return nil
                    }
                    return (legacyAccountId, CanonicalAccountEntityMapper.toDomain(entity))
                }
            )
        } catch {
            AppLogger.dataStore.warning("Canonical account domain lookup failed: \(error.localizedDescription)")
            return [:]
        }
    }

    private func canonicalAccountId(
        for legacyAccountId: String,
        canonicalIdsByLegacyId: [String: UUID]
    ) -> UUID? {
        if let mappedId = canonicalIdsByLegacyId[legacyAccountId] {
            return mappedId
        }
        if let uuid = UUID(uuidString: legacyAccountId) {
            return uuid
        }
        return nil
    }

    func canonicalCounterparty(id: UUID) -> Counterparty? {
        do {
            let descriptor = FetchDescriptor<CounterpartyEntity>(
                predicate: #Predicate { $0.counterpartyId == id }
            )
            return try modelContext.fetch(descriptor).first.map(CounterpartyEntityMapper.toDomain)
        } catch {
            AppLogger.dataStore.warning("Canonical counterparty lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    func canonicalCounterparties() -> [Counterparty] {
        guard let businessId = businessProfile?.id else {
            return []
        }
        return fetchCanonicalCounterparties(businessId: businessId)
    }

    func fetchCanonicalAccounts(businessId: UUID) -> [CanonicalAccount] {
        do {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [
                    SortDescriptor(\.displayOrder),
                    SortDescriptor(\.code)
                ]
            )
            return try modelContext.fetch(descriptor).map(CanonicalAccountEntityMapper.toDomain)
        } catch {
            AppLogger.dataStore.warning("Canonical accounts fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchCanonicalCounterparties(businessId: UUID) -> [Counterparty] {
        do {
            let descriptor = FetchDescriptor<CounterpartyEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [SortDescriptor(\.displayName)]
            )
            return try modelContext.fetch(descriptor).map(CounterpartyEntityMapper.toDomain)
        } catch {
            AppLogger.dataStore.warning("Canonical counterparties fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func upsertCanonicalCounterparty(_ counterparty: Counterparty) {
        let descriptor = FetchDescriptor<CounterpartyEntity>(
            predicate: #Predicate { $0.counterpartyId == counterparty.id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            CounterpartyEntityMapper.update(existing, from: counterparty)
        } else {
            modelContext.insert(CounterpartyEntityMapper.toEntity(counterparty))
        }
    }

    private func resolveLegacyCounterpartyReference(
        explicitId: UUID?,
        rawName: String?,
        defaultTaxCodeId: String?
    ) -> (id: UUID?, displayName: String?) {
        if let explicitId, let existing = canonicalCounterparty(id: explicitId) {
            if defaultTaxCodeId != nil, existing.defaultTaxCodeId != defaultTaxCodeId {
                upsertCanonicalCounterparty(existing.updated(defaultTaxCodeId: .some(defaultTaxCodeId)))
            }
            return (existing.id, existing.displayName)
        }

        guard let businessId = businessProfile?.id else {
            return (nil, normalizedOptionalString(rawName))
        }
        guard let displayName = normalizedOptionalString(rawName) else {
            return (nil, nil)
        }

        let counterparties = fetchCanonicalCounterparties(businessId: businessId)
        if let exactMatch = counterparties.first(where: {
            $0.displayName.compare(
                displayName,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) == .orderedSame
        }) {
            if defaultTaxCodeId != nil, exactMatch.defaultTaxCodeId != defaultTaxCodeId {
                upsertCanonicalCounterparty(exactMatch.updated(defaultTaxCodeId: .some(defaultTaxCodeId)))
            }
            return (exactMatch.id, exactMatch.displayName)
        }

        let counterparty = Counterparty(
            id: stableCounterpartyId(businessId: businessId, displayName: displayName),
            businessId: businessId,
            displayName: displayName,
            defaultTaxCodeId: defaultTaxCodeId,
            createdAt: Date(),
            updatedAt: Date()
        )
        upsertCanonicalCounterparty(counterparty)
        return (counterparty.id, counterparty.displayName)
    }

    func fetchCanonicalJournalEntries(businessId: UUID, taxYear: Int? = nil) -> [CanonicalJournalEntry] {
        do {
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
            return try modelContext.fetch(descriptor).map(CanonicalJournalEntryEntityMapper.toDomain)
        } catch {
            AppLogger.dataStore.warning("Canonical journals fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchCanonicalJournalEntries(evidenceId: UUID) -> [CanonicalJournalEntry] {
        do {
            let descriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate { $0.sourceEvidenceId == evidenceId },
                sortBy: [
                    SortDescriptor(\.journalDate, order: .reverse),
                    SortDescriptor(\.voucherNo, order: .reverse)
                ]
            )
            return try modelContext.fetch(descriptor).map(CanonicalJournalEntryEntityMapper.toDomain)
        } catch {
            AppLogger.dataStore.warning("Canonical evidence journals fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    func legacyLedgerDiagnostics() -> LegacyLedgerDiagnostics {
        do {
            let books = try modelContext.fetch(FetchDescriptor<SDLedgerBook>())
            let entries = try modelContext.fetch(FetchDescriptor<SDLedgerEntry>())
            let canonicalEntries = try modelContext.fetch(FetchDescriptor<JournalEntryEntity>())
            let journalBookIds = Set(
                books
                    .filter { $0.ledgerTypeRaw == LedgerType.journal.rawValue }
                    .map(\.id)
            )
            let legacyJournalEntryCount = entries.reduce(into: 0) { count, entry in
                if journalBookIds.contains(entry.bookId) {
                    count += 1
                }
            }

            return LegacyLedgerDiagnostics(
                legacyBookCount: books.count,
                legacyEntryCount: entries.count,
                legacyJournalBookCount: journalBookIds.count,
                legacyJournalEntryCount: legacyJournalEntryCount,
                canonicalJournalEntryCount: canonicalEntries.count
            )
        } catch {
            AppLogger.dataStore.warning("Legacy ledger diagnostics failed: \(error.localizedDescription)")
            return LegacyLedgerDiagnostics(
                legacyBookCount: 0,
                legacyEntryCount: 0,
                legacyJournalBookCount: 0,
                legacyJournalEntryCount: 0,
                canonicalJournalEntryCount: canonicalJournalEntries().count
            )
        }
    }

    private func logLegacyLedgerDiagnosticsIfNeeded() {
        let diagnostics = legacyLedgerDiagnostics()
        guard diagnostics.hasLegacyData else {
            return
        }

        AppLogger.dataStore.info(
            """
            Legacy ledger diagnostics:
              books=\(diagnostics.legacyBookCount)
              entries=\(diagnostics.legacyEntryCount)
              legacyJournalBooks=\(diagnostics.legacyJournalBookCount)
              legacyJournalEntries=\(diagnostics.legacyJournalEntryCount)
              canonicalJournalEntries=\(diagnostics.canonicalJournalEntryCount)
              journalEntryDelta=\(diagnostics.journalEntryDelta)
            """
        )

        if !FeatureFlags.useLegacyLedger {
            AppLogger.dataStore.warning("Legacy ledger UI is disabled while legacy ledger data remains in store")
        }
    }

    // MARK: - Initialization

    func loadData() {
        do {
            let projectDescriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            projects = try modelContext.fetch(projectDescriptor)

            let transactionDescriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            allTransactions = try modelContext.fetch(transactionDescriptor)

            let categoryDescriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\.name)])
            categories = try modelContext.fetch(categoryDescriptor)

            let recurringDescriptor = FetchDescriptor<PPRecurringTransaction>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            recurringTransactions = try modelContext.fetch(recurringDescriptor)

            if categories.isEmpty {
                seedDefaultCategories()
            } else {
                seedMissingCategories()
            }
            migrateNilOptionalFields()
            migrateLegacyReceiptImagesToDocumentRecords()

            // Phase 4B: 会計データの読み込み
            let accountDescriptor = FetchDescriptor<PPAccount>(sortBy: [SortDescriptor(\.displayOrder)])
            accounts = try modelContext.fetch(accountDescriptor)

            let entryDescriptor = FetchDescriptor<PPJournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            journalEntries = try modelContext.fetch(entryDescriptor)

            let lineDescriptor = FetchDescriptor<PPJournalLine>(sortBy: [SortDescriptor(\.displayOrder)])
            journalLines = try modelContext.fetch(lineDescriptor)

            runLegacyProfileMigrationIfNeeded()
            refreshCanonicalProfileCache()
            _ = loadSensitivePayload()

            let fixedAssetDescriptor = FetchDescriptor<PPFixedAsset>(sortBy: [SortDescriptor(\.acquisitionDate, order: .reverse)])
            fixedAssets = try modelContext.fetch(fixedAssetDescriptor)

            let inventoryDescriptor = FetchDescriptor<PPInventoryRecord>(sortBy: [SortDescriptor(\.fiscalYear, order: .reverse)])
            inventoryRecords = try modelContext.fetch(inventoryDescriptor)

            // Phase 4B: 会計ブートストラップ（初回のみ実行）
            let bootstrap = AccountingBootstrapService(modelContext: modelContext)
            if bootstrap.needsBootstrap() {
                let result = bootstrap.execute(categories: categories, transactions: transactions)
                save()
                refreshAccounts()
                refreshJournalEntries()
                refreshJournalLines()
                refreshCategories()
                refreshTransactions()
                runLegacyProfileMigrationIfNeeded()
                refreshCanonicalProfileCache()
                AppLogger.dataStore.info("Bootstrap完了: accounts=\(result.accountsCreated), journals=\(result.journalEntriesGenerated)")
                if !result.integrityIssues.isEmpty {
                    AppLogger.dataStore.warning("Bootstrap整合性チェック: \(result.integrityIssues.count)件の問題あり")
                    for issue in result.integrityIssues {
                        AppLogger.dataStore.warning("  - \(issue)")
                    }
                }
            }

            // 既存ユーザーに新しいデフォルト勘定科目を追加（減価償却累計額等）
            seedMissingDefaultAccounts()
            syncCanonicalAccountsFromLegacyAccountsIfNeeded()
            persistCanonicalProfileStateIfNeeded()
            logLegacyLedgerDiagnosticsIfNeeded()
        } catch {
            AppLogger.dataStore.error("Failed to load data: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
        isLoading = false
    }

    @discardableResult
    func reloadProfileSettings() async -> Bool {
        await ProfileSettingsWorkflowUseCase(
            modelContext: modelContext,
            ports: .init(
                readSensitivePayload: { self.profileSensitivePayload },
                readCurrentTaxYear: { self.currentTaxYearProfile?.taxYear },
                applyState: { self.applyProfileSettingsState($0) },
                persistSensitivePayload: { payload, businessProfileId in
                    self.persistSensitivePayload(payload, businessProfileId: businessProfileId)
                },
                setLastError: { self.lastError = $0 }
            )
        ).loadProfile()
    }

    @discardableResult
    func saveProfileSettings(
        command: SaveProfileSettingsCommand,
        sensitivePayload: ProfileSensitivePayload
    ) async -> Result<Void, Error> {
        await ProfileSettingsWorkflowUseCase(
            modelContext: modelContext,
            ports: .init(
                readSensitivePayload: { self.profileSensitivePayload },
                readCurrentTaxYear: { self.currentTaxYearProfile?.taxYear },
                applyState: { self.applyProfileSettingsState($0) },
                persistSensitivePayload: { payload, businessProfileId in
                    self.persistSensitivePayload(payload, businessProfileId: businessProfileId)
                },
                setLastError: { self.lastError = $0 }
            )
        ).saveProfile(command: command, sensitivePayload: sensitivePayload)
    }

    /// マイグレーション: SwiftDataスキーマ変更後の整合性チェック
    /// allocationMode/yearlyAmortizationMode は非Optionalに変更済み。
    /// SwiftDataが自動的にデフォルト値を適用するため、現在は追加処理不要。
    private func migrateNilOptionalFields() {
        var changed = false
        for transaction in allTransactions where transaction.taxCodeId == nil {
            guard let taxCodeId = canonicalTaxCodeId(
                explicitTaxCodeId: nil,
                legacyCategory: transaction.taxCategory,
                taxRate: transaction.taxRate
            ) else {
                continue
            }
            transaction.taxCodeId = taxCodeId
            if let taxCode = TaxCode.resolve(id: taxCodeId) {
                transaction.taxRate = taxCode.taxRatePercent
                transaction.taxCategory = taxCode.legacyCategory
            }
            transaction.updatedAt = Date()
            changed = true
        }
        if changed {
            _ = save()
        }
    }

    func refreshCanonicalProfileCache() {
        do {
            let businessDescriptor = FetchDescriptor<BusinessProfileEntity>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
            let businessEntities = try modelContext.fetch(businessDescriptor)
            if let entity = businessEntities.first {
                businessProfile = BusinessProfileEntityMapper.toDomain(entity)
            } else {
                businessProfile = nil
            }

            if let businessProfile {
                let defaultTaxYear = currentTaxYearProfile?.taxYear ?? currentFiscalYear()
                let businessId = businessProfile.id
                let taxDescriptor = FetchDescriptor<TaxYearProfileEntity>(
                    predicate: #Predicate {
                        $0.businessId == businessId && $0.taxYear == defaultTaxYear
                    }
                )
                let taxEntities = try modelContext.fetch(taxDescriptor)
                if let entity = taxEntities.first {
                    currentTaxYearProfile = TaxYearProfileEntityMapper.toDomain(entity)
                } else {
                    currentTaxYearProfile = TaxYearProfile(
                        businessId: businessProfile.id,
                        taxYear: defaultTaxYear,
                        taxPackVersion: resolvedPackVersion(for: defaultTaxYear)
                    )
                }
            } else {
                currentTaxYearProfile = nil
            }
        } catch {
            AppLogger.dataStore.warning("Canonical profile cache refresh failed: \(error.localizedDescription)")
        }
    }

    func persistCanonicalProfileStateIfNeeded() {
        guard let businessProfile, let currentTaxYearProfile else { return }

        do {
            let businessId = businessProfile.id
            let businessDescriptor = FetchDescriptor<BusinessProfileEntity>(
                predicate: #Predicate { $0.businessId == businessId }
            )
            let businessEntities = try modelContext.fetch(businessDescriptor)
            if let entity = businessEntities.first {
                BusinessProfileEntityMapper.update(entity, from: businessProfile)
            } else {
                modelContext.insert(BusinessProfileEntityMapper.toEntity(businessProfile))
            }

            let taxProfileId = currentTaxYearProfile.id
            let taxDescriptor = FetchDescriptor<TaxYearProfileEntity>(
                predicate: #Predicate { $0.profileId == taxProfileId }
            )
            let taxEntities = try modelContext.fetch(taxDescriptor)
            if let entity = taxEntities.first {
                TaxYearProfileEntityMapper.update(entity, from: currentTaxYearProfile)
            } else {
                modelContext.insert(TaxYearProfileEntityMapper.toEntity(currentTaxYearProfile))
            }

            try modelContext.save()
        } catch {
            AppLogger.dataStore.warning("Canonical profile persistence skipped: \(error.localizedDescription)")
            modelContext.rollback()
        }
    }

    func applyProfileSettingsState(_ state: ProfileSettingsState) {
        businessProfile = state.businessProfile
        currentTaxYearProfile = state.taxYearProfile
    }

    private func loadSensitivePayload() -> ProfileSensitivePayload? {
        if let canonicalProfileSecureStoreId,
           let payload = ProfileSecureStore.load(profileId: canonicalProfileSecureStoreId) {
            return payload
        }
        return nil
    }

    func persistSensitivePayload(_ payload: ProfileSensitivePayload, businessProfileId: UUID) -> Bool {
        let canonicalId = businessProfileId.uuidString
        return ProfileSecureStore.save(payload, profileId: canonicalId)
    }

    /// canonical プロフィールを直接返す（PPAccountingProfile を経由しない）
    func canonicalExportProfiles(
        for fiscalYear: Int
    ) -> (business: BusinessProfile, taxYear: TaxYearProfile, sensitive: ProfileSensitivePayload?)? {
        guard let businessProfile else {
            return nil
        }
        let taxYear = resolvedTaxYearProfileForExport(
            fiscalYear: fiscalYear,
            businessId: businessProfile.id
        )
        let sensitive = loadSensitivePayload()
        return (business: businessProfile, taxYear: taxYear, sensitive: sensitive)
    }

    private func taxYearProfileForExport(fiscalYear: Int, businessId: UUID) -> TaxYearProfile? {
        if let currentTaxYearProfile, currentTaxYearProfile.taxYear == fiscalYear {
            return currentTaxYearProfile
        }

        do {
            let descriptor = FetchDescriptor<TaxYearProfileEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == fiscalYear
                }
            )
            return try modelContext.fetch(descriptor).first.map(TaxYearProfileEntityMapper.toDomain)
        } catch {
            AppLogger.dataStore.warning("e-Tax export profile lookup failed: year=\(fiscalYear), error=\(error.localizedDescription)")
            return nil
        }
    }

    private func resolvedTaxYearProfileForExport(fiscalYear: Int, businessId: UUID) -> TaxYearProfile {
        if let profile = taxYearProfileForExport(fiscalYear: fiscalYear, businessId: businessId) {
            return profile
        }

        if let currentTaxYearProfile, currentTaxYearProfile.businessId == businessId {
            return TaxYearProfile(
                businessId: businessId,
                taxYear: fiscalYear,
                filingStyle: currentTaxYearProfile.filingStyle,
                blueDeductionLevel: currentTaxYearProfile.blueDeductionLevel,
                bookkeepingBasis: currentTaxYearProfile.bookkeepingBasis,
                vatStatus: currentTaxYearProfile.vatStatus,
                vatMethod: currentTaxYearProfile.vatMethod,
                simplifiedBusinessCategory: currentTaxYearProfile.simplifiedBusinessCategory,
                invoiceIssuerStatusAtYear: currentTaxYearProfile.invoiceIssuerStatusAtYear,
                electronicBookLevel: currentTaxYearProfile.electronicBookLevel,
                etaxSubmissionPlanned: currentTaxYearProfile.etaxSubmissionPlanned,
                yearLockState: currentTaxYearProfile.yearLockState,
                taxPackVersion: resolvedPackVersion(for: fiscalYear)
            )
        }

        return TaxYearProfile(
            businessId: businessId,
            taxYear: fiscalYear,
            taxPackVersion: resolvedPackVersion(for: fiscalYear)
        )
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func currentFiscalYear() -> Int {
        Calendar.current.component(.year, from: Date())
    }

    private func resolvedPackVersion(for taxYear: Int) -> String {
        (try? bundledTaxYearPackProvider.packSync(for: taxYear).version) ?? "\(taxYear)-v1"
    }

    private func enqueueCanonicalRecurringCounterpartySync(for recurringId: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.syncCanonicalCounterparty(forRecurringId: recurringId)
        }
    }

    #if DEBUG
    /// Legacy transaction から canonical artifact を明示同期する互換ヘルパー。
    /// テスト / fixture 互換専用で、production surface からは除外する。
    func syncCanonicalArtifacts(
        forTransactionId transactionId: UUID,
        source: CandidateSource? = nil
    ) async -> CanonicalTransactionSyncResult {
        guard let transaction = allTransactions.first(where: { $0.id == transactionId }) else {
            return CanonicalTransactionSyncResult(
                counterpartyStatus: .skippedSourceNotFound,
                postingStatus: .skippedSourceNotFound
            )
        }

        let explicitTaxCodeId = canonicalTaxCodeId(
            explicitTaxCodeId: transaction.taxCodeId,
            legacyCategory: transaction.taxCategory,
            taxRate: transaction.taxRate
        )
        let counterpartyStatus = await syncCanonicalCounterparty(
            id: transaction.counterpartyId,
            named: transaction.counterparty,
            defaultTaxCodeId: explicitTaxCodeId
        )
        let counterpartyId: UUID?
        switch counterpartyStatus {
        case .synced(let id):
            counterpartyId = id
        case .skippedSourceNotFound, .skippedBusinessProfileUnavailable, .skippedBlankName, .failed:
            counterpartyId = nil
        }
        let postingStatus = await syncCanonicalPosting(
            for: transaction,
            counterpartyId: counterpartyId,
            source: source
        )

        return CanonicalTransactionSyncResult(
            counterpartyStatus: counterpartyStatus,
            postingStatus: postingStatus
        )
    }

    /// Legacy transaction から canonical artifact を同期的に再生成する互換ヘルパー。
    /// テスト / fixture 互換専用で、production surface からは除外する。
    func syncCanonicalArtifactsSynchronously(
        forTransactionId transactionId: UUID,
        source: CandidateSource? = nil
    ) -> CanonicalTransactionSyncResult {
        guard let transaction = allTransactions.first(where: { $0.id == transactionId }) else {
            return CanonicalTransactionSyncResult(
                counterpartyStatus: .skippedSourceNotFound,
                postingStatus: .skippedSourceNotFound
            )
        }

        let explicitTaxCodeId = canonicalTaxCodeId(
            explicitTaxCodeId: transaction.taxCodeId,
            legacyCategory: transaction.taxCategory,
            taxRate: transaction.taxRate
        )
        let counterpartyStatus = syncCanonicalCounterpartyNow(
            id: transaction.counterpartyId,
            named: transaction.counterparty,
            defaultTaxCodeId: explicitTaxCodeId
        )
        let counterpartyId: UUID?
        switch counterpartyStatus {
        case .synced(let id):
            counterpartyId = id
        case .skippedSourceNotFound, .skippedBusinessProfileUnavailable, .skippedBlankName, .failed:
            counterpartyId = nil
        }

        syncCanonicalAccountsFromLegacyAccountsIfNeeded()
        let posting: CanonicalTransactionPostingBridge.Posting
        do {
            posting = try buildCanonicalPosting(
                for: transaction,
                counterpartyId: counterpartyId,
                source: source ?? .manual
            )
        } catch AppError.invalidInput(let message)
            where message.contains("事業者プロフィールが未設定") {
            return CanonicalTransactionSyncResult(
                counterpartyStatus: counterpartyStatus,
                postingStatus: .skippedBusinessProfileUnavailable
            )
        } catch AppError.yearLocked {
            return CanonicalTransactionSyncResult(
                counterpartyStatus: counterpartyStatus,
                postingStatus: .skippedBusinessProfileUnavailable
            )
        } catch {
            return CanonicalTransactionSyncResult(
                counterpartyStatus: counterpartyStatus,
                postingStatus: .skippedLegacyJournalUnavailable
            )
        }

        do {
            let journal = try canonicalPostingSupport.persistApprovedPosting(
                posting: posting,
                allocationAmounts: transaction.allocations.filter { $0.amount > 0 },
                actor: source == .importFile ? "user" : "system",
                saveChanges: true
            )
            if transaction.journalEntryId != journal.id {
                transaction.journalEntryId = journal.id
                save()
                refreshTransactions()
            }
            return CanonicalTransactionSyncResult(
                counterpartyStatus: counterpartyStatus,
                postingStatus: .synced(candidateId: posting.candidate.id, journalId: journal.id)
            )
        } catch {
            AppLogger.dataStore.warning("Canonical posting sync failed: \(error.localizedDescription)")
            return CanonicalTransactionSyncResult(
                counterpartyStatus: counterpartyStatus,
                postingStatus: .failed(error.localizedDescription)
            )
        }
    }

    /// Legacy transaction に紐づく canonical artifact を同期的に削除する互換ヘルパー。
    /// テスト / fixture 互換専用で、production surface からは除外する。
    @discardableResult
    func removeCanonicalArtifactsSynchronously(forTransactionId transactionId: UUID) -> Bool {
        guard let transaction = allTransactions.first(where: { $0.id == transactionId }),
              let journalId = transaction.journalEntryId else {
            return true
        }

        do {
            let journalDescriptor = FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate { $0.journalId == journalId }
            )
            guard let journalEntity = try modelContext.fetch(journalDescriptor).first else {
                transaction.journalEntryId = nil
                save()
                refreshTransactions()
                return true
            }

            let businessId = journalEntity.businessId
            let taxYear = journalEntity.taxYear
            let sourceCandidateId = journalEntity.sourceCandidateId

            modelContext.delete(journalEntity)

            if let sourceCandidateId {
                let candidateDescriptor = FetchDescriptor<PostingCandidateEntity>(
                    predicate: #Predicate { $0.candidateId == sourceCandidateId }
                )
                try modelContext.fetch(candidateDescriptor).forEach(modelContext.delete)
            }

            transaction.journalEntryId = nil
            try modelContext.save()
            try? LocalJournalSearchIndex(modelContext: modelContext).rebuild(
                businessId: businessId,
                taxYear: taxYear
            )
            refreshTransactions()
            refreshJournalEntries()
            refreshJournalLines()
            return true
        } catch {
            AppLogger.dataStore.warning("Canonical artifact removal failed: \(error.localizedDescription)")
            return false
        }
    }
    #endif

    func syncCanonicalCounterparty(forRecurringId recurringId: UUID) async -> CanonicalCounterpartySyncStatus {
        guard let recurring = recurringTransactions.first(where: { $0.id == recurringId }) else {
            return .skippedSourceNotFound
        }
        return await syncCanonicalCounterparty(
            id: recurring.counterpartyId,
            named: recurring.counterparty,
            defaultTaxCodeId: nil
        )
    }

    func saveManualPostingCandidate(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        taxAmount: Int? = nil,
        taxCodeId: String? = nil,
        taxRate: Int? = nil,
        isTaxIncluded: Bool? = nil,
        taxCategory: TaxCategory? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil,
        candidateSource: CandidateSource? = nil
    ) async -> Result<PostingCandidate, AppError> {
        let resolvedTaxCodeId = canonicalTaxCodeId(
            explicitTaxCodeId: taxCodeId,
            legacyCategory: taxCategory,
            taxRate: taxRate
        )
        do {
            return .success(
                try await postingIntakeUseCase.saveManualCandidate(
                    input: ManualPostingCandidateInput(
                        type: type,
                        amount: amount,
                        date: date,
                        categoryId: categoryId,
                        memo: memo,
                        allocations: allocations,
                        paymentAccountId: paymentAccountId,
                        transferToAccountId: transferToAccountId,
                        taxDeductibleRate: taxDeductibleRate,
                        taxAmount: taxAmount,
                        taxCodeId: resolvedTaxCodeId,
                        isTaxIncluded: isTaxIncluded,
                        counterpartyId: counterpartyId,
                        counterparty: counterparty,
                        candidateSource: candidateSource ?? .manual
                    )
                )
            )
        } catch let error as AppError {
            return .failure(error)
        } catch {
            let appError = AppError.saveFailed(underlying: error)
            lastError = appError
            return .failure(appError)
        }
    }

    func buildCanonicalPostingSync(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        recurringId: UUID?,
        paymentAccountId: String?,
        transferToAccountId: String?,
        taxDeductibleRate: Int?,
        taxAmount: Int?,
        taxCodeId: String?,
        taxRate: Int?,
        isTaxIncluded: Bool?,
        taxCategory: TaxCategory?,
        counterpartyId: UUID?,
        counterparty: String?,
        source: CandidateSource
    ) -> Result<CanonicalTransactionPostingBridge.Posting, AppError> {
        syncCanonicalAccountsFromLegacyAccountsIfNeeded()

        do {
            let resolvedTaxCodeId = canonicalTaxCodeId(
                explicitTaxCodeId: taxCodeId,
                legacyCategory: taxCategory,
                taxRate: taxRate
            )
            let posting = try canonicalPostingSupport.buildApprovedPosting(
                seed: CanonicalPostingSeed(
                    id: UUID(),
                    type: type,
                    amount: amount,
                    date: date,
                    categoryId: categoryId,
                    memo: memo,
                    recurringId: recurringId,
                    paymentAccountId: paymentAccountId,
                    transferToAccountId: transferToAccountId,
                    taxDeductibleRate: taxDeductibleRate,
                    taxAmount: taxAmount,
                    taxCodeId: resolvedTaxCodeId,
                    taxRate: taxRate,
                    isTaxIncluded: isTaxIncluded,
                    taxCategory: taxCategory,
                    receiptImagePath: nil,
                    lineItems: [],
                    counterpartyId: counterpartyId,
                    counterpartyName: counterparty,
                    source: source,
                    createdAt: Date(),
                    updatedAt: Date(),
                    journalEntryId: nil
                ),
                snapshot: try canonicalPostingSupport.snapshot()
            )
            lastError = nil
            return .success(posting)
        } catch let error as AppError {
            lastError = error
            return .failure(error)
        } catch {
            let appError = AppError.saveFailed(underlying: error)
            lastError = appError
            return .failure(appError)
        }
    }

    func saveApprovedPostingSync(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        recurringId: UUID? = nil,
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        taxAmount: Int? = nil,
        taxCodeId: String? = nil,
        taxRate: Int? = nil,
        isTaxIncluded: Bool? = nil,
        taxCategory: TaxCategory? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil,
        candidateSource: CandidateSource
    ) -> Result<CanonicalJournalEntry, AppError> {
        let result = buildCanonicalPostingSync(
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocations,
            recurringId: recurringId,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            taxAmount: taxAmount,
            taxCodeId: taxCodeId,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyId: counterpartyId,
            counterparty: counterparty,
            source: candidateSource
        )

        let posting: CanonicalTransactionPostingBridge.Posting
        switch result {
        case .success(let builtPosting):
            posting = builtPosting
        case .failure(let error):
            return .failure(error)
        }

        let normalizedAllocations = calculateRatioAllocations(
            amount: amount,
            allocations: type == .transfer ? [] : allocations
        )

        do {
            let actor = candidateSource == .importFile ? "user" : "system"
            let journal = try saveApprovedPostingSynchronously(
                posting,
                allocations: normalizedAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) },
                actor: actor
            )
            lastError = nil
            return .success(journal)
        } catch {
            let appError = AppError.saveFailed(underlying: error)
            lastError = appError
            return .failure(appError)
        }
    }

    func saveApprovedPostingSync(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocationAmounts: [Allocation],
        recurringId: UUID? = nil,
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        taxAmount: Int? = nil,
        taxCodeId: String? = nil,
        taxRate: Int? = nil,
        isTaxIncluded: Bool? = nil,
        taxCategory: TaxCategory? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil,
        candidateSource: CandidateSource
    ) -> Result<CanonicalJournalEntry, AppError> {
        let allocationRatios = allocationAmounts.map { allocation in
            (projectId: allocation.projectId, ratio: allocation.ratio)
        }
        let result = buildCanonicalPostingSync(
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocationRatios,
            recurringId: recurringId,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            taxAmount: taxAmount,
            taxCodeId: taxCodeId,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyId: counterpartyId,
            counterparty: counterparty,
            source: candidateSource
        )

        let posting: CanonicalTransactionPostingBridge.Posting
        switch result {
        case .success(let builtPosting):
            posting = builtPosting
        case .failure(let error):
            return .failure(error)
        }

        let normalizedAllocationAmounts = allocationAmounts.filter { $0.amount > 0 }

        do {
            let actor = candidateSource == .importFile ? "user" : "system"
            let journal = try saveApprovedPostingSynchronously(
                posting,
                allocationAmounts: normalizedAllocationAmounts,
                actor: actor
            )
            lastError = nil
            return .success(journal)
        } catch {
            let appError = AppError.saveFailed(underlying: error)
            lastError = appError
            return .failure(appError)
        }
    }

    private func saveApprovedPosting(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        recurringId: UUID? = nil,
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        taxAmount: Int? = nil,
        taxCodeId: String? = nil,
        taxRate: Int? = nil,
        isTaxIncluded: Bool? = nil,
        taxCategory: TaxCategory? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil,
        candidateSource: CandidateSource
    ) async -> Result<CanonicalJournalEntry, AppError> {
        saveApprovedPostingSync(
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocations,
            recurringId: recurringId,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            taxAmount: taxAmount,
            taxCodeId: taxCodeId,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyId: counterpartyId,
            counterparty: counterparty,
            candidateSource: candidateSource
        )
    }

    func approvePostingCandidate(
        candidateId: UUID,
        description: String? = nil
    ) async throws -> (journal: CanonicalJournalEntry, candidate: PostingCandidate) {
        guard try await postingWorkflowUseCase.candidate(candidateId) != nil else {
            let error = AppError.invalidInput(message: "承認対象の候補が見つかりません")
            lastError = error
            throw error
        }

        let journal = try await postingWorkflowUseCase.approveCandidate(
            candidateId: candidateId,
            description: description
        )
        guard let approvedCandidate = try await postingWorkflowUseCase.candidate(candidateId) else {
            let error = AppError.invalidInput(message: "承認後の候補を再取得できませんでした")
            lastError = error
            throw error
        }

        refreshTransactions()
        refreshJournalEntries()
        refreshJournalLines()
        lastError = nil
        return (journal, approvedCandidate)
    }

    private func syncCanonicalCounterpartyNow(
        id explicitId: UUID?,
        named rawName: String?,
        defaultTaxCodeId: String?
    ) -> CanonicalCounterpartySyncStatus {
        do {
            let resolved = resolveLegacyCounterpartyReference(
                explicitId: explicitId,
                rawName: rawName,
                defaultTaxCodeId: defaultTaxCodeId
            )
            guard let counterpartyId = resolved.id else {
                if explicitId != nil || businessProfile == nil {
                    return .skippedBusinessProfileUnavailable
                }
                return .skippedBlankName
            }
            try modelContext.save()
            return .synced(counterpartyId)
        } catch {
            AppLogger.dataStore.warning("Canonical counterparty sync failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private func syncCanonicalCounterparty(
        id explicitId: UUID?,
        named rawName: String?,
        defaultTaxCodeId: String?
    ) async -> CanonicalCounterpartySyncStatus {
        syncCanonicalCounterpartyNow(
            id: explicitId,
            named: rawName,
            defaultTaxCodeId: defaultTaxCodeId
        )
    }

    private func stableCounterpartyId(businessId: UUID, displayName: String) -> UUID {
        let normalizedName = displayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let seed = "\(businessId.uuidString.lowercased())|\(normalizedName)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }

    private func syncCanonicalPosting(
        for transaction: PPTransaction,
        counterpartyId: UUID?,
        source: CandidateSource?
    ) async -> CanonicalPostingSyncStatus {
        syncCanonicalAccountsFromLegacyAccountsIfNeeded()
        let posting: CanonicalTransactionPostingBridge.Posting
        do {
            posting = try buildCanonicalPosting(
                for: transaction,
                counterpartyId: counterpartyId,
                source: source ?? .manual
            )
        } catch AppError.invalidInput(let message)
            where message.contains("事業者プロフィールが未設定") {
            return .skippedBusinessProfileUnavailable
        } catch AppError.yearLocked {
            return .skippedBusinessProfileUnavailable
        } catch {
            return .skippedLegacyJournalUnavailable
        }

        do {
            let journal = try await canonicalPostingSupport.syncApprovedCandidate(
                posting: posting,
                allocationAmounts: transaction.allocations.filter { $0.amount > 0 },
                actor: source == .importFile ? "user" : "system"
            )
            if transaction.journalEntryId != journal.id {
                transaction.journalEntryId = journal.id
                save()
                refreshTransactions()
            }
            return .synced(candidateId: posting.candidate.id, journalId: journal.id)
        } catch {
            AppLogger.dataStore.warning("Canonical posting sync failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private func buildCanonicalPosting(
        for transaction: PPTransaction,
        counterpartyId: UUID?,
        source: CandidateSource
    ) throws -> CanonicalTransactionPostingBridge.Posting {
        try canonicalPostingSupport.buildApprovedPosting(
            seed: CanonicalPostingSeed(
                id: transaction.id,
                type: transaction.type,
                amount: transaction.amount,
                date: transaction.date,
                categoryId: transaction.categoryId,
                memo: transaction.memo,
                recurringId: transaction.recurringId,
                paymentAccountId: transaction.paymentAccountId,
                transferToAccountId: transaction.transferToAccountId,
                taxDeductibleRate: transaction.taxDeductibleRate,
                taxAmount: transaction.taxAmount,
                taxCodeId: transaction.taxCodeId,
                taxRate: transaction.taxRate,
                isTaxIncluded: transaction.isTaxIncluded,
                taxCategory: transaction.taxCategory,
                receiptImagePath: transaction.receiptImagePath,
                lineItems: transaction.lineItems,
                counterpartyId: counterpartyId,
                counterpartyName: transaction.counterparty,
                source: source,
                createdAt: transaction.createdAt,
                updatedAt: transaction.updatedAt,
                journalEntryId: transaction.journalEntryId
            ),
            snapshot: try canonicalPostingSupport.snapshot()
        )
    }

    /// レガシー `receiptImagePath` を法定書類台帳 (`PPDocumentRecord`) へバックフィルする。
    /// 冪等性を担保するため、同一 transactionId + originalFileName の既存レコードがあれば再作成しない。
    private func migrateLegacyReceiptImagesToDocumentRecords() {
        let legacyTransactions = transactions.filter {
            guard let path = $0.receiptImagePath else { return false }
            return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !legacyTransactions.isEmpty else { return }

        let existingRecords: [PPDocumentRecord]
        do {
            existingRecords = try modelContext.fetch(FetchDescriptor<PPDocumentRecord>())
        } catch {
            AppLogger.dataStore.warning("Legacy receipt migration skipped: document model unavailable (\(error.localizedDescription))")
            return
        }

        let existingKeys = Set(
            existingRecords.compactMap { record -> String? in
                guard record.documentType == .receipt,
                      let transactionId = record.transactionId else { return nil }
                return "\(transactionId.uuidString)|\(record.originalFileName)"
            }
        )
        let existingReceiptTransactionIds = Set(
            existingRecords.compactMap { record -> UUID? in
                guard record.documentType == .receipt else { return nil }
                return record.transactionId
            }
        )

        var changed = false
        var migratedCount = 0
        var alreadyBackfilledCount = 0
        var missingFileCount = 0
        var newDocumentFiles: [String] = []
        var legacyFilesToDelete: [String] = []
        let now = Date()

        for transaction in legacyTransactions {
            guard let legacyPath = transaction.receiptImagePath,
                  let safeLegacyPath = ReceiptImageStore.sanitizedFileName(legacyPath)
            else {
                continue
            }

            let key = "\(transaction.id.uuidString)|\(safeLegacyPath)"
            if existingKeys.contains(key) || existingReceiptTransactionIds.contains(transaction.id) {
                transaction.receiptImagePath = nil
                transaction.updatedAt = now
                legacyFilesToDelete.append(safeLegacyPath)
                changed = true
                alreadyBackfilledCount += 1
                continue
            }

            guard let imageData = ReceiptImageStore.loadImageData(fileName: safeLegacyPath) else {
                missingFileCount += 1
                AppLogger.dataStore.warning("Legacy receipt migration skipped: file missing for transaction=\(transaction.id.uuidString)")
                continue
            }

            do {
                let storedFileName = try ReceiptImageStore.saveDocumentData(imageData, originalFileName: safeLegacyPath)
                let record = PPDocumentRecord(
                    transactionId: transaction.id,
                    documentType: .receipt,
                    storedFileName: storedFileName,
                    originalFileName: safeLegacyPath,
                    mimeType: "image/jpeg",
                    fileSize: imageData.count,
                    contentHash: ReceiptImageStore.sha256Hex(data: imageData),
                    issueDate: transaction.date,
                    note: "legacy-receipt-backfill",
                    createdAt: now,
                    updatedAt: now
                )
                modelContext.insert(record)
                transaction.receiptImagePath = nil
                transaction.updatedAt = now
                newDocumentFiles.append(storedFileName)
                legacyFilesToDelete.append(safeLegacyPath)
                migratedCount += 1
                changed = true
            } catch {
                AppLogger.dataStore.error("Legacy receipt migration failed: transaction=\(transaction.id.uuidString), error=\(error.localizedDescription)")
            }
        }

        guard changed else {
            if missingFileCount > 0 {
                AppLogger.dataStore.warning("Legacy receipt migration completed with missing files: \(missingFileCount)件")
            }
            return
        }

        if save() {
            for fileName in legacyFilesToDelete {
                ReceiptImageStore.deleteImage(fileName: fileName)
            }
            AppLogger.dataStore.info("Legacy receipt migration done: migrated=\(migratedCount), alreadyBackfilled=\(alreadyBackfilledCount), missing=\(missingFileCount)")
        } else {
            for fileName in newDocumentFiles {
                ReceiptImageStore.deleteDocumentFile(fileName: fileName)
            }
            AppLogger.dataStore.error("Legacy receipt migration rolled back due to save failure")
        }
    }

    func seedDefaultCategories() {
        for cat in DEFAULT_CATEGORIES {
            let category = PPCategory(
                id: cat.id,
                name: cat.name,
                type: cat.type,
                icon: cat.icon,
                isDefault: true
            )
            modelContext.insert(category)
        }
        save()
        refreshCategories()
    }

    /// Add any new default categories that don't exist yet (for app updates)
    private func seedMissingCategories() {
        let existingIds = Set(categories.map(\.id))
        var added = false
        for cat in DEFAULT_CATEGORIES where !existingIds.contains(cat.id) {
            let category = PPCategory(
                id: cat.id,
                name: cat.name,
                type: cat.type,
                icon: cat.icon,
                isDefault: true
            )
            modelContext.insert(category)
            added = true
        }
        if added {
            save()
            refreshCategories()
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            AppLogger.dataStore.error("Save failed: \(error.localizedDescription)")
            modelContext.rollback()
            lastError = .saveFailed(underlying: error)
            refreshProjects()
            refreshTransactions()
            refreshCategories()
            refreshRecurring()
            refreshAccounts()
            refreshJournalEntries()
            refreshJournalLines()
            refreshFixedAssets()
            refreshInventoryRecords()
            return false
        }
    }

    func refreshProjects() {
        do {
            let descriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            projects = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh projects: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    func refreshTransactions() {
        do {
            let descriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            allTransactions = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh transactions: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    func refreshCategories() {
        do {
            let descriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\.name)])
            categories = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh categories: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    func refreshRecurring() {
        do {
            let descriptor = FetchDescriptor<PPRecurringTransaction>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            recurringTransactions = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh recurring: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    private func refreshAccounts() {
        do {
            let descriptor = FetchDescriptor<PPAccount>(sortBy: [SortDescriptor(\.displayOrder)])
            accounts = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh accounts: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    func refreshJournalEntries() {
        do {
            let descriptor = FetchDescriptor<PPJournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            journalEntries = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh journal entries: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    func refreshJournalLines() {
        do {
            let descriptor = FetchDescriptor<PPJournalLine>(sortBy: [SortDescriptor(\.displayOrder)])
            journalLines = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh journal lines: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    func refreshFixedAssets() {
        do {
            let descriptor = FetchDescriptor<PPFixedAsset>(sortBy: [SortDescriptor(\.acquisitionDate, order: .reverse)])
            fixedAssets = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh fixed assets: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    /// 既存ユーザーに新しいデフォルト勘定科目を追加する（冪等）
    func seedMissingDefaultAccounts() {
        let existingIds = Set(accounts.map(\.id))
        var added = false
        for def in AccountingConstants.defaultAccounts where !existingIds.contains(def.id) {
            let account = PPAccount(
                id: def.id, code: def.code, name: def.name,
                accountType: def.accountType, normalBalance: def.normalBalance,
                subtype: def.subtype, isSystem: true, displayOrder: def.displayOrder
            )
            modelContext.insert(account)
            added = true
        }
        if added {
            save()
            refreshAccounts()
        }
    }

    // MARK: - Project CRUD

#if DEBUG
    @discardableResult
    func addProject(name: String, description: String, startDate: Date? = nil, plannedEndDate: Date? = nil) -> PPProject {
        let project = projectWorkflowUseCase.createProject(
            input: ProjectUpsertInput(
                name: name,
                description: description,
                status: .active,
                startDate: startDate,
                completedAt: nil,
                plannedEndDate: plannedEndDate
            )
        )
        loadData()
        return project
    }

    func updateProject(id: UUID, name: String? = nil, description: String? = nil, status: ProjectStatus? = nil, startDate: Date?? = nil, completedAt: Date?? = nil, plannedEndDate: Date?? = nil) {
        guard let project = projects.first(where: { $0.id == id }) else { return }

        let resolvedStatus = status ?? project.status
        let resolvedStartDate: Date? = {
            if let startDate {
                return startDate
            }
            return project.startDate
        }()

        let resolvedCompletedAt: Date? = {
            if let completedAt {
                return completedAt
            }
            if resolvedStatus == .completed {
                return project.completedAt ?? Date()
            }
            return nil
        }()

        let resolvedPlannedEndDate: Date? = {
            if let plannedEndDate {
                return plannedEndDate
            }
            return project.plannedEndDate
        }()

        projectWorkflowUseCase.updateProject(
            id: id,
            input: ProjectUpsertInput(
                name: name ?? project.name,
                description: description ?? project.projectDescription,
                status: resolvedStatus,
                startDate: resolvedStartDate,
                completedAt: resolvedCompletedAt,
                plannedEndDate: resolvedPlannedEndDate
            )
        )
        loadData()
    }

    // MARK: - Archive / Unarchive

    func projectHasHistoricalReferences(_ id: UUID) -> Bool {
        if transactions.contains(where: { transaction in
            transaction.allocations.contains { $0.projectId == id }
        }) {
            return true
        }

        return canonicalJournalEntries().contains { journal in
            journal.lines.contains { $0.projectAllocationId == id }
        }
    }

    /// H9: トランザクション参照がある場合はアーカイブ（ソフトデリート）
    func archiveProject(id: UUID) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        project.isArchived = true
        project.updatedAt = Date()

        // H10+H9: アーカイブ対象プロジェクトを参照する equalAll トランザクションの手動編集フラグをクリア
        // → reprocessEqualAllCurrentPeriodTransactions で正しく再計算されるようにする
        for transaction in transactions {
            guard transaction.isManuallyEdited == true,
                  transaction.allocations.contains(where: { $0.projectId == id }),
                  let recurringId = transaction.recurringId,
                  let recurring = recurringTransactions.first(where: { $0.id == recurringId }),
                  recurring.allocationMode == .equalAll
            else { continue }
            transaction.isManuallyEdited = nil
        }

        // アーカイブ済みプロジェクトを定期取引から除外
        let now = Date()
        for recurring in recurringTransactions {
            let filtered = recurring.allocations.filter { $0.projectId != id }
            if filtered.count != recurring.allocations.count {
                if filtered.isEmpty && recurring.allocationMode == .manual {
                    // ダングリング recurringId 参照をクリア（deleteRecurring と同様）
                    for transaction in transactions where transaction.recurringId == recurring.id {
                        transaction.recurringId = nil
                        transaction.updatedAt = now
                    }
                    modelContext.delete(recurring)
                } else if !filtered.isEmpty {
                    recurring.allocations = redistributeAllocations(
                        totalAmount: recurring.amount,
                        remainingAllocations: filtered
                    )
                }
            }
        }

        save()
        refreshProjects()
        refreshRecurring()
        reprocessEqualAllCurrentPeriodTransactions()
        refreshTransactions()
    }

    func unarchiveProject(id: UUID) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        project.isArchived = nil
        project.updatedAt = Date()
        save()
        refreshProjects()
        reprocessEqualAllCurrentPeriodTransactions()
        refreshTransactions()
    }

    /// H9: トランザクション参照ありならアーカイブ、なしならハードデリート
    func deleteProject(id: UUID) {
        projectWorkflowUseCase.deleteProject(id: id)
        loadData()
    }

    func deleteProjects(ids: Set<UUID>) {
        projectWorkflowUseCase.deleteProjects(ids: ids)
        loadData()
    }
#endif

    func getProject(id: UUID) -> PPProject? {
        projects.first { $0.id == id }
    }

    func removeReceiptImage(transactionId: UUID) {
        guard let transaction = transactions.first(where: { $0.id == transactionId }) else { return }
        // C4: save成功後に削除するため画像パスを保持
        let imageToDelete = transaction.receiptImagePath
        transaction.receiptImagePath = nil
        transaction.updatedAt = Date()
        if save() {
            if let imagePath = imageToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
        }
        refreshTransactions()
    }

    func getTransaction(id: UUID) -> PPTransaction? {
        transactions.first { $0.id == id }
    }

    // MARK: - Category CRUD

    @discardableResult
    func addCategory(name: String, type: CategoryType, icon: String) -> PPCategory {
        let category = CategoryWorkflowUseCase(modelContext: modelContext).createCategory(
            input: CategoryCreateInput(name: name, type: type, icon: icon)
        )
        refreshCategories()
        return category
    }

    func updateCategory(id: String, name: String? = nil, type: CategoryType? = nil, icon: String? = nil) {
        if CategoryWorkflowUseCase(modelContext: modelContext).updateCategory(
            id: id,
            input: CategoryUpdateInput(name: name, type: type, icon: icon)
        ) {
            refreshCategories()
        }
    }

    func updateCategoryLinkedAccount(categoryId: String, accountId: String?) {
        if CategoryWorkflowUseCase(modelContext: modelContext).updateLinkedAccount(
            categoryId: categoryId,
            accountId: accountId
        ) {
            refreshCategories()
        }
    }

    func deleteCategory(id: String) {
        if CategoryWorkflowUseCase(modelContext: modelContext).deleteCategory(id: id) {
            refreshCategories()
            refreshTransactions()
            refreshRecurring()
        }
    }

    func getCategory(id: String) -> PPCategory? {
        categories.first { $0.id == id }
    }

    func getRecurring(id: UUID) -> PPRecurringTransaction? {
        recurringTransactions.first { $0.id == id }
    }

    // MARK: - Pro-Rata Reallocation

    /// equalAll定期取引の今期分トランザクションを、現在のアクティブプロジェクト一覧で再分配する
    func reprocessEqualAllCurrentPeriodTransactions() {
        let calendar = Calendar.current
        let today = todayDate()
        let todayComps = calendar.dateComponents([.year, .month], from: today)

        for recurring in recurringTransactions {
            guard recurring.isActive,
                  recurring.allocationMode == .equalAll
            else { continue }

            // この定期取引が生成した今期のトランザクションを検索
            guard let latestTx = transactions
                .filter({ $0.recurringId == recurring.id })
                .sorted(by: { $0.date > $1.date })
                .first
            else { continue }

            // H10: ユーザーが手動編集済みのトランザクションはスキップ
            guard latestTx.isManuallyEdited != true else { continue }

            let txComps = calendar.dateComponents([.year, .month], from: latestTx.date)
            let isCurrentPeriod: Bool
            if recurring.frequency == .monthly {
                isCurrentPeriod = txComps.year == todayComps.year && txComps.month == todayComps.month
            } else {
                isCurrentPeriod = txComps.year == todayComps.year
            }
            guard isCurrentPeriod else { continue }

            // 現在のアクティブプロジェクト一覧でアロケーションを再計算（H9: アーカイブ済み除外）
            let activeProjectIds = projects.filter { $0.status == .active && $0.isArchived != true }.map(\.id)
            let completedThisPeriod = projects.filter { p in
                guard p.status == .completed, p.isArchived != true, let completedAt = p.completedAt else { return false }
                let compComps = calendar.dateComponents([.year, .month], from: completedAt)
                return compComps.year == txComps.year && compComps.month == txComps.month
            }
            let allEligibleIds = activeProjectIds + completedThisPeriod.map(\.id)
            guard !allEligibleIds.isEmpty else { continue }

            var newAllocations = calculateEqualSplitAllocations(amount: recurring.amount, projectIds: allEligibleIds)

            // 日割り適用
            let isYearly = recurring.frequency == .yearly
            if let txYear = txComps.year, let txMonth = txComps.month {
                let totalDays = isYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
                let needsProRata = newAllocations.contains { alloc in
                    guard let project = projects.first(where: { $0.id == alloc.projectId }) else { return false }
                    let activeDays = isYearly
                        ? calculateActiveDaysInYear(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear)
                        : calculateActiveDaysInMonth(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear, month: txMonth)
                    return activeDays < totalDays
                }
                if needsProRata {
                    let inputs: [HolisticProRataInput] = newAllocations.map { alloc in
                        let project = projects.first { $0.id == alloc.projectId }
                        let activeDays = isYearly
                            ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                            : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                        return HolisticProRataInput(projectId: alloc.projectId, ratio: alloc.ratio, activeDays: activeDays)
                    }
                    newAllocations = calculateHolisticProRata(
                        totalAmount: recurring.amount,
                        totalDays: totalDays,
                        inputs: inputs
                    )
                }
            }

            latestTx.allocations = newAllocations
            latestTx.updatedAt = Date()
        }

        guard let businessId = businessProfile?.id else {
            save()
            return
        }

        let recurringJournals = canonicalJournalEntries().filter { $0.entryType == .recurring }
        let candidateIds = Set(recurringJournals.compactMap(\.sourceCandidateId))
        let candidatesById = fetchPostingCandidates(ids: candidateIds)

        for recurring in recurringTransactions {
            guard recurring.isActive,
                  recurring.allocationMode == .equalAll
            else { continue }

            guard let latestPosting = recurringJournals
                .compactMap({ journal -> (journal: CanonicalJournalEntry, candidate: PostingCandidate)? in
                    guard let candidateId = journal.sourceCandidateId,
                          let candidate = candidatesById[candidateId],
                          candidate.legacySnapshot?.recurringId == recurring.id else {
                        return nil
                    }
                    return (journal, candidate)
                })
                .sorted(by: { $0.journal.journalDate > $1.journal.journalDate })
                .first
            else {
                continue
            }

            let txComps = calendar.dateComponents([.year, .month], from: latestPosting.journal.journalDate)
            let isCurrentPeriod: Bool
            if recurring.frequency == .monthly {
                isCurrentPeriod = txComps.year == todayComps.year && txComps.month == todayComps.month
            } else {
                isCurrentPeriod = txComps.year == todayComps.year
            }
            guard isCurrentPeriod else { continue }

            let activeProjectIds = projects.filter { $0.status == .active && $0.isArchived != true }.map(\.id)
            let completedThisPeriod = projects.filter { project in
                guard project.status == .completed,
                      project.isArchived != true,
                      let completedAt = project.completedAt else {
                    return false
                }
                let compComps = calendar.dateComponents([.year, .month], from: completedAt)
                return compComps.year == txComps.year && compComps.month == txComps.month
            }
            let allEligibleIds = activeProjectIds + completedThisPeriod.map(\.id)
            guard !allEligibleIds.isEmpty else { continue }

            var newAllocations = calculateEqualSplitAllocations(amount: recurring.amount, projectIds: allEligibleIds)

            let isYearly = recurring.frequency == .yearly
            if let txYear = txComps.year, let txMonth = txComps.month {
                let totalDays = isYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
                let needsProRata = newAllocations.contains { allocation in
                    guard let project = projects.first(where: { $0.id == allocation.projectId }) else { return false }
                    let activeDays = isYearly
                        ? calculateActiveDaysInYear(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear)
                        : calculateActiveDaysInMonth(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear, month: txMonth)
                    return activeDays < totalDays
                }
                if needsProRata {
                    let inputs: [HolisticProRataInput] = newAllocations.map { allocation in
                        let project = projects.first { $0.id == allocation.projectId }
                        let activeDays = isYearly
                            ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                            : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                        return HolisticProRataInput(projectId: allocation.projectId, ratio: allocation.ratio, activeDays: activeDays)
                    }
                    newAllocations = calculateHolisticProRata(
                        totalAmount: recurring.amount,
                        totalDays: totalDays,
                        inputs: inputs
                    )
                }
            }

            let snapshot = CanonicalTransactionPostingBridge.TransactionSnapshot(
                id: latestPosting.candidate.id,
                type: recurring.type,
                amount: recurring.amount,
                date: latestPosting.journal.journalDate,
                categoryId: recurring.categoryId,
                memo: latestPosting.journal.description,
                recurringId: recurring.id,
                paymentAccountId: recurring.paymentAccountId,
                transferToAccountId: recurring.transferToAccountId,
                taxDeductibleRate: recurring.taxDeductibleRate,
                taxAmount: nil,
                taxCodeId: nil,
                taxRate: nil,
                isTaxIncluded: nil,
                taxCategory: nil,
                counterpartyName: recurring.counterparty,
                createdAt: latestPosting.candidate.createdAt,
                updatedAt: Date(),
                journalEntryId: latestPosting.journal.id
            )
            let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)
            guard let posting = bridge.buildApprovedPosting(
                for: snapshot,
                businessId: businessId,
                counterpartyId: latestPosting.candidate.counterpartyId,
                source: .recurring,
                categories: categories,
                legacyAccounts: accounts
            ) else {
                continue
            }

            do {
                _ = try saveApprovedPostingSynchronously(
                    posting,
                    allocations: newAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) },
                    actor: "system"
                )
            } catch {
                AppLogger.dataStore.warning("Failed to reprocess canonical equalAll posting: \(error.localizedDescription)")
            }
        }
        save()
    }

    /// H8: トランザクションの金額/アロケーション変更後、pro-rata調整を再適用する
    private func reapplyProRataIfNeeded(transaction: PPTransaction, amount: Int) {
        let calendar = Calendar.current
        let txComps = calendar.dateComponents([.year, .month], from: transaction.date)
        guard let txYear = txComps.year, let txMonth = txComps.month else { return }

        let isYearly = transaction.recurringId.flatMap { rid in
            recurringTransactions.first { $0.id == rid }
        }.map { $0.frequency == .yearly } ?? false

        let totalDays = isYearly
            ? daysInYear(txYear)
            : daysInMonth(year: txYear, month: txMonth)

        let needsProRata = transaction.allocations.contains { alloc in
            guard let project = projects.first(where: { $0.id == alloc.projectId }) else { return false }
            let activeDays = isYearly
                ? calculateActiveDaysInYear(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear)
                : calculateActiveDaysInMonth(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear, month: txMonth)
            return activeDays < totalDays
        }
        guard needsProRata else { return }

        let inputs: [HolisticProRataInput] = transaction.allocations.map { alloc in
            let project = projects.first { $0.id == alloc.projectId }
            let activeDays = isYearly
                ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
            return HolisticProRataInput(projectId: alloc.projectId, ratio: alloc.ratio, activeDays: activeDays)
        }
        transaction.allocations = calculateHolisticProRata(
            totalAmount: amount,
            totalDays: totalDays,
            inputs: inputs
        )
    }

    /// 完了状態が解除された場合、日割り済みアロケーションを元の比率ベースに復元する
    func reverseCompletionAllocations(projectId: UUID) {
        for transaction in transactions {
            guard transaction.allocations.contains(where: { $0.projectId == projectId }) else { continue }
            let restored = recalculateAllocationAmounts(amount: transaction.amount, existingAllocations: transaction.allocations)
            transaction.allocations = restored
            transaction.updatedAt = Date()
        }
        save()
    }

    /// 1つの取引に対して、全プロジェクトのactiveDaysを収集し一括日割り計算する
    func recalculateAllocationsForTransaction(_ transaction: PPTransaction, isYearly: Bool = false) {
        let calendar = Calendar.current
        let txComps = calendar.dateComponents([.year, .month], from: transaction.date)
        guard let txYear = txComps.year, let txMonth = txComps.month else { return }

        let totalDays = isYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)

        let inputs: [HolisticProRataInput] = transaction.allocations.map { alloc in
            let project = projects.first { $0.id == alloc.projectId }
            let activeDays: Int
            if isYearly {
                activeDays = calculateActiveDaysInYear(
                    startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear
                )
            } else {
                activeDays = calculateActiveDaysInMonth(
                    startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth
                )
            }
            return HolisticProRataInput(projectId: alloc.projectId, ratio: alloc.ratio, activeDays: activeDays)
        }

        // 全プロジェクトがフル稼働なら変更不要
        let allFullDays = inputs.allSatisfy { $0.activeDays >= totalDays }
        if allFullDays { return }

        let newAllocations = calculateHolisticProRata(
            totalAmount: transaction.amount,
            totalDays: totalDays,
            inputs: inputs
        )
        transaction.allocations = newAllocations
        transaction.updatedAt = Date()
    }

    /// プロジェクトの開始日/完了日/予定完了日に基づいて取引を日割り再分配する
    func recalculateAllocationsForProject(projectId: UUID) {
        guard let project = getProject(id: projectId),
              project.startDate != nil || project.effectiveEndDate != nil
        else { return }

        for transaction in transactions {
            guard transaction.allocations.contains(where: { $0.projectId == projectId }) else { continue }
            let isYearly = transaction.recurringId.flatMap { rid in
                recurringTransactions.first { $0.id == rid }
            }.map { $0.frequency == .yearly } ?? false
            recalculateAllocationsForTransaction(transaction, isYearly: isYearly)
        }

        guard let businessId = businessProfile?.id else {
            save()
            return
        }

        let recurringJournals = canonicalJournalEntries().filter { $0.entryType == .recurring }
        let candidateIds = Set(recurringJournals.compactMap(\.sourceCandidateId))
        let candidatesById = fetchPostingCandidates(ids: candidateIds)

        for recurringJournal in recurringJournals {
            guard let candidateId = recurringJournal.sourceCandidateId,
                  let candidate = candidatesById[candidateId],
                  let snapshot = candidate.legacySnapshot,
                  let recurringId = snapshot.recurringId,
                  let recurring = recurringTransactions.first(where: { $0.id == recurringId }),
                  candidate.proposedLines.contains(where: { $0.projectAllocationId == projectId }) else {
                continue
            }

            let isMonthlySpread = recurringJournal.description.hasPrefix("[定期/月次]")
            let candidateAmount = candidate.proposedLines.reduce(0) { partialResult, line in
                switch snapshot.type {
                case .income:
                    guard line.creditAccountId != nil else { return partialResult }
                case .expense:
                    guard line.debitAccountId != nil else { return partialResult }
                case .transfer:
                    return partialResult
                }
                return partialResult + NSDecimalNumber(decimal: line.amount).intValue
            }
            guard let newAllocations = recurringAllocations(
                for: recurring,
                amount: candidateAmount,
                txDate: recurringJournal.journalDate,
                treatAsYearly: recurring.frequency == .yearly && !isMonthlySpread
            ) else {
                continue
            }

            let updatedSnapshot = CanonicalTransactionPostingBridge.TransactionSnapshot(
                id: candidate.id,
                type: snapshot.type,
                amount: candidateAmount,
                date: recurringJournal.journalDate,
                categoryId: snapshot.categoryId,
                memo: recurringJournal.description,
                recurringId: snapshot.recurringId,
                paymentAccountId: snapshot.paymentAccountId,
                transferToAccountId: snapshot.transferToAccountId,
                taxDeductibleRate: snapshot.taxDeductibleRate,
                taxAmount: snapshot.taxAmount,
                taxCodeId: snapshot.taxCodeId,
                taxRate: snapshot.taxRate,
                isTaxIncluded: snapshot.isTaxIncluded,
                taxCategory: snapshot.taxCategory,
                receiptImagePath: snapshot.receiptImagePath,
                lineItems: snapshot.lineItems,
                counterpartyName: snapshot.counterpartyName,
                createdAt: candidate.createdAt,
                updatedAt: Date(),
                journalEntryId: recurringJournal.id
            )
            let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)
            guard let posting = bridge.buildApprovedPosting(
                for: updatedSnapshot,
                businessId: businessId,
                counterpartyId: candidate.counterpartyId,
                source: .recurring,
                categories: categories,
                legacyAccounts: accounts
            ) else {
                continue
            }

            do {
                _ = try saveApprovedPostingSynchronously(
                    posting,
                    allocationAmounts: newAllocations,
                    actor: "system"
                )
            } catch {
                AppLogger.dataStore.warning("Failed to recalculate canonical recurring allocations for project \(projectId.uuidString): \(error.localizedDescription)")
            }
        }

        save()
    }

    /// アプリ起動時に開始日/完了日/予定完了日を持つプロジェクトのアロケーションを再計算する
    func recalculateAllPartialPeriodProjects() {
        let partialProjects = projects.filter { $0.startDate != nil || ($0.status == .completed && $0.completedAt != nil) || $0.plannedEndDate != nil }
        guard !partialProjects.isEmpty else { return }

        // 取引単位で処理（各取引は1回だけ処理）
        let partialProjectIds = Set(partialProjects.map(\.id))
        var processedIds = Set<UUID>()
        for transaction in transactions {
            guard !processedIds.contains(transaction.id) else { continue }
            let hasPartialProject = transaction.allocations.contains { partialProjectIds.contains($0.projectId) }
            guard hasPartialProject else { continue }
            let isYearly = transaction.recurringId.flatMap { rid in
                recurringTransactions.first { $0.id == rid }
            }.map { $0.frequency == .yearly } ?? false
            recalculateAllocationsForTransaction(transaction, isYearly: isYearly)
            processedIds.insert(transaction.id)
        }
        save()
        refreshTransactions()
    }

    // MARK: - Process Recurring Transactions

    private struct RecurringDueOccurrence {
        let recurringId: UUID
        let scheduledDate: Date
        let amount: Int
        let previewMemo: String
        let postingMemo: String
        let categoryId: String
        let isMonthlySpread: Bool
        let monthKey: String?
        let projectName: String?
        let allocationMode: AllocationMode
        let isSkipped: Bool
        let isYearLocked: Bool
    }

    private func recurringProjectName(_ recurring: PPRecurringTransaction) -> String? {
        recurring.allocations.first.flatMap { allocation in
            projects.first(where: { $0.id == allocation.projectId })?.name
        }
    }

    private func recurringPostingMemo(for recurring: PPRecurringTransaction, isMonthlySpread: Bool) -> String {
        let prefix = isMonthlySpread ? "[定期/月次]" : "[定期]"
        return "\(prefix) \(recurring.name)" + (recurring.memo.isEmpty ? "" : " - \(recurring.memo)")
    }

    private func recurringPreviewMemo(for recurring: PPRecurringTransaction, isMonthlySpread: Bool) -> String {
        let prefix = isMonthlySpread ? "[定期/月次]" : "[定期]"
        return "\(prefix) \(recurring.name)"
    }

    private func monthlySpreadEligibleRemainderMonth(
        recurring: PPRecurringTransaction,
        year: Int,
        calendar: Calendar
    ) -> Int? {
        let startMonth = recurring.monthOfYear ?? 1
        var lastEligibleMonth = 12

        if let endDate = recurring.endDate {
            for month in stride(from: 12, through: startMonth, by: -1) {
                if let date = calendar.date(from: DateComponents(year: year, month: month, day: recurring.dayOfMonth)),
                   date <= endDate {
                    lastEligibleMonth = month
                    break
                }
                if month == startMonth {
                    lastEligibleMonth = startMonth
                }
            }
        }

        for month in stride(from: lastEligibleMonth, through: startMonth, by: -1) {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: recurring.dayOfMonth)) else {
                continue
            }
            if !recurring.skipDates.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                return month
            }
        }
        return nil
    }

    private func dueRecurringOccurrences(on today: Date = todayDate()) -> [RecurringDueOccurrence] {
        let calendar = Calendar.current
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentYear = todayComponents.year,
              let currentMonth = todayComponents.month,
              let currentDay = todayComponents.day else {
            return []
        }

        var occurrences: [RecurringDueOccurrence] = []

        for recurring in recurringTransactions {
            guard recurring.isActive else { continue }
            if recurring.allocationMode == .manual && recurring.allocations.isEmpty { continue }

            let projectName = recurringProjectName(recurring)

            if recurring.frequency == .monthly {
                var iterYear: Int
                var iterMonth: Int

                if let lastGen = recurring.lastGeneratedDate {
                    let lastComponents = calendar.dateComponents([.year, .month], from: lastGen)
                    iterYear = lastComponents.year ?? currentYear
                    iterMonth = (lastComponents.month ?? currentMonth) + 1
                    if iterMonth > 12 {
                        iterMonth = 1
                        iterYear += 1
                    }
                } else {
                    iterYear = currentYear
                    iterMonth = currentMonth
                }

                while iterYear < currentYear || (iterYear == currentYear && iterMonth <= currentMonth) {
                    if iterYear == currentYear && iterMonth == currentMonth && currentDay < recurring.dayOfMonth {
                        break
                    }

                    guard let scheduledDate = calendar.date(from: DateComponents(year: iterYear, month: iterMonth, day: recurring.dayOfMonth)) else {
                        iterMonth += 1
                        if iterMonth > 12 {
                            iterMonth = 1
                            iterYear += 1
                        }
                        continue
                    }

                    if let endDate = recurring.endDate, scheduledDate > endDate {
                        break
                    }

                    occurrences.append(
                        RecurringDueOccurrence(
                            recurringId: recurring.id,
                            scheduledDate: scheduledDate,
                            amount: recurring.amount,
                            previewMemo: recurringPreviewMemo(for: recurring, isMonthlySpread: false),
                            postingMemo: recurringPostingMemo(for: recurring, isMonthlySpread: false),
                            categoryId: recurring.categoryId,
                            isMonthlySpread: false,
                            monthKey: nil,
                            projectName: projectName,
                            allocationMode: recurring.allocationMode,
                            isSkipped: recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: scheduledDate) },
                            isYearLocked: isYearLocked(for: scheduledDate)
                        )
                    )

                    iterMonth += 1
                    if iterMonth > 12 {
                        iterMonth = 1
                        iterYear += 1
                    }
                }
                continue
            }

            if recurring.yearlyAmortizationMode == .monthlySpread {
                if let endDate = recurring.endDate, today > endDate {
                    continue
                }

                let startMonth = recurring.monthOfYear ?? 1
                let actualMonthCount = 12 - startMonth + 1
                let monthlyAmount = recurring.amount / actualMonthCount
                let remainder = recurring.amount - (monthlyAmount * actualMonthCount)
                let eligibleRemainderMonth = monthlySpreadEligibleRemainderMonth(
                    recurring: recurring,
                    year: currentYear,
                    calendar: calendar
                )
                let currentYearPrefix = String(format: "%d-", currentYear)
                let generatedMonths = Set(recurring.lastGeneratedMonths.filter { $0.hasPrefix(currentYearPrefix) })

                for month in startMonth...12 {
                    guard currentMonth > month || (currentMonth == month && currentDay >= recurring.dayOfMonth) else {
                        continue
                    }
                    let monthKey = String(format: "%d-%02d", currentYear, month)
                    guard !generatedMonths.contains(monthKey) else { continue }
                    guard let scheduledDate = calendar.date(from: DateComponents(year: currentYear, month: month, day: recurring.dayOfMonth)) else {
                        continue
                    }
                    if let endDate = recurring.endDate, scheduledDate > endDate {
                        continue
                    }

                    occurrences.append(
                        RecurringDueOccurrence(
                            recurringId: recurring.id,
                            scheduledDate: scheduledDate,
                            amount: month == eligibleRemainderMonth ? monthlyAmount + remainder : monthlyAmount,
                            previewMemo: recurringPreviewMemo(for: recurring, isMonthlySpread: true),
                            postingMemo: recurringPostingMemo(for: recurring, isMonthlySpread: true),
                            categoryId: recurring.categoryId,
                            isMonthlySpread: true,
                            monthKey: monthKey,
                            projectName: projectName,
                            allocationMode: recurring.allocationMode,
                            isSkipped: recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: scheduledDate) },
                            isYearLocked: isYearLocked(for: scheduledDate)
                        )
                    )
                }
                continue
            }

            let targetMonth = recurring.monthOfYear ?? 1
            let startYear: Int
            if let lastGen = recurring.lastGeneratedDate {
                startYear = calendar.component(.year, from: lastGen) + 1
            } else {
                startYear = currentYear
            }

            guard startYear <= currentYear else { continue }
            for iterYear in startYear...currentYear {
                if iterYear == currentYear,
                   (currentMonth < targetMonth || (currentMonth == targetMonth && currentDay < recurring.dayOfMonth)) {
                    break
                }

                guard let scheduledDate = calendar.date(from: DateComponents(year: iterYear, month: targetMonth, day: recurring.dayOfMonth)) else {
                    continue
                }
                if let endDate = recurring.endDate, scheduledDate > endDate {
                    break
                }

                occurrences.append(
                    RecurringDueOccurrence(
                        recurringId: recurring.id,
                        scheduledDate: scheduledDate,
                        amount: recurring.amount,
                        previewMemo: recurringPreviewMemo(for: recurring, isMonthlySpread: false),
                        postingMemo: recurringPostingMemo(for: recurring, isMonthlySpread: false),
                        categoryId: recurring.categoryId,
                        isMonthlySpread: false,
                        monthKey: nil,
                        projectName: projectName,
                        allocationMode: recurring.allocationMode,
                        isSkipped: recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: scheduledDate) },
                        isYearLocked: isYearLocked(for: scheduledDate)
                    )
                )
            }
        }

        return occurrences.sorted { lhs, rhs in
            if lhs.scheduledDate == rhs.scheduledDate {
                return lhs.recurringId.uuidString < rhs.recurringId.uuidString
            }
            return lhs.scheduledDate < rhs.scheduledDate
        }
    }

    private func recurringAllocations(
        for recurring: PPRecurringTransaction,
        amount: Int,
        txDate: Date,
        treatAsYearly: Bool
    ) -> [Allocation]? {
        let calendar = Calendar.current
        var resolvedAllocations: [Allocation]

        switch recurring.allocationMode {
        case .equalAll:
            let activeProjectIds = projects.filter { $0.status == .active && $0.isArchived != true }.map(\.id)
            let completedInPeriod = projects.filter { project in
                guard project.status == .completed,
                      project.isArchived != true,
                      let completedAt = project.completedAt else {
                    return false
                }
                let completedComponents = calendar.dateComponents([.year, .month], from: completedAt)
                let txComponents = calendar.dateComponents([.year, .month], from: txDate)
                return completedComponents.year == txComponents.year && completedComponents.month == txComponents.month
            }
            let projectIds = activeProjectIds + completedInPeriod.map(\.id)
            guard !projectIds.isEmpty else { return nil }
            resolvedAllocations = calculateEqualSplitAllocations(amount: amount, projectIds: projectIds)
        case .manual:
            resolvedAllocations = recalculateAllocationAmounts(amount: amount, existingAllocations: recurring.allocations)
        }

        let txComponents = calendar.dateComponents([.year, .month], from: txDate)
        guard let txYear = txComponents.year, let txMonth = txComponents.month else {
            return resolvedAllocations
        }

        let totalDays = treatAsYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
        let needsProRata: Bool
        switch recurring.allocationMode {
        case .equalAll:
            needsProRata = resolvedAllocations.contains { allocation in
                guard let project = projects.first(where: { $0.id == allocation.projectId }) else {
                    return false
                }
                let activeDays = treatAsYearly
                    ? calculateActiveDaysInYear(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear)
                    : calculateActiveDaysInMonth(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear, month: txMonth)
                return activeDays < totalDays
            }
        case .manual:
            needsProRata = recurring.allocations.contains { allocation in
                guard let project = projects.first(where: { $0.id == allocation.projectId }) else {
                    return false
                }
                return project.startDate != nil || project.effectiveEndDate != nil
            }
        }

        guard needsProRata else { return resolvedAllocations }

        let inputs: [HolisticProRataInput]
        switch recurring.allocationMode {
        case .equalAll:
            inputs = resolvedAllocations.map { allocation in
                let project = projects.first { $0.id == allocation.projectId }
                let activeDays = treatAsYearly
                    ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                    : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                return HolisticProRataInput(projectId: allocation.projectId, ratio: allocation.ratio, activeDays: activeDays)
            }
        case .manual:
            inputs = recurring.allocations.map { allocation in
                let project = projects.first { $0.id == allocation.projectId }
                let activeDays = treatAsYearly
                    ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                    : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                return HolisticProRataInput(projectId: allocation.projectId, ratio: allocation.ratio, activeDays: activeDays)
            }
        }

        return calculateHolisticProRata(
            totalAmount: amount,
            totalDays: totalDays,
            inputs: inputs
        )
    }

    @discardableResult
    private func consumeRecurringSkipOccurrence(
        _ occurrence: RecurringDueOccurrence,
        recurring: PPRecurringTransaction
    ) -> Bool {
        let calendar = Calendar.current
        guard occurrence.isSkipped else { return false }

        recurring.skipDates = recurring.skipDates.filter { !calendar.isDate($0, inSameDayAs: occurrence.scheduledDate) }
        if occurrence.isMonthlySpread {
            if let monthKey = occurrence.monthKey, !recurring.lastGeneratedMonths.contains(monthKey) {
                recurring.lastGeneratedMonths = recurring.lastGeneratedMonths + [monthKey]
            }
        } else {
            recurring.lastGeneratedDate = occurrence.scheduledDate
        }
        recurring.updatedAt = Date()
        return true
    }

    @discardableResult
    private func applyRecurringProcessedOccurrence(
        _ occurrence: RecurringDueOccurrence,
        recurring: PPRecurringTransaction
    ) -> Bool {
        if occurrence.isMonthlySpread,
           let monthKey = occurrence.monthKey,
           !recurring.lastGeneratedMonths.contains(monthKey) {
            recurring.lastGeneratedMonths = recurring.lastGeneratedMonths + [monthKey]
        }
        recurring.lastGeneratedDate = occurrence.scheduledDate
        recurring.updatedAt = Date()
        return true
    }

    @discardableResult
    private func pruneRecurringGeneratedMonthsForCurrentYear(on today: Date) -> Bool {
        let currentYear = Calendar.current.component(.year, from: today)
        let currentYearPrefix = String(format: "%d-", currentYear)
        var mutated = false

        for recurring in recurringTransactions where recurring.yearlyAmortizationMode == .monthlySpread {
            let filteredMonths = recurring.lastGeneratedMonths.filter { $0.hasPrefix(currentYearPrefix) }
            if filteredMonths.count != recurring.lastGeneratedMonths.count {
                recurring.lastGeneratedMonths = filteredMonths
                recurring.updatedAt = Date()
                mutated = true
            }
        }
        return mutated
    }

    /// 定期取引の生成プレビュー（dry-run）。実際の取引は生成しない。
    func previewRecurringTransactions() -> [RecurringPreviewItem] {
        dueRecurringOccurrences()
            .filter { !$0.isSkipped && !$0.isYearLocked }
            .map { occurrence in
                RecurringPreviewItem(
                    recurringId: occurrence.recurringId,
                    recurringName: recurringTransactions.first(where: { $0.id == occurrence.recurringId })?.name ?? "",
                    type: recurringTransactions.first(where: { $0.id == occurrence.recurringId })?.type ?? .expense,
                    amount: occurrence.amount,
                    scheduledDate: occurrence.scheduledDate,
                    categoryId: occurrence.categoryId,
                    memo: occurrence.previewMemo,
                    isMonthlySpread: occurrence.isMonthlySpread,
                    projectName: occurrence.projectName,
                    allocationMode: occurrence.allocationMode
                )
            }
    }

    /// 指定されたプレビュー項目のみを実際に処理する（承認フロー）
    func approveRecurringItems(_ approvedIds: Set<UUID>, from items: [RecurringPreviewItem]) async -> Int {
        let approvedItems = items.filter { approvedIds.contains($0.id) }
        var generatedCount = 0
        var didMutateRecurringState = pruneRecurringGeneratedMonthsForCurrentYear(on: todayDate())

        for occurrence in dueRecurringOccurrences().filter(\.isSkipped) {
            guard let recurring = recurringTransactions.first(where: { $0.id == occurrence.recurringId }) else { continue }
            didMutateRecurringState = consumeRecurringSkipOccurrence(occurrence, recurring: recurring) || didMutateRecurringState
        }

        for item in approvedItems {
            guard let recurring = recurringTransactions.first(where: { $0.id == item.recurringId }) else { continue }
            if isYearLocked(for: item.scheduledDate) { continue }
            guard let allocations = recurringAllocations(
                for: recurring,
                amount: item.amount,
                txDate: item.scheduledDate,
                treatAsYearly: recurring.frequency == .yearly && !item.isMonthlySpread
            ) else {
                continue
            }

            let occurrence = RecurringDueOccurrence(
                recurringId: recurring.id,
                scheduledDate: item.scheduledDate,
                amount: item.amount,
                previewMemo: item.memo,
                postingMemo: recurringPostingMemo(for: recurring, isMonthlySpread: item.isMonthlySpread),
                categoryId: recurring.categoryId,
                isMonthlySpread: item.isMonthlySpread,
                monthKey: item.isMonthlySpread
                    ? String(
                        format: "%d-%02d",
                        Calendar.current.component(.year, from: item.scheduledDate),
                        Calendar.current.component(.month, from: item.scheduledDate)
                    )
                    : nil,
                projectName: item.projectName,
                allocationMode: recurring.allocationMode,
                isSkipped: false,
                isYearLocked: false
            )
            let result = saveApprovedPostingSync(
                type: recurring.type,
                amount: item.amount,
                date: item.scheduledDate,
                categoryId: recurring.categoryId,
                memo: occurrence.postingMemo,
                allocationAmounts: allocations,
                recurringId: recurring.id,
                paymentAccountId: recurring.paymentAccountId,
                transferToAccountId: recurring.transferToAccountId,
                taxDeductibleRate: recurring.taxDeductibleRate,
                counterpartyId: recurring.counterpartyId,
                counterparty: recurring.counterparty,
                candidateSource: .recurring
            )
            if case .success = result {
                didMutateRecurringState = applyRecurringProcessedOccurrence(occurrence, recurring: recurring) || didMutateRecurringState
                generatedCount += 1
            }
        }

        if didMutateRecurringState || generatedCount > 0 {
            _ = save()
            refreshRecurring()
            if generatedCount > 0 {
                refreshTransactions()
                refreshJournalEntries()
                refreshJournalLines()

                if let businessId = businessProfile?.id {
                    let auditEvent = AuditEvent(
                        businessId: businessId,
                        eventType: .recurringApproved,
                        aggregateType: "RecurringTransaction",
                        aggregateId: UUID(),
                        actor: "system",
                        reason: "\(generatedCount)件の定期取引を承認"
                    )
                    appendAuditEvent(auditEvent)
                }
            }
        }

        return generatedCount
    }

#if DEBUG
    @discardableResult
    func processRecurringTransactions() -> Int {
        let today = todayDate()
        var generatedCount = 0
        var didMutateRecurringState = pruneRecurringGeneratedMonthsForCurrentYear(on: today)

        for occurrence in dueRecurringOccurrences(on: today) {
            guard let recurring = recurringTransactions.first(where: { $0.id == occurrence.recurringId }) else { continue }

            if occurrence.isSkipped {
                didMutateRecurringState = consumeRecurringSkipOccurrence(occurrence, recurring: recurring) || didMutateRecurringState
                continue
            }
            if occurrence.isYearLocked {
                continue
            }
            guard let allocations = recurringAllocations(
                for: recurring,
                amount: occurrence.amount,
                txDate: occurrence.scheduledDate,
                treatAsYearly: recurring.frequency == .yearly && !occurrence.isMonthlySpread
            ) else {
                continue
            }

            let result = saveApprovedPostingSync(
                type: recurring.type,
                amount: occurrence.amount,
                date: occurrence.scheduledDate,
                categoryId: recurring.categoryId,
                memo: occurrence.postingMemo,
                allocationAmounts: allocations,
                recurringId: recurring.id,
                paymentAccountId: recurring.paymentAccountId,
                transferToAccountId: recurring.transferToAccountId,
                taxDeductibleRate: recurring.taxDeductibleRate,
                counterpartyId: recurring.counterpartyId,
                counterparty: recurring.counterparty,
                candidateSource: .recurring
            )
            if case .success = result {
                didMutateRecurringState = applyRecurringProcessedOccurrence(occurrence, recurring: recurring) || didMutateRecurringState
                generatedCount += 1
            }
        }

        for recurring in recurringTransactions where recurring.isActive {
            if let endDate = recurring.endDate, today > endDate {
                recurring.isActive = false
                recurring.updatedAt = Date()
                didMutateRecurringState = true
            }
        }

        if didMutateRecurringState || generatedCount > 0 {
            _ = save()
            refreshRecurring()
            if generatedCount > 0 {
                refreshTransactions()
                refreshJournalEntries()
                refreshJournalLines()
            }
        }

        return generatedCount
    }
#endif

    // MARK: - Summary Functions

    func getProjectSummary(projectId: UUID, startDate: Date? = nil, endDate: Date? = nil) -> ProjectSummary? {
        guard let project = getProject(id: projectId) else { return nil }

        var totalIncome = 0
        var totalExpense = 0

        for t in transactions {
            if let start = startDate, t.date < start { continue }
            if let end = endDate, t.date > end { continue }
            if let alloc = t.allocations.first(where: { $0.projectId == projectId }) {
                switch t.type {
                case .income: totalIncome += alloc.amount
                case .expense: totalExpense += alloc.amount
                case .transfer: break
                }
            }
        }

        for record in canonicalSupplementalSummaryRecords(startDate: startDate, endDate: endDate) where record.projectId == projectId {
            switch record.type {
            case .income:
                totalIncome += record.amount
            case .expense:
                totalExpense += record.amount
            case .transfer:
                break
            }
        }

        let profit = totalIncome - totalExpense
        let profitMargin = totalIncome > 0 ? Double(profit) / Double(totalIncome) * 100 : 0

        return ProjectSummary(
            id: projectId,
            projectName: project.name,
            status: project.status,
            totalIncome: totalIncome,
            totalExpense: totalExpense,
            profit: profit,
            profitMargin: profitMargin
        )
    }

    func getAllProjectSummaries(startDate: Date? = nil, endDate: Date? = nil) -> [ProjectSummary] {
        projects.compactMap { getProjectSummary(projectId: $0.id, startDate: startDate, endDate: endDate) }
    }

    func getOverallSummary(startDate: Date? = nil, endDate: Date? = nil) -> OverallSummary {
        var totalIncome = 0
        var totalExpense = 0

        for t in transactions {
            if let start = startDate, t.date < start { continue }
            if let end = endDate, t.date > end { continue }
            switch t.type {
            case .income: totalIncome += t.amount
            case .expense: totalExpense += t.amount
            case .transfer: break
            }
        }

        for record in canonicalSupplementalSummaryRecords(startDate: startDate, endDate: endDate) {
            switch record.type {
            case .income:
                totalIncome += record.amount
            case .expense:
                totalExpense += record.amount
            case .transfer:
                break
            }
        }

        let netProfit = totalIncome - totalExpense
        let profitMargin = totalIncome > 0 ? Double(netProfit) / Double(totalIncome) * 100 : 0

        return OverallSummary(totalIncome: totalIncome, totalExpense: totalExpense, netProfit: netProfit, profitMargin: profitMargin)
    }

    /// `.transfer` は P&L カテゴリ集計の対象外。渡された場合は空配列を返す。
    func getCategorySummaries(type: TransactionType, startDate: Date? = nil, endDate: Date? = nil) -> [CategorySummary] {
        guard type != .transfer else { return [] }

        var totals: [String: Int] = [:]
        var grandTotal = 0

        for t in transactions {
            guard t.type == type else { continue }
            if let start = startDate, t.date < start { continue }
            if let end = endDate, t.date > end { continue }
            totals[t.categoryId, default: 0] += t.amount
            grandTotal += t.amount
        }

        for record in canonicalSupplementalSummaryRecords(startDate: startDate, endDate: endDate) {
            guard record.type == type, let categoryId = record.categoryId else { continue }
            totals[categoryId, default: 0] += record.amount
            grandTotal += record.amount
        }

        return totals.map { categoryId, total in
            let name = getCategory(id: categoryId)?.name ?? "不明"
            let percentage = grandTotal > 0 ? Double(total) / Double(grandTotal) * 100 : 0
            return CategorySummary(categoryId: categoryId, categoryName: name, total: total, percentage: percentage)
        }.sorted { $0.total > $1.total }
    }

    func getMonthlySummaries(year: Int) -> [MonthlySummary] {
        var monthlyData: [String: (income: Int, expense: Int)] = [:]
        for m in 1...12 {
            let key = String(format: "%d-%02d", year, m)
            monthlyData[key] = (0, 0)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        for t in transactions {
            let month = formatter.string(from: t.date)
            guard month.hasPrefix(String(year)), monthlyData[month] != nil else { continue }
            guard var data = monthlyData[month] else { continue }
            switch t.type {
            case .income: data.income += t.amount
            case .expense: data.expense += t.amount
            case .transfer: break
            }
            monthlyData[month] = data
        }

        for record in canonicalSupplementalSummaryRecords() {
            let month = formatter.string(from: record.date)
            guard month.hasPrefix(String(year)), monthlyData[month] != nil else { continue }
            guard var data = monthlyData[month] else { continue }
            switch record.type {
            case .income:
                data.income += record.amount
            case .expense:
                data.expense += record.amount
            case .transfer:
                break
            }
            monthlyData[month] = data
        }

        return monthlyData.sorted { $0.key < $1.key }.map { key, data in
            MonthlySummary(month: key, income: data.income, expense: data.expense, profit: data.income - data.expense)
        }
    }

    private struct CanonicalSupplementalSummaryRecord {
        let date: Date
        let type: TransactionType
        let amount: Int
        let projectId: UUID?
        let categoryId: String?
    }

    private func canonicalSupplementalSummaryRecords(
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [CanonicalSupplementalSummaryRecord] {
        let legacyTransactionIds = Set(transactions.map(\.id))
        let journals = canonicalJournalEntries().filter { journal in
            guard let sourceCandidateId = journal.sourceCandidateId else {
                return false
            }
            guard !legacyTransactionIds.contains(sourceCandidateId) else {
                return false
            }
            if let startDate, journal.journalDate < startDate {
                return false
            }
            if let endDate, journal.journalDate > endDate {
                return false
            }
            return true
        }
        guard !journals.isEmpty else {
            return []
        }

        let candidateIds = Set(journals.compactMap(\.sourceCandidateId))
        let candidatesById = fetchPostingCandidates(ids: candidateIds)

        return journals.flatMap { journal -> [CanonicalSupplementalSummaryRecord] in
            guard let candidateId = journal.sourceCandidateId,
                  let candidate = candidatesById[candidateId],
                  let transactionType = candidate.legacySnapshot?.type else {
                return []
            }

            let relevantLines: [PostingCandidateLine]
            switch transactionType {
            case .income:
                relevantLines = candidate.proposedLines.filter { $0.creditAccountId != nil }
            case .expense:
                relevantLines = candidate.proposedLines.filter { $0.debitAccountId != nil }
            case .transfer:
                relevantLines = []
            }

            let categoryId = candidate.legacySnapshot?.categoryId
            return relevantLines.compactMap { line -> CanonicalSupplementalSummaryRecord? in
                let amount = NSDecimalNumber(decimal: line.amount).intValue
                guard amount != 0 else {
                    return nil
                }

                return CanonicalSupplementalSummaryRecord(
                    date: journal.journalDate,
                    type: transactionType,
                    amount: amount,
                    projectId: line.projectAllocationId,
                    categoryId: categoryId
                )
            }
        }
    }

    private func fetchPostingCandidates(ids: Set<UUID>) -> [UUID: PostingCandidate] {
        guard !ids.isEmpty else {
            return [:]
        }

        let descriptor = FetchDescriptor<PostingCandidateEntity>()
        let entities = (try? modelContext.fetch(descriptor)) ?? []
        return entities.reduce(into: [UUID: PostingCandidate]()) { result, entity in
            guard ids.contains(entity.candidateId) else {
                return
            }
            let candidate = PostingCandidateEntityMapper.toDomain(entity)
            result[candidate.id] = candidate
        }
    }

    /// Returns 12 monthly summaries ordered by fiscal year months (e.g. Apr..Mar for startMonth=4).
    func getMonthlySummaries(fiscalYear fy: Int, startMonth: Int) -> [MonthlySummary] {
        let calendarMonths = fiscalYearCalendarMonths(fiscalYear: fy, startMonth: startMonth)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"

        var monthlyData: [(key: String, income: Int, expense: Int)] = calendarMonths.map { pair in
            let key = String(format: "%d-%02d", pair.year, pair.month)
            return (key: key, income: 0, expense: 0)
        }

        let keySet = Set(monthlyData.map(\.key))

        for t in transactions {
            let month = formatter.string(from: t.date)
            guard keySet.contains(month) else { continue }
            guard let idx = monthlyData.firstIndex(where: { $0.key == month }) else { continue }
            switch t.type {
            case .income: monthlyData[idx].income += t.amount
            case .expense: monthlyData[idx].expense += t.amount
            case .transfer: break
            }
        }

        return monthlyData.map { data in
            MonthlySummary(month: data.key, income: data.income, expense: data.expense, profit: data.income - data.expense)
        }
    }

    /// Returns fiscal-year-by-fiscal-year summaries for a specific project.
    func getYearlyProjectSummaries(projectId: UUID, startMonth: Int) -> [FiscalYearProjectSummary] {
        guard getProject(id: projectId) != nil else { return [] }

        // Collect all fiscal years that have transactions for this project
        var fySet = Set<Int>()
        for t in transactions {
            guard t.allocations.contains(where: { $0.projectId == projectId }) else { continue }
            fySet.insert(fiscalYear(for: t.date, startMonth: startMonth))
        }

        guard !fySet.isEmpty else { return [] }

        return fySet.sorted().map { fy in
            let start = startOfFiscalYear(fy, startMonth: startMonth)
            let end = endOfFiscalYear(fy, startMonth: startMonth)

            var income = 0
            var expense = 0

            for t in transactions {
                guard t.date >= start, t.date <= end else { continue }
                if let alloc = t.allocations.first(where: { $0.projectId == projectId }) {
                    switch t.type {
                    case .income: income += alloc.amount
                    case .expense: expense += alloc.amount
                    case .transfer: break
                    }
                }
            }

            return FiscalYearProjectSummary(
                fiscalYear: fy,
                label: fiscalYearLabel(fy, startMonth: startMonth),
                income: income,
                expense: expense,
                profit: income - expense
            )
        }
    }

    // MARK: - Filter & Sort

    func getFilteredTransactions(filter: TransactionFilter, sort: TransactionSort? = nil) -> [PPTransaction] {
        var result = transactions.filter { t in
            if let start = filter.startDate, t.date < start { return false }
            if let end = filter.endDate, t.date > end { return false }
            if let projectId = filter.projectId, !t.allocations.contains(where: { $0.projectId == projectId }) { return false }
            if let categoryId = filter.categoryId, t.categoryId != categoryId { return false }
            if let type = filter.type, t.type != type { return false }
            if let amountMin = filter.amountMin, t.amount < amountMin { return false }
            if let amountMax = filter.amountMax, t.amount > amountMax { return false }
            if let counterparty = filter.counterparty, !counterparty.isEmpty {
                guard let tc = t.counterparty, tc.lowercased().contains(counterparty.lowercased()) else { return false }
            }
            if !filter.searchText.isEmpty {
                let query = filter.searchText.lowercased()
                let memoMatch = t.memo.lowercased().contains(query)
                let counterpartyMatch = t.counterparty?.lowercased().contains(query) ?? false
                if !memoMatch && !counterpartyMatch { return false }
            }
            return true
        }

        let sortSpec = sort ?? TransactionSort(field: .date, order: .desc)
        result.sort { a, b in
            let comparison: Bool
            switch sortSpec.field {
            case .date:
                comparison = a.date < b.date
            case .amount:
                comparison = a.amount < b.amount
            }
            return sortSpec.order == .desc ? !comparison : comparison
        }

        return result
    }

    // MARK: - Audit Logging

    private func logFieldChange(transactionId: UUID, fieldName: String, oldValue: String?, newValue: String?) {
        guard oldValue != newValue else { return }
        let log = PPTransactionLog(
            transactionId: transactionId,
            fieldName: fieldName,
            oldValue: oldValue,
            newValue: newValue
        )
        modelContext.insert(log)
    }

    func appendAuditEvent(_ event: AuditEvent) {
        guard let businessId = businessProfile?.id else { return }
        let entity = AuditEventEntity(
            eventId: event.id,
            businessId: businessId,
            eventTypeRaw: event.eventType.rawValue,
            aggregateType: event.aggregateType,
            aggregateId: event.aggregateId,
            beforeStateHash: event.beforeStateHash,
            afterStateHash: event.afterStateHash,
            actor: event.actor,
            createdAt: event.createdAt,
            reason: event.reason,
            relatedEvidenceId: event.relatedEvidenceId,
            relatedJournalId: event.relatedJournalId
        )
        modelContext.insert(entity)
    }

    func getTransactionLogs(for transactionId: UUID) -> [PPTransactionLog] {
        do {
            let descriptor = FetchDescriptor<PPTransactionLog>(
                predicate: #Predicate { $0.transactionId == transactionId },
                sortBy: [SortDescriptor(\.changedAt, order: .reverse)]
            )
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }

    // MARK: - Soft Delete Management

    /// 指定日数以上前にソフトデリートされた取引を物理削除する（7年 = 2555日）
    func purgeDeletedTransactions(olderThan days: Int = 2555) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let toDelete = allTransactions.filter { t in
            guard let deletedAt = t.deletedAt else { return false }
            return deletedAt < cutoff
        }
        for transaction in toDelete {
            if let imagePath = transaction.receiptImagePath {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
            modelContext.delete(transaction)
        }
        if !toDelete.isEmpty {
            save()
            refreshTransactions()
        }
    }

    // MARK: - Category Archive

    func archiveCategory(id: String) {
        if CategoryWorkflowUseCase(modelContext: modelContext).archiveCategory(id: id) {
            refreshCategories()
        }
    }

    func unarchiveCategory(id: String) {
        if CategoryWorkflowUseCase(modelContext: modelContext).unarchiveCategory(id: id) {
            refreshCategories()
        }
    }

    // MARK: - CSV Import

#if DEBUG
    func importTransactions(from csvString: String) async -> CSVImportResult {
        let result = await postingIntakeUseCase.importTransactions(
            request: CSVImportRequest(
                csvString: csvString,
                originalFileName: "debug-import.csv",
                fileData: Data(csvString.utf8),
                mimeType: "text/csv",
                channel: .settingsTransactionCSV
            )
        )
        refreshProjects()
        refreshTransactions()
        refreshJournalEntries()
        refreshJournalLines()
        loadData()
        return result
    }

    // MARK: - Bulk Delete

    func deleteAllData() {
        SettingsMaintenanceUseCase(
            modelContext: modelContext,
            resetStoreState: { self.loadData() }
        ).deleteAllData()
    }
#endif

    // MARK: - Accounting CRUD

    func getAccount(id: String) -> PPAccount? {
        accounts.first { $0.id == id }
    }

    func canonicalAccounts() -> [CanonicalAccount] {
        guard let businessId = businessProfile?.id else {
            return []
        }
        return fetchCanonicalAccounts(businessId: businessId)
    }

    func canonicalAccount(id: UUID) -> CanonicalAccount? {
        canonicalAccounts().first { $0.id == id }
    }

    func legacyAccountId(for canonicalAccountId: UUID) -> String? {
        canonicalAccount(id: canonicalAccountId)?.legacyAccountId
    }

    func canonicalAccountId(for legacyAccountId: String) -> UUID? {
        guard let businessId = businessProfile?.id else {
            return UUID(uuidString: legacyAccountId)
        }
        return canonicalAccountId(
            for: legacyAccountId,
            canonicalIdsByLegacyId: canonicalAccountIdsByLegacyId(businessId: businessId)
        )
    }

    // MARK: - Canonical Report Convenience

    func canonicalTrialBalance(fiscalYear: Int) -> CanonicalTrialBalanceReport {
        AccountingReportService.generateTrialBalance(
            fiscalYear: fiscalYear,
            accounts: canonicalAccounts(),
            journals: canonicalJournalEntries(fiscalYear: fiscalYear),
            startMonth: FiscalYearSettings.startMonth
        )
    }

    func canonicalProfitLoss(fiscalYear: Int) -> CanonicalProfitLossReport {
        AccountingReportService.generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: canonicalAccounts(),
            journals: canonicalJournalEntries(fiscalYear: fiscalYear),
            startMonth: FiscalYearSettings.startMonth
        )
    }

    func canonicalBalanceSheet(fiscalYear: Int) -> CanonicalBalanceSheetReport {
        AccountingReportService.generateBalanceSheet(
            fiscalYear: fiscalYear,
            accounts: canonicalAccounts(),
            journals: canonicalJournalEntries(fiscalYear: fiscalYear),
            startMonth: FiscalYearSettings.startMonth
        )
    }

    func canonicalJournalEntries(fiscalYear: Int? = nil) -> [CanonicalJournalEntry] {
        guard let businessId = businessProfile?.id else {
            return []
        }
        return fetchCanonicalJournalEntries(businessId: businessId, taxYear: fiscalYear)
    }

    func canonicalJournalEntries(evidenceId: UUID) -> [CanonicalJournalEntry] {
        fetchCanonicalJournalEntries(evidenceId: evidenceId)
    }

    func projectedCanonicalJournals(fiscalYear requestedFiscalYear: Int? = nil) -> (entries: [PPJournalEntry], lines: [PPJournalLine]) {
        guard let businessId = businessProfile?.id else {
            return ([], [])
        }

        let canonicalAccounts = fetchCanonicalAccounts(businessId: businessId)
        let accountsById = Dictionary(uniqueKeysWithValues: canonicalAccounts.map { ($0.id, $0) })
        let journals = fetchCanonicalJournalEntries(businessId: businessId, taxYear: requestedFiscalYear)

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

        let legacySupplementalEntries = journalEntries.filter { entry in
            guard !projectedEntries.contains(where: { $0.id == entry.id }) else {
                return false
            }
            let isSupplemental = entry.sourceKey.hasPrefix("manual:")
                || entry.sourceKey.hasPrefix("opening:")
                || entry.sourceKey.hasPrefix("closing:")
                || entry.sourceKey.hasPrefix("depreciation:")
            guard isSupplemental else {
                return false
            }
            guard let requestedFiscalYear else {
                return true
            }
            return fiscalYear(for: entry.date, startMonth: FiscalYearSettings.startMonth) == requestedFiscalYear
        }
        let legacySupplementalLines = journalLines.filter { line in
            legacySupplementalEntries.contains { $0.id == line.entryId }
        }

        let mergedEntries = (projectedEntries + legacySupplementalEntries)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.date > rhs.date
            }
        let mergedLines = projectedLines + legacySupplementalLines
        return (mergedEntries, mergedLines)
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

    func getJournalEntry(id: UUID) -> PPJournalEntry? {
        journalEntries.first { $0.id == id }
    }

    func getJournalLines(for entryId: UUID) -> [PPJournalLine] {
        journalLines.filter { $0.entryId == entryId }.sorted { $0.displayOrder < $1.displayOrder }
    }

    func getJournalEntry(for transactionId: UUID) -> PPJournalEntry? {
        let sourceKey = PPJournalEntry.transactionSourceKey(transactionId)
        return journalEntries.first { $0.sourceKey == sourceKey }
    }
}
