import Foundation
import SwiftData

/// 在庫・売上原価サービス: PPInventoryRecord から COGS 決算仕訳を生成
@MainActor
enum InventoryService {

    /// COGS 仕訳の sourceKey
    static func cogsSourceKey(fiscalYear: Int) -> String {
        "cogs:\(fiscalYear)"
    }

    /// 在庫記録から COGS 決算仕訳行を生成する（仕訳の挿入は呼び出し元で行う）
    ///
    /// 仕訳パターン:
    ///   Dr 期首商品棚卸高   openingInventory
    ///   Dr 仕入高          purchases
    ///   Cr 期末商品棚卸高   closingInventory
    ///   Dr/Cr 売上原価     costOfGoodsSold (balancing entry)
    ///
    /// 簡易パターン（実務）:
    ///   Dr 売上原価  COGS額
    ///   Cr 期末商品棚卸高  closingInventory
    ///   Dr 期首商品棚卸高  openingInventory  (振替)
    ///
    /// Returns array of (accountId, debit, credit) tuples for the journal lines
    static func generateCOGSLines(
        record: PPInventoryRecord
    ) -> [(accountId: String, debit: Int, credit: Int, memo: String)] {
        var lines: [(accountId: String, debit: Int, credit: Int, memo: String)] = []

        // 期首商品棚卸高の振替: Dr 売上原価 / Cr 期首商品棚卸高
        if record.openingInventory > 0 {
            lines.append((
                accountId: AccountingConstants.cogsAccountId,
                debit: record.openingInventory,
                credit: 0,
                memo: "期首棚卸高振替"
            ))
            lines.append((
                accountId: AccountingConstants.openingInventoryAccountId,
                debit: 0,
                credit: record.openingInventory,
                memo: "期首棚卸高振替"
            ))
        }

        // 当期仕入高の振替: Dr 売上原価 / Cr 仕入高
        if record.purchases > 0 {
            lines.append((
                accountId: AccountingConstants.cogsAccountId,
                debit: record.purchases,
                credit: 0,
                memo: "当期仕入高振替"
            ))
            lines.append((
                accountId: AccountingConstants.purchasesAccountId,
                debit: 0,
                credit: record.purchases,
                memo: "当期仕入高振替"
            ))
        }

        // 期末商品棚卸高の振替: Dr 期末商品棚卸高 / Cr 売上原価
        if record.closingInventory > 0 {
            lines.append((
                accountId: AccountingConstants.closingInventoryAccountId,
                debit: record.closingInventory,
                credit: 0,
                memo: "期末棚卸高振替"
            ))
            lines.append((
                accountId: AccountingConstants.cogsAccountId,
                debit: 0,
                credit: record.closingInventory,
                memo: "期末棚卸高振替"
            ))
        }

        return lines
    }
}
