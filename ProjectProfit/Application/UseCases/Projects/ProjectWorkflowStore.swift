import Foundation
import SwiftData

@MainActor
struct ProjectWorkflowStore {
    private let modelContext: ModelContext
    private let projectRepository: any ProjectRepository
    private let recurringRepository: any RecurringRepository
    private let transactionHistoryRepository: any TransactionHistoryRepository
    private let transactionFormQueryUseCase: TransactionFormQueryUseCase
    private let allocationReprocessor: ProjectAllocationReprocessor
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        projectRepository: any ProjectRepository,
        recurringRepository: (any RecurringRepository)? = nil,
        transactionHistoryRepository: (any TransactionHistoryRepository)? = nil,
        transactionFormQueryUseCase: TransactionFormQueryUseCase? = nil,
        allocationReprocessor: ProjectAllocationReprocessor? = nil,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.projectRepository = projectRepository
        let recurringRepository = recurringRepository ?? SwiftDataRecurringRepository(modelContext: modelContext)
        let transactionHistoryRepository = transactionHistoryRepository ?? SwiftDataTransactionHistoryRepository(modelContext: modelContext)
        let transactionFormQueryUseCase = transactionFormQueryUseCase ?? TransactionFormQueryUseCase(modelContext: modelContext)
        self.recurringRepository = recurringRepository
        self.transactionHistoryRepository = transactionHistoryRepository
        self.transactionFormQueryUseCase = transactionFormQueryUseCase
        self.calendar = calendar
        self.allocationReprocessor = allocationReprocessor ?? ProjectAllocationReprocessor(
            modelContext: modelContext,
            projectRepository: projectRepository,
            recurringRepository: recurringRepository,
            transactionHistoryRepository: transactionHistoryRepository,
            transactionFormQueryUseCase: transactionFormQueryUseCase,
            postingSupport: CanonicalPostingSupport(
                modelContext: modelContext,
                transactionFormQueryUseCase: transactionFormQueryUseCase
            ),
            calendar: calendar
        )
    }

    @discardableResult
    func createProject(input: ProjectUpsertInput) -> PPProject {
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
            allocationReprocessor.reprocessEqualAllCurrentPeriodTransactions()
        } catch {
            modelContext.rollback()
        }

        return project
    }

    func updateProject(id: UUID, input: ProjectUpsertInput) {
        let project: PPProject
        do {
            guard let fetched = try projectRepository.project(id: id) else {
                return
            }
            project = fetched
        } catch {
            return
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
            return
        }

        let completedAtChanged = project.completedAt != previousCompletedAt
        let startDateChanged = project.startDate != previousStartDate
        let plannedEndDateChanged = project.plannedEndDate != previousPlannedEndDate
        let statusChangedAwayFromCompleted = previousStatus == .completed && project.status != .completed

        if completedAtChanged || startDateChanged || plannedEndDateChanged {
            if project.startDate != nil || project.effectiveEndDate != nil {
                allocationReprocessor.recalculateAllocationsForProject(projectId: id)
            } else if statusChangedAwayFromCompleted {
                allocationReprocessor.reverseCompletionAllocations(projectId: id)
                allocationReprocessor.recalculateAllPartialPeriodProjects()
            } else if previousStartDate != nil || previousCompletedAt != nil || previousPlannedEndDate != nil {
                allocationReprocessor.reverseCompletionAllocations(projectId: id)
                allocationReprocessor.recalculateAllPartialPeriodProjects()
            }
        }
    }

    func deleteProject(id: UUID) {
        guard (try? projectRepository.project(id: id)) != nil else {
            return
        }

        if projectHasHistoricalReferences(id) {
            archiveProjects(ids: [id])
        } else {
            hardDeleteProjects(ids: [id])
        }
    }

    func deleteProjects(ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
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

        if !idsToArchive.isEmpty {
            archiveProjects(ids: idsToArchive)
        }
        if !idsToHardDelete.isEmpty {
            hardDeleteProjects(ids: idsToHardDelete)
        }
    }

    private func archiveProjects(ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
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
            allocationReprocessor.reprocessEqualAllCurrentPeriodTransactions()
        } catch {
            modelContext.rollback()
        }
    }

    private func hardDeleteProjects(ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
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
            allocationReprocessor.reprocessEqualAllCurrentPeriodTransactions()
        } catch {
            modelContext.rollback()
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
