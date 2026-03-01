// ============================================================
// LedgerDataStore+Calculations.swift
// 7パターンの残高計算ロジック
// ============================================================
//
// 計算パターン一覧:
// 1. 現金出納帳: 残高 = 前行残高 + 入金 - 出金
// 2. 預金出納帳: 残高 = 前行残高 + 入金 - 出金
// 3. 売掛帳: 残高 = 前行残高 + 売上金額 - 入金金額
// 4. 買掛帳: 残高 = 前行残高 + 仕入金額 - 支払金額
// 5. 経費帳: 合計 = 前行合計 + 金額
// 6. 総勘定元帳(資産/経費/売上原価): 残高 = 前行 + 借方 - 貸方
// 7. 総勘定元帳(負債/資本/売上): 残高 = 前行 - 借方 + 貸方

import Foundation

// MARK: - Balance Row

struct LedgerBalanceRow: Identifiable {
    let id: UUID
    let entryIndex: Int
    let balance: Int
}

// MARK: - Calculations

extension LedgerDataStore {

    // MARK: - 現金出納帳 残高計算

    func cashBookBalances(for bookId: UUID) -> [LedgerBalanceRow] {
        guard let book = book(for: bookId) else { return [] }
        let metadata = LedgerBridge.decodeCashBookMetadata(from: book.metadataJSON)
        let carryForward = metadata.carryForward
        let entries = cashBookEntries(for: bookId)

        var balance = carryForward
        return entries.enumerated().map { index, entry in
            let income = entry.income ?? 0
            let expense = entry.expense ?? 0
            balance = balance + income - expense
            return LedgerBalanceRow(id: entry.id, entryIndex: index, balance: balance)
        }
    }

    // MARK: - 預金出納帳 残高計算

    func bankAccountBookBalances(for bookId: UUID) -> [LedgerBalanceRow] {
        guard let book = book(for: bookId) else { return [] }
        let metadata = LedgerBridge.decodeBankAccountBookMetadata(from: book.metadataJSON)
        let carryForward = metadata.carryForward
        let entries = bankAccountBookEntries(for: bookId)

        var balance = carryForward
        return entries.enumerated().map { index, entry in
            let deposit = entry.deposit ?? 0
            let withdrawal = entry.withdrawal ?? 0
            balance = balance + deposit - withdrawal
            return LedgerBalanceRow(id: entry.id, entryIndex: index, balance: balance)
        }
    }

    // MARK: - 売掛帳 残高計算

    func accountsReceivableBalances(for bookId: UUID) -> [LedgerBalanceRow] {
        guard let book = book(for: bookId) else { return [] }
        let metadata = LedgerBridge.decodeAccountsReceivableMetadata(from: book.metadataJSON)
        let carryForward = metadata.carryForward
        let entries = accountsReceivableEntries(for: bookId)

        var balance = carryForward
        return entries.enumerated().map { index, entry in
            let sales = entry.salesAmount ?? 0
            let received = entry.receivedAmount ?? 0
            balance = balance + sales - received
            return LedgerBalanceRow(id: entry.id, entryIndex: index, balance: balance)
        }
    }

    // MARK: - 買掛帳 残高計算

    func accountsPayableBalances(for bookId: UUID) -> [LedgerBalanceRow] {
        guard let book = book(for: bookId) else { return [] }
        let metadata = LedgerBridge.decodeAccountsPayableMetadata(from: book.metadataJSON)
        let carryForward = metadata.carryForward
        let entries = accountsPayableEntries(for: bookId)

        var balance = carryForward
        return entries.enumerated().map { index, entry in
            let purchase = entry.purchaseAmount ?? 0
            let payment = entry.paymentAmount ?? 0
            balance = balance + purchase - payment
            return LedgerBalanceRow(id: entry.id, entryIndex: index, balance: balance)
        }
    }

    // MARK: - 経費帳 累計計算

    func expenseBookRunningTotals(for bookId: UUID) -> [LedgerBalanceRow] {
        let entries = expenseBookEntries(for: bookId)

        var runningTotal = 0
        return entries.enumerated().map { index, entry in
            runningTotal += entry.amount
            return LedgerBalanceRow(id: entry.id, entryIndex: index, balance: runningTotal)
        }
    }

    // MARK: - 総勘定元帳 残高計算（属性対応）

    func generalLedgerBalances(for bookId: UUID) -> [LedgerBalanceRow] {
        guard let book = book(for: bookId) else { return [] }
        let metadata = LedgerBridge.decodeGeneralLedgerMetadata(from: book.metadataJSON)
        let carryForward = metadata.carryForward
        let attribute = metadata.accountAttribute ?? .asset
        let entries = generalLedgerEntries(for: bookId)

        let isDebitNormal = [AccountCategory.asset, .expense, .costOfSales].contains(attribute)

        var balance = carryForward
        return entries.enumerated().map { index, entry in
            let debit = entry.debit ?? 0
            let credit = entry.credit ?? 0
            if isDebitNormal {
                balance = balance + debit - credit
            } else {
                balance = balance - debit + credit
            }
            return LedgerBalanceRow(id: entry.id, entryIndex: index, balance: balance)
        }
    }

    // MARK: - 汎用: 台帳タイプ別の残高取得

    func balances(for bookId: UUID) -> [LedgerBalanceRow] {
        guard let book = book(for: bookId),
              let ledgerType = book.ledgerType else { return [] }

        switch ledgerType {
        case .cashBook, .cashBookInvoice:
            return cashBookBalances(for: bookId)
        case .bankAccountBook, .bankAccountBookInvoice:
            return bankAccountBookBalances(for: bookId)
        case .accountsReceivable:
            return accountsReceivableBalances(for: bookId)
        case .accountsPayable:
            return accountsPayableBalances(for: bookId)
        case .expenseBook, .expenseBookInvoice:
            return expenseBookRunningTotals(for: bookId)
        case .generalLedger, .generalLedgerInvoice:
            return generalLedgerBalances(for: bookId)
        case .journal, .fixedAssetDepreciation, .fixedAssetRegister,
             .transportationExpense, .whiteTaxBookkeeping, .whiteTaxBookkeepingInvoice:
            return []
        }
    }

    // MARK: - 最終残高

    func finalBalance(for bookId: UUID) -> Int? {
        balances(for: bookId).last?.balance
    }
}
