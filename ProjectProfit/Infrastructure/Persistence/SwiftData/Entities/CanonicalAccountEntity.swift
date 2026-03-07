import Foundation
import SwiftData

/// SwiftData Entity: 正規化勘定科目
@Model
final class CanonicalAccountEntity {
    @Attribute(.unique) var accountId: UUID
    var businessId: UUID
    var legacyAccountId: String?
    var code: String
    var name: String
    var accountTypeRaw: String
    var normalBalanceRaw: String
    var defaultLegalReportLineId: String?
    var defaultTaxCodeId: String?
    var projectAllocatable: Bool
    var householdProrationAllowed: Bool
    var displayOrder: Int
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        accountId: UUID = UUID(),
        businessId: UUID = UUID(),
        legacyAccountId: String? = nil,
        code: String = "",
        name: String = "",
        accountTypeRaw: String = CanonicalAccountType.expense.rawValue,
        normalBalanceRaw: String = NormalBalance.debit.rawValue,
        defaultLegalReportLineId: String? = nil,
        defaultTaxCodeId: String? = nil,
        projectAllocatable: Bool = true,
        householdProrationAllowed: Bool = false,
        displayOrder: Int = 0,
        archivedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.accountId = accountId
        self.businessId = businessId
        self.legacyAccountId = legacyAccountId
        self.code = code
        self.name = name
        self.accountTypeRaw = accountTypeRaw
        self.normalBalanceRaw = normalBalanceRaw
        self.defaultLegalReportLineId = defaultLegalReportLineId
        self.defaultTaxCodeId = defaultTaxCodeId
        self.projectAllocatable = projectAllocatable
        self.householdProrationAllowed = householdProrationAllowed
        self.displayOrder = displayOrder
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
