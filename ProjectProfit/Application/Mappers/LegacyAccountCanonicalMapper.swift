import CryptoKit
import Foundation

enum LegacyAccountCanonicalMapper {
    static func canonicalAccount(
        from legacyAccount: PPAccount,
        businessId: UUID,
        existing: CanonicalAccount? = nil
    ) -> CanonicalAccount {
        let canonicalId = existing?.id ?? canonicalAccountId(
            businessId: businessId,
            legacyAccountId: legacyAccount.id
        )
        let accountType = CanonicalAccountType(rawValue: legacyAccount.accountType.rawValue) ?? .expense
        let archivedAt: Date? = legacyAccount.isActive ? nil : (existing?.archivedAt ?? legacyAccount.updatedAt)

        return CanonicalAccount(
            id: canonicalId,
            businessId: businessId,
            legacyAccountId: legacyAccount.id,
            code: legacyAccount.code,
            name: legacyAccount.name,
            accountType: accountType,
            normalBalance: legacyAccount.normalBalance,
            defaultLegalReportLineId:
                existing?.defaultLegalReportLineId
                ?? AccountingConstants.defaultLegalReportLineId(forLegacyAccountId: legacyAccount.id)
                ?? legacyAccount.subtype.flatMap { LegalReportLine.defaultLine(for: $0)?.rawValue },
            defaultTaxCodeId: existing?.defaultTaxCodeId,
            projectAllocatable: existing?.projectAllocatable ?? true,
            householdProrationAllowed: existing?.householdProrationAllowed ?? false,
            displayOrder: legacyAccount.displayOrder,
            archivedAt: archivedAt,
            createdAt: existing?.createdAt ?? legacyAccount.createdAt,
            updatedAt: legacyAccount.updatedAt
        )
    }

    static func canonicalAccountId(businessId: UUID, legacyAccountId: String) -> UUID {
        if let uuid = UUID(uuidString: legacyAccountId) {
            return uuid
        }

        let normalizedLegacyId = legacyAccountId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let seed = "canonical-account|\(businessId.uuidString.lowercased())|\(normalizedLegacyId)"
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }
}
