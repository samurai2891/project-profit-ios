import Foundation
import SwiftData

/// 新旧モデル共存のModelContainer設定
enum ModelContainerFactory {

    /// 新旧全てのモデルを含むスキーマ
    static var canonicalSchema: [any PersistentModel.Type] {
        [
            // 新 Canonical entities
            BusinessProfileEntity.self,
            TaxYearProfileEntity.self,
            EvidenceRecordEntity.self,
            JournalEntryEntity.self,
            JournalLineEntity.self,
            PostingCandidateEntity.self,
            CounterpartyEntity.self,
            AuditEventEntity.self,
        ]
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
