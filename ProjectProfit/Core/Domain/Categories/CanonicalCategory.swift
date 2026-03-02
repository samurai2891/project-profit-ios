import Foundation

/// 入力補助カテゴリ（UI 分類限定）
/// Account(会計分類) とは明確に分離。UI でのクイック入力を支援する
struct CanonicalCategory: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let name: String
    let defaultAccountId: UUID?
    let defaultTaxCodeId: String?
    let defaultGenreTagIds: [UUID]
    let householdProrationDefault: Decimal?
    let ocrKeywordPatterns: [String]
    let counterpartyPatterns: [String]
    let sortOrder: Int
    let archivedAt: Date?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        businessId: UUID,
        name: String,
        defaultAccountId: UUID? = nil,
        defaultTaxCodeId: String? = nil,
        defaultGenreTagIds: [UUID] = [],
        householdProrationDefault: Decimal? = nil,
        ocrKeywordPatterns: [String] = [],
        counterpartyPatterns: [String] = [],
        sortOrder: Int = 0,
        archivedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.name = name
        self.defaultAccountId = defaultAccountId
        self.defaultTaxCodeId = defaultTaxCodeId
        self.defaultGenreTagIds = defaultGenreTagIds
        self.householdProrationDefault = householdProrationDefault
        self.ocrKeywordPatterns = ocrKeywordPatterns
        self.counterpartyPatterns = counterpartyPatterns
        self.sortOrder = sortOrder
        self.archivedAt = archivedAt
        self.createdAt = createdAt
    }
}
