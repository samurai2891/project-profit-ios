import Foundation
import SwiftData

@MainActor
struct ClosingWorkflowUseCase {
    private let modelContext: ModelContext
    private let reloadJournalState: @MainActor () -> Void
    private let applyTaxYearProfile: @MainActor (TaxYearProfile) -> Void
    private let setError: @MainActor (AppError?) -> Void

    init(
        modelContext: ModelContext,
        reloadJournalState: @escaping @MainActor () -> Void = {},
        applyTaxYearProfile: @escaping @MainActor (TaxYearProfile) -> Void = { _ in },
        setError: @escaping @MainActor (AppError?) -> Void = { _ in }
    ) {
        self.modelContext = modelContext
        self.reloadJournalState = reloadJournalState
        self.applyTaxYearProfile = applyTaxYearProfile
        self.setError = setError
    }

    @discardableResult
    func generateClosingEntry(for year: Int) -> CanonicalJournalEntry? {
        guard FeatureFlags.useCanonicalPosting else {
            return nil
        }
        guard canPostAdjustingEntries(for: year) else {
            return nil
        }

        WorkflowPersistenceSupport.runLegacyProfileMigrationIfNeeded(modelContext: modelContext)
        guard let businessId = try? WorkflowPersistenceSupport.defaultBusinessId(modelContext: modelContext) else {
            setError(.invalidInput(message: "申告者情報が未設定のため決算仕訳を生成できません"))
            return nil
        }

        do {
            let canonicalEntry = try ClosingEntryUseCase(modelContext: modelContext).generate(
                businessId: businessId,
                taxYear: year
            )
            deleteLegacyClosingEntryRecord(for: year)
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            setError(nil)
            reloadJournalState()
            return canonicalEntry
        } catch {
            modelContext.rollback()
            setError(.saveFailed(underlying: error))
            reloadJournalState()
            return nil
        }
    }

    func deleteClosingEntry(for year: Int) {
        guard FeatureFlags.useCanonicalPosting else {
            return
        }
        guard canPostAdjustingEntries(for: year) else {
            return
        }

        WorkflowPersistenceSupport.runLegacyProfileMigrationIfNeeded(modelContext: modelContext)
        guard let businessId = try? WorkflowPersistenceSupport.defaultBusinessId(modelContext: modelContext) else {
            setError(.invalidInput(message: "申告者情報が未設定のため決算仕訳を削除できません"))
            return
        }

        do {
            try ClosingEntryUseCase(modelContext: modelContext).delete(businessId: businessId, taxYear: year)
            deleteLegacyClosingEntryRecord(for: year)
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            setError(nil)
            reloadJournalState()
        } catch {
            modelContext.rollback()
            setError(.saveFailed(underlying: error))
            reloadJournalState()
        }
    }

    @discardableResult
    func regenerateClosingEntry(for year: Int) -> CanonicalJournalEntry? {
        guard FeatureFlags.useCanonicalPosting else {
            return nil
        }
        guard canPostAdjustingEntries(for: year) else {
            return nil
        }

        WorkflowPersistenceSupport.runLegacyProfileMigrationIfNeeded(modelContext: modelContext)
        guard let businessId = try? WorkflowPersistenceSupport.defaultBusinessId(modelContext: modelContext) else {
            setError(.invalidInput(message: "申告者情報が未設定のため決算仕訳を再生成できません"))
            return nil
        }

        do {
            let useCase = ClosingEntryUseCase(modelContext: modelContext)
            try useCase.delete(businessId: businessId, taxYear: year)
            deleteLegacyClosingEntryRecord(for: year)
            let canonicalEntry = try useCase.generate(businessId: businessId, taxYear: year)
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            setError(nil)
            reloadJournalState()
            return canonicalEntry
        } catch {
            modelContext.rollback()
            setError(.saveFailed(underlying: error))
            reloadJournalState()
            return nil
        }
    }

    @discardableResult
    func transitionFiscalYearState(_ state: YearLockState, for year: Int) -> Bool {
        WorkflowPersistenceSupport.runLegacyProfileMigrationIfNeeded(modelContext: modelContext)
        guard let businessId = try? WorkflowPersistenceSupport.defaultBusinessId(modelContext: modelContext) else {
            setError(.invalidInput(message: "申告者情報が未設定のため年度状態を更新できません"))
            return false
        }

        do {
            let fallbackProfile = try WorkflowPersistenceSupport.taxYearProfile(
                modelContext: modelContext,
                businessId: businessId,
                taxYear: year
            )
            let updated = try TaxYearStateUseCase(modelContext: modelContext).transitionYearLock(
                businessId: businessId,
                taxYear: year,
                targetState: state,
                fallbackProfile: fallbackProfile
            )
            applyTaxYearProfile(updated)
            setError(nil)
            return true
        } catch {
            modelContext.rollback()
            setError(.saveFailed(underlying: error))
            return false
        }
    }

    private func canPostAdjustingEntries(for year: Int) -> Bool {
        guard WorkflowPersistenceSupport.canPostAdjustingEntry(modelContext: modelContext, year: year) else {
            setError(.yearLocked(year: year))
            return false
        }
        return true
    }

    private func deleteLegacyClosingEntryRecord(for year: Int) {
        let sourceKey = PPJournalEntry.closingSourceKey(year: year)
        let entryDescriptor = FetchDescriptor<PPJournalEntry>(
            predicate: #Predicate { $0.sourceKey == sourceKey }
        )
        guard let entry = try? modelContext.fetch(entryDescriptor).first else {
            return
        }

        let entryId = entry.id
        let lineDescriptor = FetchDescriptor<PPJournalLine>(
            predicate: #Predicate { $0.entryId == entryId }
        )
        let lines = (try? modelContext.fetch(lineDescriptor)) ?? []
        for line in lines {
            modelContext.delete(line)
        }
        modelContext.delete(entry)
    }
}
