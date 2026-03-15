import Foundation
import SwiftData

@MainActor
struct ClosingWorkflowUseCase {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func generateClosingEntry(for year: Int) throws -> CanonicalJournalEntry? {
        guard FeatureFlags.useCanonicalPosting else {
            return nil
        }
        try validateCanPostAdjustingEntries(for: year)

        WorkflowPersistenceSupport.runLegacyProfileMigrationIfNeeded(modelContext: modelContext)
        let businessId = try resolveBusinessId(
            missingMessage: "申告者情報が未設定のため決算仕訳を生成できません"
        )

        do {
            let canonicalEntry = try ClosingEntryUseCase(modelContext: modelContext).generate(
                businessId: businessId,
                taxYear: year
            )
            deleteLegacyClosingEntryRecord(for: year)
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            return canonicalEntry
        } catch {
            modelContext.rollback()
            throw wrapped(error)
        }
    }

    func deleteClosingEntry(for year: Int) throws {
        guard FeatureFlags.useCanonicalPosting else {
            return
        }
        try validateCanPostAdjustingEntries(for: year)

        WorkflowPersistenceSupport.runLegacyProfileMigrationIfNeeded(modelContext: modelContext)
        let businessId = try resolveBusinessId(
            missingMessage: "申告者情報が未設定のため決算仕訳を削除できません"
        )

        do {
            try ClosingEntryUseCase(modelContext: modelContext).delete(businessId: businessId, taxYear: year)
            deleteLegacyClosingEntryRecord(for: year)
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
        } catch {
            modelContext.rollback()
            throw wrapped(error)
        }
    }

    func regenerateClosingEntry(for year: Int) throws -> CanonicalJournalEntry? {
        guard FeatureFlags.useCanonicalPosting else {
            return nil
        }
        try validateCanPostAdjustingEntries(for: year)

        WorkflowPersistenceSupport.runLegacyProfileMigrationIfNeeded(modelContext: modelContext)
        let businessId = try resolveBusinessId(
            missingMessage: "申告者情報が未設定のため決算仕訳を再生成できません"
        )

        do {
            let useCase = ClosingEntryUseCase(modelContext: modelContext)
            try useCase.delete(businessId: businessId, taxYear: year)
            deleteLegacyClosingEntryRecord(for: year)
            let canonicalEntry = try useCase.generate(businessId: businessId, taxYear: year)
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            return canonicalEntry
        } catch {
            modelContext.rollback()
            throw wrapped(error)
        }
    }

    func transitionFiscalYearState(_ state: YearLockState, for year: Int) throws -> TaxYearProfile {
        WorkflowPersistenceSupport.runLegacyProfileMigrationIfNeeded(modelContext: modelContext)
        let businessId = try resolveBusinessId(
            missingMessage: "申告者情報が未設定のため年度状態を更新できません"
        )

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
            return updated
        } catch {
            modelContext.rollback()
            throw wrapped(error)
        }
    }

    private func validateCanPostAdjustingEntries(for year: Int) throws {
        guard WorkflowPersistenceSupport.canPostAdjustingEntry(modelContext: modelContext, year: year) else {
            throw AppError.yearLocked(year: year)
        }
    }

    private func resolveBusinessId(missingMessage: String) throws -> UUID {
        do {
            if let businessId = try WorkflowPersistenceSupport.defaultBusinessId(modelContext: modelContext) {
                return businessId
            }
            throw AppError.invalidInput(message: missingMessage)
        } catch {
            if let appError = error as? AppError {
                throw appError
            }
            throw AppError.invalidInput(message: missingMessage)
        }
    }

    private func wrapped(_ error: Error) -> Error {
        if let appError = error as? AppError {
            return appError
        }
        if let taxError = error as? TaxYearStateUseCaseError {
            return taxError
        }
        return AppError.saveFailed(underlying: error)
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
