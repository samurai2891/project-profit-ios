import Foundation
import os
import SwiftData

// MARK: - AccountingEngine

/// 会計エンジン: PPTransaction → PPJournalEntry/PPJournalLine の自動変換
/// Todo.md 4B-4 準拠
@MainActor
final class AccountingEngine {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.projectprofit", category: "AccountingEngine")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// PPTransaction から PPJournalEntry を生成/更新する
    /// bookkeepingMode == .locked の場合はスキップ（ユーザー編集済み仕訳を保護）
    /// - Returns: 生成/更新された PPJournalEntry（locked の場合は既存を返す）
    @discardableResult
    func upsertJournalEntry(
        for transaction: PPTransaction,
        categories: [PPCategory],
        accounts: [PPAccount]
    ) -> PPJournalEntry? {
        let sourceKey = PPJournalEntry.transactionSourceKey(transaction.id)

        // 取引がロックされている場合は自動再生成しない
        if transaction.bookkeepingMode == .locked {
            return findEntryBySourceKey(sourceKey)
        }

        // ユーザーが手動編集した仕訳（entryType == .manual）は自動更新をスキップ
        if let existingEntry = findEntryBySourceKey(sourceKey),
           existingEntry.entryType == .manual {
            return existingEntry
        }

        // 既存仕訳があれば関連行を削除して再生成
        if let existing = findEntryBySourceKey(sourceKey) {
            deleteJournalLines(for: existing.id)
            let updated = buildUpdatedEntry(existing, from: transaction, categories: categories, accounts: accounts)
            return updated
        }

        // 新規仕訳を作成
        return createNewEntry(for: transaction, sourceKey: sourceKey, categories: categories, accounts: accounts)
    }

    /// トランザクション削除時に対応する仕訳と明細行を削除する
    func deleteJournalEntry(for transactionId: UUID) {
        let sourceKey = PPJournalEntry.transactionSourceKey(transactionId)
        guard let entry = findEntryBySourceKey(sourceKey) else { return }
        deleteJournalLines(for: entry.id)
        modelContext.delete(entry)
    }

    /// 全仕訳を再構築する（データ復旧用）
    func rebuildAllJournalEntries(
        transactions: [PPTransaction],
        categories: [PPCategory],
        accounts: [PPAccount]
    ) {
        // 自動仕訳のみ削除（手動仕訳・期首仕訳は保持）
        deleteAllAutoJournalEntries()

        for transaction in transactions {
            upsertJournalEntry(for: transaction, categories: categories, accounts: accounts)
        }
    }

    /// 仕訳の借方/貸方一致をチェックする
    func validateJournalEntry(_ entry: PPJournalEntry) -> [JournalValidationIssue] {
        let lines = fetchJournalLines(for: entry.id)
        return JournalValidationService.validateEntry(entry, lines: lines)
    }

    // MARK: - Opening Balance (4B-7)

    /// 指定年度の期首残高仕訳を生成する
    /// 前年度末の資産・負債・資本残高を集計し、1月1日付で opening 仕訳を作成
    /// 元入金で差額を調整（個人事業主の期首元入金 = 前期末資産 - 前期末負債）
    @discardableResult
    func generateOpeningBalanceEntry(
        for year: Int,
        accounts: [PPAccount],
        journalEntries: [PPJournalEntry],
        journalLines: [PPJournalLine]
    ) -> PPJournalEntry? {
        let sourceKey = PPJournalEntry.openingSourceKey(year: year)

        // 既存の期首仕訳があれば再生成しない
        if findEntryBySourceKey(sourceKey) != nil {
            logger.info("期首残高仕訳は既に存在します: \(year)年")
            return findEntryBySourceKey(sourceKey)
        }

        let calendar = Calendar(identifier: .gregorian)
        guard let openingDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return nil
        }

        // 前年度末（year-1 の 12/31）までの各勘定科目残高を集計
        guard let cutoffDate = calendar.date(from: DateComponents(year: year - 1, month: 12, day: 31)) else {
            return nil
        }

        // 前年度までの posted 仕訳行から残高を計算
        let priorLines = journalLines.filter { line in
            guard let entry = journalEntries.first(where: { $0.id == line.entryId }) else { return false }
            return entry.isPosted && entry.date <= cutoffDate && entry.entryType != .closing
        }

        // 勘定科目ごとの残高集計
        var balanceByAccountId: [String: Int] = [:]
        for line in priorLines {
            let current = balanceByAccountId[line.accountId, default: 0]
            guard let account = accounts.first(where: { $0.id == line.accountId }) else { continue }
            // 正常残高方向で加算
            switch account.normalBalance {
            case .debit:
                balanceByAccountId[line.accountId] = current + line.debit - line.credit
            case .credit:
                balanceByAccountId[line.accountId] = current + line.credit - line.debit
            }
        }

        // 残高がゼロの科目は除外、収益・費用科目も除外（期首残高に含めない）
        let bsAccounts = accounts.filter { [.asset, .liability, .equity].contains($0.accountType) }
        let relevantBalances = bsAccounts.compactMap { account -> (String, Int)? in
            guard let balance = balanceByAccountId[account.id], balance != 0 else { return nil }
            // 元入金は後で調整するので除外
            guard account.id != AccountingConstants.ownerCapitalAccountId else { return nil }
            return (account.id, balance)
        }

        // 残高がなければ期首仕訳は不要
        guard !relevantBalances.isEmpty else { return nil }

        let entry = PPJournalEntry(
            sourceKey: sourceKey,
            date: openingDate,
            entryType: .opening,
            memo: "\(year)年 期首残高",
            isPosted: true
        )
        modelContext.insert(entry)

        var totalDebit = 0
        var totalCredit = 0
        var order = 0

        for (accountId, balance) in relevantBalances {
            guard let account = accounts.first(where: { $0.id == accountId }) else { continue }
            let debit: Int
            let credit: Int

            switch account.normalBalance {
            case .debit:
                debit = balance
                credit = 0
            case .credit:
                debit = 0
                credit = balance
            }

            let line = PPJournalLine(
                entryId: entry.id,
                accountId: accountId,
                debit: debit,
                credit: credit,
                memo: "",
                displayOrder: order
            )
            modelContext.insert(line)
            totalDebit += debit
            totalCredit += credit
            order += 1
        }

        // 元入金で差額を調整（借方合計 == 貸方合計にする）
        let difference = totalDebit - totalCredit
        if difference != 0 {
            let capitalDebit = difference > 0 ? 0 : -difference
            let capitalCredit = difference > 0 ? difference : 0
            let capitalLine = PPJournalLine(
                entryId: entry.id,
                accountId: AccountingConstants.ownerCapitalAccountId,
                debit: capitalDebit,
                credit: capitalCredit,
                memo: "期首元入金調整",
                displayOrder: order
            )
            modelContext.insert(capitalLine)
        }

        return entry
    }

    // MARK: - Private: Entry Creation

    private func createNewEntry(
        for transaction: PPTransaction,
        sourceKey: String,
        categories: [PPCategory],
        accounts: [PPAccount]
    ) -> PPJournalEntry? {
        let entry = PPJournalEntry(
            sourceKey: sourceKey,
            date: transaction.date,
            entryType: .auto,
            memo: transaction.memo,
            isPosted: false // バリデーション後に true に設定
        )
        modelContext.insert(entry)

        let lines = buildJournalLines(for: transaction, entryId: entry.id, categories: categories, accounts: accounts)
        for line in lines {
            modelContext.insert(line)
        }

        // バリデーション: 貸借一致チェック
        let issues = JournalValidationService.validateLines(lines)
        let debitTotal = lines.reduce(0) { $0 + $1.debit }
        let creditTotal = lines.reduce(0) { $0 + $1.credit }
        if issues.isEmpty && debitTotal == creditTotal {
            entry.isPosted = true
        } else {
            logger.warning("新規仕訳バリデーション失敗 (sourceKey=\(sourceKey)): lines=\(issues), debit=\(debitTotal), credit=\(creditTotal)")
        }

        return entry
    }

    private func buildUpdatedEntry(
        _ entry: PPJournalEntry,
        from transaction: PPTransaction,
        categories: [PPCategory],
        accounts: [PPAccount]
    ) -> PPJournalEntry {
        entry.date = transaction.date
        entry.memo = transaction.memo
        entry.updatedAt = Date()

        let lines = buildJournalLines(for: transaction, entryId: entry.id, categories: categories, accounts: accounts)
        for line in lines {
            modelContext.insert(line)
        }

        // バリデーション: 貸借一致チェック
        let issues = JournalValidationService.validateLines(lines)
        if !issues.isEmpty {
            entry.isPosted = false
            logger.warning("仕訳バリデーション失敗 (sourceKey=\(entry.sourceKey)): \(issues)")
        } else {
            entry.isPosted = true
        }

        return entry
    }

    // MARK: - Private: Journal Line Building

    /// PPTransaction の type に応じて仕訳明細行を生成する
    private func buildJournalLines(
        for transaction: PPTransaction,
        entryId: UUID,
        categories: [PPCategory],
        accounts: [PPAccount]
    ) -> [PPJournalLine] {
        switch transaction.type {
        case .income:
            return buildIncomeLines(for: transaction, entryId: entryId, categories: categories, accounts: accounts)
        case .expense:
            return buildExpenseLines(for: transaction, entryId: entryId, categories: categories, accounts: accounts)
        case .transfer:
            return buildTransferLines(for: transaction, entryId: entryId)
        }
    }

    /// 収入: 借方=paymentAccount, 貸方=カテゴリ連動勘定科目(売上高等)
    /// 消費税あり: Dr 現金(税込) / Cr 売上(税抜) + Cr 仮受消費税(税額)
    private func buildIncomeLines(
        for transaction: PPTransaction,
        entryId: UUID,
        categories: [PPCategory],
        accounts: [PPAccount]
    ) -> [PPJournalLine] {
        let paymentAccountId = resolvePaymentAccountId(transaction)
        let revenueAccountId = resolveLinkedAccountId(
            categoryId: transaction.categoryId,
            categories: categories,
            fallback: AccountingConstants.salesAccountId
        )

        // 消費税対応: taxAmount > 0 かつ課税取引の場合
        if let taxAmount = transaction.taxAmount, taxAmount > 0,
           let taxCode = transaction.resolvedTaxCode, taxCode.isTaxable {
            let netAmount = transaction.amount - taxAmount
            var lines: [PPJournalLine] = []
            lines.append(PPJournalLine(
                entryId: entryId, accountId: paymentAccountId,
                debit: transaction.amount, credit: 0, memo: "", displayOrder: 0
            ))
            lines.append(PPJournalLine(
                entryId: entryId, accountId: revenueAccountId,
                debit: 0, credit: netAmount, memo: "", displayOrder: 1
            ))
            lines.append(PPJournalLine(
                entryId: entryId, accountId: AccountingConstants.outputTaxAccountId,
                debit: 0, credit: taxAmount, memo: "仮受消費税", displayOrder: 2
            ))
            return lines
        }

        return [
            PPJournalLine(
                entryId: entryId, accountId: paymentAccountId,
                debit: transaction.amount, credit: 0, memo: "", displayOrder: 0
            ),
            PPJournalLine(
                entryId: entryId, accountId: revenueAccountId,
                debit: 0, credit: transaction.amount, memo: "", displayOrder: 1
            ),
        ]
    }

    /// 経費: taxDeductibleRate に応じて2行 or 3行仕訳
    /// 100%: 借方=経費勘定, 貸方=paymentAccount
    /// 按分あり: 借方=経費勘定×rate% + 事業主貸×(100-rate)%, 貸方=paymentAccount
    /// 消費税あり: Dr 経費(税抜) + Dr 仮払消費税(税額) / Cr 現金(税込)
    private func buildExpenseLines(
        for transaction: PPTransaction,
        entryId: UUID,
        categories: [PPCategory],
        accounts: [PPAccount]
    ) -> [PPJournalLine] {
        let paymentAccountId = resolvePaymentAccountId(transaction)
        let expenseAccountId = resolveLinkedAccountId(
            categoryId: transaction.categoryId,
            categories: categories,
            fallback: AccountingConstants.miscExpenseAccountId
        )

        let rate = transaction.effectiveTaxDeductibleRate
        let amount = transaction.amount

        // 消費税対応: taxAmount > 0 かつ課税取引の場合
        let hasTax = transaction.taxAmount.map { $0 > 0 } ?? false
            && transaction.resolvedTaxCode?.isTaxable == true
        let taxAmount = hasTax ? (transaction.taxAmount ?? 0) : 0
        let expenseBase = hasTax ? (amount - taxAmount) : amount

        if rate >= 100 {
            // 全額経費
            var lines: [PPJournalLine] = []
            lines.append(PPJournalLine(entryId: entryId, accountId: expenseAccountId, debit: expenseBase, credit: 0, displayOrder: 0))
            if taxAmount > 0 {
                lines.append(PPJournalLine(entryId: entryId, accountId: AccountingConstants.inputTaxAccountId, debit: taxAmount, credit: 0, memo: "仮払消費税", displayOrder: 1))
            }
            lines.append(PPJournalLine(entryId: entryId, accountId: paymentAccountId, debit: 0, credit: amount, displayOrder: lines.count))
            return lines
        }

        // 家事按分あり: 経費 + 事業主貸（税抜ベースで按分）
        let deductibleAmount = expenseBase * rate / 100
        let personalAmount = expenseBase - deductibleAmount

        var lines: [PPJournalLine] = []
        var order = 0
        if deductibleAmount > 0 {
            lines.append(PPJournalLine(entryId: entryId, accountId: expenseAccountId, debit: deductibleAmount, credit: 0, displayOrder: order))
            order += 1
        }
        if taxAmount > 0 {
            // 仮払消費税も経費率で按分
            let deductibleTax = taxAmount * rate / 100
            let personalTax = taxAmount - deductibleTax
            if deductibleTax > 0 {
                lines.append(PPJournalLine(entryId: entryId, accountId: AccountingConstants.inputTaxAccountId, debit: deductibleTax, credit: 0, memo: "仮払消費税", displayOrder: order))
                order += 1
            }
            if personalTax > 0 {
                // 家事使用分の消費税は事業主貸に含める
                let totalPersonal = personalAmount + personalTax
                lines.append(PPJournalLine(entryId: entryId, accountId: AccountingConstants.ownerDrawingsAccountId, debit: totalPersonal, credit: 0, displayOrder: order))
                order += 1
            } else if personalAmount > 0 {
                lines.append(PPJournalLine(entryId: entryId, accountId: AccountingConstants.ownerDrawingsAccountId, debit: personalAmount, credit: 0, displayOrder: order))
                order += 1
            }
        } else if personalAmount > 0 {
            lines.append(PPJournalLine(entryId: entryId, accountId: AccountingConstants.ownerDrawingsAccountId, debit: personalAmount, credit: 0, displayOrder: order))
            order += 1
        }
        lines.append(PPJournalLine(entryId: entryId, accountId: paymentAccountId, debit: 0, credit: amount, displayOrder: order))

        return lines
    }

    /// 振替: 借方=transferToAccountId, 貸方=paymentAccountId
    private func buildTransferLines(
        for transaction: PPTransaction,
        entryId: UUID
    ) -> [PPJournalLine] {
        let fromAccountId = resolvePaymentAccountId(transaction)
        let toAccountId = transaction.transferToAccountId ?? AccountingConstants.suspenseAccountId

        return [
            PPJournalLine(entryId: entryId, accountId: toAccountId, debit: transaction.amount, credit: 0, displayOrder: 0),
            PPJournalLine(entryId: entryId, accountId: fromAccountId, debit: 0, credit: transaction.amount, displayOrder: 1),
        ]
    }

    // MARK: - Private: Account Resolution

    /// トランザクションの paymentAccountId を解決する（nil の場合はデフォルト現金口座）
    private func resolvePaymentAccountId(_ transaction: PPTransaction) -> String {
        transaction.paymentAccountId ?? AccountingConstants.defaultPaymentAccountId
    }

    /// カテゴリの linkedAccountId を解決する
    /// linkedAccountId が設定されていればそれを使用、なければ categoryToAccountMapping、最後にフォールバック
    private func resolveLinkedAccountId(
        categoryId: String,
        categories: [PPCategory],
        fallback: String
    ) -> String {
        if let category = categories.first(where: { $0.id == categoryId }) {
            if let linkedAccountId = category.linkedAccountId {
                return linkedAccountId
            }
        }
        // カテゴリマッピングからフォールバック
        if let mappedAccountId = AccountingConstants.categoryToAccountMapping[categoryId] {
            return mappedAccountId
        }
        return fallback
    }

    // MARK: - Private: Queries

    private func findExistingEntry(for transactionId: UUID) -> PPJournalEntry? {
        let sourceKey = PPJournalEntry.transactionSourceKey(transactionId)
        return findEntryBySourceKey(sourceKey)
    }

    private func findEntryBySourceKey(_ sourceKey: String) -> PPJournalEntry? {
        let descriptor = FetchDescriptor<PPJournalEntry>(
            predicate: #Predicate<PPJournalEntry> { $0.sourceKey == sourceKey }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchJournalLines(for entryId: UUID) -> [PPJournalLine] {
        let descriptor = FetchDescriptor<PPJournalLine>(
            predicate: #Predicate<PPJournalLine> { $0.entryId == entryId },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func deleteJournalLines(for entryId: UUID) {
        let lines = fetchJournalLines(for: entryId)
        for line in lines {
            modelContext.delete(line)
        }
    }

    private func deleteAllAutoJournalEntries() {
        let descriptor = FetchDescriptor<PPJournalEntry>()
        guard let entries = try? modelContext.fetch(descriptor) else { return }
        for entry in entries where entry.entryType == .auto {
            deleteJournalLines(for: entry.id)
            modelContext.delete(entry)
        }
    }
}
