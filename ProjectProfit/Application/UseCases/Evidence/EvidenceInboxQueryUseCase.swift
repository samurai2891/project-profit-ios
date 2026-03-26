import Foundation
import SwiftData

@MainActor
struct EvidenceInboxQueryUseCase {
    private let repository: any EvidenceInboxRepository
    private let evidenceCatalogUseCase: EvidenceCatalogUseCase
    private let postingWorkflowUseCase: PostingWorkflowUseCase
    private let searchIndexRebuilder: SearchIndexRebuilder
    private let startMonth: Int

    init(
        repository: any EvidenceInboxRepository,
        evidenceCatalogUseCase: EvidenceCatalogUseCase,
        postingWorkflowUseCase: PostingWorkflowUseCase,
        searchIndexRebuilder: SearchIndexRebuilder,
        startMonth: Int = FiscalYearSettings.startMonth
    ) {
        self.repository = repository
        self.evidenceCatalogUseCase = evidenceCatalogUseCase
        self.postingWorkflowUseCase = postingWorkflowUseCase
        self.searchIndexRebuilder = searchIndexRebuilder
        self.startMonth = startMonth
    }

    init(
        modelContext: ModelContext,
        currentDateProvider: @escaping () -> Date = Date.init,
        startMonth: Int = FiscalYearSettings.startMonth
    ) {
        self.init(
            repository: SwiftDataEvidenceInboxRepository(
                modelContext: modelContext,
                currentDateProvider: currentDateProvider
            ),
            evidenceCatalogUseCase: EvidenceCatalogUseCase(modelContext: modelContext),
            postingWorkflowUseCase: PostingWorkflowUseCase(modelContext: modelContext),
            searchIndexRebuilder: SearchIndexRebuilder(modelContext: modelContext),
            startMonth: startMonth
        )
    }

    func reloadKey(
        selectedStatus: ComplianceStatus?,
        searchReloadToken: String
    ) -> String {
        let businessId = (try? repository.snapshot(startMonth: startMonth).businessId)?.uuidString ?? "none"
        return [
            businessId,
            selectedStatus?.rawValue ?? "all",
            searchReloadToken,
        ].joined(separator: ":")
    }

    func isCurrentYearLocked() -> Bool {
        (try? repository.snapshot(startMonth: startMonth).isCurrentYearLocked) ?? false
    }

    func availableProjects() -> [PPProject] {
        (try? repository.snapshot(startMonth: startMonth).projects) ?? []
    }

    func projectNames(ids: [UUID]) -> [String] {
        (try? repository.projectNames(ids: ids)) ?? []
    }

    func searchEvidence(
        form: EvidenceSearchFormState,
        selectedStatus: ComplianceStatus?
    ) async throws -> [EvidenceDocument] {
        guard let businessId = try repository.snapshot(startMonth: startMonth).businessId else {
            return []
        }
        return try await evidenceCatalogUseCase.search(
            form.makeCriteria(
                businessId: businessId,
                complianceStatus: selectedStatus
            )
        )
    }

    func rebuildEvidenceIndex() async throws {
        guard let businessId = try repository.snapshot(startMonth: startMonth).businessId else {
            return
        }
        try searchIndexRebuilder.rebuildEvidenceIndex(businessId: businessId)
    }

    func candidates(evidenceId: UUID) async throws -> [PostingCandidate] {
        try await postingWorkflowUseCase.candidates(evidenceId: evidenceId)
    }

    func journals(evidenceId: UUID) async throws -> [CanonicalJournalEntry] {
        try await postingWorkflowUseCase.journals(evidenceId: evidenceId)
    }
}
