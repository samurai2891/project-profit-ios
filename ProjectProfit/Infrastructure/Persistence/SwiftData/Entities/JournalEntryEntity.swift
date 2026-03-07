import Foundation
import SwiftData

/// SwiftData Entity: 確定仕訳
@Model
final class JournalEntryEntity {
    @Attribute(.unique) var journalId: UUID
    var businessId: UUID
    var taxYear: Int
    var journalDate: Date
    var voucherNo: String
    var sourceEvidenceId: UUID?
    var sourceCandidateId: UUID?
    var entryTypeRaw: String
    var entryDescription: String
    var approvedAt: Date?
    var lockedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade)
    var lines: [JournalLineEntity]

    init(
        journalId: UUID = UUID(),
        businessId: UUID = UUID(),
        taxYear: Int = 2025,
        journalDate: Date = Date(),
        voucherNo: String = "",
        sourceEvidenceId: UUID? = nil,
        sourceCandidateId: UUID? = nil,
        entryTypeRaw: String = "normal",
        entryDescription: String = "",
        approvedAt: Date? = nil,
        lockedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lines: [JournalLineEntity] = []
    ) {
        self.journalId = journalId
        self.businessId = businessId
        self.taxYear = taxYear
        self.journalDate = journalDate
        self.voucherNo = voucherNo
        self.sourceEvidenceId = sourceEvidenceId
        self.sourceCandidateId = sourceCandidateId
        self.entryTypeRaw = entryTypeRaw
        self.entryDescription = entryDescription
        self.approvedAt = approvedAt
        self.lockedAt = lockedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lines = lines
    }
}
