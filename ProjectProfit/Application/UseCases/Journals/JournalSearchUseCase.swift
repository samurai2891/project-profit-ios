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
        let indexCount = try journalIndex.indexCount(businessId: criteria.businessId, taxYear: criteria.taxYear)
        guard indexCount == 0 else { return }
        let sourceCount = try journalIndex.sourceCount(businessId: criteria.businessId, taxYear: criteria.taxYear)
        guard sourceCount > 0 else { return }
        try SearchIndexRebuilder(modelContext: modelContext)
            .rebuildJournalIndex(businessId: criteria.businessId, taxYear: criteria.taxYear)
    }
}
