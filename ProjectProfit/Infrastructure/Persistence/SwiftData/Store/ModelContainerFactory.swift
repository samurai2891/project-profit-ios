import Foundation
import SwiftData

/// 新旧モデル共存のModelContainer設定
enum ModelContainerFactory {

    /// 現行アプリが依存する legacy schema
    /// PPAccountingProfile は旧DB migration compat 用として残す（現行の正本ではない）
    static var legacySchema: [any PersistentModel.Type] {
        [
            PPProject.self,
            PPTransaction.self,
            PPCategory.self,
            PPRecurringTransaction.self,
            PPAccount.self,
            PPJournalEntry.self,
            PPJournalLine.self,
            PPAccountingProfile.self, // migration-only legacy compat
            PPUserRule.self,
            PPFixedAsset.self,
            PPInventoryRecord.self,
            PPDocumentRecord.self,
            PPComplianceLog.self,
            PPTransactionLog.self,
            SDLedgerBook.self,
            SDLedgerEntry.self
        ]
    }

    /// 新旧全てのモデルを含むスキーマ
    static var canonicalSchema: [any PersistentModel.Type] {
        [
            // 新 Canonical entities
            BusinessProfileEntity.self,
            TaxYearProfileEntity.self,
            EvidenceRecordEntity.self,
            EvidenceSearchIndexEntity.self,
            JournalEntryEntity.self,
            JournalLineEntity.self,
            JournalSearchIndexEntity.self,
            PostingCandidateEntity.self,
            ApprovalRequestEntity.self,
            FormDraftEntity.self,
            CounterpartyEntity.self,
            CanonicalAccountEntity.self,
            DistributionRuleEntity.self,
            AuditEventEntity.self,
            StatementImportEntity.self,
            StatementLineEntity.self,
        ]
    }

    static var appSchema: [any PersistentModel.Type] {
        legacySchema + canonicalSchema
    }

    static func makeAppContainer(
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: Schema(appSchema),
            configurations: [config]
        )
    }

    /// Canonical entities のみの ModelContainer を作成（テスト用・移行用）
    static func makeCanonicalContainer(
        inMemory: Bool = false
    ) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: Schema(canonicalSchema),
            configurations: [config]
        )
    }
}
