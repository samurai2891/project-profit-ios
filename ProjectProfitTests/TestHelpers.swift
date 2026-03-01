import SwiftData
@testable import ProjectProfit

enum TestModelContainer {
    @MainActor
    static func create() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: PPProject.self,
                 PPTransaction.self,
                 PPCategory.self,
                 PPRecurringTransaction.self,
                 PPAccount.self,
                 PPJournalEntry.self,
                 PPJournalLine.self,
                 PPAccountingProfile.self,
                 PPUserRule.self,
                 PPFixedAsset.self,
                 PPInventoryRecord.self,
                 PPDocumentRecord.self,
                 PPComplianceLog.self,
                 PPTransactionLog.self,
                 SDLedgerBook.self,
                 SDLedgerEntry.self,
            configurations: config
        )
    }
}
