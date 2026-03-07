import Foundation

/// 定期取引の生成プレビュー項目
struct RecurringPreviewItem: Identifiable, Sendable {
    let id: UUID
    let recurringId: UUID
    let recurringName: String
    let type: TransactionType
    let amount: Int
    let scheduledDate: Date
    let categoryId: String
    let memo: String
    let isMonthlySpread: Bool
    let projectName: String?
    let allocationMode: AllocationMode

    init(
        id: UUID = UUID(),
        recurringId: UUID,
        recurringName: String,
        type: TransactionType,
        amount: Int,
        scheduledDate: Date,
        categoryId: String,
        memo: String,
        isMonthlySpread: Bool = false,
        projectName: String? = nil,
        allocationMode: AllocationMode = .equalAll
    ) {
        self.id = id
        self.recurringId = recurringId
        self.recurringName = recurringName
        self.type = type
        self.amount = amount
        self.scheduledDate = scheduledDate
        self.categoryId = categoryId
        self.memo = memo
        self.isMonthlySpread = isMonthlySpread
        self.projectName = projectName
        self.allocationMode = allocationMode
    }
}
