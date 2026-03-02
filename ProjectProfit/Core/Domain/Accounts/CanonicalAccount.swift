import Foundation

/// 正規化勘定科目（Account ≠ QuickCategory ≠ GenreTag ≠ LegalReportLine）
struct CanonicalAccount: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let businessId: UUID
    let code: String
    let name: String
    let accountType: CanonicalAccountType
    let normalBalance: NormalBalance
    let defaultLegalReportLineId: String?
    let defaultTaxCodeId: String?
    let projectAllocatable: Bool
    let householdProrationAllowed: Bool
    let displayOrder: Int
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        businessId: UUID,
        code: String,
        name: String,
        accountType: CanonicalAccountType,
        normalBalance: NormalBalance,
        defaultLegalReportLineId: String? = nil,
        defaultTaxCodeId: String? = nil,
        projectAllocatable: Bool = true,
        householdProrationAllowed: Bool = false,
        displayOrder: Int = 0,
        archivedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.businessId = businessId
        self.code = code
        self.name = name
        self.accountType = accountType
        self.normalBalance = normalBalance
        self.defaultLegalReportLineId = defaultLegalReportLineId
        self.defaultTaxCodeId = defaultTaxCodeId
        self.projectAllocatable = projectAllocatable
        self.householdProrationAllowed = householdProrationAllowed
        self.displayOrder = displayOrder
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// イミュータブル更新
    func updated(
        name: String? = nil,
        defaultLegalReportLineId: String?? = nil,
        defaultTaxCodeId: String?? = nil,
        projectAllocatable: Bool? = nil,
        householdProrationAllowed: Bool? = nil,
        displayOrder: Int? = nil,
        archivedAt: Date?? = nil
    ) -> CanonicalAccount {
        CanonicalAccount(
            id: self.id,
            businessId: self.businessId,
            code: self.code,
            name: name ?? self.name,
            accountType: self.accountType,
            normalBalance: self.normalBalance,
            defaultLegalReportLineId: defaultLegalReportLineId ?? self.defaultLegalReportLineId,
            defaultTaxCodeId: defaultTaxCodeId ?? self.defaultTaxCodeId,
            projectAllocatable: projectAllocatable ?? self.projectAllocatable,
            householdProrationAllowed: householdProrationAllowed ?? self.householdProrationAllowed,
            displayOrder: displayOrder ?? self.displayOrder,
            archivedAt: archivedAt ?? self.archivedAt,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
}
