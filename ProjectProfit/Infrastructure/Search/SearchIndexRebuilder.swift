import Foundation
import SwiftData

@MainActor
struct SearchIndexRebuilder {
    private let evidenceIndex: LocalEvidenceSearchIndex
    private let journalIndex: LocalJournalSearchIndex

    init(modelContext: ModelContext) {
        self.evidenceIndex = LocalEvidenceSearchIndex(modelContext: modelContext)
        self.journalIndex = LocalJournalSearchIndex(modelContext: modelContext)
    }

    func rebuildEvidenceIndex(businessId: UUID? = nil, taxYear: Int? = nil) throws {
        try evidenceIndex.rebuild(businessId: businessId, taxYear: taxYear)
    }

    func rebuildJournalIndex(businessId: UUID? = nil, taxYear: Int? = nil) throws {
        try journalIndex.rebuild(businessId: businessId, taxYear: taxYear)
    }

    func rebuildAll(businessId: UUID? = nil, taxYear: Int? = nil) throws {
        try rebuildEvidenceIndex(businessId: businessId, taxYear: taxYear)
        try rebuildJournalIndex(businessId: businessId, taxYear: taxYear)
    }
}
