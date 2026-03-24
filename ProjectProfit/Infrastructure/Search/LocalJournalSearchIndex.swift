import Foundation
import SwiftData

@MainActor
final class LocalJournalSearchIndex {
    static let indexName = "仕訳検索インデックス"

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func search(criteria: JournalSearchCriteria) throws -> [UUID] {
        let descriptor = searchDescriptor(criteria: criteria)
        return try modelContext.fetch(descriptor)
            .filter { entry in
                try matches(entry, criteria: criteria)
            }
            .map(\.journalId)
    }

    func rebuild(businessId: UUID? = nil, taxYear: Int? = nil) throws {
        let existing = try modelContext.fetch(scopedDescriptor(businessId: businessId, taxYear: taxYear))
        existing.forEach(modelContext.delete)

        let journalEntities = try modelContext.fetch(sourceDescriptor(businessId: businessId, taxYear: taxYear))

        let evidenceIds = Set(journalEntities.flatMap { entity in
            let lineEvidenceIds = entity.lines.compactMap(\.evidenceReferenceId)
            if let sourceEvidenceId = entity.sourceEvidenceId {
                return [sourceEvidenceId] + lineEvidenceIds
            }
            return lineEvidenceIds
        })

        let evidences = try modelContext.fetch(evidenceDescriptor(businessId: businessId, taxYear: taxYear))
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
        try modelContext.fetch(scopedDescriptor(businessId: businessId, taxYear: taxYear)).count
    }

    func sourceCount(businessId: UUID? = nil, taxYear: Int? = nil) throws -> Int {
        try modelContext.fetch(sourceDescriptor(businessId: businessId, taxYear: taxYear)).count
    }

    func validateIntegrity(businessId: UUID? = nil, taxYear: Int? = nil) throws {
        let entries = try scopedEntries(businessId: businessId, taxYear: taxYear)
        for entry in entries {
            _ = try decodeCounterpartyNames(from: entry)
            _ = try decodeRegistrationNumbers(from: entry)
            _ = try decodeProjectIds(from: entry)
            _ = try decodeFileHashes(from: entry)
        }
    }

    private func matches(_ entry: JournalSearchIndexEntity, criteria: JournalSearchCriteria) throws -> Bool {
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

        let counterparties = try decodeCounterpartyNames(from: entry)
        if let counterpartyText = SearchIndexNormalizer.normalizeOptionalText(criteria.counterpartyText),
           !counterparties.contains(where: { $0.contains(counterpartyText) }) {
            return false
        }

        let registrationNumbers = Set(try decodeRegistrationNumbers(from: entry))
        if let registrationNumber = SearchIndexNormalizer.normalizeIdentifier(criteria.registrationNumber),
           !registrationNumbers.contains(registrationNumber) {
            return false
        }

        let projectIds = Set(try decodeProjectIds(from: entry))
        if let projectId = criteria.projectId, !projectIds.contains(projectId) {
            return false
        }

        let fileHashes = Set(try decodeFileHashes(from: entry))
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

    private func scopedEntries(businessId: UUID? = nil, taxYear: Int? = nil) throws -> [JournalSearchIndexEntity] {
        try modelContext.fetch(scopedDescriptor(businessId: businessId, taxYear: taxYear))
    }

    private func searchDescriptor(criteria: JournalSearchCriteria) -> FetchDescriptor<JournalSearchIndexEntity> {
        let sortBy = [
            SortDescriptor(\JournalSearchIndexEntity.journalDate, order: .reverse),
            SortDescriptor(\JournalSearchIndexEntity.updatedAt, order: .reverse)
        ]
        let normalizedCounterparty = SearchIndexNormalizer.normalizeOptionalText(criteria.counterpartyText)
        let normalizedRegistrationNumber = SearchIndexNormalizer.normalizeIdentifier(criteria.registrationNumber)
        let normalizedFileHash = SearchIndexNormalizer.normalizeIdentifier(criteria.fileHash)
        let normalizedTextQuery = SearchIndexNormalizer.normalizeOptionalText(criteria.textQuery)

        guard criteria.dateRange == nil,
              criteria.amountRange == nil,
              criteria.projectId == nil
        else {
            return scopedDescriptor(
                businessId: criteria.businessId,
                taxYear: criteria.taxYear,
                sortBy: sortBy
            )
        }

        if let businessId = criteria.businessId,
           let normalizedCounterparty,
           !criteria.includeCancelled
        {
            return FetchDescriptor<JournalSearchIndexEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId
                        && !$0.isCancelledOriginal
                        && !$0.isReversal
                        && $0.searchText.contains(normalizedCounterparty)
                },
                sortBy: sortBy
            )
        }

        if let businessId = criteria.businessId,
           let normalizedRegistrationNumber,
           !criteria.includeCancelled
        {
            return FetchDescriptor<JournalSearchIndexEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId
                        && !$0.isCancelledOriginal
                        && !$0.isReversal
                        && $0.searchText.contains(normalizedRegistrationNumber)
                },
                sortBy: sortBy
            )
        }

        if let businessId = criteria.businessId,
           let normalizedFileHash,
           !criteria.includeCancelled
        {
            return FetchDescriptor<JournalSearchIndexEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId
                        && !$0.isCancelledOriginal
                        && !$0.isReversal
                        && $0.searchText.contains(normalizedFileHash)
                },
                sortBy: sortBy
            )
        }

        if let businessId = criteria.businessId,
           let normalizedTextQuery,
           !criteria.includeCancelled
        {
            return FetchDescriptor<JournalSearchIndexEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId
                        && !$0.isCancelledOriginal
                        && !$0.isReversal
                        && $0.searchText.contains(normalizedTextQuery)
                },
                sortBy: sortBy
            )
        }

        return scopedDescriptor(
            businessId: criteria.businessId,
            taxYear: criteria.taxYear,
            sortBy: sortBy
        )
    }

    private func scopedDescriptor(
        businessId: UUID? = nil,
        taxYear: Int? = nil,
        sortBy: [SortDescriptor<JournalSearchIndexEntity>] = []
    ) -> FetchDescriptor<JournalSearchIndexEntity> {
        switch (businessId, taxYear) {
        case let (.some(businessId), .some(taxYear)):
            return FetchDescriptor<JournalSearchIndexEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                },
                sortBy: sortBy
            )
        case let (.some(businessId), nil):
            return FetchDescriptor<JournalSearchIndexEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: sortBy
            )
        case let (nil, .some(taxYear)):
            return FetchDescriptor<JournalSearchIndexEntity>(
                predicate: #Predicate { $0.taxYear == taxYear },
                sortBy: sortBy
            )
        case (nil, nil):
            return FetchDescriptor<JournalSearchIndexEntity>(sortBy: sortBy)
        }
    }

    private func sourceDescriptor(
        businessId: UUID? = nil,
        taxYear: Int? = nil
    ) -> FetchDescriptor<JournalEntryEntity> {
        switch (businessId, taxYear) {
        case let (.some(businessId), .some(taxYear)):
            return FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                }
            )
        case let (.some(businessId), nil):
            return FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate { $0.businessId == businessId }
            )
        case let (nil, .some(taxYear)):
            return FetchDescriptor<JournalEntryEntity>(
                predicate: #Predicate { $0.taxYear == taxYear }
            )
        case (nil, nil):
            return FetchDescriptor<JournalEntryEntity>()
        }
    }

    private func evidenceDescriptor(
        businessId: UUID? = nil,
        taxYear: Int? = nil
    ) -> FetchDescriptor<EvidenceRecordEntity> {
        switch (businessId, taxYear) {
        case let (.some(businessId), .some(taxYear)):
            return FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                }
            )
        case let (.some(businessId), nil):
            return FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.businessId == businessId }
            )
        case let (nil, .some(taxYear)):
            return FetchDescriptor<EvidenceRecordEntity>(
                predicate: #Predicate { $0.taxYear == taxYear }
            )
        case (nil, nil):
            return FetchDescriptor<EvidenceRecordEntity>()
        }
    }

    private func decodeCounterpartyNames(from entry: JournalSearchIndexEntity) throws -> [String] {
        try decode([String].self, from: entry.counterpartyNamesJSON, recordId: entry.journalId, field: "counterpartyNamesJSON")
    }

    private func decodeRegistrationNumbers(from entry: JournalSearchIndexEntity) throws -> [String] {
        try decode([String].self, from: entry.registrationNumbersJSON, recordId: entry.journalId, field: "registrationNumbersJSON")
    }

    private func decodeProjectIds(from entry: JournalSearchIndexEntity) throws -> [UUID] {
        try decode([UUID].self, from: entry.projectIdsJSON, recordId: entry.journalId, field: "projectIdsJSON")
    }

    private func decodeFileHashes(from entry: JournalSearchIndexEntity) throws -> [String] {
        try decode([String].self, from: entry.fileHashesJSON, recordId: entry.journalId, field: "fileHashesJSON")
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from json: String?,
        recordId: UUID,
        field: String
    ) throws -> T {
        do {
            return try CanonicalJSONCoder.decodeStrict(type, from: json)
        } catch {
            throw CanonicalRepositoryError.searchIndexCorrupted(
                indexName: Self.indexName,
                recordId: recordId,
                field: field
            )
        }
    }
}
