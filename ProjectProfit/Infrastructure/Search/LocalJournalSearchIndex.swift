import Foundation
import SwiftData

@MainActor
final class LocalJournalSearchIndex {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func search(criteria: JournalSearchCriteria) throws -> [UUID] {
        let descriptor = FetchDescriptor<JournalSearchIndexEntity>(
            sortBy: [
                SortDescriptor(\.journalDate, order: .reverse),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        return try modelContext.fetch(descriptor)
            .filter { entry in
                matches(entry, criteria: criteria)
            }
            .map(\.journalId)
    }

    func rebuild(businessId: UUID? = nil, taxYear: Int? = nil) throws {
        let existingDescriptor = FetchDescriptor<JournalSearchIndexEntity>()
        let existing = try modelContext.fetch(existingDescriptor).filter { entry in
            if let businessId, entry.businessId != businessId {
                return false
            }
            if let taxYear, entry.taxYear != taxYear {
                return false
            }
            return true
        }
        existing.forEach(modelContext.delete)

        let journalDescriptor = FetchDescriptor<JournalEntryEntity>()
        let journalEntities = try modelContext.fetch(journalDescriptor).filter { entity in
            if let businessId, entity.businessId != businessId {
                return false
            }
            if let taxYear, entity.taxYear != taxYear {
                return false
            }
            return true
        }

        let evidenceIds = Set(journalEntities.flatMap { entity in
            let lineEvidenceIds = entity.lines.compactMap(\.evidenceReferenceId)
            if let sourceEvidenceId = entity.sourceEvidenceId {
                return [sourceEvidenceId] + lineEvidenceIds
            }
            return lineEvidenceIds
        })

        let evidenceDescriptor = FetchDescriptor<EvidenceRecordEntity>()
        let evidences = try modelContext.fetch(evidenceDescriptor)
            .map(EvidenceRecordEntityMapper.toDomain)
            .filter { evidenceIds.contains($0.id) }
        let evidenceById = Dictionary(uniqueKeysWithValues: evidences.map { ($0.id, $0) })

        for entity in journalEntities {
            let journal = CanonicalJournalEntryEntityMapper.toDomain(entity)
            let indexEntity = JournalSearchIndexEntity(journalId: journal.id)
            populate(indexEntity, from: journal, evidenceById: evidenceById)
            modelContext.insert(indexEntity)
        }

        try modelContext.save()
    }

    func remove(journalId: UUID) throws {
        let descriptor = FetchDescriptor<JournalSearchIndexEntity>(
            predicate: #Predicate { $0.journalId == journalId }
        )
        try modelContext.fetch(descriptor).forEach(modelContext.delete)
        try modelContext.save()
    }

    func indexCount(businessId: UUID? = nil, taxYear: Int? = nil) throws -> Int {
        let descriptor = FetchDescriptor<JournalSearchIndexEntity>()
        return try modelContext.fetch(descriptor).filter { entry in
            if let businessId, entry.businessId != businessId {
                return false
            }
            if let taxYear, entry.taxYear != taxYear {
                return false
            }
            return true
        }.count
    }

    func sourceCount(businessId: UUID? = nil, taxYear: Int? = nil) throws -> Int {
        let descriptor = FetchDescriptor<JournalEntryEntity>()
        return try modelContext.fetch(descriptor).filter { entry in
            if let businessId, entry.businessId != businessId {
                return false
            }
            if let taxYear, entry.taxYear != taxYear {
                return false
            }
            return true
        }.count
    }

    private func matches(_ entry: JournalSearchIndexEntity, criteria: JournalSearchCriteria) -> Bool {
        if let businessId = criteria.businessId, entry.businessId != businessId {
            return false
        }
        if let taxYear = criteria.taxYear, entry.taxYear != taxYear {
            return false
        }
        if let dateRange = criteria.dateRange, !dateRange.contains(entry.journalDate) {
            return false
        }
        if let amountRange = criteria.amountRange, !amountRange.contains(entry.totalAmount) {
            return false
        }
        if !criteria.includeCancelled, (entry.isCancelledOriginal || entry.isReversal) {
            return false
        }

        let counterparties = CanonicalJSONCoder.decode([String].self, from: entry.counterpartyNamesJSON, fallback: [])
        if let counterpartyText = SearchIndexNormalizer.normalizeOptionalText(criteria.counterpartyText),
           !counterparties.contains(where: { $0.contains(counterpartyText) }) {
            return false
        }

        let registrationNumbers = Set(CanonicalJSONCoder.decode([String].self, from: entry.registrationNumbersJSON, fallback: []))
        if let registrationNumber = SearchIndexNormalizer.normalizeIdentifier(criteria.registrationNumber),
           !registrationNumbers.contains(registrationNumber) {
            return false
        }

        let projectIds = Set(CanonicalJSONCoder.decode([UUID].self, from: entry.projectIdsJSON, fallback: []))
        if let projectId = criteria.projectId, !projectIds.contains(projectId) {
            return false
        }

        let fileHashes = Set(CanonicalJSONCoder.decode([String].self, from: entry.fileHashesJSON, fallback: []))
        if let fileHash = SearchIndexNormalizer.normalizeIdentifier(criteria.fileHash),
           !fileHashes.contains(fileHash) {
            return false
        }

        if let textQuery = SearchIndexNormalizer.normalizeOptionalText(criteria.textQuery),
           !entry.searchText.contains(textQuery) {
            return false
        }

        return true
    }

    private func populate(
        _ entity: JournalSearchIndexEntity,
        from journal: CanonicalJournalEntry,
        evidenceById: [UUID: EvidenceDocument]
    ) {
        let relatedEvidences = relatedEvidence(for: journal, evidenceById: evidenceById)
        let counterpartyNames = Set(
            relatedEvidences.compactMap { SearchIndexNormalizer.normalizeOptionalText($0.structuredFields?.counterpartyName) }
        )
        let registrationNumbers = Set(
            relatedEvidences.compactMap { SearchIndexNormalizer.normalizeIdentifier($0.structuredFields?.registrationNumber) }
        )
        let projectIds = Set(relatedEvidences.flatMap(\.linkedProjectIds))
        let fileHashes = Set(
            relatedEvidences.compactMap { SearchIndexNormalizer.normalizeIdentifier($0.fileHash) }
        )
        let searchTextParts = [
            journal.description,
            journal.voucherNo,
            counterpartyNames.joined(separator: " "),
            registrationNumbers.joined(separator: " "),
            fileHashes.joined(separator: " ")
        ]

        entity.businessId = journal.businessId
        entity.taxYear = journal.taxYear
        entity.journalDate = journal.journalDate
        entity.totalAmount = journal.totalDebit
        entity.counterpartyNamesJSON = CanonicalJSONCoder.encode(Array(counterpartyNames).sorted(), fallback: "[]")
        entity.registrationNumbersJSON = CanonicalJSONCoder.encode(Array(registrationNumbers).sorted(), fallback: "[]")
        entity.projectIdsJSON = CanonicalJSONCoder.encode(Array(projectIds).sorted { $0.uuidString < $1.uuidString }, fallback: "[]")
        entity.fileHashesJSON = CanonicalJSONCoder.encode(Array(fileHashes).sorted(), fallback: "[]")
        entity.searchText = SearchIndexNormalizer.normalizeText(searchTextParts.joined(separator: " "))
        entity.isCancelledOriginal = journal.lockedAt != nil
        entity.isReversal = journal.entryType == .reversal
        entity.updatedAt = journal.updatedAt
    }

    private func relatedEvidence(
        for journal: CanonicalJournalEntry,
        evidenceById: [UUID: EvidenceDocument]
    ) -> [EvidenceDocument] {
        let ids = Set(
            ([journal.sourceEvidenceId] + journal.lines.map(\.evidenceReferenceId))
                .compactMap { $0 }
        )
        return ids.compactMap { evidenceById[$0] }
    }
}
