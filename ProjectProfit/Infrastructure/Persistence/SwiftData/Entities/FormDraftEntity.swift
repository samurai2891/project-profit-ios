import Foundation
import SwiftData

@Model
final class FormDraftEntity {
    @Attribute(.unique) var draftId: UUID
    @Attribute(.unique) var draftKey: String
    var businessId: UUID
    var kindRaw: String
    var snapshotJSON: String
    var activeApprovalRequestId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        draftId: UUID = UUID(),
        draftKey: String = "",
        businessId: UUID = UUID(),
        kindRaw: String = FormDraftKind.transaction.rawValue,
        snapshotJSON: String = "{}",
        activeApprovalRequestId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.draftId = draftId
        self.draftKey = draftKey
        self.businessId = businessId
        self.kindRaw = kindRaw
        self.snapshotJSON = snapshotJSON
        self.activeApprovalRequestId = activeApprovalRequestId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
