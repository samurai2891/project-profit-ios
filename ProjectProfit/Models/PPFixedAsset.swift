import Foundation
import SwiftData

// MARK: - PPFixedAsset

/// 固定資産台帳のエントリ
/// 減価償却計算に必要な情報を保持する。
@Model
final class PPFixedAsset {
    @Attribute(.unique) var id: UUID
    var name: String                          // 資産名
    var acquisitionDate: Date                 // 取得日
    var acquisitionCost: Int                  // 取得価額（円）
    var usefulLifeYears: Int                  // 耐用年数
    var depreciationMethod: PPDepreciationMethod
    var salvageValue: Int                     // 残存価額（通常¥1）
    var assetStatus: PPAssetStatus
    var disposalDate: Date?                   // 除却/売却日
    var disposalAmount: Int?                  // 売却額
    var memo: String?
    var businessUsePercent: Int               // 事業使用割合（0-100%）
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        acquisitionDate: Date,
        acquisitionCost: Int,
        usefulLifeYears: Int,
        depreciationMethod: PPDepreciationMethod = .straightLine,
        salvageValue: Int = 1,
        assetStatus: PPAssetStatus = .active,
        disposalDate: Date? = nil,
        disposalAmount: Int? = nil,
        memo: String? = nil,
        businessUsePercent: Int = 100,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.acquisitionDate = acquisitionDate
        self.acquisitionCost = acquisitionCost
        self.usefulLifeYears = usefulLifeYears
        self.depreciationMethod = depreciationMethod
        self.salvageValue = salvageValue
        self.assetStatus = assetStatus
        self.disposalDate = disposalDate
        self.disposalAmount = disposalAmount
        self.memo = memo
        self.businessUsePercent = businessUsePercent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Computed Properties

extension PPFixedAsset {
    /// 償却基礎額（取得価額 - 残存価額）
    var depreciableBasis: Int {
        max(0, acquisitionCost - salvageValue)
    }

    /// 定額法の年間償却額（端数切捨）
    var annualStraightLineAmount: Int {
        guard usefulLifeYears > 0 else { return 0 }
        return depreciableBasis / usefulLifeYears
    }

    /// 200%定率法の償却率
    var decliningBalanceRate: Double {
        guard usefulLifeYears > 0 else { return 0 }
        return 2.0 / Double(usefulLifeYears)
    }

    /// 減価償却仕訳の sourceKey
    static func depreciationSourceKey(assetId: UUID, year: Int) -> String {
        "depreciation:\(assetId.uuidString):\(year)"
    }
}
