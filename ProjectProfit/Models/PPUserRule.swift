import SwiftData
import Foundation

/// ユーザー定義の分類ルール（トランザクション → TaxLine 自動分類用）
@Model
final class PPUserRule {
    @Attribute(.unique) var id: UUID
    var keyword: String          // マッチ対象のキーワード（memo や categoryName に部分一致）
    var taxLine: TaxLine         // 分類先の TaxLine
    var priority: Int            // 優先度（高い方が優先）
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        keyword: String,
        taxLine: TaxLine,
        priority: Int = 100,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.keyword = keyword
        self.taxLine = taxLine
        self.priority = priority
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
