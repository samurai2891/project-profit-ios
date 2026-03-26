import Foundation
import SwiftData

@MainActor
final class SwiftDataApprovalQueueRepository: ApprovalQueueRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func snapshot() throws -> ApprovalQueueSnapshot {
        let businessDescriptor = FetchDescriptor<BusinessProfileEntity>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let businessId = try modelContext.fetch(businessDescriptor).first?.businessId

        let projectDescriptor = FetchDescriptor<PPProject>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let projects = try modelContext.fetch(projectDescriptor)

        let canonicalAccounts: [CanonicalAccount]
        if let businessId {
            let accountDescriptor = FetchDescriptor<CanonicalAccountEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [
                    SortDescriptor(\.displayOrder),
                    SortDescriptor(\.code),
                ]
            )
            canonicalAccounts = try modelContext
                .fetch(accountDescriptor)
                .map(CanonicalAccountEntityMapper.toDomain)
        } else {
            canonicalAccounts = []
        }

        return ApprovalQueueSnapshot(
            businessId: businessId,
            projects: projects,
            canonicalAccounts: canonicalAccounts
        )
    }

    func yearLockState(businessId: UUID, taxYear: Int) throws -> YearLockState {
        let descriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate {
                $0.businessId == businessId && $0.taxYear == taxYear
            }
        )
        let rawValue = try modelContext.fetch(descriptor).first?.yearLockStateRaw
        return rawValue.flatMap(YearLockState.init(rawValue:)) ?? .open
    }

    func projectName(id: UUID) throws -> String? {
        let descriptor = FetchDescriptor<PPProject>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first?.name
    }
}
