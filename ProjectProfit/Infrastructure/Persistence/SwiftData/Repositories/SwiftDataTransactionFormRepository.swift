import Foundation
import SwiftData

@MainActor
final class SwiftDataTransactionFormRepository: TransactionFormRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func snapshot() throws -> TransactionFormSnapshot {
        let businessDescriptor = FetchDescriptor<BusinessProfileEntity>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let businessProfile = try modelContext
            .fetch(businessDescriptor)
            .first
            .map(BusinessProfileEntityMapper.toDomain)

        let accountDescriptor = FetchDescriptor<PPAccount>(
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        let categoryDescriptor = FetchDescriptor<PPCategory>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.name)]
        )
        let projectDescriptor = FetchDescriptor<PPProject>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        let accounts = try modelContext.fetch(accountDescriptor)
        let activeCategories = try modelContext.fetch(categoryDescriptor)
        let projects = try modelContext.fetch(projectDescriptor)

        let counterparties: [Counterparty]
        if let businessId = businessProfile?.id {
            let descriptor = FetchDescriptor<CounterpartyEntity>(
                predicate: #Predicate { $0.businessId == businessId },
                sortBy: [SortDescriptor(\.displayName)]
            )
            counterparties = try modelContext
                .fetch(descriptor)
                .map(CounterpartyEntityMapper.toDomain)
        } else {
            counterparties = []
        }

        return TransactionFormSnapshot(
            businessId: businessProfile?.id,
            accounts: accounts,
            activeCategories: activeCategories,
            projects: projects,
            counterparties: counterparties,
            defaultPaymentAccountId: businessProfile?.defaultPaymentAccountId,
            isLegacyTransactionEditingEnabled: !FeatureFlags.useCanonicalPosting,
            legacyTransactionMutationDisabledMessage: AppError.legacyTransactionMutationDisabled.errorDescription
                ?? "この操作は現在利用できません"
        )
    }

    func legacyAccountId(for canonicalAccountId: UUID) throws -> String? {
        let descriptor = FetchDescriptor<CanonicalAccountEntity>(
            predicate: #Predicate { $0.accountId == canonicalAccountId }
        )
        return try modelContext.fetch(descriptor).first?.legacyAccountId
    }
}
