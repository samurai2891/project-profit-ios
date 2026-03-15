import Foundation
import SwiftData

struct ProjectUpsertInput: Equatable, Sendable {
    let name: String
    let description: String
    let status: ProjectStatus
    let startDate: Date?
    let completedAt: Date?
    let plannedEndDate: Date?
}

@MainActor
struct ProjectWorkflowUseCase {
    private let workflowStore: ProjectWorkflowStore
    private let allocationReprocessor: ProjectAllocationReprocessor

    init(
        modelContext: ModelContext,
        projectRepository: (any ProjectRepository)? = nil,
        recurringRepository: (any RecurringRepository)? = nil,
        transactionHistoryRepository: (any TransactionHistoryRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        postingSupport: CanonicalPostingSupport? = nil,
        calendar: Calendar = .current
    ) {
        let projectRepository = projectRepository ?? SwiftDataProjectRepository(modelContext: modelContext)
        let recurringRepository = recurringRepository ?? SwiftDataRecurringRepository(modelContext: modelContext)
        let transactionHistoryRepository = transactionHistoryRepository ?? SwiftDataTransactionHistoryRepository(modelContext: modelContext)
        let transactionFormQueryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        let postingSupport = postingSupport ?? CanonicalPostingSupport(
            modelContext: modelContext,
            transactionFormQueryUseCase: transactionFormQueryUseCase
        )
        self.workflowStore = ProjectWorkflowStore(
            modelContext: modelContext,
            projectRepository: projectRepository,
            recurringRepository: recurringRepository,
            transactionHistoryRepository: transactionHistoryRepository,
            calendar: calendar
        )
        self.allocationReprocessor = ProjectAllocationReprocessor(
            modelContext: modelContext,
            projectRepository: projectRepository,
            recurringRepository: recurringRepository,
            transactionHistoryRepository: transactionHistoryRepository,
            transactionFormQueryUseCase: transactionFormQueryUseCase,
            postingSupport: postingSupport,
            calendar: calendar
        )
    }

    @discardableResult
    func createProject(input: ProjectUpsertInput) -> PPProject {
        let result = workflowStore.createProject(input: input)
        if result.didPersist {
            allocationReprocessor.reprocessEqualAllCurrentPeriodTransactions()
        }
        return result.project
    }

    func updateProject(id: UUID, input: ProjectUpsertInput) {
        let result = workflowStore.updateProject(id: id, input: input)
        guard result.didPersist else {
            return
        }

        if result.requiresProjectAllocationRecalculation {
            allocationReprocessor.recalculateAllocationsForProject(projectId: result.projectId)
        }
        if result.requiresReverseCompletionAllocations {
            allocationReprocessor.reverseCompletionAllocations(projectId: result.projectId)
        }
        if result.requiresFullPartialPeriodRecalculation {
            allocationReprocessor.recalculateAllPartialPeriodProjects()
        }
    }

    func deleteProject(id: UUID) {
        let result = workflowStore.deleteProject(id: id)
        if result.reprocessesCurrentEqualAllTransactions {
            allocationReprocessor.reprocessEqualAllCurrentPeriodTransactions()
        }
    }

    func deleteProjects(ids: Set<UUID>) {
        let result = workflowStore.deleteProjects(ids: ids)
        if result.reprocessesCurrentEqualAllTransactions {
            allocationReprocessor.reprocessEqualAllCurrentPeriodTransactions()
        }
    }
}
