import Foundation
import SwiftData

struct ProjectWorkflowCreateResult {
    let project: PPProject
    let didPersist: Bool
}

struct ProjectWorkflowUpdateResult {
    let didPersist: Bool
    let projectId: UUID
    let requiresProjectAllocationRecalculation: Bool
    let requiresReverseCompletionAllocations: Bool
    let requiresFullPartialPeriodRecalculation: Bool
}

struct ProjectWorkflowDeleteResult {
    let didPersist: Bool
    let affectedProjectIds: Set<UUID>
    let reprocessesCurrentEqualAllTransactions: Bool
}

@MainActor
struct ProjectWorkflowStore {
    private let modelContext: ModelContext
    private let projectRepository: any ProjectRepository
    private let recurringRepository: any RecurringRepository
    private let transactionHistoryRepository: any TransactionHistoryRepository
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        projectRepository: any ProjectRepository,
        recurringRepository: (any RecurringRepository)? = nil,
        transactionHistoryRepository: (any TransactionHistoryRepository)? = nil,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.projectRepository = projectRepository
        self.recurringRepository = recurringRepository ?? SwiftDataRecurringRepository(modelContext: modelContext)
        self.transactionHistoryRepository = transactionHistoryRepository ?? SwiftDataTransactionHistoryRepository(modelContext: modelContext)
        self.calendar = calendar
    }

    @discardableResult
    func createProject(input: ProjectUpsertInput) -> ProjectWorkflowCreateResult {
        let project = PPProject(
            name: input.name,
            projectDescription: input.description,
            status: input.status,
            startDate: input.startDate,
            completedAt: normalizedCompletedAt(
                startDate: input.startDate,
                completedAt: input.completedAt,
                status: input.status
            ),
            plannedEndDate: normalizedPlannedEndDate(
                startDate: input.startDate,
                plannedEndDate: input.plannedEndDate
            )
        )
        projectRepository.insert(project)

        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            return ProjectWorkflowCreateResult(project: project, didPersist: true)
        } catch {
            modelContext.rollback()
            return ProjectWorkflowCreateResult(project: project, didPersist: false)
        }
    }

    func updateProject(id: UUID, input: ProjectUpsertInput) -> ProjectWorkflowUpdateResult {
        let project: PPProject
        do {
            guard let fetched = try projectRepository.project(id: id) else {
                return ProjectWorkflowUpdateResult(
                    didPersist: false,
                    projectId: id,
                    requiresProjectAllocationRecalculation: false,
                    requiresReverseCompletionAllocations: false,
                    requiresFullPartialPeriodRecalculation: false
                )
            }
            project = fetched
        } catch {
            return ProjectWorkflowUpdateResult(
                didPersist: false,
                projectId: id,
                requiresProjectAllocationRecalculation: false,
                requiresReverseCompletionAllocations: false,
                requiresFullPartialPeriodRecalculation: false
            )
        }

        let previousStatus = project.status
        let previousCompletedAt = project.completedAt
        let previousStartDate = project.startDate
        let previousPlannedEndDate = project.plannedEndDate

        project.name = input.name
        project.projectDescription = input.description
        project.status = input.status
        project.startDate = input.startDate
        project.completedAt = normalizedCompletedAt(
            startDate: input.startDate,
            completedAt: input.completedAt,
            status: input.status
        )
        project.plannedEndDate = normalizedPlannedEndDate(
            startDate: input.startDate,
            plannedEndDate: input.plannedEndDate
        )
        project.updatedAt = Date()

        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
        } catch {
            modelContext.rollback()
            return ProjectWorkflowUpdateResult(
                didPersist: false,
                projectId: id,
                requiresProjectAllocationRecalculation: false,
                requiresReverseCompletionAllocations: false,
                requiresFullPartialPeriodRecalculation: false
            )
        }

        let completedAtChanged = project.completedAt != previousCompletedAt
        let startDateChanged = project.startDate != previousStartDate
        let plannedEndDateChanged = project.plannedEndDate != previousPlannedEndDate
        let statusChangedAwayFromCompleted = previousStatus == .completed && project.status != .completed
        let requiresDateDrivenRecalculation = completedAtChanged || startDateChanged || plannedEndDateChanged

        return ProjectWorkflowUpdateResult(
            didPersist: true,
            projectId: id,
            requiresProjectAllocationRecalculation: requiresDateDrivenRecalculation
                && (project.startDate != nil || project.effectiveEndDate != nil),
            requiresReverseCompletionAllocations: requiresDateDrivenRecalculation
                && !(project.startDate != nil || project.effectiveEndDate != nil)
                && (statusChangedAwayFromCompleted
                    || previousStartDate != nil
                    || previousCompletedAt != nil
                    || previousPlannedEndDate != nil),
            requiresFullPartialPeriodRecalculation: requiresDateDrivenRecalculation
                && !(project.startDate != nil || project.effectiveEndDate != nil)
                && (statusChangedAwayFromCompleted
                    || previousStartDate != nil
                    || previousCompletedAt != nil
                    || previousPlannedEndDate != nil)
        )
    }

    func deleteProject(id: UUID) -> ProjectWorkflowDeleteResult {
        guard (try? projectRepository.project(id: id)) != nil else {
            return ProjectWorkflowDeleteResult(
                didPersist: false,
                affectedProjectIds: [],
                reprocessesCurrentEqualAllTransactions: false
            )
        }

        if projectHasHistoricalReferences(id) {
            return archiveProjects(ids: [id])
        } else {
            return hardDeleteProjects(ids: [id])
        }
    }

    func deleteProjects(ids: Set<UUID>) -> ProjectWorkflowDeleteResult {
        guard !ids.isEmpty else {
            return ProjectWorkflowDeleteResult(
                didPersist: false,
                affectedProjectIds: [],
                reprocessesCurrentEqualAllTransactions: false
            )
        }

        var idsToArchive = Set<UUID>()
        var idsToHardDelete = Set<UUID>()

        for id in ids {
            if projectHasHistoricalReferences(id) {
                idsToArchive.insert(id)
            } else {
                idsToHardDelete.insert(id)
            }
        }

        var didPersist = false
        var affectedProjectIds = Set<UUID>()

        if !idsToArchive.isEmpty {
            let result = archiveProjects(ids: idsToArchive)
            didPersist = didPersist || result.didPersist
            affectedProjectIds.formUnion(result.affectedProjectIds)
        }
        if !idsToHardDelete.isEmpty {
            let result = hardDeleteProjects(ids: idsToHardDelete)
            didPersist = didPersist || result.didPersist
            affectedProjectIds.formUnion(result.affectedProjectIds)
        }

        return ProjectWorkflowDeleteResult(
            didPersist: didPersist,
            affectedProjectIds: affectedProjectIds,
            reprocessesCurrentEqualAllTransactions: didPersist
        )
    }

    private func archiveProjects(ids: Set<UUID>) -> ProjectWorkflowDeleteResult {
        guard !ids.isEmpty else {
            return ProjectWorkflowDeleteResult(
                didPersist: false,
                affectedProjectIds: [],
                reprocessesCurrentEqualAllTransactions: false
            )
        }

        let now = Date()
        let archivedProjects = (try? projectRepository.projects(ids: ids)) ?? []

        for project in archivedProjects {
            project.isArchived = true
            project.updatedAt = now
        }

        let transactions = allTransactions()
        let recurrings = allRecurringTransactions()

        for transaction in transactions {
            guard transaction.isManuallyEdited == true,
                  transaction.allocations.contains(where: { ids.contains($0.projectId) }),
                  let recurringId = transaction.recurringId,
                  let recurring = recurrings.first(where: { $0.id == recurringId }),
                  recurring.allocationMode == .equalAll
            else {
                continue
            }
            transaction.isManuallyEdited = nil
        }

        for recurring in recurrings {
            let filtered = recurring.allocations.filter { !ids.contains($0.projectId) }
            if filtered.count != recurring.allocations.count {
                if filtered.isEmpty && recurring.allocationMode == .manual {
                    for transaction in transactions where transaction.recurringId == recurring.id {
                        transaction.recurringId = nil
                        transaction.updatedAt = now
                    }
                    recurringRepository.delete(recurring)
                } else if !filtered.isEmpty {
                    recurring.allocations = redistributeAllocations(
                        totalAmount: recurring.amount,
                        remainingAllocations: filtered
                    )
                }
            }
        }

        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            return ProjectWorkflowDeleteResult(
                didPersist: true,
                affectedProjectIds: ids,
                reprocessesCurrentEqualAllTransactions: true
            )
        } catch {
            modelContext.rollback()
            return ProjectWorkflowDeleteResult(
                didPersist: false,
                affectedProjectIds: [],
                reprocessesCurrentEqualAllTransactions: false
            )
        }
    }

    private func hardDeleteProjects(ids: Set<UUID>) -> ProjectWorkflowDeleteResult {
        guard !ids.isEmpty else {
            return ProjectWorkflowDeleteResult(
                didPersist: false,
                affectedProjectIds: [],
                reprocessesCurrentEqualAllTransactions: false
            )
        }

        var imagesToDelete: [String] = []
        let recurrings = allRecurringTransactions()

        for recurring in recurrings {
            let filtered = recurring.allocations.filter { !ids.contains($0.projectId) }
            if filtered.count != recurring.allocations.count {
                if filtered.isEmpty {
                    if let imagePath = recurring.receiptImagePath {
                        imagesToDelete.append(imagePath)
                    }
                    recurringRepository.delete(recurring)
                } else {
                    recurring.allocations = redistributeAllocations(
                        totalAmount: recurring.amount,
                        remainingAllocations: filtered
                    )
                }
            }
        }

        let projects = (try? projectRepository.projects(ids: ids)) ?? []
        for project in projects {
            projectRepository.delete(project)
        }

        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            for imagePath in imagesToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
            return ProjectWorkflowDeleteResult(
                didPersist: true,
                affectedProjectIds: ids,
                reprocessesCurrentEqualAllTransactions: true
            )
        } catch {
            modelContext.rollback()
            return ProjectWorkflowDeleteResult(
                didPersist: false,
                affectedProjectIds: [],
                reprocessesCurrentEqualAllTransactions: false
            )
        }
    }

    private func projectHasHistoricalReferences(_ id: UUID) -> Bool {
        if allTransactions().contains(where: { transaction in
            transaction.allocations.contains { $0.projectId == id }
        }) {
            return true
        }

        return canonicalJournalEntries().contains { journal in
            journal.lines.contains { $0.projectAllocationId == id }
        }
    }

    private func allTransactions() -> [PPTransaction] {
        (try? transactionHistoryRepository.allTransactions()) ?? []
    }

    private func allRecurringTransactions() -> [PPRecurringTransaction] {
        (try? recurringRepository.allRecurringTransactions()) ?? []
    }

    private func canonicalJournalEntries() -> [CanonicalJournalEntry] {
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            sortBy: [
                SortDescriptor(\.journalDate, order: .reverse),
                SortDescriptor(\.voucherNo, order: .reverse)
            ]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(CanonicalJournalEntryEntityMapper.toDomain)
    }

    private func normalizedCompletedAt(
        startDate: Date?,
        completedAt: Date?,
        status: ProjectStatus
    ) -> Date? {
        guard status == .completed else {
            return nil
        }

        let resolvedCompletedAt = completedAt ?? Date()
        guard let startDate else {
            return resolvedCompletedAt
        }

        return calendar.startOfDay(for: startDate) > calendar.startOfDay(for: resolvedCompletedAt)
            ? nil
            : resolvedCompletedAt
    }

    private func normalizedPlannedEndDate(
        startDate: Date?,
        plannedEndDate: Date?
    ) -> Date? {
        guard let plannedEndDate else {
            return nil
        }

        guard let startDate else {
            return plannedEndDate
        }

        return calendar.startOfDay(for: startDate) > calendar.startOfDay(for: plannedEndDate)
            ? nil
            : plannedEndDate
    }
}
