import Foundation
import SwiftData

struct InventoryUpsertInput: Equatable, Sendable {
    let fiscalYear: Int
    let openingInventory: Int
    let purchases: Int
    let closingInventory: Int
    let memo: String?
}

@MainActor
struct InventoryWorkflowUseCase {
    private let modelContext: ModelContext
    private let inventoryRepository: any InventoryRepository
    private let reloadInventoryRecords: @MainActor () -> Void
    private let setError: @MainActor (AppError?) -> Void

    init(
        modelContext: ModelContext,
        inventoryRepository: (any InventoryRepository)? = nil,
        reloadInventoryRecords: @escaping @MainActor () -> Void = {},
        setError: @escaping @MainActor (AppError?) -> Void = { _ in }
    ) {
        self.modelContext = modelContext
        self.inventoryRepository = inventoryRepository ?? SwiftDataInventoryRepository(modelContext: modelContext)
        self.reloadInventoryRecords = reloadInventoryRecords
        self.setError = setError
    }

    @discardableResult
    func save(existingRecordId: UUID?, input: InventoryUpsertInput) -> Bool {
        if let existingRecordId {
            return updateInventoryRecord(id: existingRecordId, input: input)
        }
        return createInventoryRecord(input: input) != nil
    }

    @discardableResult
    func createInventoryRecord(input: InventoryUpsertInput) -> PPInventoryRecord? {
        guard !isYearLocked(input.fiscalYear) else {
            return nil
        }

        let record = PPInventoryRecord(
            fiscalYear: input.fiscalYear,
            openingInventory: input.openingInventory,
            purchases: input.purchases,
            closingInventory: input.closingInventory,
            memo: input.memo
        )
        inventoryRepository.insert(record)

        guard saveChanges() else {
            return nil
        }

        setError(nil)
        reloadInventoryRecords()
        return record
    }

    @discardableResult
    func updateInventoryRecord(id: UUID, input: InventoryUpsertInput) -> Bool {
        let record: PPInventoryRecord
        do {
            guard let fetched = try inventoryRepository.inventoryRecord(id: id) else {
                return false
            }
            record = fetched
        } catch {
            setError(.saveFailed(underlying: error))
            return false
        }

        guard !isYearLocked(record.fiscalYear) else {
            return false
        }

        record.openingInventory = max(0, input.openingInventory)
        record.purchases = max(0, input.purchases)
        record.closingInventory = max(0, input.closingInventory)
        record.memo = input.memo
        record.updatedAt = Date()

        guard saveChanges() else {
            return false
        }

        setError(nil)
        reloadInventoryRecords()
        return true
    }

    @discardableResult
    func deleteInventoryRecord(id: UUID) -> Bool {
        let record: PPInventoryRecord
        do {
            guard let fetched = try inventoryRepository.inventoryRecord(id: id) else {
                return false
            }
            record = fetched
        } catch {
            setError(.saveFailed(underlying: error))
            return false
        }

        guard !isYearLocked(record.fiscalYear) else {
            return false
        }

        modelContext.delete(record)
        guard saveChanges() else {
            return false
        }

        setError(nil)
        reloadInventoryRecords()
        return true
    }

    private func saveChanges() -> Bool {
        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            return true
        } catch {
            setError(.saveFailed(underlying: error))
            return false
        }
    }

    private func isYearLocked(_ year: Int) -> Bool {
        guard !WorkflowPersistenceSupport.isYearLocked(modelContext: modelContext, year: year) else {
            setError(.yearLocked(year: year))
            return true
        }
        return false
    }
}
