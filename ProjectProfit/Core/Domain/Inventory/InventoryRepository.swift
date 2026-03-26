import Foundation

@MainActor
protocol InventoryRepository {
    func inventoryRecord(id: UUID) throws -> PPInventoryRecord?
    func inventoryRecord(fiscalYear: Int) throws -> PPInventoryRecord?
    func insert(_ record: PPInventoryRecord)
}
