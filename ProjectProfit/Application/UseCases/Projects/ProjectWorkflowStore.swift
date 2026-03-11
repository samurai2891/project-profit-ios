import Foundation
import SwiftData

@MainActor
struct ProjectWorkflowStore {
    private let modelContext: ModelContext
    private let projectRepository: any ProjectRepository
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        projectRepository: any ProjectRepository,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.projectRepository = projectRepository
        self.calendar = calendar
    }

    @discardableResult
    func createProject(input: ProjectUpsertInput) -> PPProject {
        let dataStore = configuredDataStore()
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

        if dataStore.save() {
            dataStore.refreshProjects()
            dataStore.reprocessEqualAllCurrentPeriodTransactions()
            dataStore.refreshTransactions()
        }

        return project
    }

    func updateProject(id: UUID, input: ProjectUpsertInput) {
        let dataStore = configuredDataStore()
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

        guard dataStore.save() else {
            return
        }

        dataStore.refreshProjects()

        let completedAtChanged = project.completedAt != previousCompletedAt
        let startDateChanged = project.startDate != previousStartDate
        let plannedEndDateChanged = project.plannedEndDate != previousPlannedEndDate
        let statusChangedAwayFromCompleted = previousStatus == .completed && project.status != .completed

        if completedAtChanged || startDateChanged || plannedEndDateChanged {
            if project.startDate != nil || project.effectiveEndDate != nil {
                dataStore.recalculateAllocationsForProject(projectId: id)
            } else if statusChangedAwayFromCompleted {
                dataStore.reverseCompletionAllocations(projectId: id)
                dataStore.recalculateAllPartialPeriodProjects()
            } else if previousStartDate != nil || previousCompletedAt != nil || previousPlannedEndDate != nil {
                dataStore.reverseCompletionAllocations(projectId: id)
                dataStore.recalculateAllPartialPeriodProjects()
            }
            dataStore.refreshTransactions()
        }
    }

    func deleteProject(id: UUID) {
        let dataStore = configuredDataStore()
        do {
            guard try projectRepository.project(id: id) != nil else {
                return
            }
        } catch {
            return
        }

        if dataStore.projectHasHistoricalReferences(id) {
            archiveProjects(ids: [id], dataStore: dataStore)
        } else {
            hardDeleteProjects(ids: [id], dataStore: dataStore)
        }
    }

    func deleteProjects(ids: Set<UUID>) {
        let dataStore = configuredDataStore()
        guard !ids.isEmpty else {
            return
        }

        var idsToArchive = Set<UUID>()
        var idsToHardDelete = Set<UUID>()

        for id in ids {
            if dataStore.projectHasHistoricalReferences(id) {
                idsToArchive.insert(id)
            } else {
                idsToHardDelete.insert(id)
            }
        }

        if !idsToArchive.isEmpty {
            archiveProjects(ids: idsToArchive, dataStore: dataStore)
        }
        if !idsToHardDelete.isEmpty {
            hardDeleteProjects(ids: idsToHardDelete, dataStore: dataStore)
        }
    }

    private func archiveProjects(ids: Set<UUID>, dataStore: DataStore) {
        guard !ids.isEmpty else {
            return
        }

        let now = Date()
        let archivedProjects = (try? projectRepository.projects(ids: ids)) ?? []

        for project in archivedProjects {
            project.isArchived = true
            project.updatedAt = now
        }

        for transaction in dataStore.transactions {
            guard transaction.isManuallyEdited == true,
                  transaction.allocations.contains(where: { ids.contains($0.projectId) }),
                  let recurringId = transaction.recurringId,
                  let recurring = dataStore.recurringTransactions.first(where: { $0.id == recurringId }),
                  recurring.allocationMode == .equalAll
            else {
                continue
            }
            transaction.isManuallyEdited = nil
        }

        for recurring in dataStore.recurringTransactions {
            let filtered = recurring.allocations.filter { !ids.contains($0.projectId) }
            if filtered.count != recurring.allocations.count {
                if filtered.isEmpty && recurring.allocationMode == .manual {
                    for transaction in dataStore.transactions where transaction.recurringId == recurring.id {
                        transaction.recurringId = nil
                        transaction.updatedAt = now
                    }
                    dataStore.modelContext.delete(recurring)
                } else if !filtered.isEmpty {
                    recurring.allocations = redistributeAllocations(
                        totalAmount: recurring.amount,
                        remainingAllocations: filtered
                    )
                }
            }
        }

        guard dataStore.save() else {
            return
        }

        dataStore.refreshProjects()
        dataStore.refreshRecurring()
        dataStore.reprocessEqualAllCurrentPeriodTransactions()
        dataStore.refreshTransactions()
    }

    private func hardDeleteProjects(ids: Set<UUID>, dataStore: DataStore) {
        guard !ids.isEmpty else {
            return
        }

        var imagesToDelete: [String] = []

        for recurring in dataStore.recurringTransactions {
            let filtered = recurring.allocations.filter { !ids.contains($0.projectId) }
            if filtered.count != recurring.allocations.count {
                if filtered.isEmpty {
                    if let imagePath = recurring.receiptImagePath {
                        imagesToDelete.append(imagePath)
                    }
                    dataStore.modelContext.delete(recurring)
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

        if dataStore.save() {
            for imagePath in imagesToDelete {
                ReceiptImageStore.deleteImage(fileName: imagePath)
            }
        } else {
            return
        }

        dataStore.refreshProjects()
        dataStore.refreshTransactions()
        dataStore.refreshRecurring()
        dataStore.reprocessEqualAllCurrentPeriodTransactions()
        dataStore.refreshTransactions()
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

    private func configuredDataStore() -> DataStore {
        let dataStore = DataStore(modelContext: modelContext)
        dataStore.loadData()
        return dataStore
    }
}
