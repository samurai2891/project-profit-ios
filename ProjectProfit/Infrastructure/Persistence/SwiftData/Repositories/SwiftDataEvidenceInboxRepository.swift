import Foundation
import SwiftData

@MainActor
final class SwiftDataEvidenceInboxRepository: EvidenceInboxRepository {
    private let modelContext: ModelContext
    private let currentDateProvider: () -> Date

    init(
        modelContext: ModelContext,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.currentDateProvider = currentDateProvider
    }

    func snapshot(startMonth: Int) throws -> EvidenceInboxSnapshot {
        let projects = try modelContext.fetch(
            FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        )
        let businessId = try currentBusinessId()
        let currentYear = fiscalYear(for: currentDateProvider(), startMonth: startMonth)

        let isCurrentYearLocked: Bool
        if let businessId {
            let descriptor = FetchDescriptor<TaxYearProfileEntity>(
                predicate: #Predicate {
                    $0.businessId == businessId && $0.taxYear == currentYear
                }
            )
            let rawState = try modelContext.fetch(descriptor).first?.yearLockStateRaw
            let state = rawState.flatMap(YearLockState.init(rawValue:)) ?? .open
            isCurrentYearLocked = !state.allowsNormalPosting
        } else {
            isCurrentYearLocked = false
        }

        return EvidenceInboxSnapshot(
            businessId: businessId,
            isCurrentYearLocked: isCurrentYearLocked,
            projects: projects
        )
    }

    func projectNames(ids: [UUID]) throws -> [String] {
        guard !ids.isEmpty else { return [] }

        let projects = try modelContext.fetch(FetchDescriptor<PPProject>())
        let namesById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        return ids.compactMap { namesById[$0] }
    }

    private func currentBusinessId() throws -> UUID? {
        let descriptor = FetchDescriptor<BusinessProfileEntity>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor).first?.businessId
    }
}
