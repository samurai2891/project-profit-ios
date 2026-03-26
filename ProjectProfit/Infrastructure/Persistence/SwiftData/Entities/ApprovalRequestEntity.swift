import Foundation
import SwiftData

@Model
final class ApprovalRequestEntity {
    @Attribute(.unique) var requestId: UUID
    var businessId: UUID
    var kindRaw: String
    var statusRaw: String
    var targetKindRaw: String
    var targetKey: String
    var title: String
    var subtitle: String?
    var payloadJSON: String
    var createdAt: Date
    var updatedAt: Date
    var resolvedAt: Date?

    init(
        requestId: UUID = UUID(),
        businessId: UUID = UUID(),
        kindRaw: String = ApprovalRequestKind.distribution.rawValue,
        statusRaw: String = ApprovalRequestStatus.pending.rawValue,
        targetKindRaw: String = ApprovalRequestTargetKind.transactionDraft.rawValue,
        targetKey: String = "",
        title: String = "",
        subtitle: String? = nil,
        payloadJSON: String = "{}",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.requestId = requestId
        self.businessId = businessId
        self.kindRaw = kindRaw
        self.statusRaw = statusRaw
        self.targetKindRaw = targetKindRaw
        self.targetKey = targetKey
        self.title = title
        self.subtitle = subtitle
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
    }
}
