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

    private var profileSettingsUseCase: ProfileSettingsUseCase {
        ProfileSettingsUseCase(modelContext: modelContext)
    }

    private var counterpartyMasterUseCase: CounterpartyMasterUseCase {
        CounterpartyMasterUseCase(modelContext: modelContext)
    }

    private var postingWorkflowUseCase: PostingWorkflowUseCase {
        PostingWorkflowUseCase(modelContext: modelContext)
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

    private func fetchCanonicalAccounts(businessId: UUID) -> [CanonicalAccount] {
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
        runLegacyProfileMigrationIfNeeded()
        refreshCanonicalProfileCache()
        let payload = loadSensitivePayload()
        do {
            let defaultTaxYear = currentTaxYearProfile?.taxYear ?? currentFiscalYear()
            let state = try await profileSettingsUseCase.load(
                defaultTaxYear: defaultTaxYear,
                sensitivePayload: payload
            )
            applyProfileSettingsState(state)
            return true
        } catch {
            AppLogger.dataStore.error("Failed to reload profile settings: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
            return false
        }
    }

    @discardableResult
    func saveProfileSettings(
        command: SaveProfileSettingsCommand,
        sensitivePayload: ProfileSensitivePayload
    ) async -> Result<Void, Error> {
        runLegacyProfileMigrationIfNeeded()
        refreshCanonicalProfileCache()
        do {
            let state = try await profileSettingsUseCase.load(
                defaultTaxYear: command.taxYear,
                sensitivePayload: sensitivePayload
            )
            guard persistSensitivePayload(sensitivePayload, businessProfileId: state.businessProfile.id) else {
                return .failure(AppError.saveFailed(underlying: NSError(domain: "ProfileSecureStore", code: 1)))
            }
            let savedState = try await profileSettingsUseCase.save(
                command: command,
                currentState: state
            )

            applyProfileSettingsState(savedState)

            if save() {
                return .success(())
            }
            return .failure(lastError ?? AppError.saveFailed(underlying: NSError(domain: "ProfileSettings", code: 2)))
        } catch {
            AppLogger.dataStore.error("Failed to save profile settings: \(error.localizedDescription)")
            lastError = .saveFailed(underlying: error)
            return .failure(error)
        }
    }

    /// マイグレーション: SwiftDataスキーマ変更後の整合性チェック
    /// allocationMode/yearlyAmortizationMode は非Optionalに変更済み。
    /// SwiftDataが自動的にデフォルト値を適用するため、現在は追加処理不要。
    private func migrateNilOptionalFields() {
        // SwiftData handles schema migration with default values from init.
        // This method is retained as a hook for future migrations.
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

    private func applyProfileSettingsState(_ state: ProfileSettingsState) {
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

    private func persistSensitivePayload(_ payload: ProfileSensitivePayload, businessProfileId: UUID) -> Bool {
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

    private func guardLegacyTransactionMutationAllowed(
        source: LegacyTransactionMutationSource
    ) -> AppError? {
        guard source == .userInitiated, FeatureFlags.useCanonicalPosting else {
            return nil
        }
        let error = AppError.legacyTransactionMutationDisabled
        lastError = error
        return error
    }

    private func enqueueCanonicalTransactionSync(for transactionId: UUID, source: CandidateSource?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.syncCanonicalArtifacts(forTransactionId: transactionId, source: source)
        }
    }

    private func enqueueCanonicalRecurringCounterpartySync(for recurringId: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.syncCanonicalCounterparty(forRecurringId: recurringId)
        }
    }

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

        let explicitTaxCodeId = TaxCode.resolve(
            legacyCategory: transaction.taxCategory,
            taxRate: transaction.taxRate
        )?.rawValue
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
        let result = await buildCanonicalPosting(
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocations,
            recurringId: nil,
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
            source: candidateSource ?? .manual
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
        let candidate = candidateWithProjectAllocations(
            posting.candidate.updated(status: .draft),
            allocations: normalizedAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) }
        )

        do {
            try await postingWorkflowUseCase.saveCandidate(candidate)
            lastError = nil
            return .success(candidate)
        } catch {
            let appError = AppError.saveFailed(underlying: error)
            lastError = appError
            return .failure(appError)
        }
    }

    private func buildCanonicalPosting(
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
    ) async -> Result<CanonicalTransactionPostingBridge.Posting, AppError> {
        guard !cannotPostNormalEntry(for: date) else {
            return .failure(.yearLocked(year: fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)))
        }
        guard let businessId = businessProfile?.id else {
            let error = AppError.invalidInput(message: "事業者プロフィールが未設定のため承認待ち候補を作成できません")
            lastError = error
            return .failure(error)
        }

        let safeCategoryId: String
        switch type {
        case .transfer:
            safeCategoryId = categoryId
        case .income, .expense:
            safeCategoryId = categoryId.isEmpty ? Self.defaultCategoryId(for: type) : categoryId
        }

        let explicitTaxCodeId = resolvedExplicitTaxCodeId(
            explicitTaxCodeId: taxCodeId,
            taxCategory: taxCategory,
            taxRate: taxRate
        )
        let counterpartyStatus = await syncCanonicalCounterparty(
            id: counterpartyId,
            named: counterparty,
            defaultTaxCodeId: explicitTaxCodeId
        )
        let resolvedCounterpartyId: UUID?
        switch counterpartyStatus {
        case .synced(let id):
            resolvedCounterpartyId = id
        case .skippedSourceNotFound, .skippedBusinessProfileUnavailable, .skippedBlankName, .failed:
            resolvedCounterpartyId = nil
        }

        syncCanonicalAccountsFromLegacyAccountsIfNeeded()
        let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)
        let snapshot = CanonicalTransactionPostingBridge.TransactionSnapshot(
            id: UUID(),
            type: type,
            amount: amount,
            date: date,
            categoryId: safeCategoryId,
            memo: memo,
            recurringId: recurringId,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            taxAmount: taxAmount,
            taxCodeId: explicitTaxCodeId,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            createdAt: Date(),
            updatedAt: Date(),
            journalEntryId: nil
        )

        guard let posting = bridge.buildApprovedPosting(
            for: snapshot,
            businessId: businessId,
            counterpartyId: resolvedCounterpartyId,
            source: source,
            categories: categories,
            legacyAccounts: accounts
        ) else {
            let error = AppError.invalidInput(message: "承認待ち候補の勘定科目または税区分を解決できません")
            lastError = error
            return .failure(error)
        }

        lastError = nil
        return .success(posting)
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
        let result = await buildCanonicalPosting(
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
        let candidate = candidateWithProjectAllocations(
            posting.candidate,
            allocations: normalizedAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) }
        )

        do {
            let journal = try await postingWorkflowUseCase.syncApprovedCandidate(
                candidate,
                journalId: posting.journalId,
                entryType: posting.entryType,
                description: posting.description,
                approvedAt: posting.approvedAt
            )
            lastError = nil
            return .success(journal)
        } catch {
            let appError = AppError.saveFailed(underlying: error)
            lastError = appError
            return .failure(appError)
        }
    }

    private func resolvedExplicitTaxCodeId(
        explicitTaxCodeId: String?,
        taxCategory: TaxCategory?,
        taxRate: Int?
    ) -> String? {
        if let explicitTaxCodeId {
            return explicitTaxCodeId
        }
        return TaxCode.resolve(
            legacyCategory: taxCategory,
            taxRate: taxRate
        )?.rawValue
    }

    private func candidateWithProjectAllocations(
        _ candidate: PostingCandidate,
        allocations: [(projectId: UUID, ratio: Int)]
    ) -> PostingCandidate {
        guard !allocations.isEmpty else {
            return candidate
        }

        let normalizedAllocations = allocations.filter { $0.ratio > 0 }
        guard !normalizedAllocations.isEmpty else {
            return candidate
        }

        let expandedLines = candidate.proposedLines.flatMap { line -> [PostingCandidateLine] in
            if normalizedAllocations.count == 1, let allocation = normalizedAllocations.first {
                return [line.updated(projectAllocationId: .some(allocation.projectId))]
            }

            let lineAmount = NSDecimalNumber(decimal: line.amount).intValue
            let splitAllocations = calculateRatioAllocations(amount: lineAmount, allocations: normalizedAllocations)
            return splitAllocations.compactMap { allocation in
                guard allocation.amount > 0 else {
                    return nil
                }
                return PostingCandidateLine(
                    debitAccountId: line.debitAccountId,
                    creditAccountId: line.creditAccountId,
                    amount: Decimal(allocation.amount),
                    taxCodeId: line.taxCodeId,
                    legalReportLineId: line.legalReportLineId,
                    projectAllocationId: allocation.projectId,
                    memo: line.memo,
                    evidenceLineReferenceId: line.evidenceLineReferenceId,
                    withholdingTaxCodeId: line.withholdingTaxCodeId,
                    withholdingTaxAmount: line.withholdingTaxAmount
                )
            }
        }

        guard !expandedLines.isEmpty else {
            return candidate
        }
        return candidate.updated(proposedLines: expandedLines)
    }

    private func syncCanonicalCounterparty(
        id explicitId: UUID?,
        named rawName: String?,
        defaultTaxCodeId: String?
    ) async -> CanonicalCounterpartySyncStatus {
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
        guard let businessId = businessProfile?.id else {
            return .skippedBusinessProfileUnavailable
        }
        syncCanonicalAccountsFromLegacyAccountsIfNeeded()
        let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)
        let snapshot = CanonicalTransactionPostingBridge.TransactionSnapshot(transaction: transaction)
        guard let posting = bridge.buildApprovedPosting(
            for: snapshot,
            businessId: businessId,
            counterpartyId: counterpartyId,
            source: source,
            categories: categories,
            legacyAccounts: accounts
        ) else {
            return .skippedLegacyJournalUnavailable
        }

        do {
            let journal = try await postingWorkflowUseCase.syncApprovedCandidate(
                posting.candidate,
                journalId: posting.journalId,
                entryType: posting.entryType,
                description: posting.description,
                approvedAt: posting.approvedAt
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
            if existingKeys.contains(key) {
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

    private func seedDefaultCategories() {
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

    private func refreshProjects() {
        do {
            let descriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            projects = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh projects: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    private func refreshTransactions() {
        do {
            let descriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            allTransactions = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh transactions: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    private func refreshCategories() {
        do {
            let descriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\.name)])
            categories = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh categories: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }

    private func refreshRecurring() {
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

    @discardableResult
    func addProject(name: String, description: String, startDate: Date? = nil, plannedEndDate: Date? = nil) -> PPProject {
        let safePlannedEndDate: Date? = {
            guard let start = startDate, let planned = plannedEndDate else { return plannedEndDate }
            let calendar = Calendar.current
            return calendar.startOfDay(for: start) > calendar.startOfDay(for: planned) ? nil : plannedEndDate
        }()
        let project = PPProject(name: name, projectDescription: description, startDate: startDate, plannedEndDate: safePlannedEndDate)
        modelContext.insert(project)
        save()
        refreshProjects()
        reprocessEqualAllCurrentPeriodTransactions()
        refreshTransactions()
        return project
    }

    func updateProject(id: UUID, name: String? = nil, description: String? = nil, status: ProjectStatus? = nil, startDate: Date?? = nil, completedAt: Date?? = nil, plannedEndDate: Date?? = nil) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        if let name { project.name = name }
        if let description { project.projectDescription = description }

        let previousStatus = project.status
        let previousCompletedAt = project.completedAt
        let previousStartDate = project.startDate
        let previousPlannedEndDate = project.plannedEndDate

        if let status { project.status = status }

        // startDateの処理: 明示的に指定された場合はそれを使用
        if let startDate {
            project.startDate = startDate
        }

        // completedAtの処理: 明示的に指定された場合はそれを使用、そうでなければ自動管理
        if let completedAt {
            // 明示的に指定された（nilも含む）
            project.completedAt = completedAt
        } else {
            // 指定されていない場合、ステータスに基づいて自動管理
            if project.status == .completed && project.completedAt == nil {
                project.completedAt = Date()
            }
            if project.status != .completed {
                project.completedAt = nil
            }
        }

        // plannedEndDateの処理
        if let plannedEndDate {
            project.plannedEndDate = plannedEndDate
        }

        // 防御的ガード: startDate > completedAt の場合は completedAt をクリア
        if let currentStart = project.startDate, let currentCompleted = project.completedAt {
            let calendar = Calendar.current
            if calendar.startOfDay(for: currentStart) > calendar.startOfDay(for: currentCompleted) {
                project.completedAt = nil
            }
        }
        // 防御的ガード: startDate > plannedEndDate の場合は plannedEndDate をクリア
        if let currentStart = project.startDate, let currentPlanned = project.plannedEndDate {
            let calendar = Calendar.current
            if calendar.startOfDay(for: currentStart) > calendar.startOfDay(for: currentPlanned) {
                project.plannedEndDate = nil
            }
        }

        project.updatedAt = Date()
        save()
        refreshProjects()

        // completedAt、startDate、またはplannedEndDateが変更された場合の処理
        let completedAtChanged = project.completedAt != previousCompletedAt
        let startDateChanged = project.startDate != previousStartDate
        let plannedEndDateChanged = project.plannedEndDate != previousPlannedEndDate
        let statusChangedAwayFromCompleted = previousStatus == .completed && project.status != .completed
        if completedAtChanged || startDateChanged || plannedEndDateChanged {
            if project.startDate != nil || project.effectiveEndDate != nil {
                recalculateAllocationsForProject(projectId: id)
            } else if statusChangedAwayFromCompleted {
                // 両方の日付がクリアされ、かつ完了→非完了へ遷移した場合
                reverseCompletionAllocations(projectId: id)
                // 他のプロジェクトの日割りを再適用
                recalculateAllPartialPeriodProjects()
            } else if previousStartDate != nil || previousCompletedAt != nil || previousPlannedEndDate != nil {
                // 日割り対象だったが全日付がクリアされた場合、比率ベースに復元
                reverseCompletionAllocations(projectId: id)
                // 他のプロジェクトの日割りを再適用
                recalculateAllPartialPeriodProjects()
            }
            refreshTransactions()
        }
    }

    // MARK: - Archive / Unarchive

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
        guard let project = projects.first(where: { $0.id == id }) else { return }

        // トランザクション参照があるか確認
        let hasTransactionReferences = transactions.contains { tx in
            tx.allocations.contains { $0.projectId == id }
        }

        // 参照がある場合はアーカイブに委譲
        if hasTransactionReferences {
            archiveProject(id: id)
            return
        }

        // 参照なし: 従来通りハードデリート
        // C4: save成功後に削除するため画像パスを収集
        var imagesToDelete: [String] = []

        // Remove allocations from recurring
        for recurring in recurringTransactions {
            let filtered = recurring.allocations.filter { $0.projectId != id }
            if filtered.count != recurring.allocations.count {
                if filtered.isEmpty {
                    if let imagePath = recurring.receiptImagePath {
                        imagesToDelete.append(imagePath)
                    }
                    modelContext.delete(recurring)
                } else {
                    recurring.allocations = redistributeAllocations(
                        totalAmount: recurring.amount,
                        remainingAllocations: filtered
                    )
                }
            }
        }

        modelContext.delete(project)
        if save() {
            for imagePath in imagesToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
        }
        refreshProjects()
        refreshTransactions()
        refreshRecurring()
        // H1: equalAll定期取引の今期分トランザクションをaddProjectと対称的に再計算
        reprocessEqualAllCurrentPeriodTransactions()
        refreshTransactions()
    }

    func deleteProjects(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        // H9: トランザクション参照があるプロジェクトはアーカイブ、ないものはハードデリート
        var idsToArchive = Set<UUID>()
        var idsToHardDelete = Set<UUID>()
        for id in ids {
            let hasReferences = transactions.contains { tx in
                tx.allocations.contains { $0.projectId == id }
            }
            if hasReferences {
                idsToArchive.insert(id)
            } else {
                idsToHardDelete.insert(id)
            }
        }

        // バッチアーカイブ（save/refreshを1回にまとめる）
        if !idsToArchive.isEmpty {
            let now = Date()
            for id in idsToArchive {
                guard let project = projects.first(where: { $0.id == id }) else { continue }
                project.isArchived = true
                project.updatedAt = now
            }
            // H10+H9: アーカイブ対象を参照する equalAll トランザクションの手動編集フラグをクリア
            for transaction in transactions {
                guard transaction.isManuallyEdited == true,
                      transaction.allocations.contains(where: { idsToArchive.contains($0.projectId) }),
                      let recurringId = transaction.recurringId,
                      let recurring = recurringTransactions.first(where: { $0.id == recurringId }),
                      recurring.allocationMode == .equalAll
                else { continue }
                transaction.isManuallyEdited = nil
            }
            for recurring in recurringTransactions {
                let filtered = recurring.allocations.filter { !idsToArchive.contains($0.projectId) }
                if filtered.count != recurring.allocations.count {
                    if filtered.isEmpty && recurring.allocationMode == .manual {
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

        guard !idsToHardDelete.isEmpty else { return }

        // C4: save成功後に削除するため画像パスを収集
        var imagesToDelete: [String] = []

        for recurring in recurringTransactions {
            let filtered = recurring.allocations.filter { !idsToHardDelete.contains($0.projectId) }
            if filtered.count != recurring.allocations.count {
                if filtered.isEmpty {
                    if let imagePath = recurring.receiptImagePath {
                        imagesToDelete.append(imagePath)
                    }
                    modelContext.delete(recurring)
                } else {
                    recurring.allocations = redistributeAllocations(
                        totalAmount: recurring.amount,
                        remainingAllocations: filtered
                    )
                }
            }
        }

        for id in idsToHardDelete {
            if let project = projects.first(where: { $0.id == id }) {
                modelContext.delete(project)
            }
        }

        if save() {
            for imagePath in imagesToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
        }
        refreshProjects()
        refreshTransactions()
        refreshRecurring()
        // H1: equalAll定期取引の今期分トランザクションをaddProjectと対称的に再計算
        reprocessEqualAllCurrentPeriodTransactions()
        refreshTransactions()
    }

    func getProject(id: UUID) -> PPProject? {
        projects.first { $0.id == id }
    }

    // MARK: - Transaction CRUD

    /// 取引を追加し、保存結果を返す。
    /// 年度ロックなどで追加できない場合は `.failure` を返す。
    func addTransactionResult(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        recurringId: UUID? = nil,
        receiptImagePath: String? = nil,
        lineItems: [ReceiptLineItem] = [],
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        taxAmount: Int? = nil,
        taxRate: Int? = nil,
        isTaxIncluded: Bool? = nil,
        taxCategory: TaxCategory? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil,
        candidateSource: CandidateSource? = nil,
        enqueueCanonicalSync: Bool = true,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> Result<PPTransaction, AppError> {
        if let error = guardLegacyTransactionMutationAllowed(source: mutationSource) {
            return .failure(error)
        }
        // T5: 年度ロックガード（段階的チェック）
        guard !cannotPostNormalEntry(for: date) else {
            return .failure(.yearLocked(year: fiscalYear(for: date, startMonth: FiscalYearSettings.startMonth)))
        }
        let safeCategoryId: String
        switch type {
        case .transfer:
            // 振替はカテゴリ不要。入力がなければ空文字を保持する。
            safeCategoryId = categoryId
        case .income, .expense:
            safeCategoryId = categoryId.isEmpty ? Self.defaultCategoryId(for: type) : categoryId
        }
        let baseAllocations = type == .transfer ? [] : allocations
        let allocs = calculateRatioAllocations(amount: amount, allocations: baseAllocations)
        let explicitTaxCodeId = TaxCode.resolve(
            legacyCategory: taxCategory,
            taxRate: taxRate
        )?.rawValue
        let resolvedCounterparty = resolveLegacyCounterpartyReference(
            explicitId: counterpartyId,
            rawName: counterparty,
            defaultTaxCodeId: explicitTaxCodeId
        )
        let transaction = PPTransaction(
            type: type,
            amount: amount,
            date: date,
            categoryId: safeCategoryId,
            memo: memo,
            allocations: allocs,
            recurringId: recurringId,
            receiptImagePath: receiptImagePath,
            lineItems: lineItems,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            taxAmount: taxAmount,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyId: resolvedCounterparty.id,
            counterparty: resolvedCounterparty.displayName
        )
        modelContext.insert(transaction)

        // canonical正本では legacy journal を生成しない

        save()
        refreshTransactions()
        refreshJournalEntries()
        refreshJournalLines()
        if enqueueCanonicalSync {
            enqueueCanonicalTransactionSync(for: transaction.id, source: candidateSource)
        }
        return .success(transaction)
    }

    @discardableResult
    func addTransaction(
        type: TransactionType,
        amount: Int,
        date: Date,
        categoryId: String,
        memo: String,
        allocations: [(projectId: UUID, ratio: Int)],
        recurringId: UUID? = nil,
        receiptImagePath: String? = nil,
        lineItems: [ReceiptLineItem] = [],
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        taxAmount: Int? = nil,
        taxRate: Int? = nil,
        isTaxIncluded: Bool? = nil,
        taxCategory: TaxCategory? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil,
        candidateSource: CandidateSource? = nil,
        enqueueCanonicalSync: Bool = true,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> PPTransaction {
        switch addTransactionResult(
            type: type,
            amount: amount,
            date: date,
            categoryId: categoryId,
            memo: memo,
            allocations: allocations,
            recurringId: recurringId,
            receiptImagePath: receiptImagePath,
            lineItems: lineItems,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            taxAmount: taxAmount,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            counterpartyId: counterpartyId,
            counterparty: counterparty,
            candidateSource: candidateSource,
            enqueueCanonicalSync: enqueueCanonicalSync,
            mutationSource: mutationSource
        ) {
        case .success(let transaction):
            return transaction
        case .failure(let error):
            preconditionFailure("DataStore.addTransaction failed: \(error.localizedDescription). Use addTransactionResult() for failure handling.")
        }
    }

    @discardableResult
    func updateTransaction(
        id: UUID,
        type: TransactionType? = nil,
        amount: Int? = nil,
        date: Date? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        allocations: [(projectId: UUID, ratio: Int)]? = nil,
        receiptImagePath: String?? = nil,
        lineItems: [ReceiptLineItem]? = nil,
        paymentAccountId: String?? = nil,
        transferToAccountId: String?? = nil,
        taxDeductibleRate: Int?? = nil,
        taxAmount: Int?? = nil,
        taxRate: Int?? = nil,
        isTaxIncluded: Bool?? = nil,
        taxCategory: TaxCategory?? = nil,
        counterpartyId: UUID?? = nil,
        counterparty: String?? = nil,
        candidateSource: CandidateSource? = nil,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) -> Bool {
        if guardLegacyTransactionMutationAllowed(source: mutationSource) != nil {
            return false
        }
        guard let transaction = transactions.first(where: { $0.id == id }) else {
            lastError = .transactionNotFound(id: id)
            return false
        }
        // T5: 年度ロックガード（段階的チェック：変更先の日付と現在の日付の両方）
        if cannotPostNormalEntry(for: transaction.date) {
            return false
        }
        if let date, cannotPostNormalEntry(for: date) {
            return false
        }
        lastError = nil
        // Phase 9: 監査ログ（変更前の値を記録）
        let txId = transaction.id
        if let type {
            logFieldChange(transactionId: txId, fieldName: "type", oldValue: transaction.type.rawValue, newValue: type.rawValue)
            transaction.type = type
        }
        if let date {
            logFieldChange(transactionId: txId, fieldName: "date", oldValue: transaction.date.ISO8601Format(), newValue: date.ISO8601Format())
            transaction.date = date
        }
        if let categoryId {
            logFieldChange(transactionId: txId, fieldName: "categoryId", oldValue: transaction.categoryId, newValue: categoryId)
            transaction.categoryId = categoryId
        }
        if let memo {
            logFieldChange(transactionId: txId, fieldName: "memo", oldValue: transaction.memo, newValue: memo)
            transaction.memo = memo
        }
        if let receiptImagePath {
            logFieldChange(transactionId: txId, fieldName: "receiptImagePath", oldValue: transaction.receiptImagePath, newValue: receiptImagePath)
            transaction.receiptImagePath = receiptImagePath
        }
        if let lineItems { transaction.lineItems = lineItems }
        if let paymentAccountId {
            logFieldChange(transactionId: txId, fieldName: "paymentAccountId", oldValue: transaction.paymentAccountId, newValue: paymentAccountId)
            transaction.paymentAccountId = paymentAccountId
        }
        if let transferToAccountId {
            logFieldChange(transactionId: txId, fieldName: "transferToAccountId", oldValue: transaction.transferToAccountId, newValue: transferToAccountId)
            transaction.transferToAccountId = transferToAccountId
        }
        if let taxDeductibleRate {
            logFieldChange(transactionId: txId, fieldName: "taxDeductibleRate", oldValue: transaction.taxDeductibleRate.map(String.init), newValue: taxDeductibleRate.map(String.init))
            transaction.taxDeductibleRate = taxDeductibleRate
        }
        if let taxAmount {
            logFieldChange(transactionId: txId, fieldName: "taxAmount", oldValue: transaction.taxAmount.map(String.init), newValue: taxAmount.map(String.init))
            transaction.taxAmount = taxAmount
        }
        if let taxRate {
            logFieldChange(transactionId: txId, fieldName: "taxRate", oldValue: transaction.taxRate.map(String.init), newValue: taxRate.map(String.init))
            transaction.taxRate = taxRate
        }
        if let isTaxIncluded {
            logFieldChange(transactionId: txId, fieldName: "isTaxIncluded", oldValue: transaction.isTaxIncluded.map(String.init), newValue: isTaxIncluded.map(String.init))
            transaction.isTaxIncluded = isTaxIncluded
        }
        if let taxCategory {
            logFieldChange(transactionId: txId, fieldName: "taxCategory", oldValue: transaction.taxCategory?.rawValue, newValue: taxCategory?.rawValue)
            transaction.taxCategory = taxCategory
        }
        if let counterpartyId {
            logFieldChange(
                transactionId: txId,
                fieldName: "counterpartyId",
                oldValue: transaction.counterpartyId?.uuidString,
                newValue: counterpartyId?.uuidString
            )
            transaction.counterpartyId = counterpartyId
        }
        if let counterparty {
            logFieldChange(transactionId: txId, fieldName: "counterparty", oldValue: transaction.counterparty, newValue: counterparty)
            transaction.counterparty = counterparty
        }

        if counterpartyId != nil || counterparty != nil {
            let explicitTaxCodeId = TaxCode.resolve(
                legacyCategory: taxCategory ?? transaction.taxCategory,
                taxRate: taxRate ?? transaction.taxRate
            )?.rawValue
            let resolvedCounterparty = resolveLegacyCounterpartyReference(
                explicitId: transaction.counterpartyId,
                rawName: transaction.counterparty,
                defaultTaxCodeId: explicitTaxCodeId
            )
            transaction.counterpartyId = resolvedCounterparty.id
            transaction.counterparty = resolvedCounterparty.displayName
        }

        let finalAmount = amount ?? transaction.amount
        if let amount {
            logFieldChange(transactionId: txId, fieldName: "amount", oldValue: String(transaction.amount), newValue: String(amount))
            transaction.amount = amount
        }

        if let allocations {
            transaction.allocations = calculateRatioAllocations(amount: finalAmount, allocations: allocations)
            // H10: equalAll定期取引の配分をユーザーが手動変更した場合にフラグを立てる
            if let recurringId = transaction.recurringId,
               let recurring = recurringTransactions.first(where: { $0.id == recurringId }),
               recurring.allocationMode == .equalAll {
                transaction.isManuallyEdited = true
            }
        } else if amount != nil {
            transaction.allocations = recalculateAllocationAmounts(amount: finalAmount, existingAllocations: transaction.allocations)
            // H8: 金額変更時、pro-rata調整を再適用（ユーザー指定allocationsの場合は意図を尊重し適用しない）
            reapplyProRataIfNeeded(transaction: transaction, amount: finalAmount)
        }

        transaction.updatedAt = Date()

        // canonical正本では legacy journal を再生成しない

        save()
        refreshTransactions()
        refreshJournalEntries()
        refreshJournalLines()
        enqueueCanonicalTransactionSync(for: transaction.id, source: candidateSource)
        return true
    }

    func deleteTransaction(
        id: UUID,
        mutationSource: LegacyTransactionMutationSource = .systemGenerated
    ) {
        if guardLegacyTransactionMutationAllowed(source: mutationSource) != nil {
            return
        }
        guard let transaction = allTransactions.first(where: { $0.id == id }) else { return }
        // T5: 年度ロックガード（段階的チェック）
        if cannotPostNormalEntry(for: transaction.date) { return }

        // ソフトデリート: 物理削除ではなく deletedAt を設定
        transaction.deletedAt = Date()
        transaction.updatedAt = Date()

        // canonical正本では legacy journal を削除しない

        save()
        refreshTransactions()
        refreshJournalEntries()
        refreshJournalLines()

        // Roll back recurring generation tracking so the deleted period can be regenerated
        if let recurringId = transaction.recurringId, let recurring = recurringTransactions.first(where: { $0.id == recurringId }) {
            rollBackRecurringGenerationState(recurring: recurring, deletedTransactionDate: transaction.date)
        }
    }

    /// Roll back recurring generation tracking after a linked transaction is deleted.
    /// Allows processRecurringTransactions() to regenerate the deleted period on next run.
    private func rollBackRecurringGenerationState(
        recurring: PPRecurringTransaction,
        deletedTransactionDate: Date
    ) {
        let calendar = Calendar.current

        // Find remaining transactions still linked to this recurring template
        let remainingTransactions = transactions
            .filter { $0.recurringId == recurring.id }
            .sorted { $0.date < $1.date }

        if recurring.frequency == .yearly,
           recurring.yearlyAmortizationMode == .monthlySpread {
            // Monthly spread mode: remove the deleted month key from lastGeneratedMonths
            let deletedComps = calendar.dateComponents([.year, .month], from: deletedTransactionDate)
            if let year = deletedComps.year, let month = deletedComps.month {
                let monthKey = String(format: "%d-%02d", year, month)
                recurring.lastGeneratedMonths = recurring.lastGeneratedMonths.filter { $0 != monthKey }
            }
            // Also update lastGeneratedDate to the latest remaining transaction date, or nil
            recurring.lastGeneratedDate = remainingTransactions.last?.date
        } else {
            // Monthly or Yearly (lumpSum): set lastGeneratedDate to the latest
            // remaining linked transaction's date, or nil if none remain.
            recurring.lastGeneratedDate = remainingTransactions.last?.date
        }

        recurring.updatedAt = Date()
        save()
        refreshRecurring()
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
        // 同名・同タイプの重複チェック: 既存があればそれを返す
        if let existing = categories.first(where: { $0.type == type && $0.name == name }) {
            return existing
        }
        let category = PPCategory(id: UUID().uuidString, name: name, type: type, icon: icon)
        modelContext.insert(category)
        save()
        refreshCategories()
        return category
    }

    func updateCategory(id: String, name: String? = nil, type: CategoryType? = nil, icon: String? = nil) {
        guard let category = categories.first(where: { $0.id == id }) else { return }
        if let name {
            let targetType = type ?? category.type
            if categories.contains(where: { $0.id != id && $0.type == targetType && $0.name == name }) {
                return
            }
            category.name = name
        }
        if let type { category.type = type }
        if let icon { category.icon = icon }
        save()
        refreshCategories()
    }

    func updateCategoryLinkedAccount(categoryId: String, accountId: String?) {
        guard let category = categories.first(where: { $0.id == categoryId }) else { return }
        category.linkedAccountId = accountId
        save()
        refreshCategories()
    }

    func deleteCategory(id: String) {
        guard let category = categories.first(where: { $0.id == id }) else { return }
        guard !category.isDefault else { return }

        // タイプに応じたフォールバックカテゴリ
        let fallbackId: String = switch category.type {
        case .expense: "cat-other-expense"
        case .income: "cat-other-income"
        }

        // 参照しているトランザクションを移行
        let now = Date()
        for transaction in transactions where transaction.categoryId == id {
            transaction.categoryId = fallbackId
            transaction.updatedAt = now
        }
        for recurring in recurringTransactions where recurring.categoryId == id {
            recurring.categoryId = fallbackId
            recurring.updatedAt = now
        }

        modelContext.delete(category)
        save()
        refreshCategories()
        refreshTransactions()
        refreshRecurring()
    }

    func getCategory(id: String) -> PPCategory? {
        categories.first { $0.id == id }
    }

    static func defaultCategoryId(for type: TransactionType) -> String {
        switch type {
        case .expense, .transfer: "cat-other-expense"
        case .income: "cat-other-income"
        }
    }

    // MARK: - Recurring CRUD

    @discardableResult
    func addRecurring(
        name: String,
        type: TransactionType,
        amount: Int,
        categoryId: String,
        memo: String,
        allocationMode: AllocationMode = .manual,
        allocations: [(projectId: UUID, ratio: Int)],
        frequency: RecurringFrequency,
        dayOfMonth: Int,
        monthOfYear: Int? = nil,
        endDate: Date? = nil,
        yearlyAmortizationMode: YearlyAmortizationMode = .lumpSum,
        receiptImagePath: String? = nil,
        paymentAccountId: String? = nil,
        transferToAccountId: String? = nil,
        taxDeductibleRate: Int? = nil,
        counterpartyId: UUID? = nil,
        counterparty: String? = nil
    ) -> PPRecurringTransaction {
        let safeCategoryId = categoryId.isEmpty ? Self.defaultCategoryId(for: type) : categoryId
        let allocs: [Allocation]
        switch allocationMode {
        case .equalAll:
            allocs = []
        case .manual:
            allocs = calculateRatioAllocations(amount: amount, allocations: allocations)
        }
        let resolvedCounterparty = resolveLegacyCounterpartyReference(
            explicitId: counterpartyId,
            rawName: counterparty,
            defaultTaxCodeId: nil
        )
        let recurring = PPRecurringTransaction(
            name: name,
            type: type,
            amount: amount,
            categoryId: safeCategoryId,
            memo: memo,
            allocationMode: allocationMode,
            allocations: allocs,
            frequency: frequency,
            dayOfMonth: dayOfMonth,
            monthOfYear: monthOfYear,
            endDate: endDate,
            yearlyAmortizationMode: yearlyAmortizationMode,
            receiptImagePath: receiptImagePath,
            paymentAccountId: paymentAccountId,
            transferToAccountId: transferToAccountId,
            taxDeductibleRate: taxDeductibleRate,
            counterpartyId: resolvedCounterparty.id,
            counterparty: resolvedCounterparty.displayName
        )
        modelContext.insert(recurring)
        save()
        refreshRecurring()
        onRecurringScheduleChanged?(recurringTransactions)
        enqueueCanonicalRecurringCounterpartySync(for: recurring.id)
        return recurring
    }

    func updateRecurring(
        id: UUID,
        name: String? = nil,
        type: TransactionType? = nil,
        amount: Int? = nil,
        categoryId: String? = nil,
        memo: String? = nil,
        allocationMode: AllocationMode? = nil,
        allocations: [(projectId: UUID, ratio: Int)]? = nil,
        frequency: RecurringFrequency? = nil,
        dayOfMonth: Int? = nil,
        monthOfYear: Int? = nil,
        isActive: Bool? = nil,
        endDate: Date?? = nil,
        yearlyAmortizationMode: YearlyAmortizationMode? = nil,
        notificationTiming: NotificationTiming? = nil,
        skipDates: [Date]? = nil,
        receiptImagePath: String?? = nil,
        paymentAccountId: String?? = nil,
        transferToAccountId: String?? = nil,
        taxDeductibleRate: Int?? = nil,
        counterpartyId: UUID?? = nil,
        counterparty: String?? = nil
    ) {
        guard let recurring = recurringTransactions.first(where: { $0.id == id }) else { return }
        if let name { recurring.name = name }
        if let type { recurring.type = type }
        if let categoryId { recurring.categoryId = categoryId }
        if let memo { recurring.memo = memo }
        if let allocationMode { recurring.allocationMode = allocationMode }
        if let frequency {
            let frequencyChanged = recurring.frequency != frequency
            recurring.frequency = frequency
            if frequency == .monthly {
                recurring.monthOfYear = nil
                // monthlyに変更した場合、月次分割モードをクリア
                recurring.yearlyAmortizationMode = .lumpSum
                recurring.lastGeneratedMonths = []
                if frequencyChanged {
                    recurring.lastGeneratedDate = nil
                }
            } else {
                if let monthOfYear {
                    recurring.monthOfYear = (1...12).contains(monthOfYear) ? monthOfYear : recurring.monthOfYear
                }
                if frequencyChanged {
                    recurring.lastGeneratedDate = nil
                    recurring.lastGeneratedMonths = []
                }
            }
        } else if let monthOfYear {
            recurring.monthOfYear = (1...12).contains(monthOfYear) ? monthOfYear : recurring.monthOfYear
        }
        if let dayOfMonth { recurring.dayOfMonth = min(28, max(1, dayOfMonth)) }
        if let isActive { recurring.isActive = isActive }
        if let endDate { recurring.endDate = endDate }
        if let yearlyAmortizationMode {
            let previousMode = recurring.yearlyAmortizationMode
            recurring.yearlyAmortizationMode = yearlyAmortizationMode
            // モード切替時の処理
            if previousMode != yearlyAmortizationMode {
                if yearlyAmortizationMode == .lumpSum {
                    // 月次→一括: lastGeneratedMonthsをクリア
                    recurring.lastGeneratedMonths = []
                }
                // 一括→月次: lastGeneratedDateが今年ならその年は生成しない（既存ロジックで対応）
            }
        }
        if let notificationTiming { recurring.notificationTiming = notificationTiming }
        if let skipDates { recurring.skipDates = skipDates }
        if let receiptImagePath { recurring.receiptImagePath = receiptImagePath }
        if let paymentAccountId { recurring.paymentAccountId = paymentAccountId }
        if let transferToAccountId { recurring.transferToAccountId = transferToAccountId }
        if let taxDeductibleRate { recurring.taxDeductibleRate = taxDeductibleRate }
        if let counterpartyId { recurring.counterpartyId = counterpartyId }
        if let counterparty { recurring.counterparty = counterparty }
        if counterpartyId != nil || counterparty != nil {
            let resolvedCounterparty = resolveLegacyCounterpartyReference(
                explicitId: recurring.counterpartyId,
                rawName: recurring.counterparty,
                defaultTaxCodeId: nil
            )
            recurring.counterpartyId = resolvedCounterparty.id
            recurring.counterparty = resolvedCounterparty.displayName
        }

        let resolvedMode = allocationMode ?? recurring.allocationMode
        let finalAmount = amount ?? recurring.amount
        if let amount { recurring.amount = amount }

        switch resolvedMode {
        case .equalAll:
            recurring.allocations = []
        case .manual:
            if let allocations {
                recurring.allocations = calculateRatioAllocations(amount: finalAmount, allocations: allocations)
            } else if amount != nil {
                recurring.allocations = recalculateAllocationAmounts(amount: finalAmount, existingAllocations: recurring.allocations)
            }
        }

        recurring.updatedAt = Date()
        save()
        refreshRecurring()
        onRecurringScheduleChanged?(recurringTransactions)
        enqueueCanonicalRecurringCounterpartySync(for: recurring.id)
    }

    func deleteRecurring(id: UUID) {
        guard let recurring = recurringTransactions.first(where: { $0.id == id }) else { return }

        // 生成済みトランザクションの recurringId をクリア（ダングリング参照防止）
        let now = Date()
        for transaction in transactions where transaction.recurringId == id {
            transaction.recurringId = nil
            transaction.updatedAt = now
        }

        // C4: save成功後に削除するため画像パスを保持
        let imageToDelete = recurring.receiptImagePath
        modelContext.delete(recurring)
        if save() {
            if let imagePath = imageToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
        }
        refreshRecurring()
        refreshTransactions()
        onRecurringScheduleChanged?(recurringTransactions)
    }

    func getRecurring(id: UUID) -> PPRecurringTransaction? {
        recurringTransactions.first { $0.id == id }
    }

    // MARK: - Pro-Rata Reallocation

    /// equalAll定期取引の今期分トランザクションを、現在のアクティブプロジェクト一覧で再分配する
    private func reprocessEqualAllCurrentPeriodTransactions() {
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

    /// 1件の定期取引から実取引を生成する共通ヘルパー
    @discardableResult
    private func createTransactionFromRecurring(
        _ recurring: PPRecurringTransaction,
        txDate: Date,
        isYearly: Bool,
        calendar: Calendar
    ) -> PPTransaction? {
        let memo = "[定期] \(recurring.name)" + (recurring.memo.isEmpty ? "" : " - \(recurring.memo)")
        var txAllocations: [Allocation]
        switch recurring.allocationMode {
        case .equalAll:
            // H9: アーカイブ済みプロジェクトを除外
            let activeProjectIds = projects.filter { $0.status == .active && $0.isArchived != true }.map(\.id)
            let completedThisMonth = projects.filter { p in
                guard p.status == .completed, p.isArchived != true, let completedAt = p.completedAt else { return false }
                let compComps = calendar.dateComponents([.year, .month], from: completedAt)
                let txComps = calendar.dateComponents([.year, .month], from: txDate)
                return compComps.year == txComps.year && compComps.month == txComps.month
            }
            let allEligibleIds = activeProjectIds + completedThisMonth.map(\.id)
            guard !allEligibleIds.isEmpty else { return nil }
            txAllocations = calculateEqualSplitAllocations(amount: recurring.amount, projectIds: allEligibleIds)

            let txCompsEq = calendar.dateComponents([.year, .month], from: txDate)
            if let txYear = txCompsEq.year, let txMonth = txCompsEq.month {
                let totalDays = isYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
                let needsProRata = txAllocations.contains { alloc in
                    guard let project = projects.first(where: { $0.id == alloc.projectId }) else { return false }
                    let activeDays = isYearly
                        ? calculateActiveDaysInYear(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear)
                        : calculateActiveDaysInMonth(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear, month: txMonth)
                    return activeDays < totalDays
                }
                if needsProRata {
                    let inputs: [HolisticProRataInput] = txAllocations.map { alloc in
                        let project = projects.first { $0.id == alloc.projectId }
                        let activeDays = isYearly
                            ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                            : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                        return HolisticProRataInput(projectId: alloc.projectId, ratio: alloc.ratio, activeDays: activeDays)
                    }
                    txAllocations = calculateHolisticProRata(
                        totalAmount: recurring.amount,
                        totalDays: totalDays,
                        inputs: inputs
                    )
                }
            }
        case .manual:
            txAllocations = recalculateAllocationAmounts(amount: recurring.amount, existingAllocations: recurring.allocations)
            let txCompsMan = calendar.dateComponents([.year, .month], from: txDate)
            if let txYear = txCompsMan.year, let txMonth = txCompsMan.month {
                let totalDays = isYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
                let needsProRata = recurring.allocations.contains { alloc in
                    guard let project = projects.first(where: { $0.id == alloc.projectId }) else { return false }
                    return project.startDate != nil || project.effectiveEndDate != nil
                }
                if needsProRata {
                    let inputs: [HolisticProRataInput] = recurring.allocations.map { alloc in
                        let project = projects.first { $0.id == alloc.projectId }
                        let activeDays = isYearly
                            ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                            : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                        return HolisticProRataInput(projectId: alloc.projectId, ratio: alloc.ratio, activeDays: activeDays)
                    }
                    txAllocations = calculateHolisticProRata(
                        totalAmount: recurring.amount,
                        totalDays: totalDays,
                        inputs: inputs
                    )
                }
            }
        }
        let txRatios = txAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) }
        switch addTransactionResult(
            type: recurring.type,
            amount: recurring.amount,
            date: txDate,
            categoryId: recurring.categoryId,
            memo: memo,
            allocations: txRatios,
            recurringId: recurring.id,
            paymentAccountId: recurring.paymentAccountId,
            transferToAccountId: recurring.transferToAccountId,
            taxDeductibleRate: recurring.taxDeductibleRate,
            counterpartyId: recurring.counterpartyId,
            counterparty: recurring.counterparty,
            candidateSource: .recurring
        ) {
        case .success(let transaction):
            transaction.allocations = txAllocations
            transaction.updatedAt = Date()
            return transaction
        case .failure:
            return nil
        }
    }

    /// 定期取引の生成プレビュー（dry-run）。実際の取引は生成しない。
    func previewRecurringTransactions() -> [RecurringPreviewItem] {
        let calendar = Calendar.current
        let today = todayDate()
        let todayComps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentYear = todayComps.year, let currentMonth = todayComps.month, let currentDay = todayComps.day else { return [] }

        var items: [RecurringPreviewItem] = []

        for recurring in recurringTransactions {
            guard recurring.isActive else { continue }
            if recurring.allocationMode == .manual && recurring.allocations.isEmpty { continue }

            let projectName = recurring.allocations.first.flatMap { alloc in
                projects.first(where: { $0.id == alloc.projectId })?.name
            }

            if recurring.frequency == .monthly {
                var iterYear: Int
                var iterMonth: Int

                if let lastGen = recurring.lastGeneratedDate {
                    let lastComps = calendar.dateComponents([.year, .month], from: lastGen)
                    iterYear = lastComps.year!
                    iterMonth = lastComps.month!
                    iterMonth += 1
                    if iterMonth > 12 { iterMonth = 1; iterYear += 1 }
                } else {
                    iterYear = currentYear
                    iterMonth = currentMonth
                }

                while iterYear < currentYear || (iterYear == currentYear && iterMonth <= currentMonth) {
                    if iterYear == currentYear && iterMonth == currentMonth && currentDay < recurring.dayOfMonth { break }

                    guard let txDate = calendar.date(from: DateComponents(year: iterYear, month: iterMonth, day: recurring.dayOfMonth)) else {
                        iterMonth += 1
                        if iterMonth > 12 { iterMonth = 1; iterYear += 1 }
                        continue
                    }

                    if let endDate = recurring.endDate, txDate > endDate { break }

                    let yearLocked = isYearLocked(for: txDate)
                    let isSkipped = recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: txDate) }
                    if !yearLocked && !isSkipped {
                        items.append(RecurringPreviewItem(
                            recurringId: recurring.id,
                            recurringName: recurring.name,
                            type: recurring.type,
                            amount: recurring.amount,
                            scheduledDate: txDate,
                            categoryId: recurring.categoryId,
                            memo: "[定期] \(recurring.name)",
                            projectName: projectName,
                            allocationMode: recurring.allocationMode
                        ))
                    }

                    iterMonth += 1
                    if iterMonth > 12 { iterMonth = 1; iterYear += 1 }
                }
            } else if recurring.yearlyAmortizationMode == .monthlySpread {
                if let endDate = recurring.endDate, today > endDate { continue }
                let startMonth = recurring.monthOfYear ?? 1
                let actualMonthCount = 12 - startMonth + 1
                let monthlyAmount = recurring.amount / actualMonthCount
                let remainder = recurring.amount - (monthlyAmount * actualMonthCount)
                let currentYearPrefix = String(format: "%d-", currentYear)
                let generatedMonths = recurring.lastGeneratedMonths.filter { $0.hasPrefix(currentYearPrefix) }

                for month in startMonth...12 {
                    guard currentMonth > month || (currentMonth == month && currentDay >= recurring.dayOfMonth) else { continue }
                    let monthKey = String(format: "%d-%02d", currentYear, month)
                    guard !generatedMonths.contains(monthKey) else { continue }
                    guard let txDate = calendar.date(from: DateComponents(year: currentYear, month: month, day: recurring.dayOfMonth)) else { continue }
                    if let endDate = recurring.endDate, txDate > endDate { continue }
                    if isYearLocked(for: txDate) { continue }
                    let isSkipped = recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: txDate) }
                    if !isSkipped {
                        let txAmount = month == 12 ? monthlyAmount + remainder : monthlyAmount
                        items.append(RecurringPreviewItem(
                            recurringId: recurring.id,
                            recurringName: recurring.name,
                            type: recurring.type,
                            amount: txAmount,
                            scheduledDate: txDate,
                            categoryId: recurring.categoryId,
                            memo: "[定期/月次] \(recurring.name)",
                            isMonthlySpread: true,
                            projectName: projectName,
                            allocationMode: recurring.allocationMode
                        ))
                    }
                }
            } else {
                let targetMonth = recurring.monthOfYear ?? 1
                let startYear: Int
                if let lastGen = recurring.lastGeneratedDate {
                    startYear = calendar.component(.year, from: lastGen) + 1
                } else {
                    startYear = currentYear
                }
                guard startYear <= currentYear else { continue }
                for iterYear in startYear...currentYear {
                    if iterYear == currentYear {
                        if currentMonth < targetMonth || (currentMonth == targetMonth && currentDay < recurring.dayOfMonth) { break }
                    }
                    guard let txDate = calendar.date(from: DateComponents(year: iterYear, month: targetMonth, day: recurring.dayOfMonth)) else { continue }
                    if let endDate = recurring.endDate, txDate > endDate { break }
                    if isYearLocked(for: txDate) { continue }
                    let isSkipped = recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: txDate) }
                    if !isSkipped {
                        items.append(RecurringPreviewItem(
                            recurringId: recurring.id,
                            recurringName: recurring.name,
                            type: recurring.type,
                            amount: recurring.amount,
                            scheduledDate: txDate,
                            categoryId: recurring.categoryId,
                            memo: "[定期] \(recurring.name)",
                            projectName: projectName,
                            allocationMode: recurring.allocationMode
                        ))
                    }
                }
            }
        }

        return items.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    /// 指定されたプレビュー項目のみを実際に処理する（承認フロー）
    func approveRecurringItems(_ approvedIds: Set<UUID>, from items: [RecurringPreviewItem]) async -> Int {
        let approvedItems = items.filter { approvedIds.contains($0.id) }
        var generatedCount = 0

        for item in approvedItems {
            guard let recurring = recurringTransactions.first(where: { $0.id == item.recurringId }) else { continue }
            if isYearLocked(for: item.scheduledDate) { continue }
            let calendar = Calendar.current
            let txDate = item.scheduledDate

            if item.isMonthlySpread {
                let monthKey = String(format: "%d-%02d", calendar.component(.year, from: txDate), calendar.component(.month, from: txDate))
                let memo = "[定期/月次] \(recurring.name)" + (recurring.memo.isEmpty ? "" : " - \(recurring.memo)")

                var txAllocations: [Allocation]
                switch recurring.allocationMode {
                case .equalAll:
                    let activeProjectIds = projects.filter { $0.status == .active && $0.isArchived != true }.map(\.id)
                    guard !activeProjectIds.isEmpty else { continue }
                    txAllocations = calculateEqualSplitAllocations(amount: item.amount, projectIds: activeProjectIds)
                case .manual:
                    txAllocations = recalculateAllocationAmounts(amount: item.amount, existingAllocations: recurring.allocations)
                }

                let txRatios = txAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) }
                let result = await saveApprovedPosting(
                    type: recurring.type,
                    amount: item.amount,
                    date: txDate,
                    categoryId: recurring.categoryId,
                    memo: memo,
                    allocations: txRatios,
                    recurringId: recurring.id,
                    paymentAccountId: recurring.paymentAccountId,
                    transferToAccountId: recurring.transferToAccountId,
                    taxDeductibleRate: recurring.taxDeductibleRate,
                    counterpartyId: recurring.counterpartyId,
                    counterparty: recurring.counterparty,
                    candidateSource: .recurring
                )
                switch result {
                case .success:
                    recurring.lastGeneratedMonths = recurring.lastGeneratedMonths + [monthKey]
                    recurring.updatedAt = Date()
                    generatedCount += 1
                case .failure:
                    break
                }
            } else {
                let isYearly = recurring.frequency == .yearly
                let memo = "[定期] \(recurring.name)" + (recurring.memo.isEmpty ? "" : " - \(recurring.memo)")
                var txAllocations: [Allocation]
                switch recurring.allocationMode {
                case .equalAll:
                    let activeProjectIds = projects.filter { $0.status == .active && $0.isArchived != true }.map(\.id)
                    let completedThisMonth = projects.filter { project in
                        guard project.status == .completed,
                              project.isArchived != true,
                              let completedAt = project.completedAt
                        else {
                            return false
                        }
                        let completedComponents = calendar.dateComponents([.year, .month], from: completedAt)
                        let txComponents = calendar.dateComponents([.year, .month], from: txDate)
                        return completedComponents.year == txComponents.year && completedComponents.month == txComponents.month
                    }
                    let allEligibleIds = activeProjectIds + completedThisMonth.map(\.id)
                    guard !allEligibleIds.isEmpty else { continue }
                    txAllocations = calculateEqualSplitAllocations(amount: recurring.amount, projectIds: allEligibleIds)

                    let txComponents = calendar.dateComponents([.year, .month], from: txDate)
                    if let txYear = txComponents.year, let txMonth = txComponents.month {
                        let totalDays = isYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
                        let needsProRata = txAllocations.contains { allocation in
                            guard let project = projects.first(where: { $0.id == allocation.projectId }) else { return false }
                            let activeDays = isYearly
                                ? calculateActiveDaysInYear(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear)
                                : calculateActiveDaysInMonth(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear, month: txMonth)
                            return activeDays < totalDays
                        }
                        if needsProRata {
                            let inputs: [HolisticProRataInput] = txAllocations.map { allocation in
                                let project = projects.first { $0.id == allocation.projectId }
                                let activeDays = isYearly
                                    ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                                    : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                                return HolisticProRataInput(projectId: allocation.projectId, ratio: allocation.ratio, activeDays: activeDays)
                            }
                            txAllocations = calculateHolisticProRata(
                                totalAmount: recurring.amount,
                                totalDays: totalDays,
                                inputs: inputs
                            )
                        }
                    }
                case .manual:
                    txAllocations = recalculateAllocationAmounts(amount: recurring.amount, existingAllocations: recurring.allocations)
                    let txComponents = calendar.dateComponents([.year, .month], from: txDate)
                    if let txYear = txComponents.year, let txMonth = txComponents.month {
                        let totalDays = isYearly ? daysInYear(txYear) : daysInMonth(year: txYear, month: txMonth)
                        let needsProRata = recurring.allocations.contains { allocation in
                            guard let project = projects.first(where: { $0.id == allocation.projectId }) else { return false }
                            return project.startDate != nil || project.effectiveEndDate != nil
                        }
                        if needsProRata {
                            let inputs: [HolisticProRataInput] = recurring.allocations.map { allocation in
                                let project = projects.first { $0.id == allocation.projectId }
                                let activeDays = isYearly
                                    ? calculateActiveDaysInYear(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear)
                                    : calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                                return HolisticProRataInput(projectId: allocation.projectId, ratio: allocation.ratio, activeDays: activeDays)
                            }
                            txAllocations = calculateHolisticProRata(
                                totalAmount: recurring.amount,
                                totalDays: totalDays,
                                inputs: inputs
                            )
                        }
                    }
                }

                let txRatios = txAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) }
                let result = await saveApprovedPosting(
                    type: recurring.type,
                    amount: recurring.amount,
                    date: txDate,
                    categoryId: recurring.categoryId,
                    memo: memo,
                    allocations: txRatios,
                    recurringId: recurring.id,
                    paymentAccountId: recurring.paymentAccountId,
                    transferToAccountId: recurring.transferToAccountId,
                    taxDeductibleRate: recurring.taxDeductibleRate,
                    counterpartyId: recurring.counterpartyId,
                    counterparty: recurring.counterparty,
                    candidateSource: .recurring
                )
                if case .success = result {
                    recurring.lastGeneratedDate = txDate
                    recurring.updatedAt = Date()
                    generatedCount += 1
                }
            }
        }

        if generatedCount > 0 {
            save()
            refreshRecurring()
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

        return generatedCount
    }

    @discardableResult
    func processRecurringTransactions() -> Int {
        let calendar = Calendar.current
        let today = todayDate()
        let todayComps = calendar.dateComponents([.year, .month, .day], from: today)
        guard let currentYear = todayComps.year, let currentMonth = todayComps.month, let currentDay = todayComps.day else { return 0 }

        var generatedCount = 0

        for recurring in recurringTransactions {
            guard recurring.isActive else { continue }
            if recurring.allocationMode == .manual && recurring.allocations.isEmpty { continue }

            if recurring.frequency == .monthly {
                // 月次キャッチアップループ: lastGeneratedDate の翌月から現在月まで
                var iterYear: Int
                var iterMonth: Int

                if let lastGen = recurring.lastGeneratedDate {
                    let lastComps = calendar.dateComponents([.year, .month], from: lastGen)
                    iterYear = lastComps.year!
                    iterMonth = lastComps.month!
                    // lastGeneratedDate の翌月から開始
                    iterMonth += 1
                    if iterMonth > 12 {
                        iterMonth = 1
                        iterYear += 1
                    }
                } else {
                    // 初回: 現在月から
                    iterYear = currentYear
                    iterMonth = currentMonth
                }

                while iterYear < currentYear || (iterYear == currentYear && iterMonth <= currentMonth) {
                    // 今月の場合、dayOfMonth がまだ来ていなければ生成しない
                    if iterYear == currentYear && iterMonth == currentMonth && currentDay < recurring.dayOfMonth {
                        break
                    }

                    guard let txDate = calendar.date(from: DateComponents(year: iterYear, month: iterMonth, day: recurring.dayOfMonth)) else {
                        iterMonth += 1
                        if iterMonth > 12 { iterMonth = 1; iterYear += 1 }
                        continue
                    }

                    // endDate チェック
                    if let endDate = recurring.endDate, txDate > endDate { break }

                    // skipDates チェック
                    let isSkipped = recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: txDate) }
                    if isSkipped {
                        recurring.lastGeneratedDate = txDate
                        recurring.skipDates = recurring.skipDates.filter { !calendar.isDate($0, inSameDayAs: txDate) }
                        recurring.updatedAt = Date()
                    } else if createTransactionFromRecurring(recurring, txDate: txDate, isYearly: false, calendar: calendar) != nil {
                        recurring.lastGeneratedDate = txDate
                        recurring.updatedAt = Date()
                        generatedCount += 1
                    }

                    iterMonth += 1
                    if iterMonth > 12 { iterMonth = 1; iterYear += 1 }
                }
            } else if recurring.yearlyAmortizationMode == .monthlySpread {
                // endDateを過ぎた定期取引は月次分割前に停止チェック
                if let endDate = recurring.endDate, today > endDate {
                    recurring.isActive = false
                    recurring.updatedAt = Date()
                    continue
                }
                // 月次分割モード: monthOfYear月から12月まで毎月生成
                let generated = generateMonthlySpreadTransactions(
                    recurring: recurring,
                    currentYear: currentYear,
                    currentMonth: currentMonth,
                    currentDay: currentDay,
                    calendar: calendar
                )
                generatedCount += generated
                continue
            } else {
                // 年次キャッチアップループ: lastGeneratedDate の翌年から現在年まで
                let targetMonth = recurring.monthOfYear ?? 1
                let startYear: Int
                if let lastGen = recurring.lastGeneratedDate {
                    startYear = calendar.component(.year, from: lastGen) + 1
                } else {
                    startYear = currentYear
                }

                guard startYear <= currentYear else { continue }
                for iterYear in startYear...currentYear {
                    // 今年の場合、対象月/日がまだ来ていなければ生成しない
                    if iterYear == currentYear {
                        if currentMonth < targetMonth || (currentMonth == targetMonth && currentDay < recurring.dayOfMonth) {
                            break
                        }
                    }

                    guard let txDate = calendar.date(from: DateComponents(year: iterYear, month: targetMonth, day: recurring.dayOfMonth)) else { continue }

                    // endDate チェック
                    if let endDate = recurring.endDate, txDate > endDate { break }

                    // skipDates チェック
                    let isSkipped = recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: txDate) }
                    if isSkipped {
                        recurring.lastGeneratedDate = txDate
                        recurring.skipDates = recurring.skipDates.filter { !calendar.isDate($0, inSameDayAs: txDate) }
                        recurring.updatedAt = Date()
                    } else if createTransactionFromRecurring(recurring, txDate: txDate, isYearly: true, calendar: calendar) != nil {
                        recurring.lastGeneratedDate = txDate
                        recurring.updatedAt = Date()
                        generatedCount += 1
                    }
                }
            }

            // endDateを過ぎた定期取引はキャッチアップ完了後に自動停止
            if let endDate = recurring.endDate, today > endDate {
                recurring.isActive = false
                recurring.updatedAt = Date()
            }
        }

        if generatedCount > 0 {
            save()
            refreshRecurring()
            refreshTransactions()
            refreshJournalEntries()
            refreshJournalLines()
        }

        return generatedCount
    }

    // MARK: - Monthly Spread Generation

    /// 年次定期取引を月次分割で生成する
    /// monthOfYear月から12月まで、各月のdayOfMonth日に取引を生成する
    private func generateMonthlySpreadTransactions(
        recurring: PPRecurringTransaction,
        currentYear: Int,
        currentMonth: Int,
        currentDay: Int,
        calendar: Calendar
    ) -> Int {
        let startMonth = recurring.monthOfYear ?? 1
        var generatedCount = 0

        // 年が変わったら前年のエントリをクリア
        let currentYearPrefix = String(format: "%d-", currentYear)
        let filteredMonths = recurring.lastGeneratedMonths.filter { $0.hasPrefix(currentYearPrefix) }
        if filteredMonths.count != recurring.lastGeneratedMonths.count {
            recurring.lastGeneratedMonths = filteredMonths
        }

        // H4: 月額計算: 実際の生成月数で除算（年途中開始を考慮）
        let actualMonthCount = 12 - startMonth + 1
        let monthlyAmount = recurring.amount / actualMonthCount
        let remainder = recurring.amount - (monthlyAmount * actualMonthCount)

        // 最終生成月を事前計算（endDateやskipDatesを考慮し、端数を正しい月に加算するため）
        var lastEligibleMonth = 12
        if let endDate = recurring.endDate {
            for m in stride(from: 12, through: startMonth, by: -1) {
                if let d = calendar.date(from: DateComponents(year: currentYear, month: m, day: recurring.dayOfMonth)), d <= endDate {
                    lastEligibleMonth = m
                    break
                }
                if m == startMonth { lastEligibleMonth = startMonth }
            }
        }

        // H3: skipDatesを考慮して端数加算月を調整（スキップ月に端数が消失するのを防止）
        var foundEligibleMonth = false
        for m in stride(from: lastEligibleMonth, through: startMonth, by: -1) {
            guard let d = calendar.date(from: DateComponents(year: currentYear, month: m, day: recurring.dayOfMonth)) else { continue }
            if !recurring.skipDates.contains(where: { calendar.isDate($0, inSameDayAs: d) }) {
                lastEligibleMonth = m
                foundEligibleMonth = true
                break
            }
        }
        // 全月がスキップの場合、端数を付与する対象月がないためsentinel値を設定
        if !foundEligibleMonth {
            lastEligibleMonth = -1
        }

        for month in startMonth...12 {
            // まだ到来していない月はスキップ
            guard currentMonth > month || (currentMonth == month && currentDay >= recurring.dayOfMonth) else { continue }

            let monthKey = String(format: "%d-%02d", currentYear, month)

            // 重複防止
            guard !recurring.lastGeneratedMonths.contains(monthKey) else { continue }

            // endDateチェック
            guard let txDate = calendar.date(from: DateComponents(year: currentYear, month: month, day: recurring.dayOfMonth)) else { continue }
            if let endDate = recurring.endDate, txDate > endDate { continue }

            // skipDatesチェック
            let isSkipped = recurring.skipDates.contains { calendar.isDate($0, inSameDayAs: txDate) }
            if isSkipped {
                recurring.lastGeneratedMonths = recurring.lastGeneratedMonths + [monthKey]
                recurring.skipDates = recurring.skipDates.filter { !calendar.isDate($0, inSameDayAs: txDate) }
                recurring.updatedAt = Date()
                continue
            }

            // 最終生成月に端数を加算
            let txAmount = month == lastEligibleMonth ? monthlyAmount + remainder : monthlyAmount

            let memo = "[定期/月次] \(recurring.name)" + (recurring.memo.isEmpty ? "" : " - \(recurring.memo)")

            var txAllocations: [Allocation]
            switch recurring.allocationMode {
            case .equalAll:
                // H9: アーカイブ済みプロジェクトを除外
                let activeProjectIds = projects.filter { $0.status == .active && $0.isArchived != true }.map(\.id)
                let completedThisMonth = projects.filter { p in
                    guard p.status == .completed, p.isArchived != true, let completedAt = p.completedAt else { return false }
                    let compComps = calendar.dateComponents([.year, .month], from: completedAt)
                    return compComps.year == currentYear && compComps.month == month
                }
                let allEligibleIds = activeProjectIds + completedThisMonth.map(\.id)
                guard !allEligibleIds.isEmpty else { continue }
                txAllocations = calculateEqualSplitAllocations(amount: txAmount, projectIds: allEligibleIds)

                // 月次プロラタ適用
                let txComps = calendar.dateComponents([.year, .month], from: txDate)
                if let txYear = txComps.year, let txMonth = txComps.month {
                    let totalDays = daysInMonth(year: txYear, month: txMonth)
                    let needsProRata = txAllocations.contains { alloc in
                        guard let project = projects.first(where: { $0.id == alloc.projectId }) else { return false }
                        let activeDays = calculateActiveDaysInMonth(startDate: project.startDate, completedAt: project.effectiveEndDate, year: txYear, month: txMonth)
                        return activeDays < totalDays
                    }
                    if needsProRata {
                        let inputs: [HolisticProRataInput] = txAllocations.map { alloc in
                            let project = projects.first { $0.id == alloc.projectId }
                            let activeDays = calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                            return HolisticProRataInput(projectId: alloc.projectId, ratio: alloc.ratio, activeDays: activeDays)
                        }
                        txAllocations = calculateHolisticProRata(
                            totalAmount: txAmount,
                            totalDays: totalDays,
                            inputs: inputs
                        )
                    }
                }
            case .manual:
                txAllocations = recalculateAllocationAmounts(amount: txAmount, existingAllocations: recurring.allocations)
                // 月次プロラタ適用
                let txComps = calendar.dateComponents([.year, .month], from: txDate)
                if let txYear = txComps.year, let txMonth = txComps.month {
                    let totalDays = daysInMonth(year: txYear, month: txMonth)
                    let needsProRata = recurring.allocations.contains { alloc in
                        guard let project = projects.first(where: { $0.id == alloc.projectId }) else { return false }
                        return project.startDate != nil || project.effectiveEndDate != nil
                    }
                    if needsProRata {
                        let inputs: [HolisticProRataInput] = recurring.allocations.map { alloc in
                            let project = projects.first { $0.id == alloc.projectId }
                            let activeDays = calculateActiveDaysInMonth(startDate: project?.startDate, completedAt: project?.effectiveEndDate, year: txYear, month: txMonth)
                            return HolisticProRataInput(projectId: alloc.projectId, ratio: alloc.ratio, activeDays: activeDays)
                        }
                        txAllocations = calculateHolisticProRata(
                            totalAmount: txAmount,
                            totalDays: totalDays,
                            inputs: inputs
                        )
                    }
                }
            }

            let txRatios = txAllocations.map { (projectId: $0.projectId, ratio: $0.ratio) }
            switch addTransactionResult(
                type: recurring.type,
                amount: txAmount,
                date: txDate,
                categoryId: recurring.categoryId,
                memo: memo,
                allocations: txRatios,
                recurringId: recurring.id,
                paymentAccountId: recurring.paymentAccountId,
                transferToAccountId: recurring.transferToAccountId,
                taxDeductibleRate: recurring.taxDeductibleRate,
                counterpartyId: recurring.counterpartyId,
                counterparty: recurring.counterparty,
                candidateSource: .recurring
            ) {
            case .success(let transaction):
                transaction.allocations = txAllocations
                transaction.updatedAt = Date()
            case .failure:
                continue
            }

            recurring.lastGeneratedMonths = recurring.lastGeneratedMonths + [monthKey]
            recurring.lastGeneratedDate = txDate
            recurring.updatedAt = Date()
            generatedCount += 1
        }

        return generatedCount
    }

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

        return monthlyData.sorted { $0.key < $1.key }.map { key, data in
            MonthlySummary(month: key, income: data.income, expense: data.expense, profit: data.income - data.expense)
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
        guard let category = categories.first(where: { $0.id == id }) else { return }
        category.archivedAt = Date()
        save()
        refreshCategories()
    }

    func unarchiveCategory(id: String) {
        guard let category = categories.first(where: { $0.id == id }) else { return }
        category.archivedAt = nil
        save()
        refreshCategories()
    }

    // MARK: - CSV Import

    func importTransactions(from csvString: String) async -> CSVImportResult {
        var successCount = 0
        var errorCount = 0
        var errors: [String] = []

        let parsed = parseCSV(csvString: csvString)

        for entry in parsed {
            let allocations: [(projectId: UUID, ratio: Int)] = entry.allocations.compactMap { allocation in
                if let existing = projects.first(where: { $0.name == allocation.projectName }) {
                    return (projectId: existing.id, ratio: allocation.ratio)
                }
                let created = addProject(name: allocation.projectName, description: "")
                return (projectId: created.id, ratio: allocation.ratio)
            }

            if entry.type != .transfer {
                guard !allocations.isEmpty else {
                    errorCount += 1
                    errors.append("プロジェクトが見つかりません")
                    continue
                }

                let totalRatio = allocations.reduce(0) { $0 + $1.ratio }
                guard totalRatio == 100 else {
                    errorCount += 1
                    errors.append("配分比率が不正です（合計: \(totalRatio)%）")
                    continue
                }
            }

            let categoryId: String
            switch entry.type {
            case .transfer:
                categoryId = ""
            case .income, .expense:
                let categoryType: CategoryType = entry.type == .income ? .income : .expense
                if let existing = categories.first(where: { $0.name == entry.categoryName && $0.type == categoryType }) {
                    categoryId = existing.id
                } else if let fallback = categories.first(where: { $0.name == entry.categoryName }) {
                    categoryId = fallback.id
                } else {
                    errorCount += 1
                    errors.append("カテゴリが見つかりません: \(entry.categoryName)")
                    continue
                }
            }

            let explicitTaxCodeId = resolvedExplicitTaxCodeId(
                explicitTaxCodeId: nil,
                taxCategory: entry.taxCategory,
                taxRate: entry.taxRate
            )
            let result = await saveApprovedPosting(
                type: entry.type,
                amount: entry.amount,
                date: entry.date,
                categoryId: categoryId,
                memo: entry.memo,
                allocations: entry.type == .transfer ? [] : allocations,
                paymentAccountId: entry.paymentAccountId,
                transferToAccountId: entry.type == .transfer ? entry.transferToAccountId : nil,
                taxDeductibleRate: entry.type == .expense ? entry.taxDeductibleRate : nil,
                taxAmount: entry.taxAmount,
                taxCodeId: explicitTaxCodeId,
                taxRate: entry.taxRate,
                isTaxIncluded: entry.isTaxIncluded,
                taxCategory: entry.taxCategory,
                counterparty: entry.counterparty,
                candidateSource: .importFile
            )

            if case .failure(let error) = result {
                errorCount += 1
                errors.append(error.localizedDescription)
                continue
            }
            successCount += 1
        }

        return CSVImportResult(successCount: successCount, errorCount: errorCount, errors: errors)
    }

    // MARK: - Bulk Delete

    func deleteAllData() {
        // C4: save成功後に削除するため画像パスを収集（トランザクション＋定期取引の両方）
        let imagesToDelete = transactions.compactMap(\.receiptImagePath)
            + recurringTransactions.compactMap(\.receiptImagePath)
        let documentRecords = listDocumentRecords()
        let documentFilesToDelete = documentRecords.map(\.storedFileName)
        let complianceLogs = listComplianceLogs(limit: Int.max)
        let secureStoreIds = Set([canonicalProfileSecureStoreId].compactMap { $0 })

        for p in projects { modelContext.delete(p) }
        for t in transactions { modelContext.delete(t) }
        for c in categories { modelContext.delete(c) }
        for r in recurringTransactions { modelContext.delete(r) }
        // Phase 4B: 会計データも削除
        for a in accounts { modelContext.delete(a) }
        for je in journalEntries { modelContext.delete(je) }
        for jl in journalLines { modelContext.delete(jl) }
        if let legacyProfiles = try? modelContext.fetch(FetchDescriptor<PPAccountingProfile>()) {
            for profile in legacyProfiles { modelContext.delete(profile) }
        }
        if let businessProfiles = try? modelContext.fetch(FetchDescriptor<BusinessProfileEntity>()) {
            for profile in businessProfiles {
                modelContext.delete(profile)
            }
        }
        if let taxYearProfiles = try? modelContext.fetch(FetchDescriptor<TaxYearProfileEntity>()) {
            for profile in taxYearProfiles {
                modelContext.delete(profile)
            }
        }
        for fa in fixedAssets { modelContext.delete(fa) }
        for document in documentRecords { modelContext.delete(document) }
        for log in complianceLogs { modelContext.delete(log) }
        if save() {
            for imagePath in imagesToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
            for fileName in documentFilesToDelete {
                ReceiptImageStore.deleteDocumentFile(fileName: fileName)
            }
        }
        for profileId in secureStoreIds {
            _ = ProfileSecureStore.delete(profileId: profileId)
        }
        projects = []
        allTransactions = []
        categories = []
        recurringTransactions = []
        accounts = []
        journalEntries = []
        journalLines = []
        businessProfile = nil
        currentTaxYearProfile = nil
        fixedAssets = []
        seedDefaultCategories()
    }

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
