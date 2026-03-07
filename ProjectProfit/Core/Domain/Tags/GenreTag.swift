import Foundation

/// ジャンルタグ（自由分類）
/// Account ≠ QuickCategory ≠ GenreTag ≠ LegalReportLine
struct GenreTag: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let name: String
    let parentGenreId: UUID?
    let color: String?
    let icon: String?
    let sortOrder: Int
    let archived: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        businessId: UUID,
        name: String,
        parentGenreId: UUID? = nil,
        color: String? = nil,
        icon: String? = nil,
        sortOrder: Int = 0,
        archived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.name = name
        self.parentGenreId = parentGenreId
        self.color = color
        self.icon = icon
        self.sortOrder = sortOrder
        self.archived = archived
        self.createdAt = createdAt
    }
}
