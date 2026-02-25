import os
import SwiftData
import SwiftUI

@MainActor
@Observable
class DataStore {
    var modelContext: ModelContext

    var projects: [PPProject] = []
    var transactions: [PPTransaction] = []
    var categories: [PPCategory] = []
    var recurringTransactions: [PPRecurringTransaction] = []
    var accounts: [PPAccount] = []
    var journalEntries: [PPJournalEntry] = []
    var journalLines: [PPJournalLine] = []
    var accountingProfile: PPAccountingProfile?
    var fixedAssets: [PPFixedAsset] = []
    var isLoading = true
    var lastError: AppError?

    /// H2: 定期取引の追加/更新/削除時に通知スケジュールを再構成するためのコールバック
    var onRecurringScheduleChanged: (([PPRecurringTransaction]) -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Initialization

    func loadData() {
        do {
            let projectDescriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            projects = try modelContext.fetch(projectDescriptor)

            let transactionDescriptor = FetchDescriptor<PPTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            transactions = try modelContext.fetch(transactionDescriptor)

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

            // Phase 4B: 会計データの読み込み
            let accountDescriptor = FetchDescriptor<PPAccount>(sortBy: [SortDescriptor(\.displayOrder)])
            accounts = try modelContext.fetch(accountDescriptor)

            let entryDescriptor = FetchDescriptor<PPJournalEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            journalEntries = try modelContext.fetch(entryDescriptor)

            let lineDescriptor = FetchDescriptor<PPJournalLine>(sortBy: [SortDescriptor(\.displayOrder)])
            journalLines = try modelContext.fetch(lineDescriptor)

            let profileDescriptor = FetchDescriptor<PPAccountingProfile>()
            accountingProfile = try modelContext.fetch(profileDescriptor).first

            let fixedAssetDescriptor = FetchDescriptor<PPFixedAsset>(sortBy: [SortDescriptor(\.acquisitionDate, order: .reverse)])
            fixedAssets = try modelContext.fetch(fixedAssetDescriptor)

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
                let profileDesc = FetchDescriptor<PPAccountingProfile>()
                accountingProfile = try? modelContext.fetch(profileDesc).first
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
        } catch {
            AppLogger.dataStore.error("Failed to load data: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
        isLoading = false
    }

    /// マイグレーション: SwiftDataスキーマ変更後の整合性チェック
    /// allocationMode/yearlyAmortizationMode は非Optionalに変更済み。
    /// SwiftDataが自動的にデフォルト値を適用するため、現在は追加処理不要。
    private func migrateNilOptionalFields() {
        // SwiftData handles schema migration with default values from init.
        // This method is retained as a hook for future migrations.
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
            transactions = try modelContext.fetch(descriptor)
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
        processRecurringTransactions()
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
            processRecurringTransactions()
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
        taxDeductibleRate: Int? = nil
    ) -> PPTransaction {
        // T5: 年度ロックガード
        guard !isYearLocked(for: date) else {
            return PPTransaction(type: type, amount: amount, date: date, categoryId: categoryId, memo: memo)
        }
        let safeCategoryId = categoryId.isEmpty ? Self.defaultCategoryId(for: type) : categoryId
        let allocs = calculateRatioAllocations(amount: amount, allocations: allocations)
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
            taxDeductibleRate: taxDeductibleRate
        )
        modelContext.insert(transaction)

        // Phase 4B: 仕訳を自動生成
        let engine = AccountingEngine(modelContext: modelContext)
        if let entry = engine.upsertJournalEntry(for: transaction, categories: categories, accounts: accounts) {
            transaction.journalEntryId = entry.id
        }

        save()
        refreshTransactions()
        refreshJournalEntries()
        refreshJournalLines()
        return transaction
    }

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
        taxDeductibleRate: Int?? = nil
    ) {
        guard let transaction = transactions.first(where: { $0.id == id }) else { return }
        // T5: 年度ロックガード（変更先の日付と現在の日付の両方をチェック）
        if isYearLocked(for: transaction.date) { return }
        if let date, isYearLocked(for: date) { return }
        if let type { transaction.type = type }
        if let date { transaction.date = date }
        if let categoryId { transaction.categoryId = categoryId }
        if let memo { transaction.memo = memo }
        if let receiptImagePath { transaction.receiptImagePath = receiptImagePath }
        if let lineItems { transaction.lineItems = lineItems }
        if let paymentAccountId { transaction.paymentAccountId = paymentAccountId }
        if let transferToAccountId { transaction.transferToAccountId = transferToAccountId }
        if let taxDeductibleRate { transaction.taxDeductibleRate = taxDeductibleRate }

        let finalAmount = amount ?? transaction.amount
        if let amount { transaction.amount = amount }

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

        // Phase 4B: 仕訳を再生成（bookkeepingMode が locked でない場合）
        let engine = AccountingEngine(modelContext: modelContext)
        if let entry = engine.upsertJournalEntry(for: transaction, categories: categories, accounts: accounts) {
            transaction.journalEntryId = entry.id
        }

        save()
        refreshTransactions()
        refreshJournalEntries()
        refreshJournalLines()
    }

    func deleteTransaction(id: UUID) {
        guard let transaction = transactions.first(where: { $0.id == id }) else { return }
        // T5: 年度ロックガード
        if isYearLocked(for: transaction.date) { return }

        // C4: save成功後に削除するため画像パスを保持
        let imageToDelete = transaction.receiptImagePath

        // Capture recurring info before deletion
        let recurringId = transaction.recurringId
        let deletedDate = transaction.date

        // Phase 4B: 対応する仕訳を削除
        let engine = AccountingEngine(modelContext: modelContext)
        engine.deleteJournalEntry(for: transaction.id)

        modelContext.delete(transaction)
        if save() {
            if let imagePath = imageToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
        }
        refreshTransactions()
        refreshJournalEntries()
        refreshJournalLines()

        // Roll back recurring generation tracking so the deleted period can be regenerated
        if let recurringId, let recurring = recurringTransactions.first(where: { $0.id == recurringId }) {
            rollBackRecurringGenerationState(recurring: recurring, deletedTransactionDate: deletedDate)
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
        taxDeductibleRate: Int? = nil
    ) -> PPRecurringTransaction {
        let safeCategoryId = categoryId.isEmpty ? Self.defaultCategoryId(for: type) : categoryId
        let allocs: [Allocation]
        switch allocationMode {
        case .equalAll:
            allocs = []
        case .manual:
            allocs = calculateRatioAllocations(amount: amount, allocations: allocations)
        }
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
            taxDeductibleRate: taxDeductibleRate
        )
        modelContext.insert(recurring)
        save()
        refreshRecurring()
        processRecurringTransactions()
        refreshTransactions()
        onRecurringScheduleChanged?(recurringTransactions)
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
        taxDeductibleRate: Int?? = nil
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
        processRecurringTransactions()
        refreshTransactions()
        onRecurringScheduleChanged?(recurringTransactions)
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
        let transaction = PPTransaction(
            type: recurring.type,
            amount: recurring.amount,
            date: txDate,
            categoryId: recurring.categoryId,
            memo: memo,
            allocations: txAllocations,
            recurringId: recurring.id,
            paymentAccountId: recurring.paymentAccountId,
            transferToAccountId: recurring.transferToAccountId,
            taxDeductibleRate: recurring.taxDeductibleRate
        )
        modelContext.insert(transaction)
        return transaction
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

            let transaction = PPTransaction(
                type: recurring.type,
                amount: txAmount,
                date: txDate,
                categoryId: recurring.categoryId,
                memo: memo,
                allocations: txAllocations,
                recurringId: recurring.id
            )
            modelContext.insert(transaction)

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

    // MARK: - CSV Import

    func importTransactions(from csvString: String) -> CSVImportResult {
        var successCount = 0
        var errorCount = 0
        var errors: [String] = []

        let parsed = parseCSV(
            csvString: csvString,
            getOrCreateProject: { [self] name in
                if let existing = projects.first(where: { $0.name == name }) {
                    return existing.id
                }
                let newProject = addProject(name: name, description: "")
                return newProject.id
            },
            getCategoryId: { [self] name, type in
                let categoryType: CategoryType = switch type {
                case .income: .income
                case .expense, .transfer: .expense
                }
                if let existing = categories.first(where: { $0.name == name && $0.type == categoryType }) {
                    return existing.id
                }
                // Also try matching by name only as a fallback
                if let existing = categories.first(where: { $0.name == name }) {
                    return existing.id
                }
                return nil
            }
        )

        for entry in parsed {
            let allocations: [(projectId: UUID, ratio: Int)] = entry.allocations.compactMap { alloc in
                if let project = projects.first(where: { $0.name == alloc.projectName }) {
                    return (projectId: project.id, ratio: alloc.ratio)
                }
                return nil
            }

            guard !allocations.isEmpty else {
                errorCount += 1
                errors.append("プロジェクトが見つかりません: \(entry.projectName)")
                continue
            }

            let totalRatio = allocations.reduce(0) { $0 + $1.ratio }
            guard totalRatio > 0, totalRatio <= 100 else {
                errorCount += 1
                errors.append("配分比率が不正です（合計: \(totalRatio)%）")
                continue
            }

            addTransaction(
                type: entry.type,
                amount: entry.amount,
                date: entry.date,
                categoryId: entry.categoryId,
                memo: entry.memo,
                allocations: allocations
            )
            successCount += 1
        }

        return CSVImportResult(successCount: successCount, errorCount: errorCount, errors: errors)
    }

    // MARK: - Bulk Delete

    func deleteAllData() {
        // C4: save成功後に削除するため画像パスを収集（トランザクション＋定期取引の両方）
        let imagesToDelete = transactions.compactMap(\.receiptImagePath)
            + recurringTransactions.compactMap(\.receiptImagePath)

        for p in projects { modelContext.delete(p) }
        for t in transactions { modelContext.delete(t) }
        for c in categories { modelContext.delete(c) }
        for r in recurringTransactions { modelContext.delete(r) }
        // Phase 4B: 会計データも削除
        for a in accounts { modelContext.delete(a) }
        for je in journalEntries { modelContext.delete(je) }
        for jl in journalLines { modelContext.delete(jl) }
        if let profile = accountingProfile { modelContext.delete(profile) }
        for fa in fixedAssets { modelContext.delete(fa) }
        if save() {
            for imagePath in imagesToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
        }
        projects = []
        transactions = []
        categories = []
        recurringTransactions = []
        accounts = []
        journalEntries = []
        journalLines = []
        accountingProfile = nil
        fixedAssets = []
        seedDefaultCategories()
    }

    // MARK: - Accounting CRUD

    func getAccount(id: String) -> PPAccount? {
        accounts.first { $0.id == id }
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
