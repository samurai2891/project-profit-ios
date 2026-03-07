import Foundation
import SwiftData

@MainActor
final class LocalEvidenceSearchIndex {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func search(criteria: EvidenceSearchCriteria) throws -> [UUID] {
        let descriptor = FetchDescriptor<EvidenceSearchIndexEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
            .filter { entry in
                matches(entry, criteria: criteria)
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
        let existingDescriptor = FetchDescriptor<EvidenceSearchIndexEntity>()
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

        let sourceDescriptor = FetchDescriptor<EvidenceRecordEntity>()
        let records = try modelContext.fetch(sourceDescriptor).filter { record in
            if let businessId, record.businessId != businessId {
                return false
            }
            if let taxYear, record.taxYear != taxYear {
                return false
            }
            return true
        }
        for record in records {
            let evidence = EvidenceRecordEntityMapper.toDomain(record)
            let entity = EvidenceSearchIndexEntity(evidenceId: evidence.id)
            populate(entity, from: evidence)
            modelContext.insert(entity)
        }

        try modelContext.save()
    }

    func indexCount(businessId: UUID? = nil, taxYear: Int? = nil) throws -> Int {
        let descriptor = FetchDescriptor<EvidenceSearchIndexEntity>()
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
        let descriptor = FetchDescriptor<EvidenceRecordEntity>()
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

    private func matches(_ entry: EvidenceSearchIndexEntity, criteria: EvidenceSearchCriteria) -> Bool {
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
            let projectIds = Set(CanonicalJSONCoder.decode([UUID].self, from: entry.projectIdsJSON, fallback: []))
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
}
