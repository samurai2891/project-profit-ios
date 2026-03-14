import Foundation

enum FormDraftEntityMapper {
    static func toDomain(_ entity: FormDraftEntity) -> FormDraft {
        FormDraft(
            id: entity.draftId,
            businessId: entity.businessId,
            draftKey: entity.draftKey,
            kind: FormDraftKind(rawValue: entity.kindRaw) ?? .transaction,
            snapshotJSON: entity.snapshotJSON,
            activeApprovalRequestId: entity.activeApprovalRequestId,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    static func toEntity(_ domain: FormDraft) -> FormDraftEntity {
        FormDraftEntity(
            draftId: domain.id,
            draftKey: domain.draftKey,
            businessId: domain.businessId,
            kindRaw: domain.kind.rawValue,
            snapshotJSON: domain.snapshotJSON,
            activeApprovalRequestId: domain.activeApprovalRequestId,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    static func update(_ entity: FormDraftEntity, from domain: FormDraft) {
        entity.businessId = domain.businessId
        entity.kindRaw = domain.kind.rawValue
        entity.snapshotJSON = domain.snapshotJSON
        entity.activeApprovalRequestId = domain.activeApprovalRequestId
        entity.updatedAt = domain.updatedAt
    }
}
