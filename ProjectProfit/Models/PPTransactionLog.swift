import SwiftData
import Foundation

/// 取引の変更履歴（監査証跡）
@Model
final class PPTransactionLog {
    @Attribute(.unique) var id: UUID
    var transactionId: UUID
    var fieldName: String
    var oldValue: String?
    var newValue: String?
    var changedAt: Date

    init(
        id: UUID = UUID(),
        transactionId: UUID,
        fieldName: String,
        oldValue: String? = nil,
        newValue: String? = nil,
        changedAt: Date = Date()
    ) {
        self.id = id
        self.transactionId = transactionId
        self.fieldName = fieldName
        self.oldValue = oldValue
        self.newValue = newValue
        self.changedAt = changedAt
    }
}
