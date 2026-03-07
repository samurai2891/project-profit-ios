import Foundation
import os
import SwiftData

// MARK: - Bootstrap Result

/// ブートストラップ実行結果
struct BootstrapResult {
    let accountsCreated: Int
    let categoriesLinked: Int
    let transactionsBackfilled: Int
    let journalEntriesGenerated: Int
    let integrityIssues: [JournalValidationIssue]
    let openingEntryGenerated: Bool
}

// MARK: - AccountingBootstrapService

/// 会計データ初期化サービス（Todo.md 4B-3 準拠: 8ステップ移行）
/// 仕様書 §6.2.2 準拠。アプリ初回起動時または会計データ未初期化時に実行する。
@MainActor
final class AccountingBootstrapService {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.projectprofit", category: "AccountingBootstrap")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// 会計データのブートストラップが必要かどうかを判定する
    func needsBootstrap() -> Bool {
        let legacyDescriptor = FetchDescriptor<PPAccountingProfile>()
        let legacyProfiles = (try? modelContext.fetch(legacyDescriptor)) ?? []
        if !legacyProfiles.isEmpty { return false }

        let canonicalDescriptor = FetchDescriptor<BusinessProfileEntity>()
        let canonicalProfiles = (try? modelContext.fetch(canonicalDescriptor)) ?? []
        return canonicalProfiles.isEmpty
    }

    /// 8ステップの移行を実行する
    func execute(
        categories: [PPCategory],
        transactions: [PPTransaction]
    ) -> BootstrapResult {
        logger.info("会計ブートストラップ開始")

        // Step 1: プロフィール作成（canonical のみ or canonical + legacy）
        let defaultPaymentAccountId: String
        if FeatureFlags.useCanonicalProfileOnly {
            defaultPaymentAccountId = step1_createCanonicalProfileOnly()
        } else {
            let profile = step1_createProfileIfNeeded()
            defaultPaymentAccountId = profile.defaultPaymentAccountId
        }

        // Step 2: デフォルト勘定科目を挿入
        let accountsCreated = step2_seedDefaultAccounts()

        // Step 3: 既存カテゴリの linkedAccountId を設定
        let categoriesLinked = step3_linkCategoriesToAccounts(categories: categories)

        // Step 4: フィールド補完（paymentAccountId, taxDeductibleRate, bookkeepingMode）
        let transactionsBackfilled = step4_backfillTransactionFields(
            transactions: transactions,
            defaultPaymentAccountId: defaultPaymentAccountId
        )

        // Step 5: 未マッピングカテゴリを仮勘定にリンク
        step5_linkUnmappedCategoriesToSuspense(categories: categories)

        // Step 6 は Step 7 の後に実行（仕訳生成後に整合性チェック）

        // Step 7: 既存トランザクションから仕訳を一括生成
        let accounts = fetchAllAccounts()
        let updatedCategories = fetchAllCategories()
        let journalEntriesGenerated = step7_generateJournalEntries(
            transactions: transactions,
            categories: updatedCategories,
            accounts: accounts
        )

        // Step 6: 整合性チェック
        let integrityIssues = step6_integrityCheck()

        // Step 8: 期首残高仕訳を生成
        let openingEntryGenerated = step8_generateOpeningBalance(
            transactions: transactions,
            accounts: accounts
        )

        logger.info("会計ブートストラップ完了: accounts=\(accountsCreated), categories=\(categoriesLinked), journals=\(journalEntriesGenerated)")

        return BootstrapResult(
            accountsCreated: accountsCreated,
            categoriesLinked: categoriesLinked,
            transactionsBackfilled: transactionsBackfilled,
            journalEntriesGenerated: journalEntriesGenerated,
            integrityIssues: integrityIssues,
            openingEntryGenerated: openingEntryGenerated
        )
    }

    // MARK: - Step 1: Create Profile

    /// canonical のみモード: BusinessProfileEntity + TaxYearProfileEntity を作成し、
    /// PPAccountingProfile の insert をスキップする。
    private func step1_createCanonicalProfileOnly() -> String {
        let calendar = Calendar(identifier: .gregorian)
        let currentYear = calendar.component(.year, from: Date())

        let businessId = UUID()
        let businessEntity = step1_ensureBusinessProfileEntity(businessId: businessId)
        modelContext.insert(businessEntity)

        let taxYearEntity = step1_ensureTaxYearProfileEntity(
            businessId: businessId,
            taxYear: currentYear
        )
        modelContext.insert(taxYearEntity)

        logger.info("Step 1: canonical プロファイルのみ作成完了（PPAccountingProfile スキップ）")
        return AccountingConstants.defaultPaymentAccountId
    }

    /// canonical プロフィール（BusinessProfileEntity + TaxYearProfileEntity）を先に作成し、
    /// レガシー PPAccountingProfile はその derived projection として生成する。
    private func step1_createProfileIfNeeded() -> PPAccountingProfile {
        let descriptor = FetchDescriptor<PPAccountingProfile>()
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let calendar = Calendar(identifier: .gregorian)
        let currentYear = calendar.component(.year, from: Date())

        // canonical: BusinessProfileEntity を作成
        let businessId = UUID()
        let businessEntity = step1_ensureBusinessProfileEntity(businessId: businessId)
        modelContext.insert(businessEntity)

        // canonical: TaxYearProfileEntity を作成
        let taxYearEntity = step1_ensureTaxYearProfileEntity(
            businessId: businessId,
            taxYear: currentYear
        )
        modelContext.insert(taxYearEntity)

        // legacy: canonical からの派生として PPAccountingProfile を生成
        let profile = PPAccountingProfile(
            id: AccountingConstants.defaultProfileId,
            fiscalYear: currentYear,
            bookkeepingMode: .doubleEntry,
            isBlueReturn: true,
            defaultPaymentAccountId: AccountingConstants.defaultPaymentAccountId
        )
        modelContext.insert(profile)
        logger.info("Step 1: canonical + legacy プロファイル作成完了")
        return profile
    }

    private func step1_ensureBusinessProfileEntity(businessId: UUID) -> BusinessProfileEntity {
        let descriptor = FetchDescriptor<BusinessProfileEntity>()
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        return BusinessProfileEntity(
            businessId: businessId,
            defaultPaymentAccountId: AccountingConstants.defaultPaymentAccountId
        )
    }

    private func step1_ensureTaxYearProfileEntity(
        businessId: UUID,
        taxYear: Int
    ) -> TaxYearProfileEntity {
        let descriptor = FetchDescriptor<TaxYearProfileEntity>()
        if let existing = (try? modelContext.fetch(descriptor))?.first,
           existing.taxYear == taxYear {
            return existing
        }
        return TaxYearProfileEntity(
            businessId: businessId,
            taxYear: taxYear
        )
    }

    // MARK: - Step 2: Seed Default Accounts

    /// デフォルト勘定科目を PPAccount に挿入する（code で重複排除）
    private func step2_seedDefaultAccounts() -> Int {
        let descriptor = FetchDescriptor<PPAccount>()
        let existingAccounts = (try? modelContext.fetch(descriptor)) ?? []
        let existingIds = Set(existingAccounts.map(\.id))

        var created = 0
        for def in AccountingConstants.defaultAccounts where !existingIds.contains(def.id) {
            let account = PPAccount(
                id: def.id,
                code: def.code,
                name: def.name,
                accountType: def.accountType,
                normalBalance: def.normalBalance,
                subtype: def.subtype,
                isSystem: true,
                isActive: true,
                displayOrder: def.displayOrder
            )
            modelContext.insert(account)
            created += 1
        }

        logger.info("Step 2: デフォルト勘定科目 \(created) 件作成")
        return created
    }

    // MARK: - Step 3: Link Categories to Accounts

    /// 既存カテゴリの linkedAccountId を 4B-2 マッピングに基づいて設定する
    private func step3_linkCategoriesToAccounts(categories: [PPCategory]) -> Int {
        var linked = 0
        for category in categories {
            // 既に linkedAccountId が設定されていればスキップ
            guard category.linkedAccountId == nil else { continue }

            if let accountId = AccountingConstants.categoryToAccountMapping[category.id] {
                category.linkedAccountId = accountId
                linked += 1
            }
        }
        logger.info("Step 3: カテゴリ \(linked) 件にアカウントをリンク")
        return linked
    }

    // MARK: - Step 4: Backfill Transaction Fields

    /// 既存トランザクションの未設定フィールドをデフォルト値で補完する
    private func step4_backfillTransactionFields(
        transactions: [PPTransaction],
        defaultPaymentAccountId: String
    ) -> Int {
        var backfilled = 0
        for transaction in transactions {
            var changed = false

            if transaction.paymentAccountId == nil {
                transaction.paymentAccountId = defaultPaymentAccountId
                changed = true
            }
            if transaction.taxDeductibleRate == nil {
                transaction.taxDeductibleRate = 100
                changed = true
            }
            if transaction.bookkeepingMode == nil {
                transaction.bookkeepingMode = .auto
                changed = true
            }

            if changed {
                transaction.updatedAt = Date()
                backfilled += 1
            }
        }
        logger.info("Step 4: トランザクション \(backfilled) 件のフィールドを補完")
        return backfilled
    }

    // MARK: - Step 5: Link Unmapped Categories to Suspense

    /// マッピングのないユーザー作成カテゴリを仮勘定にリンクする
    private func step5_linkUnmappedCategoriesToSuspense(categories: [PPCategory]) {
        var linked = 0
        for category in categories where category.linkedAccountId == nil {
            category.linkedAccountId = AccountingConstants.suspenseAccountId
            linked += 1
        }
        if linked > 0 {
            logger.info("Step 5: 未マッピングカテゴリ \(linked) 件を仮勘定にリンク")
        }
    }

    // MARK: - Step 6: Integrity Check

    /// 全仕訳の貸借一致チェックを行う
    private func step6_integrityCheck() -> [JournalValidationIssue] {
        let entryDescriptor = FetchDescriptor<PPJournalEntry>()
        let lineDescriptor = FetchDescriptor<PPJournalLine>()

        guard let entries = try? modelContext.fetch(entryDescriptor),
              let allLines = try? modelContext.fetch(lineDescriptor)
        else {
            return []
        }

        var allIssues: [JournalValidationIssue] = []
        for entry in entries {
            let lines = allLines.filter { $0.entryId == entry.id }
            let issues = JournalValidationService.validateLines(lines)

            let debitTotal = lines.reduce(0) { $0 + $1.debit }
            let creditTotal = lines.reduce(0) { $0 + $1.credit }
            if debitTotal != creditTotal {
                entry.isPosted = false
                allIssues.append(.unbalanced(debitTotal: debitTotal, creditTotal: creditTotal))
                logger.warning("Step 6: 仕訳 \(entry.sourceKey) 貸借不一致 (借方=\(debitTotal), 貸方=\(creditTotal))")
            }
            allIssues.append(contentsOf: issues)
        }

        logger.info("Step 6: 整合性チェック完了 (問題 \(allIssues.count) 件)")
        return allIssues
    }

    // MARK: - Step 7: Generate Journal Entries

    /// 既存トランザクションから PPJournalEntry/PPJournalLine を一括生成する
    private func step7_generateJournalEntries(
        transactions: [PPTransaction],
        categories: [PPCategory],
        accounts: [PPAccount]
    ) -> Int {
        let engine = AccountingEngine(modelContext: modelContext)
        var generated = 0

        for transaction in transactions {
            // 既に journalEntryId がある場合はスキップ
            guard transaction.journalEntryId == nil else { continue }

            if let entry = engine.upsertJournalEntry(for: transaction, categories: categories, accounts: accounts) {
                transaction.journalEntryId = entry.id
                generated += 1
            }
        }

        logger.info("Step 7: 仕訳 \(generated) 件生成")
        return generated
    }

    // MARK: - Step 8: Generate Opening Balance

    /// 最古のトランザクション年度の1月1日付で期首残高仕訳を生成する
    private func step8_generateOpeningBalance(
        transactions: [PPTransaction],
        accounts: [PPAccount]
    ) -> Bool {
        // 最古のトランザクション年度を取得
        guard let oldestDate = transactions.map(\.date).min() else { return false }

        let calendar = Calendar(identifier: .gregorian)
        let oldestYear = calendar.component(.year, from: oldestDate)

        let engine = AccountingEngine(modelContext: modelContext)
        let entryDescriptor = FetchDescriptor<PPJournalEntry>()
        let lineDescriptor = FetchDescriptor<PPJournalLine>()

        guard let entries = try? modelContext.fetch(entryDescriptor),
              let lines = try? modelContext.fetch(lineDescriptor)
        else {
            return false
        }

        let entry = engine.generateOpeningBalanceEntry(
            for: oldestYear,
            accounts: accounts,
            journalEntries: entries,
            journalLines: lines
        )

        if entry != nil {
            logger.info("Step 8: \(oldestYear)年の期首残高仕訳を生成")
        }
        return entry != nil
    }

    // MARK: - Private Helpers

    private func fetchAllAccounts() -> [PPAccount] {
        let descriptor = FetchDescriptor<PPAccount>(sortBy: [SortDescriptor(\.displayOrder)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchAllCategories() -> [PPCategory] {
        let descriptor = FetchDescriptor<PPCategory>(sortBy: [SortDescriptor(\.name)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
