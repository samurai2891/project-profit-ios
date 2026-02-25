import SwiftData
import SwiftUI

// MARK: - DataStore Inventory Extension

extension DataStore {

    // MARK: - CRUD

    @discardableResult
    func addInventoryRecord(
        fiscalYear: Int,
        openingInventory: Int = 0,
        purchases: Int = 0,
        closingInventory: Int = 0,
        memo: String? = nil
    ) -> PPInventoryRecord {
        let record = PPInventoryRecord(
            fiscalYear: fiscalYear,
            openingInventory: openingInventory,
            purchases: purchases,
            closingInventory: closingInventory,
            memo: memo
        )
        modelContext.insert(record)
        save()
        refreshInventoryRecords()
        return record
    }

    func updateInventoryRecord(
        id: UUID,
        openingInventory: Int? = nil,
        purchases: Int? = nil,
        closingInventory: Int? = nil,
        memo: String?? = nil
    ) {
        guard let record = inventoryRecords.first(where: { $0.id == id }) else { return }

        if let openingInventory { record.openingInventory = max(0, openingInventory) }
        if let purchases { record.purchases = max(0, purchases) }
        if let closingInventory { record.closingInventory = max(0, closingInventory) }
        if let memo { record.memo = memo }
        record.updatedAt = Date()

        save()
        refreshInventoryRecords()
    }

    func deleteInventoryRecord(id: UUID) {
        guard let record = inventoryRecords.first(where: { $0.id == id }) else { return }
        modelContext.delete(record)
        save()
        refreshInventoryRecords()
    }

    func getInventoryRecord(fiscalYear: Int) -> PPInventoryRecord? {
        inventoryRecords.first { $0.fiscalYear == fiscalYear }
    }

    func refreshInventoryRecords() {
        do {
            let descriptor = FetchDescriptor<PPInventoryRecord>(
                sortBy: [SortDescriptor(\.fiscalYear, order: .reverse)]
            )
            inventoryRecords = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to refresh inventory records: \(error.localizedDescription)")
            lastError = .dataLoadFailed(underlying: error)
        }
    }
}
