# ProjectProfit リリース向け修正チケット一覧（粒度見直し版 / 2026-03-10）

元資料: `release_ticket_list.md` を基準に、チケットの**意味・スコープは変えず**、子タスク単位まで分解し直した版。  
この改定は **zip 内のコード実体を再確認した事実だけ** で構成し、未確認の実行結果は根拠に含めていない。

## 確認対象と判定ルール

### 確認対象
- 作業ツリー: `project-profit-ios.zip` の展開内容
- index スナップショット: zip 内 `.git` の index を `git checkout-index` で展開した内容

### 整合性メモ
- この zip は **HEAD を持たない未コミット作業スナップショット** で、`git rev-parse --verify HEAD` は失敗した。
- `git status --porcelain` では `352 A / 199 AD / 1 ??` を確認した。
- 元の `release_ticket_list.md` に書かれている **実在パス 90 件** のうち、**24 件は作業ツリーでは欠落していたが git index には存在**した。
- そのため、本改定では **git index スナップショットを主たる確認元** とし、作業ツリーは補助確認として扱った。

### 状態の見方
- **完了**: 子タスクの本線実装がコード上で確認できる
- **部分実装**: 本線実装はあるが、互換経路・旧導線・未統合箇所が残る
- **未実装**: 接続や実装をコード上で確認できない

---

## P0（リリースブロッカー）

### REL-P0-01 単一正本へカットオーバーする
- 関連既存チケット: `PP-003`, `PP-056`
- 総合状態: **部分実装**

#### 完了
- アプリ起動時に canonical フラグへ切り替える
  - 確認: `ProjectProfit/ProjectProfitApp.swift` → `FeatureFlags.switchToCanonical()`
- canonical 既定値で legacy ledger 書き込みを拒否する
  - 確認: `ProjectProfit/App/FeatureFlags.swift`, `ProjectProfit/Ledger/Services/LedgerDataStore.swift`
- 手入力の新規保存を `PPTransaction` 直生成ではなく draft candidate 保存へ切り替える
  - 確認: `ProjectProfit/Views/Components/TransactionFormView.swift`, `ProjectProfit/Application/UseCases/Posting/PostingIntakeUseCase.swift`
- canonical 有効時の取引画面文言を候補ベース UI に切り替える
  - 確認: `ProjectProfit/Views/Transactions/TransactionsView.swift`
- 手入力候補承認・定期候補承認・CSV import で canonical journal を作成する
  - 確認: `ProjectProfit/Services/DataStore.swift` → `approvePostingCandidate(...)`, `approveRecurringItems(...)`, `importTransactions(from:)`
- `processRecurringTransactions()` の write path を canonical posting 保存へ統一する
  - 確認: `ProjectProfit/Services/DataStore.swift` → `processRecurringTransactions()`, `saveApprovedPostingSync(...)`
- canonical 有効時にユーザー起点の legacy transaction 変更を止める
  - 確認: `ProjectProfit/Services/DataStore.swift` → `guardLegacyTransactionMutationAllowed(...)`
- production UI / ViewModel から legacy transaction mutation 呼び出しを外す
  - 確認: `ProjectProfit/Views/`, `ProjectProfit/Features/`, `ProjectProfit/ViewModels/` 内で `addTransactionResult(...)`, `updateTransaction(...)`, `deleteTransaction(...)` の参照なし
- 上記 cutover 主要経路のテストコードが存在する
  - 確認: `ProjectProfitTests/DataStoreAccountingTests.swift`

#### 部分実装
- 互換ヘルパーとして `addTransactionResult(...)` が残っている
  - 確認: `ProjectProfit/Services/DataStore.swift`
- 互換同期用の `syncCanonicalArtifacts(forTransactionId:)` は `#if DEBUG` 配下に残っている
  - 確認: `ProjectProfit/Services/DataStore.swift`
- legacy transaction 系 API は完全撤去ではなく「ユーザー起点のみ禁止」の止め方になっている
  - 確認: `ProjectProfit/Services/DataStore.swift`

#### 未実装
- 該当なし

### REL-P0-02 Repository / UseCase 層を完成させる
- 関連既存チケット: `PP-010`
- 総合状態: **部分実装**

#### 完了
- canonical 主要集約の repository 実装を配置する
  - 確認: `ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/`
- masters / evidence / filing / journals / posting / distribution の UseCase 実装を配置する
  - 確認: `ProjectProfit/Application/UseCases/`
- Receipt review を evidence intake use case へ接続する
  - 確認: `ProjectProfit/Views/Receipt/ReceiptReviewView.swift`
- Approval Queue を posting workflow use case へ接続する
  - 確認: `ProjectProfit/Features/ApprovalQueue/ApprovalQueueView.swift`
- Profile settings 保存を canonical profile use case 経由へ接続する
  - 確認: `ProjectProfit/Views/Settings/ProfileSettingsView.swift`, `ProjectProfit/Application/UseCases/Masters/ProfileSettingsWorkflowUseCase.swift`
- 手入力候補保存を posting intake use case 経由へ接続する
  - 確認: `ProjectProfit/Views/Components/TransactionFormView.swift`, `ProjectProfit/Application/UseCases/Posting/PostingIntakeUseCase.swift`
- 定期候補承認と CSV import を async canonical path へ接続する
  - 確認: `ProjectProfit/Features/Recurring/RecurringPreviewView.swift`, `ProjectProfit/Application/UseCases/Recurring/RecurringWorkflowUseCase.swift`, `ProjectProfit/Application/UseCases/Posting/PostingIntakeUseCase.swift`
- 定期取引の作成 / 更新 / 削除 / 有効化 / スキップ / 通知更新を recurring workflow use case へ接続する
  - 確認: `ProjectProfit/Views/Components/RecurringFormView.swift`, `ProjectProfit/ViewModels/RecurringViewModel.swift`, `ProjectProfit/Application/UseCases/Recurring/RecurringWorkflowUseCase.swift`
- settings の全削除を maintenance use case 経由へ接続する
  - 確認: `ProjectProfit/Views/Settings/SettingsView.swift`, `ProjectProfit/Features/Settings/Presentation/Screens/SettingsMainView.swift`, `ProjectProfit/Application/UseCases/Settings/SettingsMaintenanceUseCase.swift`
- project の作成 / 更新 / 単体削除 / 一括削除を project workflow use case へ接続する
  - 確認: `ProjectProfit/Views/Components/ProjectFormView.swift`, `ProjectProfit/ViewModels/ProjectsViewModel.swift`, `ProjectProfit/Application/UseCases/Projects/ProjectWorkflowUseCase.swift`, `ProjectProfit/Core/Domain/Projects/ProjectRepository.swift`
- inventory の保存更新を inventory workflow use case へ接続する
  - 確認: `ProjectProfit/Views/Accounting/InventoryInputView.swift`, `ProjectProfit/ViewModels/InventoryViewModel.swift`, `ProjectProfit/Application/UseCases/Inventory/InventoryWorkflowUseCase.swift`, `ProjectProfit/Core/Domain/Inventory/InventoryRepository.swift`
- closing 画面の決算仕訳生成 / 再生成 / 年度状態更新を closing workflow use case 経由へ接続する
  - 確認: `ProjectProfit/Views/Accounting/ClosingEntryView.swift`, `ProjectProfit/Application/UseCases/Closing/ClosingWorkflowUseCase.swift`
- fixed asset の作成 / 更新 / 除却 / 削除 / 償却計上を fixed asset workflow use case へ接続する
  - 確認: `ProjectProfit/Views/Accounting/FixedAssetFormView.swift`, `ProjectProfit/Views/Accounting/FixedAssetDetailView.swift`, `ProjectProfit/Views/Accounting/FixedAssetListView.swift`, `ProjectProfit/Application/UseCases/FixedAssets/FixedAssetWorkflowUseCase.swift`, `ProjectProfit/Core/Domain/FixedAssets/FixedAssetRepository.swift`
- category の作成 / 更新 / アーカイブ / 復元 / linked account 更新を category workflow use case へ接続する
  - 確認: `ProjectProfit/Features/Masters/Categories/Presentation/Screens/CategoryListView.swift`, `ProjectProfit/Views/Components/CategoryManageView.swift`, `ProjectProfit/Views/Accounting/CategoryAccountMappingView.swift`, `ProjectProfit/Application/UseCases/Masters/CategoryWorkflowUseCase.swift`, `ProjectProfit/Core/Domain/Categories/CategoryRepository.swift`
- documents の追加 / 削除確認 / 台帳一覧読込を document workflow use case へ接続する
  - 確認: `ProjectProfit/Views/Transactions/TransactionDocumentsView.swift`, `ProjectProfit/Views/Accounting/LegalDocumentLedgerView.swift`, `ProjectProfit/Application/UseCases/Documents/DocumentWorkflowUseCase.swift`, `ProjectProfit/Core/Domain/Documents/DocumentRepository.swift`

#### 部分実装
- `DataStore` が orchestration と永続化更新の両方を引き続き持っている
  - 確認: `ProjectProfit/Services/DataStore.swift`
- `DataStore` に直接 mutation API が残っている
  - 確認: `addTransactionResult(...)`, `updateTransaction(...)`, `processRecurringTransactions()`, `importTransactions(from:)`
- 旧 UI / service 経路が `DataStore` を直接参照している
  - 確認: `ProjectProfit/Views/Report/ReportView.swift`, `ProjectProfit/ViewModels/TransactionsViewModel.swift`, `ProjectProfit/Views/Accounting/ManualJournalFormView.swift`

#### 未実装
- UI からの直接 mutation を UseCase / Repository 境界へ完全移管する
- `DataStore` の直接依存を旧画面・旧 service から全面的に縮退する

### REL-P0-03 `PPAccountingProfile` 依存を切って `BusinessProfile` / `TaxYearProfile` に移行する
- 関連既存チケット: `PP-005`
- 総合状態: **部分実装**

#### 完了
- profile settings の正本を `BusinessProfile` / `TaxYearProfile` に置く
  - 確認: `ProjectProfit/Application/UseCases/Masters/ProfileSettingsUseCase.swift`
- `DataStore` から canonical profile load / save を呼ぶ
  - 確認: `ProjectProfit/Services/DataStore.swift` → `reloadProfileSettings()`, `saveProfileSettings(...)`
- profile settings UI を canonical 保存経路へ接続する
  - 確認: `ProjectProfit/Views/Settings/ProfileSettingsView.swift`
- backup payload を canonical profile 主体で組み立てる
  - 確認: `ProjectProfit/Infrastructure/FileStorage/BackupService.swift`
- secure payload の business 識別子を canonical UUID 優先で扱う
  - 確認: `ProjectProfit/Infrastructure/FileStorage/BackupService.swift`
- restore を canonical profile 先行で行い、欠落時のみ legacy profile を補完する
  - 確認: `ProjectProfit/Infrastructure/FileStorage/RestoreService.swift`
- 既に migrated と判定された場合でも secure payload の legacy → canonical 載せ替えを実行する
  - 確認: `ProjectProfit/Application/Migrations/LegacyProfileMigrationRunner.swift`

#### 部分実装
- legacy model `PPAccountingProfile` が互換用途で残っている
  - 確認: `ProjectProfit/Models/PPAccountingProfile.swift`
- backup / restore 用 snapshot モデルに legacy accounting profile が残っている
  - 確認: `ProjectProfit/Infrastructure/FileStorage/AppSnapshotModels.swift`
- restore 側に legacy profile upsert が残っている
  - 確認: `ProjectProfit/Infrastructure/FileStorage/RestoreService+Upserts.swift`

#### 未実装
- backup / restore / migration 互換入力から `PPAccountingProfile` 依存を完全除去する
- legacy accounting profile 用 schema / upsert / migration 分岐を全面撤去する

### REL-P0-04 TaxYearPack を本番経路に接続し、2026年分を埋める
- 関連既存チケット: `PP-015`
- 総合状態: **完了**

#### 完了
- filing 定義を `TaxYearPacks/<year>/filing/*.json` から組み立てる
  - 確認: `ProjectProfit/Services/TaxYearDefinitionLoader.swift`
- 2025 年分 filing 定義を配置する
  - 確認: `ProjectProfit/Resources/TaxYearPacks/2025/filing/`
- 2026 年分 filing 定義を配置する
  - 確認: `ProjectProfit/Resources/TaxYearPacks/2026/filing/`
- 2025 / 2026 の consumption tax ルールを配置する
  - 確認: `ProjectProfit/Resources/TaxYearPacks/2025/consumption_tax/rules.json`, `ProjectProfit/Resources/TaxYearPacks/2026/consumption_tax/rules.json`
- pack provider で profile と消費税ルールをマージして `TaxYearPack` を返す
  - 確認: `ProjectProfit/Infrastructure/TaxYearPack/BundledTaxYearPackProvider.swift`
- 税ルール評価で pack の経過措置・少額特例を使う
  - 確認: `ProjectProfit/Core/Domain/Tax/TaxRuleEvaluator.swift`
- e-Tax export / XTX export / form build を TaxYearPack 読み込みへ接続する
  - 確認: `ProjectProfit/ViewModels/EtaxExportViewModel.swift`, `ProjectProfit/Services/EtaxXtxExporter.swift`, `ProjectProfit/Services/FormEngine.swift`
- 旧 `TaxYear2025.json` / `TaxYear2026.json` は本体参照から外れている
  - 確認: repo 全体検索で参照なし

#### 部分実装
- 該当なし

#### 未実装
- 該当なし

### REL-P0-05 税務状態エンジンを UI / 出力 / ロックに接続する
- 関連既存チケット: `PP-017`
- 総合状態: **部分実装**

#### 完了
- filing style / VAT / year lock の遷移検証を use case に集約する
  - 確認: `ProjectProfit/Application/UseCases/Filing/TaxYearStateUseCase.swift`
- profile 保存時に税務状態遷移検証を必ず通す
  - 確認: `ProjectProfit/Application/UseCases/Masters/ProfileSettingsUseCase.swift`
- year lock の runtime 判定を canonical tax year profile から読む
  - 確認: `ProjectProfit/Services/DataStore+YearLock.swift`
- closing entry 画面で preflight / year state を参照する
  - 確認: `ProjectProfit/Views/Accounting/ClosingEntryView.swift`
- e-Tax export 前に preflight / year state を参照する
  - 確認: `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
- export coordinator 側でも preflight / year state を参照する
  - 確認: `ProjectProfit/Services/ExportCoordinator.swift`
- legacy `lockedYears` を canonical `yearLockState` へ移送する
  - 確認: `ProjectProfit/Application/Migrations/LegacyProfileMigrationRunner.swift`

#### 部分実装
- `PPAccountingProfile.lockedYears` が互換用途で残っている
  - 確認: `ProjectProfit/Models/PPAccountingProfile.swift`
- snapshot / restore / migration 周辺に `lockedYears` 互換経路が残っている
  - 確認: `ProjectProfit/Infrastructure/FileStorage/AppSnapshotModels.swift`, `ProjectProfit/Infrastructure/FileStorage/RestoreService+Upserts.swift`

#### 未実装
- `lockedYears` 互換フィールドと互換復元経路を完全撤去する

### REL-P0-06 TaxCode master と消費税ルールを canonical 側へ統合する
- 関連既存チケット: `PP-018`, `PP-019`, `PP-045`
- 総合状態: **部分実装**

#### 完了
- evidence intake request で `taxCodeId` を受ける
  - 確認: `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`
- evidence intake で canonical `TaxCode.resolve(id:)` を使う
  - 確認: `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`
- receipt review から `taxCodeId` を intake request へ渡す
  - 確認: `ProjectProfit/Views/Receipt/ReceiptReviewView.swift`
- 手入力 candidate 保存で `selectedTaxCode` を `taxCodeId` として保存する
  - 確認: `ProjectProfit/Views/Components/TransactionFormView.swift`
- transaction bootstrap bridge が `taxCodeId` を優先して canonical 税コードへ解決する
  - 確認: `ProjectProfit/Services/AccountingBootstrapService.swift`
- canonical journal と `TaxCode` から消費税集計を生成する
  - 確認: `ProjectProfit/Services/ConsumptionTaxReportService.swift`

#### 部分実装
- `TaxCode` に `legacyCategory` と legacy 解決 API が残っている
  - 確認: `ProjectProfit/Core/Domain/Tax/TaxCode.swift`
- transaction / form / store 側に legacy 税表現が残っている
  - 確認: `ProjectProfit/Models/Models.swift`, `ProjectProfit/Services/DataStore.swift`, `ProjectProfit/Views/Components/TransactionFormView.swift`
- bootstrap bridge が tax code 未設定時に legacy 税表現へフォールバックする
  - 確認: `ProjectProfit/Services/AccountingBootstrapService.swift`

#### 未実装
- `taxCategory` / `taxRate` / `isTaxIncluded` を main path から完全撤去する
- 税区分入力・保存・集計を `taxCodeId` 正本に一本化する

### REL-P0-07 Evidence intake パイプラインを作り、Receipt 直登録をやめる
- 関連既存チケット: `PP-022`, `PP-023`, `PP-029`
- 総合状態: **完了**

#### 完了
- scanner UI に camera / photo library / PDF import / file import を揃える
  - 確認: `ProjectProfit/Views/Receipt/ReceiptScannerView.swift`
- share extension からアプリグループ inbox へ受け渡す
  - 確認: `ProjectProfitShareExtension/Info.plist`, `ProjectProfitShareExtension/ShareViewController.swift`
- share inbox を pending queue として保持する
  - 確認: `ProjectProfit/Services/ShareImportInboxService.swift`
- share-in → inbox → scanner の導線を接続する
  - 確認: `ProjectProfit/Features/EvidenceInbox/EvidenceInboxView.swift`, `ProjectProfit/Views/Receipt/ReceiptScannerView.swift`
- receipt review 完了時に evidence intake use case を呼ぶ
  - 確認: `ProjectProfit/Views/Receipt/ReceiptReviewView.swift`
- intake で `EvidenceDocument` と `PostingCandidate` を同時生成する
  - 確認: `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`
- intake で `fileHash` 重複を拒否する
  - 確認: `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`
- share inbox item を intake 成功後にだけ消費する
  - 確認: `ProjectProfit/Views/Receipt/ReceiptScannerView.swift` → `onIntakeSucceeded`, `consumeSharedImportIfNeeded()`, `ShareImportInboxService.markConsumed(_:)`
- shared PDF と review 側の PDF 判定条件を一致させる
  - 確認: `ProjectProfit/Views/Receipt/ReceiptScannerView.swift`, `ProjectProfit/Views/Receipt/ReceiptReviewView.swift`
- receipt review 完了後に `PPTransaction` を直生成する経路は確認できない
  - 確認: receipt review / intake / scanner 周辺を再確認

#### 部分実装
- 該当なし

#### 未実装
- 該当なし

### REL-P0-08 PostingCandidate フローと PostingEngine を実装する
- 関連既存チケット: `PP-030`, `PP-031`, `PP-032`
- 総合状態: **部分実装**

#### 完了
- posting workflow use case に candidate 保存・承認・取消・再レビュー・仕訳生成を実装する
  - 確認: `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift`
- approval queue を canonical candidate UUID ベース UI へ接続する
  - 確認: `ProjectProfit/Features/ApprovalQueue/ApprovalQueueView.swift`
- bootstrap bridge を `TransactionSnapshot` 入力に差し替える
  - 確認: `ProjectProfit/Services/AccountingBootstrapService.swift`
- 手入力保存で draft candidate を保存する
  - 確認: `ProjectProfit/Services/DataStore.swift` → `saveManualPostingCandidate(...)`
- 候補承認・定期承認・CSV import で canonical journal を作る
  - 確認: `ProjectProfit/Services/DataStore.swift`
- 非 mirror の approved candidate を summary 補完へ反映する
  - 確認: `ProjectProfit/Services/DataStore.swift` → `canonicalSupplementalSummaryRecords(...)`
- posting 周辺の主要 canonical 経路を検証するテストコードが存在する
  - 確認: `ProjectProfitTests/DataStoreAccountingTests.swift`

#### 部分実装
- production caller の add / update / delete が `AccountingEngine` 一本ではない
  - 確認: `ProjectProfit/Services/DataStore.swift`
- approved candidate 同期の互換経路が残っている
  - 確認: `ProjectProfit/Services/DataStore.swift` → `PostingWorkflowUseCase.syncApprovedCandidate(...)`
- legacy bridge と summary 補完で canonical / legacy 併存を吸収している
  - 確認: `ProjectProfit/Services/DataStore.swift`, `ProjectProfit/Services/AccountingBootstrapService.swift`

#### 未実装
- `processRecurringTransactions()` など legacy bridge を外し、posting 周辺の本線を canonical engine のみに統一する
- transaction add / update / delete の production path を canonical posting engine に一本化する

### REL-P0-09 承認・取消・監査ログ・締め前チェックを一つのフローにする
- 関連既存チケット: `PP-033`, `PP-046`, `PP-051`
- 総合状態: **完了**

#### 完了
- candidate 承認・却下・取消・取消後再レビュー・再オープンの use case を実装する
  - 確認: `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift`
- intake 時の監査イベントを保存する
  - 確認: `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`
- posting workflow 時の監査イベントを保存する
  - 確認: `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift`
- preflight で不整合 / 保留候補 / 未マップ / closing / year state を検査する
  - 確認: `ProjectProfit/Application/UseCases/Filing/FilingPreflightUseCase.swift`
- export coordinator から preflight blocker を評価する
  - 確認: `ProjectProfit/Services/ExportCoordinator.swift`
- e-Tax export view model から preflight blocker を評価する
  - 確認: `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
- journal detail 画面に取消 → 再レビュー導線を持つ
  - 確認: `ProjectProfit/Views/Accounting/JournalDetailView.swift`

#### 部分実装
- 該当なし

#### 未実装
- 該当なし

### REL-P0-10 Evidence / Journal 検索インデックスを実装する
- 関連既存チケット: `PP-012`
- 総合状態: **完了**

#### 完了
- evidence 検索条件モデルを定義する
  - 確認: `ProjectProfit/Core/Domain/Evidence/EvidenceSearchCriteria.swift`
- evidence / journal 用検索 index entity を持つ
  - 確認: `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/EvidenceSearchIndexEntity.swift`, `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/JournalSearchIndexEntity.swift`
- local evidence search index を実装する
  - 確認: `ProjectProfit/Infrastructure/Search/LocalEvidenceSearchIndex.swift`
- local journal search index を実装する
  - 確認: `ProjectProfit/Infrastructure/Search/LocalJournalSearchIndex.swift`
- index 再構築サービスを実装する
  - 確認: `ProjectProfit/Infrastructure/Search/SearchIndexRebuilder.swift`
- evidence inbox から再索引できる
  - 確認: `ProjectProfit/Features/EvidenceInbox/EvidenceInboxView.swift`
- journal list から再索引できる
  - 確認: `ProjectProfit/Views/Accounting/JournalListView.swift`
- performance gate 用検索 seed 規模を定義している
  - 確認: `ProjectProfitTests/ReleasePerformanceGateTests.swift` → `CorpusSize.search = 1_000`

#### 部分実装
- 該当なし

#### 未実装
- 該当なし

### REL-P0-11 Migration Runner と backup/restore を先に入れる
- 関連既存チケット: `PP-013`, `PP-014`
- 総合状態: **完了**

#### 完了
- migration dry-run / 差分 / orphan 検出 runner を実装する
  - 確認: `ProjectProfit/Application/Migrations/MigrationReportRunner.swift`
- backup service を実装する
  - 確認: `ProjectProfit/Infrastructure/FileStorage/BackupService.swift`
- restore service を実装する
  - 確認: `ProjectProfit/Infrastructure/FileStorage/RestoreService.swift`
- execute migration を実装する
  - 確認: `ProjectProfit/Application/Migrations/LegacyDataMigrationExecutor.swift`
- settings 画面から backup / restore / migration rehearsal / execute を触れる
  - 確認: `ProjectProfit/Views/Settings/SettingsView.swift`, `ProjectProfit/Features/Settings/Presentation/Screens/SettingsMainView.swift`
- backup/restore と canonical flow E2E のテストコードが存在する
  - 確認: `ProjectProfitTests/BackupRestoreServiceTests.swift`, `ProjectProfitTests/CanonicalFlowE2ETests.swift`

#### 部分実装
- 該当なし

#### 未実装
- 該当なし

### REL-P0-12 Golden / E2E / 性能ゲートを閉じる
- 関連既存チケット: `PP-055`
- 総合状態: **部分実装**

#### 完了
- golden baseline テスト群を配置する
  - 確認: `ProjectProfitTests/Golden/GoldenBaselineTests.swift`
- canonical flow E2E テスト群を配置する
  - 確認: `ProjectProfitTests/CanonicalFlowE2ETests.swift`
- release performance gate テスト群を配置する
  - 確認: `ProjectProfitTests/ReleasePerformanceGateTests.swift`
- GitHub Actions に release quality workflow を配置する
  - 確認: `.github/workflows/release-quality.yml`
- workflow に golden / canonical-e2e / migration rehearsal / performance gate の job を持つ
  - 確認: `.github/workflows/release-quality.yml`

#### 部分実装
- zip 内コードだけでは、最新時点の golden baseline 再実行結果までは確認できない
- 同様に E2E / performance の最新実行成否は、コード存在と workflow 定義までは確認できるが、再実行結果そのものは未確認

#### 未実装
- この zip 単体で未確認だった gate 実行結果の再検証記録をコード管理物として揃える
- golden baseline を含む release gate の最新 green 根拠をリポジトリ内で追跡可能な形に固定する

---

## P1（正式リリース前に入れたい重要機能）

### REL-P1-01 取引先マスタと T番号照合を実装する
- 関連既存チケット: `PP-006`, `PP-025`
- 総合状態: **完了**

#### 完了
- 取引先マスタ use case に load / search / save / delete を持つ
  - 確認: `ProjectProfit/Application/UseCases/Masters/CounterpartyMasterUseCase.swift`
- T番号での直接検索を持つ
  - 確認: `ProjectProfit/Application/UseCases/Masters/CounterpartyMasterUseCase.swift`
- OCR 候補から取引先候補を解決する
  - 確認: `ProjectProfit/Application/UseCases/Masters/CounterpartyMasterUseCase.swift`
- 取引先フォームで T番号を編集できる
  - 確認: `ProjectProfit/Features/Masters/Counterparties/Presentation/Screens/CounterpartyFormView.swift`
- 取引先フォームで税区分・デフォルト勘定・デフォルトプロジェクトを編集できる
  - 確認: `ProjectProfit/Features/Masters/Counterparties/Presentation/Screens/CounterpartyFormView.swift`
- evidence intake で OCR 抽出名と登録番号から既存取引先照合を行う
  - 確認: `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`
- intake で照合できない場合に候補生成 / 新規作成へフォールバックする
  - 確認: `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`

#### 部分実装
- 該当なし

#### 未実装
- 該当なし

### REL-P1-02 Chart of Accounts v2 と custom account CRUD を実装する
- 関連既存チケット: `PP-007`
- 総合状態: **完了**

#### 完了
- chart of accounts 画面から add を行える
  - 確認: `ProjectProfit/Views/Accounting/ChartOfAccountsView.swift`
- chart of accounts 画面から edit を行える
  - 確認: `ProjectProfit/Views/Accounting/ChartOfAccountsView.swift`
- chart of accounts 画面から archive を行える
  - 確認: `ProjectProfit/Views/Accounting/ChartOfAccountsView.swift`
- account form で `defaultLegalReportLineId` を編集できる
  - 確認: `ProjectProfit/Features/Masters/Accounts/Presentation/Screens/AccountFormView.swift`
- account 保存時に `defaultLegalReportLineId` を必須検証する
  - 確認: `ProjectProfit/Application/UseCases/Masters/ChartOfAccountsUseCase.swift`

#### 部分実装
- 該当なし

#### 未実装
- 該当なし

### REL-P1-03 Recurring / Distribution を preview → approve 方式へ再設計する
- 関連既存チケット: `PP-034`, `PP-035`, `PP-036`
- 総合状態: **部分実装**

#### 完了
- recurring preview 画面を持つ
  - 確認: `ProjectProfit/Features/Recurring/RecurringPreviewView.swift`
- 定期実行の preview データを `DataStore.previewRecurringTransactions()` で生成する
  - 確認: `ProjectProfit/Services/DataStore.swift`
- アプリ起動後に pending recurring があれば preview を表示する
  - 確認: `ProjectProfit/Views/ContentView.swift`
- distribution template の CRUD/use case を持つ
  - 確認: `ProjectProfit/Application/UseCases/Distribution/DistributionTemplateUseCase.swift`
- distribution template 適用 use case を持つ
  - 確認: `ProjectProfit/Application/UseCases/Distribution/DistributionTemplateApplicationUseCase.swift`

#### 部分実装
- recurring 側は preview → approve 導線があるが、distribution 側はフォーム内の即時適用が残る
  - 確認: `ProjectProfit/Views/Components/RecurringFormView.swift`, `ProjectProfit/Views/Components/TransactionFormView.swift`
- distribution 割当生成は use case を使っているが、承認キューと分離された preview ステップは確認できない
  - 確認: `ProjectProfit/Application/UseCases/Distribution/DistributionTemplateApplicationUseCase.swift`

#### 未実装
- distribution を preview → approve ワークフローへ再設計する
- recurring / distribution を同じ候補承認体験へ統一する

### REL-P1-04 canonical 帳簿生成エンジンに統一する
- 関連既存チケット: `PP-039`, `PP-041`, `PP-044`
- 総合状態: **部分実装**

#### 完了
- canonical journal 向け帳票 API を持つ
  - 確認: `ProjectProfit/Services/AccountingReportService.swift`
- export coordinator で projected canonical journals を使う
  - 確認: `ProjectProfit/Services/ExportCoordinator.swift`
- canonical projection を `DataStore.projectedCanonicalJournals(...)` から取得できる
  - 確認: `ProjectProfit/Services/DataStore.swift`

#### 部分実装
- `AccountingReportService` に legacy API と canonical API が並存している
  - 確認: `ProjectProfit/Services/AccountingReportService.swift`
- 帳簿生成の一部は canonical projection を使うが、legacy 型を受ける経路も残る
  - 確認: `ProjectProfit/Services/AccountingReportService.swift`

#### 未実装
- `PPJournalEntry` / `PPJournalLine` 前提の帳簿生成 API を縮退し、帳簿生成を canonical 側へ一本化する
- `BookProjectionEngine` / `BookSpecRegistry` 相当の専用統一レイヤを実装する
  - 確認: repo 全体検索で該当名なし

### REL-P1-05 FormEngine を完成させ、現金主義様式まで広げる
- 関連既存チケット: `PP-047`, `PP-048`, `PP-049`, `PP-050`
- 総合状態: **部分実装**

#### 完了
- FormEngine が青色一般・青色現金主義・白色を扱う
  - 確認: `ProjectProfit/Services/FormEngine.swift`
- form type に `blueCashBasis` を持つ
  - 確認: `ProjectProfit/Models/EtaxModels.swift`
- 2025 / 2026 の filing pack に現金主義様式 JSON を配置する
  - 確認: `ProjectProfit/Resources/TaxYearPacks/2025/filing/`, `ProjectProfit/Resources/TaxYearPacks/2026/filing/`

#### 部分実装
- 一部 builder が legacy 帳簿型を受ける互換 API のまま残っている
  - 確認: `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
- form build 全体が canonical projection のみで完結する構成にはまだなっていない
  - 確認: `ShushiNaiyakushoBuilder.swift` が `PPAccount` / `PPJournalEntry` / `PPJournalLine` を受ける

#### 未実装
- form build を canonical projection 入力へ統一する
- legacy 帳簿型依存の builder / adapter を縮退する

### REL-P1-06 設定 / マスタ UI を再設計する
- 関連既存チケット: `PP-053`
- 総合状態: **完了**

#### 完了
- 新 settings 画面を配置する
  - 確認: `ProjectProfit/Features/Settings/Presentation/Screens/SettingsMainView.swift`
- profile settings 画面で canonical profile / tax year profile を編集できる
  - 確認: `ProjectProfit/Views/Settings/ProfileSettingsView.swift`
- account form を新 UI として配置する
  - 確認: `ProjectProfit/Features/Masters/Accounts/Presentation/Screens/AccountFormView.swift`
- counterparty form を新 UI として配置する
  - 確認: `ProjectProfit/Features/Masters/Counterparties/Presentation/Screens/CounterpartyFormView.swift`
- distribution template 管理 UI を配置する
  - 確認: `ProjectProfit/Features/Masters/DistributionTemplates/Presentation/Screens/DistributionTemplateListView.swift`

#### 部分実装
- 該当なし

#### 未実装
- 該当なし

### REL-P1-07 ワークフロー UI を繋ぐ
- 関連既存チケット: `PP-054`
- 総合状態: **部分実装**

#### 完了
- main tab に evidence inbox を置く
  - 確認: `ProjectProfit/Views/ContentView.swift`
- main tab に approval queue を置く
  - 確認: `ProjectProfit/Views/ContentView.swift`
- filing dashboard 画面を配置する
  - 確認: `ProjectProfit/Features/Filing/Presentation/Screens/FilingDashboardView.swift`
- journal browser 画面を配置する
  - 確認: `ProjectProfit/Features/Journals/Presentation/Screens/JournalBrowserView.swift`
- settings main view を main tab に置く
  - 確認: `ProjectProfit/Views/ContentView.swift`

#### 部分実装
- main tab のレポート導線はまだ旧 `ReportView` を使っている
  - 確認: `ProjectProfit/Views/ContentView.swift`, `ProjectProfit/Views/Report/ReportView.swift`
- 旧 `AccountingHomeView` が残っている
  - 確認: `ProjectProfit/Views/Accounting/AccountingHomeView.swift`

#### 未実装
- filing / journals / reports / approvals を新 workflow UI に統一し、旧導線を整理する
- `ReportView` / `AccountingHomeView` ベースの旧遷移を縮退する

### REL-P1-08 ExportCoordinator へ出力系を集約する
- 関連既存チケット: `PP-052`
- 総合状態: **部分実装**

#### 完了
- 共通 export coordinator を実装する
  - 確認: `ProjectProfit/Services/ExportCoordinator.swift`
- export menu ボタンを共通 UI として実装する
  - 確認: `ProjectProfit/Views/Components/ExportMenuButton.swift`
- PL / BS / TB / Journal / Ledger / Fixed Assets を export menu に寄せる
  - 確認: `ProjectProfit/Views/Accounting/ProfitLossView.swift`, `BalanceSheetView.swift`, `TrialBalanceView.swift`, `JournalListView.swift`, `LedgerView.swift`, `FixedAssetListView.swift`
- transaction CSV export を export coordinator に寄せる
  - 確認: `ProjectProfit/ViewModels/TransactionsViewModel.swift`
- sub ledger export を export coordinator に寄せる
  - 確認: `ProjectProfit/Views/Accounting/SubLedgerView.swift`
- e-Tax の XTX / CSV export を export coordinator に寄せる
  - 確認: `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
- coordinator 側で target / format / preflight 判定を持つ
  - 確認: `ProjectProfit/Services/ExportCoordinator.swift`
- export coordinator のテストコードが存在する
  - 確認: `ProjectProfitTests/ExportCoordinatorTests.swift`

#### 部分実装
- 個別 export service が互換用途で残っている
  - 確認: `ProjectProfit/Ledger/Services/`
- 出力の入り口はかなり集約されたが、実体 service の完全撤去までは到達していない
  - 確認: repo 全体走査

#### 未実装
- legacy / 個別 export service を縮退し、出力本線を `ExportCoordinator` に完全統一する

---

## P2（初回正式版の後でもよいが、ロードマップには入れるべきもの）

### REL-P2-01 銀行 / カード照合を実装する
- 関連既存チケット: `PP-038`
- 総合状態: **未実装**

#### 完了
- 該当なし

#### 部分実装
- 該当なし

#### 未実装
- 銀行明細取込を実装する
- カード明細取込を実装する
- 消込 / 照合ロジックを実装する
- 照合 UI を実装する
  - 確認: repo 全体検索で対応コードを確認できない

### REL-P2-02 User Rule Engine とローカル学習メモリを実装する
- 関連既存チケット: `PP-037`
- 総合状態: **部分実装**

#### 完了
- `PPUserRule` モデルを持つ
  - 確認: `ProjectProfit/Models/PPUserRule.swift`
- user rule / 辞書 / フォールバックの分類エンジンを持つ
  - 確認: `ProjectProfit/Services/ClassificationEngine.swift`
- 手動分類修正から user rule を学習するサービスを持つ
  - 確認: `ProjectProfit/Services/ClassificationLearningService.swift`
- 分類結果と user rule を扱う view model を持つ
  - 確認: `ProjectProfit/ViewModels/ClassificationViewModel.swift`
- 未分類取引 UI から分類修正を学習へ返す導線がある
  - 確認: `ProjectProfit/Views/Accounting/UnclassifiedTransactionsView.swift`

#### 部分実装
- 学習対象が `PPTransaction` ベースで、canonical candidate / evidence workflow への統合は確認できない
  - 確認: `ProjectProfit/Services/ClassificationLearningService.swift`, `ProjectProfit/ViewModels/ClassificationViewModel.swift`
- rule 適用の主経路が旧 transaction 分類に寄っている
  - 確認: `ProjectProfit/Services/ClassificationEngine.swift`

#### 未実装
- user rule engine を main workflow（candidate 生成 / 承認前レビュー）へ統合する
- ローカル学習メモリを canonical evidence / candidate 単位へ広げる
- candidate feedback loop を approval workflow と接続する

### REL-P2-03 源泉徴収 / 支払調書の基礎モデルを入れる
- 関連既存チケット: `PP-021`
- 総合状態: **部分実装**

#### 完了
- 源泉徴収税コードを定義する
  - 確認: `ProjectProfit/Core/Domain/Tax/WithholdingTaxCode.swift`
- 源泉徴収税計算器を実装する
  - 確認: `ProjectProfit/Core/Domain/Tax/WithholdingTaxCalculator.swift`
- 取引先の payee 情報モデルを持つ
  - 確認: `ProjectProfit/Core/Domain/Counterparties/PayeeInfo.swift`
- 取引先ドメインに payee 情報を保持する
  - 確認: `ProjectProfit/Core/Domain/Counterparties/Counterparty.swift`
- posting candidate line / journal line に源泉徴収属性を保持する
  - 確認: `ProjectProfit/Core/Domain/Posting/PostingCandidateLine.swift`, `ProjectProfit/Core/Domain/Posting/JournalLine.swift`
- 永続化 entity / mapper に源泉徴収属性を通す
  - 確認: `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/JournalLineEntity.swift`, `ProjectProfit/Application/Mappers/JournalLineEntityMapper.swift`, `ProjectProfit/Application/Mappers/CounterpartyEntityMapper.swift`

#### 部分実装
- 基礎モデルと計算器はあるが、専用 UI / dedicated workflow までは確認できない
  - 確認: repo 全体走査

#### 未実装
- 支払調書の作成 UI を実装する
- 支払調書の出力フローを実装する
- 源泉徴収対象取引の end-to-end workflow を main path に接続する

### REL-P2-04 Import チャネルの残タスクを詰める
- 関連既存チケット: `PP-023`
- 総合状態: **部分実装**

#### 完了
- camera / photo / PDF / file import を持つ
  - 確認: `ProjectProfit/Views/Receipt/ReceiptScannerView.swift`
- share extension からの share-in を持つ
  - 確認: `ProjectProfitShareExtension/ShareViewController.swift`
- app group inbox で受け取りを保持する
  - 確認: `ProjectProfit/Services/ShareImportInboxService.swift`
- CSV import の canonical 取込経路を持つ
  - 確認: `ProjectProfit/Services/DataStore.swift` → `importTransactions(from:)`

#### 部分実装
- legacy ledger CSV import service が残っている
  - 確認: `ProjectProfit/Ledger/Services/LedgerCSVImportService.swift`
- CSV import は canonical journal 生成へ接続されるが、evidence draft / candidate queue 経由ではない
  - 確認: `ProjectProfit/Services/DataStore.swift`

#### 未実装
- CSV / 外部 import を evidence draft / posting candidate フローへ統合する
- legacy ledger import service を縮退する

### REL-P2-05 リリース補助ファイルを repo 管理に寄せる
- 関連既存チケット: 独立追加
- 総合状態: **部分実装**

#### 完了
- privacy manifest を repo に含める
  - 確認: `ProjectProfit/PrivacyInfo.xcprivacy`
- privacy manifest を Xcode project に組み込む
  - 確認: `ProjectProfit.xcodeproj/project.pbxproj`
- privacy policy 文書ファイルが repo 内に存在する
  - 確認: `Docs/privacy_policy.md`

#### 部分実装
- support URL の repo 管理物は今回の走査では確認できない
- 独立した release checklist 管理ファイルは今回の走査では確認できない
  - 補足: 計画書内の言及はあるが、専用の checklist ファイルは確認できない

#### 未実装
- support URL を repo 管理物として明示する
- release checklist を repo 管理ファイルとして追加・固定化する

### REL-P2-06 CI を e-Tax 以外へ広げる
- 関連既存チケット: `PP-055` の派生
- 総合状態: **完了**

#### 完了
- e-Tax CI workflow を持つ
  - 確認: `.github/workflows/etax-ci.yml`
- release quality workflow を持つ
  - 確認: `.github/workflows/release-quality.yml`
- release quality workflow に golden baseline / canonical E2E / migration rehearsal / performance gate を持つ
  - 確認: `.github/workflows/release-quality.yml`
- e-Tax 専用以外の books / forms 系 job も持つ
  - 確認: `.github/workflows/release-quality.yml`

#### 部分実装
- 該当なし

#### 未実装
- 該当なし

---

## 付録: 作業ツリーに欠落していたが git index には存在した参照パス
- `ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/`
- `ProjectProfit/Features/Settings/Presentation/Screens/SettingsMainView.swift`
- `ProjectProfit/Application/UseCases/Masters/ProfileSettingsUseCase.swift`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/`
- `ProjectProfit/Resources/TaxYearPacks/2025/consumption_tax/rules.json`
- `ProjectProfit/Core/Domain/Tax/TaxRuleEvaluator.swift`
- `ProjectProfit/Application/UseCases/Filing/TaxYearStateUseCase.swift`
- `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`
- `ProjectProfit/Core/Domain/Tax/TaxCode.swift`
- `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift`
- `ProjectProfit/Application/UseCases/Filing/FilingPreflightUseCase.swift`
- `ProjectProfit/Core/Domain/Evidence/EvidenceSearchCriteria.swift`
- `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/EvidenceSearchIndexEntity.swift`
- `ProjectProfit/Application/UseCases/Masters/CounterpartyMasterUseCase.swift`
- `ProjectProfit/Features/Masters/Counterparties/Presentation/Screens/CounterpartyFormView.swift`
- `ProjectProfit/Features/Masters/Accounts/Presentation/Screens/AccountFormView.swift`
- `ProjectProfit/Application/UseCases/Masters/ChartOfAccountsUseCase.swift`
- `ProjectProfit/Application/UseCases/Distribution/DistributionTemplateUseCase.swift`
- `ProjectProfit/Features/Masters/DistributionTemplates/Presentation/Screens/DistributionTemplateListView.swift`
- `ProjectProfit/Features/Filing/Presentation/Screens/FilingDashboardView.swift`
- `ProjectProfit/Features/Journals/Presentation/Screens/JournalBrowserView.swift`
- `ProjectProfit/Core/Domain/Tax/WithholdingTaxCalculator.swift`
- `ProjectProfit/Core/Domain/Counterparties/PayeeInfo.swift`

## 付録: この改定で補正した点
- 元資料のうち `REL-P2-05` の「privacy policy を repo 管理している証拠が確認できない」は、今回の zip 再確認では **`Docs/privacy_policy.md` が存在**したため、その点だけ事実に合わせて補正した。
- それ以外のチケットは、元のチケット内容を変えず、確認単位を細かくした。
