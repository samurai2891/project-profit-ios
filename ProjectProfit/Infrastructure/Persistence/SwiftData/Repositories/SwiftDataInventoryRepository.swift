import Foundation
import SwiftData

@MainActor
final class SwiftDataInventoryRepository: InventoryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func inventoryRecord(id: UUID) throws -> PPInventoryRecord? {
        let predicate = #Predicate<PPInventoryRecord> { $0.id == id }
        let descriptor = FetchDescriptor<PPInventoryRecord>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    func inventoryRecord(fiscalYear: Int) throws -> PPInventoryRecord? {
        let predicate = #Predicate<PPInventoryRecord> { $0.fiscalYear == fiscalYear }
        let descriptor = FetchDescriptor<PPInventoryRecord>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    func insert(_ record: PPInventoryRecord) {
        modelContext.insert(record)
    }
}
