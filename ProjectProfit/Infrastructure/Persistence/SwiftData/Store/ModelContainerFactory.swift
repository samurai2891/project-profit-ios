import Foundation
import SwiftData

/// 新旧モデル共存のModelContainer設定
enum ModelContainerFactory {

    /// 現行アプリが依存する legacy schema
    /// PPAccountingProfile は read-only legacy として残す（既存データ読込・バックアップ/リストア互換用）
    static var legacySchema: [any PersistentModel.Type] {
        [
            PPProject.self,
            PPTransaction.self,
            PPCategory.self,
            PPRecurringTransaction.self,
            PPAccount.self,
            PPJournalEntry.self,
            PPJournalLine.self,
            PPAccountingProfile.self, // read-only legacy: 既存データ読込用
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
            CounterpartyEntity.self,
            CanonicalAccountEntity.self,
            DistributionRuleEntity.self,
            AuditEventEntity.self,
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
