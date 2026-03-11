import Foundation

struct RecurringListSnapshot {
    let recurringTransactions: [PPRecurringTransaction]
    let projectNamesById: [UUID: String]
    let categoryNamesById: [String: String]

    static let empty = RecurringListSnapshot(
        recurringTransactions: [],
        projectNamesById: [:],
        categoryNamesById: [:]
    )
}

struct RecurringHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let amount: Int
    let type: TransactionType
    let categoryName: String?
    let projectNames: [String]
}

@MainActor
protocol RecurringRepository {
    func listSnapshot() throws -> RecurringListSnapshot
    func historyEntries(recurringId: UUID) throws -> [RecurringHistoryEntry]
}
