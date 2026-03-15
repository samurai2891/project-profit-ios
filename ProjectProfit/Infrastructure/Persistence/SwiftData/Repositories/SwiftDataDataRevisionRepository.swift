import Foundation
import SwiftData

@MainActor
final class SwiftDataDataRevisionRepository: DataRevisionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func dashboardRevisionKey() throws -> String {
        try revisionKey(includeJournals: true, scope: "dashboard")
    }

    func reportRevisionKey() throws -> String {
        try revisionKey(includeJournals: true, scope: "report")
    }

    func transactionsRevisionKey() throws -> String {
        try revisionKey(includeJournals: false, scope: "transactions")
    }

    private func revisionKey(includeJournals: Bool, scope: String) throws -> String {
        let transactions = try modelContext.fetch(FetchDescriptor<PPTransaction>())
        let projects = try modelContext.fetch(FetchDescriptor<PPProject>())
        let categories = try modelContext.fetch(FetchDescriptor<PPCategory>())
        let journalEntries = includeJournals
            ? try modelContext.fetch(FetchDescriptor<PPJournalEntry>())
            : []

        let transactionStamp = transactions.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let projectStamp = projects.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let journalStamp = journalEntries.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let categorySignature = categories
            .map { "\($0.id):\($0.name):\($0.archivedAt?.timeIntervalSince1970 ?? 0):\($0.linkedAccountId ?? "")" }
            .sorted()
            .joined(separator: "|")

        var parts = [
            scope,
            String(transactions.count),
            String(projects.count),
            String(categories.count),
            String(transactionStamp),
            String(projectStamp),
            categorySignature,
        ]

        if includeJournals {
            parts.append(String(journalEntries.count))
            parts.append(String(journalStamp))
        }

        return parts.joined(separator: ":")
    }
}
