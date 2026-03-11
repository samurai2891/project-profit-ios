import Foundation
import SwiftData

@MainActor
struct ApprovalQueueQueryUseCase {
    private let repository: any ApprovalQueueRepository
    private let startMonth: Int

    init(
        repository: any ApprovalQueueRepository,
        startMonth: Int = FiscalYearSettings.startMonth
    ) {
        self.repository = repository
        self.startMonth = startMonth
    }

    init(
        modelContext: ModelContext,
        startMonth: Int = FiscalYearSettings.startMonth
    ) {
        self.init(
            repository: SwiftDataApprovalQueueRepository(modelContext: modelContext),
            startMonth: startMonth
        )
    }

    func reloadKey(selectedFilterRawValue: String) -> String {
        [
            currentBusinessId()?.uuidString ?? "none",
            selectedFilterRawValue,
        ].joined(separator: ":")
    }

    func currentBusinessId() -> UUID? {
        try? repository.snapshot().businessId
    }

    func isYearLocked(date: Date) -> Bool {
        guard let businessId = currentBusinessId() else {
            return false
        }
        let taxYear = fiscalYear(for: date, startMonth: startMonth)
        let state = (try? repository.yearLockState(businessId: businessId, taxYear: taxYear)) ?? .open
        return !state.allowsNormalPosting
    }

    func canonicalAccounts() -> [CanonicalAccount] {
        (try? repository.snapshot().canonicalAccounts) ?? []
    }

    func availableProjects() -> [PPProject] {
        (try? repository.snapshot().projects) ?? []
    }

    func projectName(id: UUID?) -> String? {
        guard let id else { return nil }
        return try? repository.projectName(id: id)
    }
}
