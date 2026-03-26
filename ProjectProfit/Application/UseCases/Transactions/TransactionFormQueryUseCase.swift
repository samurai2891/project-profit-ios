import Foundation
import SwiftData

struct TransactionFormDistributionTemplates {
    let supportedRules: [DistributionRule]
    let unsupportedCount: Int
}

struct TransactionFormCounterpartyDefaults {
    let displayName: String
    let taxCode: TaxCode?
    let paymentAccountId: String?
    let projectId: UUID?
}

extension TransactionFormSnapshot {
    static let empty = TransactionFormSnapshot(
        businessId: nil,
        accounts: [],
        activeCategories: [],
        projects: [],
        counterparties: [],
        defaultPaymentAccountId: nil,
        isLegacyTransactionEditingEnabled: !FeatureFlags.useCanonicalPosting,
        legacyTransactionMutationDisabledMessage: AppError.legacyTransactionMutationDisabled.errorDescription
            ?? "この操作は現在利用できません"
    )
}

@MainActor
struct TransactionFormQueryUseCase {
    private let repository: any TransactionFormRepository
    private let distributionTemplateUseCase: DistributionTemplateUseCase
    private let templateApplicationUseCase: DistributionTemplateApplicationUseCase

    init(
        repository: any TransactionFormRepository,
        distributionTemplateUseCase: DistributionTemplateUseCase,
        templateApplicationUseCase: DistributionTemplateApplicationUseCase = .init()
    ) {
        self.repository = repository
        self.distributionTemplateUseCase = distributionTemplateUseCase
        self.templateApplicationUseCase = templateApplicationUseCase
    }

    init(modelContext: ModelContext) {
        self.init(
            repository: SwiftDataTransactionFormRepository(modelContext: modelContext),
            distributionTemplateUseCase: DistributionTemplateUseCase(modelContext: modelContext)
        )
    }

    func snapshot() throws -> TransactionFormSnapshot {
        try repository.snapshot()
    }

    func paymentAccounts(snapshot: TransactionFormSnapshot) -> [PPAccount] {
        snapshot.accounts.filter { $0.isPaymentAccount && $0.isActive }
    }

    func categories(
        for type: TransactionType,
        snapshot: TransactionFormSnapshot
    ) -> [PPCategory] {
        let categoryType: CategoryType = switch type {
        case .income:
            .income
        case .expense, .transfer:
            .expense
        }
        return snapshot.activeCategories.filter { $0.type == categoryType }
    }

    func activeProjects(snapshot: TransactionFormSnapshot) -> [PPProject] {
        snapshot.projects.filter { $0.isArchived != true }
    }

    func projectName(id: UUID, snapshot: TransactionFormSnapshot) -> String? {
        snapshot.projects.first { $0.id == id }?.name
    }

    func counterparty(id: UUID, snapshot: TransactionFormSnapshot) -> Counterparty? {
        snapshot.counterparties.first { $0.id == id }
    }

    func counterpartyDefaults(
        for counterpartyId: UUID,
        type: TransactionType,
        snapshot: TransactionFormSnapshot
    ) -> TransactionFormCounterpartyDefaults? {
        guard let counterparty = counterparty(id: counterpartyId, snapshot: snapshot) else {
            return nil
        }

        let paymentAccountId = counterparty.defaultAccountId.flatMap { canonicalAccountId in
            try? repository.legacyAccountId(for: canonicalAccountId)
        }

        let projectId: UUID?
        if type == .transfer {
            projectId = nil
        } else if let defaultProjectId = counterparty.defaultProjectId,
                  activeProjects(snapshot: snapshot).contains(where: { $0.id == defaultProjectId }) {
            projectId = defaultProjectId
        } else {
            projectId = nil
        }

        return TransactionFormCounterpartyDefaults(
            displayName: counterparty.displayName,
            taxCode: counterparty.defaultTaxCodeId.flatMap(TaxCode.resolve(id:)),
            paymentAccountId: paymentAccountId,
            projectId: projectId
        )
    }

    func activeDistributionTemplates(
        businessId: UUID,
        at date: Date
    ) async throws -> TransactionFormDistributionTemplates {
        let activeRules = try await distributionTemplateUseCase.activeRules(
            businessId: businessId,
            at: date
        )
        let supportedRules = activeRules
            .filter { templateApplicationUseCase.isSupported($0, allocationPeriod: .month) }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        return TransactionFormDistributionTemplates(
            supportedRules: supportedRules,
            unsupportedCount: activeRules.count - supportedRules.count
        )
    }

    func previewDistribution(
        rule: DistributionRule,
        snapshot: TransactionFormSnapshot,
        referenceDate: Date,
        totalAmount: Int
    ) -> DistributionApplicationPreview {
        templateApplicationUseCase.previewAllocations(
            rule: rule,
            projects: snapshot.projects,
            referenceDate: referenceDate,
            totalAmount: totalAmount,
            allocationPeriod: .month
        )
    }
}
