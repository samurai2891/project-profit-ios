import Foundation
import SwiftData

@MainActor
final class SwiftDataRecurringRepository: RecurringRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func listSnapshot() throws -> RecurringListSnapshot {
        let recurringDescriptor = FetchDescriptor<PPRecurringTransaction>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let projectDescriptor = FetchDescriptor<PPProject>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let categoryDescriptor = FetchDescriptor<PPCategory>(
            sortBy: [SortDescriptor(\.name)]
        )

        let recurrings = try modelContext.fetch(recurringDescriptor)
        let projects = try modelContext.fetch(projectDescriptor)
        let categories = try modelContext.fetch(categoryDescriptor)

        return RecurringListSnapshot(
            recurringTransactions: recurrings,
            projectNamesById: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) }),
            categoryNamesById: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        )
    }

    func historyEntries(recurringId: UUID) throws -> [RecurringHistoryEntry] {
        let transactionDescriptor = FetchDescriptor<PPTransaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let projectDescriptor = FetchDescriptor<PPProject>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let categoryDescriptor = FetchDescriptor<PPCategory>(
            sortBy: [SortDescriptor(\.name)]
        )

        let transactions = try modelContext.fetch(transactionDescriptor)
            .filter { $0.recurringId == recurringId }
        let projects = try modelContext.fetch(projectDescriptor)
        let categories = try modelContext.fetch(categoryDescriptor)

        let projectNamesById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        let categoryNamesById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })

        return transactions.map { transaction in
            RecurringHistoryEntry(
                id: transaction.id,
                date: transaction.date,
                amount: transaction.amount,
                type: transaction.type,
                categoryName: categoryNamesById[transaction.categoryId],
                projectNames: transaction.allocations.compactMap { projectNamesById[$0.projectId] }
            )
        }
    }
}
