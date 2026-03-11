import Foundation

struct InventoryUpsertInput: Equatable, Sendable {
    let fiscalYear: Int
    let openingInventory: Int
    let purchases: Int
    let closingInventory: Int
    let memo: String?
}

@MainActor
struct InventoryWorkflowUseCase {
    private let dataStore: DataStore
    private let inventoryRepository: any InventoryRepository

    init(
        dataStore: DataStore,
        inventoryRepository: (any InventoryRepository)? = nil
    ) {
        self.dataStore = dataStore
        self.inventoryRepository = inventoryRepository ?? SwiftDataInventoryRepository(modelContext: dataStore.modelContext)
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
        guard !dataStore.isYearLocked(input.fiscalYear) else {
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

        guard dataStore.save() else {
            return nil
        }

        dataStore.refreshInventoryRecords()
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
            return false
        }

        guard !dataStore.isYearLocked(record.fiscalYear) else {
            return false
        }

        record.openingInventory = max(0, input.openingInventory)
        record.purchases = max(0, input.purchases)
        record.closingInventory = max(0, input.closingInventory)
        record.memo = input.memo
        record.updatedAt = Date()

        guard dataStore.save() else {
            return false
        }

        dataStore.refreshInventoryRecords()
        return true
    }
}
