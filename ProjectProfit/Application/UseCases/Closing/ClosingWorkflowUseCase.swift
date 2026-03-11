import Foundation

@MainActor
struct ClosingWorkflowUseCase {
    private let dataStore: DataStore

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    @discardableResult
    func generateClosingEntry(for year: Int) -> CanonicalJournalEntry? {
        dataStore.generateClosingEntry(for: year)
    }

    func deleteClosingEntry(for year: Int) {
        dataStore.deleteClosingEntry(for: year)
    }

    @discardableResult
    func regenerateClosingEntry(for year: Int) -> CanonicalJournalEntry? {
        dataStore.regenerateClosingEntry(for: year)
    }

    @discardableResult
    func transitionFiscalYearState(_ state: YearLockState, for year: Int) -> Bool {
        dataStore.transitionFiscalYearState(state, for: year)
    }
}
