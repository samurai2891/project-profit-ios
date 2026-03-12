import SwiftData
import SwiftUI

// MARK: - DataStore Inventory Extension

extension DataStore {

    // MARK: - CRUD

#if DEBUG
    @discardableResult
    func addInventoryRecord(
        fiscalYear: Int,
        openingInventory: Int = 0,
        purchases: Int = 0,
        closingInventory: Int = 0,
        memo: String? = nil
    ) -> PPInventoryRecord? {
        guard !isYearLocked(fiscalYear) else { return nil }

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

    @discardableResult
    func updateInventoryRecord(
        id: UUID,
        openingInventory: Int? = nil,
        purchases: Int? = nil,
        closingInventory: Int? = nil,
        memo: String?? = nil
    ) -> Bool {
        guard let record = inventoryRecords.first(where: { $0.id == id }) else { return false }
        guard !isYearLocked(record.fiscalYear) else { return false }

        if let openingInventory { record.openingInventory = max(0, openingInventory) }
        if let purchases { record.purchases = max(0, purchases) }
        if let closingInventory { record.closingInventory = max(0, closingInventory) }
        if let memo { record.memo = memo }
        record.updatedAt = Date()

        save()
        refreshInventoryRecords()
        return true
    }

    @discardableResult
    func deleteInventoryRecord(id: UUID) -> Bool {
        guard let record = inventoryRecords.first(where: { $0.id == id }) else { return false }
        guard !isYearLocked(record.fiscalYear) else { return false }
        modelContext.delete(record)
        save()
        refreshInventoryRecords()
        return true
    }
#endif

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
