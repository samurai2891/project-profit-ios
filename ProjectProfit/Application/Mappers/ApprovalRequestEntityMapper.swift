import Foundation

enum ApprovalRequestEntityMapper {
    static func toDomain(_ entity: ApprovalRequestEntity) -> ApprovalRequest {
        ApprovalRequest(
            id: entity.requestId,
            businessId: entity.businessId,
            kind: ApprovalRequestKind(rawValue: entity.kindRaw) ?? .distribution,
            status: ApprovalRequestStatus(rawValue: entity.statusRaw) ?? .pending,
            targetKind: ApprovalRequestTargetKind(rawValue: entity.targetKindRaw) ?? .transactionDraft,
            targetKey: entity.targetKey,
            title: entity.title,
            subtitle: entity.subtitle,
            payloadJSON: entity.payloadJSON,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            resolvedAt: entity.resolvedAt
        )
    }

    static func toEntity(_ domain: ApprovalRequest) -> ApprovalRequestEntity {
        ApprovalRequestEntity(
            requestId: domain.id,
            businessId: domain.businessId,
            kindRaw: domain.kind.rawValue,
            statusRaw: domain.status.rawValue,
            targetKindRaw: domain.targetKind.rawValue,
            targetKey: domain.targetKey,
            title: domain.title,
            subtitle: domain.subtitle,
            payloadJSON: domain.payloadJSON,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            resolvedAt: domain.resolvedAt
        )
    }

    static func update(_ entity: ApprovalRequestEntity, from domain: ApprovalRequest) {
        entity.businessId = domain.businessId
        entity.kindRaw = domain.kind.rawValue
        entity.statusRaw = domain.status.rawValue
        entity.targetKindRaw = domain.targetKind.rawValue
        entity.targetKey = domain.targetKey
        entity.title = domain.title
        entity.subtitle = domain.subtitle
        entity.payloadJSON = domain.payloadJSON
        entity.updatedAt = domain.updatedAt
        entity.resolvedAt = domain.resolvedAt
    }
}
