import Foundation
import SwiftData

@MainActor
final class LocalEvidenceSearchIndex {
    static let indexName = "証憑検索インデックス"

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func search(criteria: EvidenceSearchCriteria) throws -> [UUID] {
        let descriptor = searchDescriptor(criteria: criteria)
        return try modelContext.fetch(descriptor)
            .filter { entry in
                try matches(entry, criteria: criteria)
            }
            .map(\.evidenceId)
    }

    func upsert(_ evidence: EvidenceDocument) throws {
        let descriptor = FetchDescriptor<EvidenceSearchIndexEntity>(
            predicate: #Predicate { $0.evidenceId == evidence.id }
        )
        let existing = try modelContext.fetch(descriptor).first
        let entity = existing ?? EvidenceSearchIndexEntity(evidenceId: evidence.id)
        populate(entity, from: evidence)
        if existing == nil {
            modelContext.insert(entity)
        }
        try modelContext.save()
    }

    func remove(evidenceId: UUID) throws {
        let descriptor = FetchDescriptor<EvidenceSearchIndexEntity>(
            predicate: #Predicate { $0.evidenceId == evidenceId }
        )
        try modelContext.fetch(descriptor).forEach(modelContext.delete)
        try modelContext.save()
    }

    func rebuild(businessId: UUID? = nil, taxYear: Int? = nil) throws {
        let existing = try modelContext.fetch(scopedDescriptor(businessId: businessId, taxYear: taxYear))
        existing.forEach(modelContext.delete)

        let records = try modelContext.fetch(sourceDescriptor(businessId: businessId, taxYear: taxYear))
        for record in records {
            let evidence = EvidenceRecordEntityMapper.toDomain(record)
            let entity = EvidenceSearchIndexEntity(evidenceId: evidence.id)
            populate(entity, from: evidence)
            modelContext.insert(entity)
        }

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
            _ = try decodeProjectIds(from: entry)
        }
    }

    private func matches(_ entry: EvidenceSearchIndexEntity, criteria: EvidenceSearchCriteria) throws -> Bool {
        if let businessId = criteria.businessId, entry.businessId != businessId {
            return false
        }
        if let taxYear = criteria.taxYear, entry.taxYear != taxYear {
            return false
        }
        if let dateRange = criteria.dateRange {
            let date = entry.issueDate ?? entry.receivedAt
            if !dateRange.contains(date) {
                return false
            }
        }
        if let amountRange = criteria.amountRange {
            guard let totalAmount = entry.totalAmount, amountRange.contains(totalAmount) else {
                return false
            }
        }
        if let legalDocumentTypes = criteria.legalDocumentTypes, !legalDocumentTypes.contains(where: { $0.rawValue == entry.legalDocumentTypeRaw }) {
            return false
        }
        if let complianceStatus = criteria.complianceStatus, complianceStatus.rawValue != entry.complianceStatusRaw {
            return false
        }
        if !criteria.includeDeleted, entry.deletedAt != nil {
            return false
        }
        if let counterpartyText = SearchIndexNormalizer.normalizeOptionalText(criteria.counterpartyText),
           !entry.counterpartyNameNormalized.contains(counterpartyText) {
            return false
        }
        if let registrationNumber = SearchIndexNormalizer.normalizeIdentifier(criteria.registrationNumber),
           entry.registrationNumberNormalized != registrationNumber {
            return false
        }
        if let projectId = criteria.projectId {
            let projectIds = Set(try decodeProjectIds(from: entry))
            if !projectIds.contains(projectId) {
                return false
            }
        }
        if let fileHash = SearchIndexNormalizer.normalizeIdentifier(criteria.fileHash),
           entry.fileHashNormalized != fileHash {
            return false
        }
        if let textQuery = SearchIndexNormalizer.normalizeOptionalText(criteria.textQuery),
           !entry.searchText.contains(textQuery) {
            return false
        }
        return true
    }

    private func populate(_ entity: EvidenceSearchIndexEntity, from evidence: EvidenceDocument) {
        let searchParts: [String?] = [
            evidence.originalFilename,
            evidence.ocrText,
            evidence.structuredFields?.counterpartyName,
            evidence.structuredFields?.registrationNumber,
            evidence.structuredFields?.invoiceNumber,
            evidence.fileHash,
            evidence.searchTokens.joined(separator: " ")
        ]
        entity.businessId = evidence.businessId
        entity.taxYear = evidence.taxYear
        entity.issueDate = evidence.issueDate ?? evidence.structuredFields?.transactionDate
        entity.receivedAt = evidence.receivedAt
        entity.totalAmount = evidence.structuredFields?.totalAmount
        entity.counterpartyNameNormalized = SearchIndexNormalizer.normalizeText(evidence.structuredFields?.counterpartyName)
        entity.registrationNumberNormalized = SearchIndexNormalizer.normalizeIdentifier(evidence.structuredFields?.registrationNumber)
        entity.projectIdsJSON = CanonicalJSONCoder.encode(evidence.linkedProjectIds, fallback: "[]")
        entity.fileHashNormalized = SearchIndexNormalizer.normalizeIdentifier(evidence.fileHash) ?? ""
        entity.legalDocumentTypeRaw = evidence.legalDocumentType.rawValue
        entity.complianceStatusRaw = evidence.complianceStatus.rawValue
        entity.deletedAt = evidence.deletedAt
        entity.searchText = SearchIndexNormalizer.normalizeText(searchParts.compactMap { $0 }.joined(separator: " "))
        entity.updatedAt = evidence.updatedAt
    }

    private func scopedEntries(businessId: UUID? = nil, taxYear: Int? = nil) throws -> [EvidenceSearchIndexEntity] {
        try modelContext.fetch(scopedDescriptor(businessId: businessId, taxYear: taxYear))
    }

    private func searchDescriptor(criteria: EvidenceSearchCriteria) -> FetchDescriptor<EvidenceSearchIndexEntity> {
        let sortBy = [SortDescriptor(\EvidenceSearchIndexEntity.updatedAt, order: .reverse)]
        let normalizedCounterparty = SearchIndexNormalizer.normalizeOptionalText(criteria.counterpartyText)
        let normalizedRegistrationNumber = SearchIndexNormalizer.normalizeIdentifier(criteria.registrationNumber)
        let normalizedFileHash = SearchIndexNormalizer.normalizeIdentifier(criteria.fileHash)
        let normalizedTextQuery = SearchIndexNormalizer.normalizeOptionalText(criteria.textQuery)

        guard criteria.dateRange == nil,
              criteria.amountRange == nil,
              criteria.legalDocumentTypes == nil,
              criteria.complianceStatus == nil,
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
           !criteria.includeDeleted
        {
            return FetchDescriptor<EvidenceSearchIndexEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId
                        && $0.deletedAt == nil
                        && $0.counterpartyNameNormalized.contains(normalizedCounterparty)
                },
                sortBy: sortBy
            )
        }

        if let businessId = criteria.businessId,
           let normalizedRegistrationNumber,
           !criteria.includeDeleted
        {
            return FetchDescriptor<EvidenceSearchIndexEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId
                        && $0.deletedAt == nil
                        && $0.registrationNumberNormalized == normalizedRegistrationNumber
                },
                sortBy: sortBy
            )
        }

        if let businessId = criteria.businessId,
           let normalizedFileHash,
           !criteria.includeDeleted
        {
            return FetchDescriptor<EvidenceSearchIndexEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId
                        && $0.deletedAt == nil
                        && $0.fileHashNormalized == normalizedFileHash
                },
                sortBy: sortBy
            )
        }

        if let businessId = criteria.businessId,
           let normalizedTextQuery,
           !criteria.includeDeleted
        {
            return FetchDescriptor<EvidenceSearchIndexEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId
                        && $0.deletedAt == nil
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
        sortBy: [SortDescriptor<EvidenceSearchIndexEntity>] = []
    ) -> FetchDescriptor<EvidenceSearchIndexEntity> {
        switch (businessId, taxYear) {
        case let (.some(businessId), .some(taxYear)):
            return FetchDescriptor<EvidenceSearchIndexEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == taxYear
                },
                sortBy: sortBy
            )
        case let (.some(businessId), nil):
            return FetchDescriptor<EvidenceSearchIndexEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: sortBy
            )
        case let (nil, .some(taxYear)):
            return FetchDescriptor<EvidenceSearchIndexEntity>(
                predicate: #Predicate { $0.taxYear == taxYear },
                sortBy: sortBy
            )
        case (nil, nil):
            return FetchDescriptor<EvidenceSearchIndexEntity>(sortBy: sortBy)
        }
    }

    private func sourceDescriptor(
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

    private func decodeProjectIds(from entry: EvidenceSearchIndexEntity) throws -> [UUID] {
        do {
            return try CanonicalJSONCoder.decodeStrict([UUID].self, from: entry.projectIdsJSON)
        } catch {
            throw CanonicalRepositoryError.searchIndexCorrupted(
                indexName: Self.indexName,
                recordId: entry.evidenceId,
                field: "projectIdsJSON"
            )
        }
    }
}
