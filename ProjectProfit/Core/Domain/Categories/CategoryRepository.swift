import Foundation
import SwiftData

@MainActor
protocol CategoryRepository {
    func categories() throws -> [PPCategory]
    func category(id: String) throws -> PPCategory?
    func transactions(categoryId: String) throws -> [PPTransaction]
    func recurringTransactions(categoryId: String) throws -> [PPRecurringTransaction]
    func insert(_ category: PPCategory)
    func delete(_ category: PPCategory)
    func saveChanges() throws
}
