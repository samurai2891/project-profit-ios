import Foundation

/// CanonicalAccount ↔ CanonicalAccountEntity の変換
enum CanonicalAccountEntityMapper {
    static func toDomain(_ entity: CanonicalAccountEntity) -> CanonicalAccount {
        CanonicalAccount(
            id: entity.accountId,
            businessId: entity.businessId,
            legacyAccountId: entity.legacyAccountId,
            code: entity.code,
            name: entity.name,
            accountType: CanonicalAccountType(rawValue: entity.accountTypeRaw) ?? .expense,
            normalBalance: NormalBalance(rawValue: entity.normalBalanceRaw) ?? .debit,
            defaultLegalReportLineId: entity.defaultLegalReportLineId,
            defaultTaxCodeId: entity.defaultTaxCodeId,
            projectAllocatable: entity.projectAllocatable,
            householdProrationAllowed: entity.householdProrationAllowed,
            displayOrder: entity.displayOrder,
            archivedAt: entity.archivedAt,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    static func toEntity(_ domain: CanonicalAccount) -> CanonicalAccountEntity {
        CanonicalAccountEntity(
            accountId: domain.id,
            businessId: domain.businessId,
            legacyAccountId: domain.legacyAccountId,
            code: domain.code,
            name: domain.name,
            accountTypeRaw: domain.accountType.rawValue,
            normalBalanceRaw: domain.normalBalance.rawValue,
            defaultLegalReportLineId: domain.defaultLegalReportLineId,
            defaultTaxCodeId: domain.defaultTaxCodeId,
            projectAllocatable: domain.projectAllocatable,
            householdProrationAllowed: domain.householdProrationAllowed,
            displayOrder: domain.displayOrder,
            archivedAt: domain.archivedAt,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    static func update(_ entity: CanonicalAccountEntity, from domain: CanonicalAccount) {
        entity.businessId = domain.businessId
        entity.legacyAccountId = domain.legacyAccountId
        entity.code = domain.code
        entity.name = domain.name
        entity.accountTypeRaw = domain.accountType.rawValue
        entity.normalBalanceRaw = domain.normalBalance.rawValue
        entity.defaultLegalReportLineId = domain.defaultLegalReportLineId
        entity.defaultTaxCodeId = domain.defaultTaxCodeId
        entity.projectAllocatable = domain.projectAllocatable
        entity.householdProrationAllowed = domain.householdProrationAllowed
        entity.displayOrder = domain.displayOrder
        entity.archivedAt = domain.archivedAt
        entity.updatedAt = domain.updatedAt
    }
}
