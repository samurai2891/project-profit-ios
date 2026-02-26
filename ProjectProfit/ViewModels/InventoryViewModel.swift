import SwiftUI

@MainActor
@Observable
final class InventoryViewModel {
    let dataStore: DataStore

    var fiscalYear: Int
    var openingInventoryText: String = ""
    var purchasesText: String = ""
    var closingInventoryText: String = ""
    var memo: String = ""
    var existingRecord: PPInventoryRecord?

    init(dataStore: DataStore) {
        self.dataStore = dataStore
        let currentYear = Calendar.current.component(.year, from: Date())
        self.fiscalYear = currentYear - 1
    }

    // MARK: - Parsed Values

    private var openingInventory: Int {
        Int(openingInventoryText) ?? 0
    }

    private var purchases: Int {
        Int(purchasesText) ?? 0
    }

    private var closingInventory: Int {
        Int(closingInventoryText) ?? 0
    }

    /// 売上原価 = 期首商品棚卸高 + 当期仕入高 - 期末商品棚卸高
    var costOfGoodsSold: Int {
        openingInventory + purchases - closingInventory
    }

    // MARK: - Data Loading

    func loadForYear() {
        let record = dataStore.getInventoryRecord(fiscalYear: fiscalYear)
        existingRecord = record

        if let record {
            openingInventoryText = record.openingInventory > 0 ? "\(record.openingInventory)" : ""
            purchasesText = record.purchases > 0 ? "\(record.purchases)" : ""
            closingInventoryText = record.closingInventory > 0 ? "\(record.closingInventory)" : ""
            memo = record.memo ?? ""
        } else {
            openingInventoryText = ""
            purchasesText = ""
            closingInventoryText = ""
            memo = ""
        }
    }

    // MARK: - Save

    func save() {
        let memoValue: String? = memo.isEmpty ? nil : memo

        let saved: Bool
        if let existing = existingRecord {
            saved = dataStore.updateInventoryRecord(
                id: existing.id,
                openingInventory: openingInventory,
                purchases: purchases,
                closingInventory: closingInventory,
                memo: memoValue
            )
        } else {
            saved = dataStore.addInventoryRecord(
                fiscalYear: fiscalYear,
                openingInventory: openingInventory,
                purchases: purchases,
                closingInventory: closingInventory,
                memo: memoValue
            ) != nil
        }

        // 保存成功時のみ再読込してフォーム値を同期する
        if saved {
            loadForYear()
        }
    }
}
