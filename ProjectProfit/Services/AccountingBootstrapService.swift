import CryptoKit
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

        // Step 1: canonical profile を作成
        let defaultPaymentAccountId = step1_createCanonicalProfileOnly()

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

    /// 既存トランザクションから canonical candidate / journal を一括生成する
    private func step7_generateJournalEntries(
        transactions: [PPTransaction],
        categories: [PPCategory],
        accounts: [PPAccount]
    ) -> Int {
        guard let businessId = fetchBusinessId() else {
            logger.warning("Step 7 skipped: canonical business profile unavailable")
            return 0
        }

        let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)
        var generated = 0

        for transaction in transactions {
            guard transaction.deletedAt == nil else { continue }
            guard transaction.journalEntryId == nil else { continue }

            let snapshot = CanonicalTransactionPostingBridge.TransactionSnapshot(transaction: transaction)
            guard let posting = bridge.buildApprovedPosting(
                for: snapshot,
                businessId: businessId,
                categories: categories,
                legacyAccounts: accounts
            ) else {
                continue
            }

            do {
                let journal = try bridge.persist(posting: posting)
                transaction.journalEntryId = journal.id
                generated += 1
            } catch {
                logger.warning("Step 7: canonical posting sync failed for transaction \(transaction.id.uuidString): \(error.localizedDescription)")
            }
        }

        logger.info("Step 7: canonical 仕訳 \(generated) 件生成")
        return generated
    }

    // MARK: - Step 8: Generate Opening Balance

    /// 最古のトランザクション年度の1月1日付で期首残高仕訳を生成する
    private func step8_generateOpeningBalance(
        transactions: [PPTransaction],
        accounts: [PPAccount]
    ) -> Bool {
        guard let businessId = fetchBusinessId() else {
            return false
        }
        guard let oldestDate = transactions
            .filter({ $0.deletedAt == nil })
            .map(\.date)
            .min()
        else {
            return false
        }

        let calendar = Calendar(identifier: .gregorian)
        let oldestYear = calendar.component(.year, from: oldestDate)

        let bridge = CanonicalTransactionPostingBridge(modelContext: modelContext)
        let entry = try? bridge.generateOpeningBalanceEntry(
            businessId: businessId,
            year: oldestYear,
            legacyAccounts: accounts
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

    private func fetchBusinessId() -> UUID? {
        let descriptor = FetchDescriptor<BusinessProfileEntity>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? modelContext.fetch(descriptor))?.first?.businessId
    }
}

@MainActor
struct CanonicalTransactionPostingBridge {
    struct Posting {
        let candidate: PostingCandidate
        let journalId: UUID
        let entryType: CanonicalJournalEntryType
        let description: String
        let approvedAt: Date
    }

    struct TransactionSnapshot: Sendable {
        let id: UUID
        let type: TransactionType
        let amount: Int
        let date: Date
        let categoryId: String
        let memo: String
        let recurringId: UUID?
        let paymentAccountId: String?
        let transferToAccountId: String?
        let taxDeductibleRate: Int?
        let taxAmount: Int?
        let taxCodeId: String?
        let taxRate: Int?
        let isTaxIncluded: Bool?
        let taxCategory: TaxCategory?
        let receiptImagePath: String?
        let lineItems: [ReceiptLineItem]
        let counterpartyName: String?
        let createdAt: Date
        let updatedAt: Date
        let journalEntryId: UUID?

        init(transaction: PPTransaction) {
            id = transaction.id
            type = transaction.type
            amount = transaction.amount
            date = transaction.date
            categoryId = transaction.categoryId
            memo = transaction.memo
            recurringId = transaction.recurringId
            paymentAccountId = transaction.paymentAccountId
            transferToAccountId = transaction.transferToAccountId
            taxDeductibleRate = transaction.taxDeductibleRate
            taxAmount = transaction.taxAmount
            taxCodeId = nil
            taxRate = transaction.taxRate
            isTaxIncluded = transaction.isTaxIncluded
            taxCategory = transaction.taxCategory
            receiptImagePath = transaction.receiptImagePath
            lineItems = transaction.lineItems
            counterpartyName = transaction.counterparty
            createdAt = transaction.createdAt
            updatedAt = transaction.updatedAt
            journalEntryId = transaction.journalEntryId
        }

        init(
            id: UUID,
            type: TransactionType,
            amount: Int,
            date: Date,
            categoryId: String,
            memo: String,
            recurringId: UUID?,
            paymentAccountId: String?,
            transferToAccountId: String?,
            taxDeductibleRate: Int?,
            taxAmount: Int?,
            taxCodeId: String?,
            taxRate: Int?,
            isTaxIncluded: Bool?,
            taxCategory: TaxCategory?,
            receiptImagePath: String? = nil,
            lineItems: [ReceiptLineItem] = [],
            counterpartyName: String? = nil,
            createdAt: Date,
            updatedAt: Date,
            journalEntryId: UUID?
        ) {
            self.id = id
            self.type = type
            self.amount = amount
            self.date = date
            self.categoryId = categoryId
            self.memo = memo
            self.recurringId = recurringId
            self.paymentAccountId = paymentAccountId
            self.transferToAccountId = transferToAccountId
            self.taxDeductibleRate = taxDeductibleRate
            self.taxAmount = taxAmount
            self.taxCodeId = taxCodeId
            self.taxRate = taxRate
            self.isTaxIncluded = isTaxIncluded
            self.taxCategory = taxCategory
            self.receiptImagePath = receiptImagePath
            self.lineItems = lineItems
            self.counterpartyName = counterpartyName
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.journalEntryId = journalEntryId
        }

        var effectiveTaxDeductibleRate: Int {
            max(0, min(100, taxDeductibleRate ?? 100))
        }

        var netAmount: Int {
            if let taxAmount, taxAmount > 0 {
                return max(0, amount - taxAmount)
            }
            return amount
        }

        var resolvedTaxCode: TaxCode? {
            if let taxCodeId {
                return TaxCode.resolve(id: taxCodeId)
            }
            return TaxCode.resolve(legacyCategory: taxCategory, taxRate: taxRate)
        }
    }

    private struct LegacyPostingLineSnapshot: Sendable {
        let accountId: String
        let debit: Int
        let credit: Int
        let memo: String

        var amount: Int {
            max(debit, credit)
        }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func buildApprovedPosting(
        for snapshot: TransactionSnapshot,
        businessId: UUID,
        counterpartyId: UUID? = nil,
        source: CandidateSource? = nil,
        categories: [PPCategory],
        legacyAccounts: [PPAccount]
    ) -> Posting? {
        syncCanonicalAccountsFromLegacyAccountsIfNeeded(
            businessId: businessId,
            legacyAccounts: legacyAccounts
        )

        let legacyLines = synthesizeLegacyPostingLines(for: snapshot, categories: categories)
        guard !legacyLines.isEmpty else {
            return nil
        }

        let canonicalIdsByLegacyId = canonicalAccountIdsByLegacyId(businessId: businessId)
        let canonicalAccountsByLegacyId = canonicalAccountsByLegacyId(businessId: businessId)
        let unmappableAccountIds = Set(
            legacyLines.compactMap { line in
                canonicalAccountId(
                    for: line.accountId,
                    canonicalIdsByLegacyId: canonicalIdsByLegacyId
                ) == nil ? line.accountId : nil
            }
        )
        guard unmappableAccountIds.isEmpty else {
            return nil
        }

        let counterparty = counterpartyId.flatMap(canonicalCounterparty(id:))
        let resolvedTaxCodeId = resolvedCanonicalTaxCodeId(
            for: snapshot,
            counterparty: counterparty,
            legacyLines: legacyLines,
            canonicalAccountsByLegacyId: canonicalAccountsByLegacyId
        )
        let taxYear = fiscalYear(for: snapshot.date, startMonth: FiscalYearSettings.startMonth)
        let taxYearProfile = resolvedTaxYearProfile(
            businessId: businessId,
            taxYear: taxYear
        )
        let pack = try? BundledTaxYearPackProvider(bundle: .main).packSync(for: taxYear)
        let resolvedTaxAnalysis = makeCanonicalTaxAnalysis(
            for: snapshot,
            taxCodeId: resolvedTaxCodeId,
            counterparty: counterparty,
            taxYearProfile: taxYearProfile,
            pack: pack
        )

        let candidateLines = legacyLines.compactMap { line -> PostingCandidateLine? in
            guard let accountId = canonicalAccountId(
                for: line.accountId,
                canonicalIdsByLegacyId: canonicalIdsByLegacyId
            ) else {
                return nil
            }
            return PostingCandidateLine(
                debitAccountId: line.debit > 0 ? accountId : nil,
                creditAccountId: line.credit > 0 ? accountId : nil,
                amount: Decimal(line.amount),
                taxCodeId: resolvedTaxCodeId,
                legalReportLineId: canonicalAccountsByLegacyId[line.accountId]?.defaultLegalReportLineId,
                memo: normalizedOptionalString(line.memo)
            )
        }

        guard !candidateLines.isEmpty else {
            return nil
        }

        let now = snapshot.updatedAt
        let description = normalizedOptionalString(snapshot.memo) ?? ""
        let inferredSource: CandidateSource = source ?? (snapshot.recurringId == nil ? .manual : .recurring)
        let candidate = PostingCandidate(
            id: snapshot.id,
            evidenceId: nil,
            businessId: businessId,
            taxYear: taxYear,
            candidateDate: snapshot.date,
            counterpartyId: counterpartyId,
            proposedLines: candidateLines,
            taxAnalysis: resolvedTaxAnalysis,
            confidenceScore: 1.0,
            status: .approved,
            source: inferredSource,
            memo: description,
            legacySnapshot: PostingCandidateLegacySnapshot(
                type: snapshot.type,
                categoryId: snapshot.categoryId,
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
                counterpartyName: snapshot.counterpartyName
            ),
            createdAt: snapshot.createdAt,
            updatedAt: now
        )

        return Posting(
            candidate: candidate,
            journalId: snapshot.journalEntryId ?? stableJournalId(for: snapshot.id),
            entryType: snapshot.recurringId == nil ? .normal : .recurring,
            description: description,
            approvedAt: now
        )
    }

    private func stableJournalId(for transactionId: UUID) -> UUID {
        let seed = "journal|\(transactionId.uuidString.lowercased())"
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

    func persist(posting: Posting) throws -> CanonicalJournalEntry {
        let candidateId = posting.candidate.id
        let candidateDescriptor = FetchDescriptor<PostingCandidateEntity>(
            predicate: #Predicate { $0.candidateId == candidateId }
        )
        if let existingCandidate = try modelContext.fetch(candidateDescriptor).first {
            PostingCandidateEntityMapper.update(existingCandidate, from: posting.candidate)
        } else {
            modelContext.insert(PostingCandidateEntityMapper.toEntity(posting.candidate))
        }

        let journal = try makeJournal(from: posting)
        let journalDescriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.journalId == journal.id }
        )
        if let existingJournal = try modelContext.fetch(journalDescriptor).first {
            let previousLines = existingJournal.lines
            CanonicalJournalEntryEntityMapper.update(existingJournal, from: journal)
            existingJournal.lines = []
            previousLines.forEach(modelContext.delete)
            existingJournal.lines = CanonicalJournalEntryEntityMapper.makeLineEntities(
                from: journal.lines,
                journalEntry: existingJournal
            )
        } else {
            modelContext.insert(CanonicalJournalEntryEntityMapper.toEntity(journal))
        }

        try? LocalJournalSearchIndex(modelContext: modelContext).rebuild(
            businessId: journal.businessId,
            taxYear: journal.taxYear
        )
        return journal
    }

    func generateOpeningBalanceEntry(
        businessId: UUID,
        year: Int,
        legacyAccounts: [PPAccount]
    ) throws -> CanonicalJournalEntry? {
        let openingEntryTypeRaw = CanonicalJournalEntryType.opening.rawValue
        let existingDescriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate {
                $0.businessId == businessId
                    && $0.taxYear == year
                    && $0.entryTypeRaw == openingEntryTypeRaw
            }
        )
        if let existing = try modelContext.fetch(existingDescriptor).first {
            return CanonicalJournalEntryEntityMapper.toDomain(existing)
        }

        syncCanonicalAccountsFromLegacyAccountsIfNeeded(
            businessId: businessId,
            legacyAccounts: legacyAccounts
        )
        let canonicalAccounts = try fetchCanonicalAccounts(businessId: businessId)
        let accountsById = Dictionary(uniqueKeysWithValues: canonicalAccounts.map { ($0.id, $0) })
        let calendar = Calendar(identifier: .gregorian)
        guard let cutoffDate = calendar.date(from: DateComponents(year: year - 1, month: 12, day: 31)),
              let openingDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return nil
        }

        let journalDescriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.businessId == businessId }
        )
        let priorEntries = try modelContext.fetch(journalDescriptor)
            .filter { entity in
                entity.approvedAt != nil
                    && entity.journalDate <= cutoffDate
                    && entity.entryTypeRaw != CanonicalJournalEntryType.closing.rawValue
            }

        var balanceByAccountId: [UUID: Int] = [:]
        for entry in priorEntries {
            let journal = CanonicalJournalEntryEntityMapper.toDomain(entry)
            for line in journal.lines {
                guard let account = accountsById[line.accountId] else {
                    continue
                }
                let current = balanceByAccountId[line.accountId, default: 0]
                switch account.normalBalance {
                case .debit:
                    balanceByAccountId[line.accountId] = current + decimalToInt(line.debitAmount) - decimalToInt(line.creditAmount)
                case .credit:
                    balanceByAccountId[line.accountId] = current + decimalToInt(line.creditAmount) - decimalToInt(line.debitAmount)
                }
            }
        }

        guard let ownerCapitalAccount = canonicalAccounts.first(where: {
            $0.legacyAccountId == AccountingConstants.ownerCapitalAccountId
        }) else {
            return nil
        }

        let relevantBalances = canonicalAccounts.compactMap { account -> (CanonicalAccount, Int)? in
            guard [.asset, .liability, .equity].contains(account.accountType) else {
                return nil
            }
            guard account.id != ownerCapitalAccount.id else {
                return nil
            }
            guard let balance = balanceByAccountId[account.id], balance != 0 else {
                return nil
            }
            return (account, balance)
        }
        guard !relevantBalances.isEmpty else {
            return nil
        }

        let now = Date()
        let voucherNo = nextVoucherNumber(
            businessId: businessId,
            taxYear: year,
            month: 1
        ).value
        let journalId = UUID()
        var lines: [JournalLine] = []
        var totalDebit = 0
        var totalCredit = 0
        var sortOrder = 0

        for (account, balance) in relevantBalances {
            let debitAmount: Decimal
            let creditAmount: Decimal
            switch account.normalBalance {
            case .debit:
                debitAmount = Decimal(balance)
                creditAmount = 0
                totalDebit += balance
            case .credit:
                debitAmount = 0
                creditAmount = Decimal(balance)
                totalCredit += balance
            }
            lines.append(
                JournalLine(
                    journalId: journalId,
                    accountId: account.id,
                    debitAmount: debitAmount,
                    creditAmount: creditAmount,
                    legalReportLineId: account.defaultLegalReportLineId,
                    sortOrder: sortOrder
                )
            )
            sortOrder += 1
        }

        let difference = totalDebit - totalCredit
        if difference != 0 {
            lines.append(
                JournalLine(
                    journalId: journalId,
                    accountId: ownerCapitalAccount.id,
                    debitAmount: difference > 0 ? 0 : Decimal(-difference),
                    creditAmount: difference > 0 ? Decimal(difference) : 0,
                    legalReportLineId: ownerCapitalAccount.defaultLegalReportLineId,
                    sortOrder: sortOrder
                )
            )
        }

        let entry = CanonicalJournalEntry(
            id: journalId,
            businessId: businessId,
            taxYear: year,
            journalDate: openingDate,
            voucherNo: voucherNo,
            entryType: .opening,
            description: "\(year)年 期首残高",
            lines: lines,
            approvedAt: now,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(CanonicalJournalEntryEntityMapper.toEntity(entry))
        try? LocalJournalSearchIndex(modelContext: modelContext).rebuild(
            businessId: businessId,
            taxYear: year
        )
        return entry
    }

    private func makeJournal(from posting: Posting) throws -> CanonicalJournalEntry {
        let journalId = posting.journalId
        let existingDescriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.journalId == journalId }
        )
        let existingJournal = try modelContext.fetch(existingDescriptor).first.map(CanonicalJournalEntryEntityMapper.toDomain)
        let voucherNo: String
        if let existingJournal {
            voucherNo = existingJournal.voucherNo
        } else {
            let month = Calendar.current.component(.month, from: posting.candidate.candidateDate)
            voucherNo = nextVoucherNumber(
                businessId: posting.candidate.businessId,
                taxYear: posting.candidate.taxYear,
                month: month
            ).value
        }

        let lines = try makeJournalLines(
            from: posting.candidate,
            journalId: posting.journalId
        )
        let entry = CanonicalJournalEntry(
            id: posting.journalId,
            businessId: posting.candidate.businessId,
            taxYear: posting.candidate.taxYear,
            journalDate: posting.candidate.candidateDate,
            voucherNo: voucherNo,
            sourceEvidenceId: posting.candidate.evidenceId,
            sourceCandidateId: posting.candidate.id,
            entryType: posting.entryType,
            description: posting.description,
            lines: lines,
            approvedAt: posting.approvedAt,
            createdAt: existingJournal?.createdAt ?? posting.approvedAt,
            updatedAt: posting.approvedAt
        )

        guard entry.isBalanced else {
            throw PostingWorkflowUseCaseError.journalNotBalanced(posting.candidate.id)
        }
        return entry
    }

    private func makeJournalLines(
        from candidate: PostingCandidate,
        journalId: UUID
    ) throws -> [JournalLine] {
        var journalLines: [JournalLine] = []
        var sortOrder = 0

        for line in candidate.proposedLines {
            guard line.amount > 0 else {
                throw PostingWorkflowUseCaseError.invalidAmount(line.id)
            }
            guard line.debitAccountId != nil || line.creditAccountId != nil else {
                throw PostingWorkflowUseCaseError.missingAccount(line.id)
            }

            if let debitAccountId = line.debitAccountId {
                journalLines.append(
                    JournalLine(
                        journalId: journalId,
                        accountId: debitAccountId,
                        debitAmount: line.amount,
                        creditAmount: 0,
                        taxCodeId: line.taxCodeId,
                        legalReportLineId: try resolvedLegalReportLineId(
                            accountId: debitAccountId,
                            fallback: line.legalReportLineId
                        ),
                        counterpartyId: candidate.counterpartyId,
                        projectAllocationId: line.projectAllocationId,
                        evidenceReferenceId: line.evidenceLineReferenceId ?? candidate.evidenceId,
                        sortOrder: sortOrder,
                        withholdingTaxCodeId: line.withholdingTaxCodeId,
                        withholdingTaxAmount: line.withholdingTaxAmount
                    )
                )
                sortOrder += 1
            }

            if let creditAccountId = line.creditAccountId {
                journalLines.append(
                    JournalLine(
                        journalId: journalId,
                        accountId: creditAccountId,
                        debitAmount: 0,
                        creditAmount: line.amount,
                        taxCodeId: line.taxCodeId,
                        legalReportLineId: try resolvedLegalReportLineId(
                            accountId: creditAccountId,
                            fallback: line.legalReportLineId
                        ),
                        counterpartyId: candidate.counterpartyId,
                        projectAllocationId: line.projectAllocationId,
                        evidenceReferenceId: line.evidenceLineReferenceId ?? candidate.evidenceId,
                        sortOrder: sortOrder,
                        withholdingTaxCodeId: line.withholdingTaxCodeId,
                        withholdingTaxAmount: line.withholdingTaxAmount
                    )
                )
                sortOrder += 1
            }
        }

        return journalLines
    }

    private func resolvedLegalReportLineId(
        accountId: UUID,
        fallback: String?
    ) throws -> String {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(
            predicate: #Predicate { $0.accountId == accountId }
        )
        guard let account = try modelContext.fetch(descriptor).first.map(CanonicalAccountEntityMapper.toDomain) else {
            throw PostingWorkflowUseCaseError.accountNotFound(accountId)
        }
        if let accountLineId = account.defaultLegalReportLineId,
           LegalReportLine(rawValue: accountLineId) != nil {
            return accountLineId
        }
        if let fallback, LegalReportLine(rawValue: fallback) != nil {
            return fallback
        }
        throw PostingWorkflowUseCaseError.missingLegalReportLine(accountId)
    }

    private func syncCanonicalAccountsFromLegacyAccountsIfNeeded(
        businessId: UUID,
        legacyAccounts: [PPAccount]
    ) {
        do {
            let descriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.businessId == businessId }
            )
            let entities = try modelContext.fetch(descriptor)
            let entitiesByLegacyId: [String: CanonicalAccountEntity] = Dictionary(
                uniqueKeysWithValues: entities.compactMap { entity in
                    guard let legacyAccountId = entity.legacyAccountId else {
                        return nil
                    }
                    return (legacyAccountId, entity)
                }
            )
            let entitiesByAccountId = Dictionary(uniqueKeysWithValues: entities.map { ($0.accountId, $0) })
            let entitiesByCode = Dictionary(uniqueKeysWithValues: entities.map { ($0.code, $0) })

            for legacyAccount in legacyAccounts {
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
                    CanonicalAccountEntityMapper.update(existingEntity, from: canonicalAccount)
                } else {
                    modelContext.insert(CanonicalAccountEntityMapper.toEntity(canonicalAccount))
                }
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
        return UUID(uuidString: legacyAccountId)
    }

    private func canonicalCounterparty(id: UUID) -> Counterparty? {
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

    private func synthesizeLegacyPostingLines(
        for snapshot: TransactionSnapshot,
        categories: [PPCategory]
    ) -> [LegacyPostingLineSnapshot] {
        switch snapshot.type {
        case .income:
            return synthesizeIncomePostingLines(for: snapshot, categories: categories)
        case .expense:
            return synthesizeExpensePostingLines(for: snapshot, categories: categories)
        case .transfer:
            return synthesizeTransferPostingLines(for: snapshot)
        }
    }

    private func synthesizeIncomePostingLines(
        for snapshot: TransactionSnapshot,
        categories: [PPCategory]
    ) -> [LegacyPostingLineSnapshot] {
        let paymentAccountId = snapshot.paymentAccountId ?? AccountingConstants.defaultPaymentAccountId
        let revenueAccountId = resolvedLegacyLinkedAccountId(
            categoryId: snapshot.categoryId,
            categories: categories,
            fallback: AccountingConstants.salesAccountId
        )

        if let taxAmount = snapshot.taxAmount, taxAmount > 0,
           snapshot.resolvedTaxCode?.isTaxable == true {
            let netAmount = snapshot.amount - taxAmount
            return [
                LegacyPostingLineSnapshot(accountId: paymentAccountId, debit: snapshot.amount, credit: 0, memo: ""),
                LegacyPostingLineSnapshot(accountId: revenueAccountId, debit: 0, credit: netAmount, memo: ""),
                LegacyPostingLineSnapshot(accountId: AccountingConstants.outputTaxAccountId, debit: 0, credit: taxAmount, memo: "仮受消費税")
            ]
        }

        return [
            LegacyPostingLineSnapshot(accountId: paymentAccountId, debit: snapshot.amount, credit: 0, memo: ""),
            LegacyPostingLineSnapshot(accountId: revenueAccountId, debit: 0, credit: snapshot.amount, memo: "")
        ]
    }

    private func synthesizeExpensePostingLines(
        for snapshot: TransactionSnapshot,
        categories: [PPCategory]
    ) -> [LegacyPostingLineSnapshot] {
        let paymentAccountId = snapshot.paymentAccountId ?? AccountingConstants.defaultPaymentAccountId
        let expenseAccountId = resolvedLegacyLinkedAccountId(
            categoryId: snapshot.categoryId,
            categories: categories,
            fallback: AccountingConstants.miscExpenseAccountId
        )

        let rate = snapshot.effectiveTaxDeductibleRate
        let amount = snapshot.amount
        let hasTax = (snapshot.taxAmount ?? 0) > 0 && snapshot.resolvedTaxCode?.isTaxable == true
        let taxAmount = hasTax ? (snapshot.taxAmount ?? 0) : 0
        let expenseBase = hasTax ? (amount - taxAmount) : amount

        if rate >= 100 {
            var lines = [
                LegacyPostingLineSnapshot(accountId: expenseAccountId, debit: expenseBase, credit: 0, memo: "")
            ]
            if taxAmount > 0 {
                lines.append(
                    LegacyPostingLineSnapshot(
                        accountId: AccountingConstants.inputTaxAccountId,
                        debit: taxAmount,
                        credit: 0,
                        memo: "仮払消費税"
                    )
                )
            }
            lines.append(LegacyPostingLineSnapshot(accountId: paymentAccountId, debit: 0, credit: amount, memo: ""))
            return lines
        }

        let deductibleAmount = expenseBase * rate / 100
        let personalAmount = expenseBase - deductibleAmount
        var lines: [LegacyPostingLineSnapshot] = []

        if deductibleAmount > 0 {
            lines.append(LegacyPostingLineSnapshot(accountId: expenseAccountId, debit: deductibleAmount, credit: 0, memo: ""))
        }
        if taxAmount > 0 {
            let deductibleTax = taxAmount * rate / 100
            let personalTax = taxAmount - deductibleTax
            if deductibleTax > 0 {
                lines.append(
                    LegacyPostingLineSnapshot(
                        accountId: AccountingConstants.inputTaxAccountId,
                        debit: deductibleTax,
                        credit: 0,
                        memo: "仮払消費税"
                    )
                )
            }
            if personalTax > 0 {
                lines.append(
                    LegacyPostingLineSnapshot(
                        accountId: AccountingConstants.ownerDrawingsAccountId,
                        debit: personalAmount + personalTax,
                        credit: 0,
                        memo: ""
                    )
                )
            } else if personalAmount > 0 {
                lines.append(
                    LegacyPostingLineSnapshot(
                        accountId: AccountingConstants.ownerDrawingsAccountId,
                        debit: personalAmount,
                        credit: 0,
                        memo: ""
                    )
                )
            }
        } else if personalAmount > 0 {
            lines.append(
                LegacyPostingLineSnapshot(
                    accountId: AccountingConstants.ownerDrawingsAccountId,
                    debit: personalAmount,
                    credit: 0,
                    memo: ""
                )
            )
        }

        lines.append(LegacyPostingLineSnapshot(accountId: paymentAccountId, debit: 0, credit: amount, memo: ""))
        return lines
    }

    private func synthesizeTransferPostingLines(
        for snapshot: TransactionSnapshot
    ) -> [LegacyPostingLineSnapshot] {
        let fromAccountId = snapshot.paymentAccountId ?? AccountingConstants.defaultPaymentAccountId
        let toAccountId = snapshot.transferToAccountId ?? AccountingConstants.suspenseAccountId
        return [
            LegacyPostingLineSnapshot(accountId: toAccountId, debit: snapshot.amount, credit: 0, memo: ""),
            LegacyPostingLineSnapshot(accountId: fromAccountId, debit: 0, credit: snapshot.amount, memo: "")
        ]
    }

    private func resolvedLegacyLinkedAccountId(
        categoryId: String,
        categories: [PPCategory],
        fallback: String
    ) -> String {
        if let category = categories.first(where: { $0.id == categoryId }),
           let linkedAccountId = category.linkedAccountId {
            return linkedAccountId
        }
        if let mappedAccountId = AccountingConstants.categoryToAccountMapping[categoryId] {
            return mappedAccountId
        }
        return fallback
    }

    private func resolvedCanonicalTaxCodeId(
        for snapshot: TransactionSnapshot,
        counterparty: Counterparty?,
        legacyLines: [LegacyPostingLineSnapshot],
        canonicalAccountsByLegacyId: [String: CanonicalAccount]
    ) -> String? {
        if let taxCodeId = snapshot.taxCodeId {
            return taxCodeId
        }
        if let explicitTaxCodeId = TaxCode.resolve(
            legacyCategory: snapshot.taxCategory,
            taxRate: snapshot.taxRate
        )?.rawValue {
            return explicitTaxCodeId
        }
        if let counterpartyDefault = counterparty?.defaultTaxCodeId {
            return counterpartyDefault
        }
        for legacyLine in legacyLines {
            guard let account = canonicalAccountsByLegacyId[legacyLine.accountId] else {
                continue
            }
            guard account.accountType == .expense || account.accountType == .revenue else {
                continue
            }
            if let defaultTaxCodeId = account.defaultTaxCodeId {
                return defaultTaxCodeId
            }
        }
        return nil
    }

    private func makeCanonicalTaxAnalysis(
        for snapshot: TransactionSnapshot,
        taxCodeId: String?,
        counterparty: Counterparty?,
        taxYearProfile: TaxYearProfile,
        pack: TaxYearPack?
    ) -> TaxAnalysis? {
        guard let taxCode = TaxCode.resolve(id: taxCodeId), taxCode.isTaxable else {
            return nil
        }
        guard let taxAmount = snapshot.taxAmount, taxAmount > 0 else {
            return nil
        }

        let evaluator = TaxRuleEvaluator(profile: taxYearProfile, pack: pack)
        let counterpartyInvoiceStatus = counterparty?.invoiceIssuerStatus ?? .unknown
        let grossAmount = Decimal(snapshot.amount)
        let creditMethod: InputTaxCreditMethod
        if snapshot.type == .expense {
            creditMethod = evaluator.evaluateInputTaxCreditMethod(
                transactionDate: snapshot.date,
                counterpartyInvoiceStatus: counterpartyInvoiceStatus,
                amount: grossAmount
            )
        } else {
            creditMethod = .notApplicable
        }

        let deductibleTaxAmount: Decimal
        if snapshot.type == .expense {
            deductibleTaxAmount = Decimal(taxAmount) * creditMethod.creditRate
        } else {
            deductibleTaxAmount = 0
        }

        return TaxAnalysis(
            creditMethod: creditMethod,
            taxRateBreakdown: taxCode.rateBreakdown(using: pack),
            taxableAmount: Decimal(snapshot.netAmount),
            taxAmount: Decimal(taxAmount),
            deductibleTaxAmount: deductibleTaxAmount
        )
    }

    private func resolvedTaxYearProfile(
        businessId: UUID,
        taxYear: Int
    ) -> TaxYearProfile {
        do {
            let descriptor = FetchDescriptor<TaxYearProfileEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                }
            )
            if let entity = try modelContext.fetch(descriptor).first {
                return TaxYearProfileEntityMapper.toDomain(entity)
            }
        } catch {
            AppLogger.dataStore.warning("Tax year profile lookup failed: \(error.localizedDescription)")
        }

        return TaxYearProfile(
            businessId: businessId,
            taxYear: taxYear,
            taxPackVersion: (try? BundledTaxYearPackProvider(bundle: .main).packSync(for: taxYear).version)
                ?? "\(taxYear)-v1"
        )
    }

    private func fetchCanonicalAccounts(businessId: UUID) throws -> [CanonicalAccount] {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(
            predicate: #Predicate { $0.businessId == businessId },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return try modelContext.fetch(descriptor).map(CanonicalAccountEntityMapper.toDomain)
    }

    private func nextVoucherNumber(
        businessId: UUID,
        taxYear: Int,
        month: Int
    ) -> VoucherNumber {
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == taxYear
            },
            sortBy: [SortDescriptor(\.voucherNo, order: .reverse)]
        )
        let sequence = ((try? modelContext.fetch(descriptor)) ?? [])
            .compactMap { VoucherNumber(rawValue: $0.voucherNo) }
            .filter { $0.taxYear == taxYear && $0.month == month }
            .compactMap(\.sequence)
            .max() ?? 0
        return VoucherNumber(taxYear: taxYear, month: month, sequence: sequence + 1)
    }

    private func fiscalYear(for date: Date, startMonth: Int) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        if month < startMonth {
            return year - 1
        }
        return year
    }

    private func decimalToInt(_ value: Decimal) -> Int {
        NSDecimalNumber(decimal: value).intValue
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
