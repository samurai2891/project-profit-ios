import Foundation
import SwiftData

// MARK: - PPInventoryRecord

/// 棚卸記録（年度ごとの在庫・仕入データ）
/// COGS（売上原価）= 期首商品棚卸高 + 当期仕入高 - 期末商品棚卸高
@Model
final class PPInventoryRecord {
    @Attribute(.unique) var id: UUID
    var fiscalYear: Int                // 対象年度
    var openingInventory: Int          // 期首商品棚卸高（円）
    var purchases: Int                 // 当期仕入高（円）
    var closingInventory: Int          // 期末商品棚卸高（円）
    var memo: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        fiscalYear: Int,
        openingInventory: Int = 0,
        purchases: Int = 0,
        closingInventory: Int = 0,
        memo: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fiscalYear = fiscalYear
        self.openingInventory = max(0, openingInventory)
        self.purchases = max(0, purchases)
        self.closingInventory = max(0, closingInventory)
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Computed Properties

extension PPInventoryRecord {
    /// 売上原価 = 期首商品棚卸高 + 当期仕入高 - 期末商品棚卸高
    var costOfGoodsSold: Int {
        openingInventory + purchases - closingInventory
    }
}
