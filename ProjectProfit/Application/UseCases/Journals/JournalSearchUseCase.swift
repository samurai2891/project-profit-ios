import Foundation
import SwiftData

@MainActor
struct JournalSearchUseCase {
    private let journalIndex: LocalJournalSearchIndex
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.journalIndex = LocalJournalSearchIndex(modelContext: modelContext)
    }

    func search(criteria: JournalSearchCriteria) async throws -> [UUID] {
        try autoRepairIfNeeded(criteria: criteria)
        return try journalIndex.search(criteria: criteria)
    }

    func rebuildIndex(businessId: UUID? = nil, taxYear: Int? = nil) async throws {
        try journalIndex.rebuild(businessId: businessId, taxYear: taxYear)
    }

    private func autoRepairIfNeeded(criteria: JournalSearchCriteria) throws {
        let sourceCount = try journalIndex.sourceCount(businessId: criteria.businessId, taxYear: criteria.taxYear)
        let indexCount = try journalIndex.indexCount(businessId: criteria.businessId, taxYear: criteria.taxYear)

        if sourceCount == 0, indexCount == 0 {
            return
        }

        let needsRepair = try indexCount != sourceCount || isIntegrityCorrupted(criteria: criteria)
        guard needsRepair else { return }

        do {
            try SearchIndexRebuilder(modelContext: modelContext)
                .rebuildJournalIndex(businessId: criteria.businessId, taxYear: criteria.taxYear)
        } catch {
            throw CanonicalRepositoryError.searchIndexRebuildFailed(
                indexName: LocalJournalSearchIndex.indexName,
                underlying: error
            )
        }

        try verifyRebuiltIndex(criteria: criteria)
    }

    private func isIntegrityCorrupted(criteria: JournalSearchCriteria) throws -> Bool {
        do {
            try journalIndex.validateIntegrity(businessId: criteria.businessId, taxYear: criteria.taxYear)
            return false
        } catch let error as CanonicalRepositoryError {
            switch error {
            case .searchIndexCorrupted:
                return true
            default:
                throw error
            }
        } catch {
            throw error
        }
    }

    private func verifyRebuiltIndex(criteria: JournalSearchCriteria) throws {
        let sourceCount = try journalIndex.sourceCount(businessId: criteria.businessId, taxYear: criteria.taxYear)
        let indexCount = try journalIndex.indexCount(businessId: criteria.businessId, taxYear: criteria.taxYear)

        guard sourceCount == indexCount else {
            throw CanonicalRepositoryError.searchIndexRebuildFailed(
                indexName: LocalJournalSearchIndex.indexName,
                underlying: SearchIndexRepairVerificationError.countMismatch(
                    indexCount: indexCount,
                    sourceCount: sourceCount
                )
            )
        }

        do {
            try journalIndex.validateIntegrity(businessId: criteria.businessId, taxYear: criteria.taxYear)
        } catch {
            throw CanonicalRepositoryError.searchIndexRebuildFailed(
                indexName: LocalJournalSearchIndex.indexName,
                underlying: error
            )
        }
    }
}
