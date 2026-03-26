import Foundation
import SwiftData

struct RecurringFormSnapshot {
    let businessId: UUID?
    let accounts: [PPAccount]
    let activeCategories: [PPCategory]
    let projects: [PPProject]
    let counterparties: [Counterparty]
    let defaultPaymentAccountId: String?
    fileprivate let transactionFormSnapshot: TransactionFormSnapshot

    private init(
        businessId: UUID?,
        accounts: [PPAccount],
        activeCategories: [PPCategory],
        projects: [PPProject],
        counterparties: [Counterparty],
        defaultPaymentAccountId: String?,
        transactionFormSnapshot: TransactionFormSnapshot
    ) {
        self.businessId = businessId
        self.accounts = accounts
        self.activeCategories = activeCategories
        self.projects = projects
        self.counterparties = counterparties
        self.defaultPaymentAccountId = defaultPaymentAccountId
        self.transactionFormSnapshot = transactionFormSnapshot
    }

    static let empty = RecurringFormSnapshot(
        businessId: nil,
        accounts: [],
        activeCategories: [],
        projects: [],
        counterparties: [],
        defaultPaymentAccountId: nil,
        transactionFormSnapshot: .empty
    )

    init(transactionFormSnapshot: TransactionFormSnapshot) {
        self.businessId = transactionFormSnapshot.businessId
        self.accounts = transactionFormSnapshot.accounts
        self.activeCategories = transactionFormSnapshot.activeCategories
        self.projects = transactionFormSnapshot.projects
        self.counterparties = transactionFormSnapshot.counterparties
        self.defaultPaymentAccountId = transactionFormSnapshot.defaultPaymentAccountId
        self.transactionFormSnapshot = transactionFormSnapshot
    }
}

struct RecurringDistributionTemplates {
    let supportedRules: [DistributionRule]
    let unsupportedCount: Int
}

@MainActor
struct RecurringQueryUseCase {
    private let recurringRepository: any RecurringRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let distributionTemplateUseCase: DistributionTemplateUseCase
    private let templateApplicationUseCase: DistributionTemplateApplicationUseCase

    init(
        modelContext: ModelContext,
        recurringRepository: (any RecurringRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        distributionTemplateUseCase: DistributionTemplateUseCase? = nil,
        templateApplicationUseCase: DistributionTemplateApplicationUseCase = .init()
    ) {
        self.recurringRepository = recurringRepository ?? SwiftDataRecurringRepository(modelContext: modelContext)
        self.transactionFormQueryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        self.distributionTemplateUseCase = distributionTemplateUseCase ?? DistributionTemplateUseCase(modelContext: modelContext)
        self.templateApplicationUseCase = templateApplicationUseCase
    }

    func formSnapshot() -> RecurringFormSnapshot {
        RecurringFormSnapshot(
            transactionFormSnapshot: (try? transactionFormQueryUseCase.snapshot()) ?? .empty
        )
    }

    func paymentAccounts(snapshot: RecurringFormSnapshot) -> [PPAccount] {
        transactionFormQueryUseCase.paymentAccounts(snapshot: snapshot.transactionFormSnapshot)
    }

    func categories(
        for type: TransactionType,
        snapshot: RecurringFormSnapshot
    ) -> [PPCategory] {
        transactionFormQueryUseCase.categories(for: type, snapshot: snapshot.transactionFormSnapshot)
    }

    func activeProjects(snapshot: RecurringFormSnapshot) -> [PPProject] {
        transactionFormQueryUseCase.activeProjects(snapshot: snapshot.transactionFormSnapshot)
    }

    func projectName(id: UUID, snapshot: RecurringFormSnapshot) -> String? {
        transactionFormQueryUseCase.projectName(id: id, snapshot: snapshot.transactionFormSnapshot)
    }

    func counterparty(id: UUID, snapshot: RecurringFormSnapshot) -> Counterparty? {
        transactionFormQueryUseCase.counterparty(id: id, snapshot: snapshot.transactionFormSnapshot)
    }

    func counterpartyDefaults(
        for counterpartyId: UUID,
        type: TransactionType,
        snapshot: RecurringFormSnapshot
    ) -> TransactionFormCounterpartyDefaults? {
        transactionFormQueryUseCase.counterpartyDefaults(
            for: counterpartyId,
            type: type,
            snapshot: snapshot.transactionFormSnapshot
        )
    }

    func activeDistributionTemplates(
        businessId: UUID,
        at date: Date,
        allocationPeriod: DistributionTemplateApplicationUseCase.AllocationPeriod
    ) async throws -> RecurringDistributionTemplates {
        let activeRules = try await distributionTemplateUseCase.activeRules(
            businessId: businessId,
            at: date
        )
        let supportedRules = activeRules
            .filter {
                templateApplicationUseCase.isSupported($0, allocationPeriod: allocationPeriod)
                    || templateApplicationUseCase.shouldUseDynamicEqualAll(for: $0)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        return RecurringDistributionTemplates(
            supportedRules: supportedRules,
            unsupportedCount: activeRules.count - supportedRules.count
        )
    }

    func previewDistribution(
        rule: DistributionRule,
        snapshot: RecurringFormSnapshot,
        referenceDate: Date,
        totalAmount: Int,
        allocationPeriod: DistributionTemplateApplicationUseCase.AllocationPeriod
    ) -> DistributionApplicationPreview {
        templateApplicationUseCase.previewAllocations(
            rule: rule,
            projects: snapshot.projects,
            referenceDate: referenceDate,
            totalAmount: totalAmount,
            allocationPeriod: allocationPeriod
        )
    }

    func listSnapshot() -> RecurringListSnapshot {
        (try? recurringRepository.listSnapshot()) ?? .empty
    }

    func historyEntries(recurringId: UUID) -> [RecurringHistoryEntry] {
        (try? recurringRepository.historyEntries(recurringId: recurringId)) ?? []
    }
}
