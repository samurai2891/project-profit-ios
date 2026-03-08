# ProjectProfit リリース向け修正チケット一覧（2026-03-09 実装反映版）

作成日: 2026-03-09  
前提: `/Users/yutaro/project-profit-ios` を二度走査し、2026-03-09 時点の未コミット差分も含めて `release_ticket_list.md` の各項目を現コードに合わせて更新した。  
確認方法:
- 一次確認: `rg` による全体走査で実装有無と参照経路を抽出
- 二次確認: 該当ファイルを開いて active path と補助経路を再確認

状態の意味:
- **完了**: 対象の本線実装がコード上で確認でき、原文の根拠に明確な誤りがある
- **部分実装**: 本線実装はあるが、legacy 依存・互換経路・未統合箇所が残る
- **未実装**: 対応コードを確認できない

---

## P0（リリースブロッカー）

### REL-P0-01 単一正本へカットオーバーする
- 関連既存チケット: `PP-003`, `PP-056`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/ProjectProfitApp.swift` で起動時に `FeatureFlags.switchToCanonical()` を実行している。
  - `ProjectProfit/App/FeatureFlags.swift` では `useCanonicalPosting = true`、`useLegacyLedger = false` を canonical 既定値として扱っている。
  - `ProjectProfit/Ledger/Services/LedgerDataStore.swift` は `FeatureFlags.useLegacyLedger == false` のとき書き込みを拒否する。
  - `ProjectProfit/Views/Components/TransactionFormView.swift` の canonical 新規入力は `DataStore.saveManualPostingCandidate(...)` を呼び、`PPTransaction` を作らず draft candidate として保存する。
  - `ProjectProfit/Views/Transactions/TransactionsView.swift` の canonical 時の空状態ボタンと FAB は `新規取引` ではなく `最初の候補を作成` / `候補を手入力` 表示になっている。
  - `ProjectProfit/Services/DataStore.swift` の `approveRecurringItems(...)` と `importTransactions(from:)` は `saveApprovedPosting(...)` を使い、canonical journal を直接作る。
  - `ProjectProfitTests/DataStoreAccountingTests.swift` には manual candidate 保存、recurring 承認、CSV import の各経路で legacy transaction 件数が増えないことを確認するテストがある。
  - 一方で `ProjectProfit/Services/DataStore.swift` には `addTransactionResult(...)`、`updateTransaction(...)`、`deleteTransaction(...)` が残る。
  - `ProjectProfit/Services/DataStore.swift` の transaction 同期は `PostingWorkflowUseCase.syncApprovedCandidate(...)` を呼ぶため、transaction 起点の posting はまだ即時承認前提である。

### REL-P0-02 Repository / UseCase 層を完成させる
- 関連既存チケット: `PP-010`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/` に `BusinessProfile`、`TaxYearProfile`、`Evidence`、`Counterparty`、`PostingCandidate`、`CanonicalJournalEntry`、`ChartOfAccounts`、`DistributionTemplate`、`Audit` の repository 実装がある。
  - `ProjectProfit/Application/UseCases/` に masters / evidence / filing / journals / posting / distribution の UseCase 実装がある。
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift`、`ProjectProfit/Features/ApprovalQueue/ApprovalQueueView.swift`、`ProjectProfit/Views/Settings/ProfileSettingsView.swift` は UseCase 側へ接続されている。
  - `ProjectProfit/Views/Components/TransactionFormView.swift` の canonical 新規保存は `DataStore.saveManualPostingCandidate(...)` を介して `PostingWorkflowUseCase.saveCandidate(...)` に到達する。
  - `ProjectProfit/Features/Recurring/RecurringPreviewView.swift` は `approveRecurringItems(...)` を await し、`ProjectProfit/Views/Settings/SettingsView.swift` と `ProjectProfit/Features/Settings/Presentation/Screens/SettingsMainView.swift` の CSV import は async で canonical import を呼ぶ。
  - 一方で `ProjectProfit/Services/DataStore.swift` は orchestration と永続化更新を両方持っており、`addTransactionResult(...)`、`updateTransaction(...)`、`processRecurringTransactions()`、import 系処理などの直接 mutation API が残る。
  - `ProjectProfit/Views/Components/TransactionFormView.swift` の edit mode と、`ProjectProfit/Views/Components/RecurringFormView.swift`、`ProjectProfit/Views/Report/ReportView.swift` など、`DataStore` を直接参照する UI / service 経路はまだ残っている。

### REL-P0-03 `PPAccountingProfile` 依存を切って `BusinessProfile` / `TaxYearProfile` に移行する
- 関連既存チケット: `PP-005`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Application/UseCases/Masters/ProfileSettingsUseCase.swift` は `BusinessProfile` / `TaxYearProfile` を正本に読み書きしている。
  - `ProjectProfit/Services/DataStore.swift` の `reloadProfileSettings()` / `saveProfileSettings()` は `legacyProfile` を渡さず canonical load/save を行っている。
  - `ProjectProfit/Views/Settings/ProfileSettingsView.swift` は canonical profile 保存経路に接続されている。
  - 一方で `ProjectProfit/Models/PPAccountingProfile.swift` は model として残っており、`ProjectProfit/Infrastructure/FileStorage/BackupService.swift`、`ProjectProfit/Infrastructure/FileStorage/RestoreService.swift`、`ProjectProfit/Application/Migrations/LegacyProfileMigrationRunner.swift` でも参照が残る。

### REL-P0-04 TaxYearPack を本番経路に接続し、2026年分を埋める
- 関連既存チケット: `PP-015`
- 状態: **完了**
- 根拠:
  - `ProjectProfit/Services/TaxYearDefinitionLoader.swift` は filing 定義を `Resources/TaxYearPacks/<year>/filing/*.json` から組み立てる。
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/` と `ProjectProfit/Resources/TaxYearPacks/2026/filing/` に `common.json`、`blue_general.json`、`blue_cash_basis.json`、`white_shushi.json` がある。
  - `ProjectProfit/Resources/TaxYearPacks/2025/consumption_tax/rules.json` と `2026/consumption_tax/rules.json` がある。
  - `ProjectProfit/Infrastructure/TaxYearPack/BundledTaxYearPackProvider.swift` は `profile.json` と `consumption_tax/rules.json` をマージして `TaxYearPack` を返す。
  - `ProjectProfit/Core/Domain/Tax/TaxRuleEvaluator.swift` は経過措置判定で `pack.transitionalMeasures` と `pack.smallAmountThreshold` を使う。
  - `ProjectProfit/ViewModels/EtaxExportViewModel.swift`、`ProjectProfit/Services/EtaxXtxExporter.swift`、`ProjectProfit/Services/FormEngine.swift` は `TaxYearDefinitionLoader` を介して pack 定義を使っている。
  - `ProjectProfit/Resources/TaxYear2025.json` と `TaxYear2026.json` はリソースとして残るが、`ProjectProfit` 本体コードからの参照は確認できなかった。

### REL-P0-05 税務状態エンジンを UI / 出力 / ロックに接続する
- 関連既存チケット: `PP-017`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Application/UseCases/Filing/TaxYearStateUseCase.swift` は filing style / VAT / year lock の遷移検証を行う。
  - `ProjectProfit/Application/UseCases/Masters/ProfileSettingsUseCase.swift` は保存時に `TaxYearStateUseCase.validateTransition` を必ず通す。
  - `ProjectProfit/Services/DataStore+YearLock.swift` の runtime 判定は `TaxYearProfileEntity.yearLockStateRaw` を読む。
  - `ProjectProfit/Views/Accounting/ClosingEntryView.swift`、`ProjectProfit/ViewModels/EtaxExportViewModel.swift`、`ProjectProfit/Services/ExportCoordinator.swift` は preflight / year state を使っている。
  - 一方で `PPAccountingProfile.lockedYears` は `ProjectProfit/Models/PPAccountingProfile.swift`、`ProjectProfit/Infrastructure/FileStorage/AppSnapshotModels.swift`、`ProjectProfit/Infrastructure/FileStorage/RestoreService+Upserts.swift`、migration 関連に残っている。

### REL-P0-06 TaxCode master と消費税ルールを canonical 側へ統合する
- 関連既存チケット: `PP-018`, `PP-019`, `PP-045`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift` は `ReceiptEvidenceIntakeRequest.taxCodeId` を受け、`TaxCode.resolve(id:)` を使う。
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift` は intake request に `taxCodeId` を詰める。
  - `ProjectProfit/Views/Components/TransactionFormView.swift` の canonical 新規候補保存は `selectedTaxCode?.rawValue` を `taxCodeId` として渡す。
  - `ProjectProfit/Services/AccountingBootstrapService.swift` の `TransactionSnapshot` は `taxCodeId` を持ち、bridge は `taxCodeId` を優先して canonical 税コードを解決する。
  - `ProjectProfit/Services/ConsumptionTaxReportService.swift` は canonical `JournalEntry` と `TaxCode` から worksheet / summary を生成する。
  - 一方で `ProjectProfit/Core/Domain/Tax/TaxCode.swift` には `legacyCategory` と `resolve(legacyCategory:taxRate:)` が残る。
  - `ProjectProfit/Models/Models.swift`、`ProjectProfit/Services/DataStore.swift`、`ProjectProfit/Views/Components/TransactionFormView.swift` などには `taxCategory` / `taxRate` / `isTaxIncluded` の legacy transaction 表現が残る。

### REL-P0-07 Evidence intake パイプラインを作り、Receipt 直登録をやめる
- 関連既存チケット: `PP-022`, `PP-023`, `PP-029`
- 状態: **完了**
- 根拠:
  - `ProjectProfit/Views/Receipt/ReceiptScannerView.swift` に camera / photo library / PDF import / file import の UI がある。
  - `ProjectProfitShareExtension/Info.plist` と `ProjectProfitShareExtension/ShareViewController.swift` に Share Extension 実装がある。
  - `ProjectProfit/Services/ShareImportInboxService.swift`、`ProjectProfit/Features/EvidenceInbox/EvidenceInboxView.swift`、`ProjectProfit/Views/Receipt/ReceiptScannerView.swift` で share-in → inbox → scanner の受け渡しがある。
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift` は `ReceiptEvidenceIntakeUseCase.intake(...)` を呼び、`ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift` は `EvidenceDocument` と `PostingCandidate` を生成する。
  - `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift` は `fileHash` 既存照合で重複 evidence を拒否する。
  - `ProjectProfit/Services/ShareImportInboxService.swift` は `oldestItem()` で pending item を読むだけにし、`markConsumed(_:)` は intake 成功後にだけ呼ばれる。
  - `ProjectProfit/Views/Receipt/ReceiptScannerView.swift` の shared PDF 経路は `importedPDF` を使い、`ReceiptReviewView.swift` の PDF 判定条件と一致している。
  - receipt review 完了後に `PPTransaction` を直接生成するコードは確認できなかった。

### REL-P0-08 PostingCandidate フローと PostingEngine を実装する
- 関連既存チケット: `PP-030`, `PP-031`, `PP-032`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift` に candidate 保存、承認、取消、再レビュー、仕訳生成がある。
  - `ProjectProfit/Features/ApprovalQueue/ApprovalQueueView.swift` は canonical `UUID` ベースの candidate 編集 UI を持つ。
  - `ProjectProfit/Services/AccountingBootstrapService.swift` は `CanonicalTransactionPostingBridge` を使って bootstrap 時の canonical candidate / journal を生成する。
  - `ProjectProfit/Services/DataStore.swift` の add / update / delete では production caller として `AccountingEngine` を使っていない。
  - `ProjectProfit/Services/AccountingBootstrapService.swift` の `CanonicalTransactionPostingBridge` は `TransactionSnapshot` を受けるようになり、橋渡し入力は `PPTransaction` 全体ではなく snapshot 化されている。
  - `ProjectProfit/Services/DataStore.swift` の `saveManualPostingCandidate(...)` は bridge の出力 candidate を `.draft` に更新して `PostingWorkflowUseCase.saveCandidate(...)` だけを呼ぶ。
  - `ProjectProfit/Services/DataStore.swift` の `approveRecurringItems(...)` と `importTransactions(from:)` は `saveApprovedPosting(...)` 経由で canonical journal を作り、legacy transaction を増やさない。
  - `ProjectProfitTests/DataStoreAccountingTests.swift` には manual candidate 保存、recurring 承認、CSV import の各経路を確認するテストがある。
  - 一方で `ProjectProfit/Services/DataStore.swift` は transaction 同期で `PostingWorkflowUseCase.syncApprovedCandidate(...)` を呼び、`ProjectProfit/Services/AccountingBootstrapService.swift` の bridge candidate status も `.approved` を返す。

### REL-P0-09 承認・取消・監査ログ・締め前チェックを一つのフローにする
- 関連既存チケット: `PP-033`, `PP-046`, `PP-051`
- 状態: **完了**
- 根拠:
  - `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift` に `approveCandidate`、`rejectCandidate`、`cancelJournal`、`cancelAndReopenJournal`、`reopenCandidate` がある。
  - `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift` と `PostingWorkflowUseCase.swift` は `AuditEvent` を保存する。
  - `ProjectProfit/Application/UseCases/Filing/FilingPreflightUseCase.swift` は trial balance mismatch、suspense、pending candidate、unmapped category、closing entry、year state をチェックする。
  - `ProjectProfit/Services/ExportCoordinator.swift` と `ProjectProfit/ViewModels/EtaxExportViewModel.swift` は preflight blocker を export 前に評価する。
  - `ProjectProfit/Views/Accounting/JournalDetailView.swift` に取消 → 再レビューの UI 導線がある。

### REL-P0-10 Evidence / Journal 検索インデックスを実装する
- 関連既存チケット: `PP-012`
- 状態: **完了**
- 根拠:
  - `ProjectProfit/Core/Domain/Evidence/EvidenceSearchCriteria.swift` に日付、金額、取引先、T番号、プロジェクト、ファイルハッシュ条件がある。
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/EvidenceSearchIndexEntity.swift`、`JournalSearchIndexEntity.swift`、`ProjectProfit/Infrastructure/Search/SearchIndexRebuilder.swift` がある。
  - `ProjectProfit/Infrastructure/Search/LocalEvidenceSearchIndex.swift` と `LocalJournalSearchIndex.swift` は索引検索と再構築を実装している。
  - `ProjectProfit/Features/EvidenceInbox/EvidenceInboxView.swift` と `ProjectProfit/Views/Accounting/JournalListView.swift` に再索引導線がある。
  - `ProjectProfitTests/ReleasePerformanceGateTests.swift` の検索性能 seed は `CorpusSize.search = 1_000` になっている。
  - 2026-03-09 に `ReleasePerformanceGateTests` を実行し、`performance.search.seconds=0.24588000774383545` で green を確認した。

### REL-P0-11 Migration Runner と backup/restore を先に入れる
- 関連既存チケット: `PP-013`, `PP-014`
- 状態: **完了**
- 根拠:
  - `ProjectProfit/Application/Migrations/MigrationReportRunner.swift` は dry-run、差分、孤児検出を実装している。
  - `ProjectProfit/Infrastructure/FileStorage/BackupService.swift` と `RestoreService.swift` は checksum / dry-run / apply / rollback を持つ。
  - `ProjectProfit/Application/Migrations/LegacyDataMigrationExecutor.swift` は transaction / journal / document の execute migration を実装している。
  - `ProjectProfit/Views/Settings/SettingsView.swift` と `ProjectProfit/Features/Settings/Presentation/Screens/SettingsMainView.swift` に backup / restore / migration dry-run / execute の導線がある。
  - 2026-03-09 に `ProjectProfitTests/BackupRestoreServiceTests.swift` を実行し、4 tests / 0 failures を確認した。
  - 2026-03-09 に `ProjectProfitTests/CanonicalFlowE2ETests.swift` を実行し、`testBackupRestoreRoundTripRestoresSearchableCanonicalArtifacts` と `testMigrationRehearsalOnGoldenFixtureHasNoOrphans` が green であることを確認した。

### REL-P0-12 Golden / E2E / 性能ゲートを閉じる
- 関連既存チケット: `PP-055`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfitTests/Golden/GoldenBaselineTests.swift` は journal / trial balance / blue return / consumption tax worksheet / migration dry-run の snapshot を持つ。
  - `ProjectProfitTests/CanonicalFlowE2ETests.swift` と `ProjectProfitTests/ReleasePerformanceGateTests.swift` がある。
  - `.github/workflows/release-quality.yml` は `golden-baseline`、`canonical-e2e`、`migration-rehearsal`、`performance-gate` の job を持つ。
  - 2026-03-09 に `CanonicalFlowE2ETests` と `ReleasePerformanceGateTests` は green を確認した。
  - 一方で `GoldenBaselineTests` の実行結果は、この更新時点では確認していない。

---

## P1（正式リリース前に入れたい重要機能）

### REL-P1-01 取引先マスタと T番号照合を実装する
- 関連既存チケット: `PP-006`, `PP-025`
- 状態: **完了**
- 根拠:
  - `ProjectProfit/Application/UseCases/Masters/CounterpartyMasterUseCase.swift` に load / search / OCR 候補解決がある。
  - `ProjectProfit/Features/Masters/Counterparties/Presentation/Screens/CounterpartyFormView.swift` は T番号、税区分、デフォルト勘定科目、プロジェクトを編集できる。
  - `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift` は OCR 抽出名・登録番号から取引先候補を解決する。

### REL-P1-02 Chart of Accounts v2 と custom account CRUD を実装する
- 関連既存チケット: `PP-007`
- 状態: **完了**
- 根拠:
  - `ProjectProfit/Views/Accounting/ChartOfAccountsView.swift` から add / edit / archive の導線がある。
  - `ProjectProfit/Features/Masters/Accounts/Presentation/Screens/AccountFormView.swift` は `defaultLegalReportLineId` を UI から編集できる。
  - `ProjectProfit/Application/UseCases/Masters/ChartOfAccountsUseCase.swift` は保存時に `defaultLegalReportLineId` を必須検証する。

### REL-P1-03 Recurring / Distribution を preview → approve 方式へ再設計する
- 関連既存チケット: `PP-034`, `PP-035`, `PP-036`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Features/Recurring/RecurringPreviewView.swift` と `DataStore.previewRecurringTransactions()` は存在する。
  - `ProjectProfit/Views/ContentView.swift` は `previewRecurringTransactions()` の結果で `RecurringPreviewView` を表示する。
  - `ProjectProfit/Application/UseCases/Distribution/DistributionTemplateUseCase.swift` と `DistributionTemplateApplicationUseCase.swift` は存在する。
  - 一方で `ProjectProfit/Views/Components/RecurringFormView.swift` と `ProjectProfit/Views/Components/TransactionFormView.swift` では `DistributionTemplateApplicationUseCase` をフォーム内で直接適用しており、distribution 側の preview → approve ワークフローは確認できなかった。

### REL-P1-04 canonical 帳簿生成エンジンに統一する
- 関連既存チケット: `PP-039`, `PP-041`, `PP-044`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Services/AccountingReportService.swift` には legacy `PPJournalEntry/PPJournalLine` 向け API と canonical `CanonicalJournalEntry` 向け API が並存している。
  - `ProjectProfit/Services/ExportCoordinator.swift` は帳票 export で `projectedCanonicalJournals(...)` を使う。
  - 一方で `BookProjectionEngine` / `BookSpecRegistry` という名前の実装は確認できなかった。

### REL-P1-05 FormEngine を完成させ、現金主義様式まで広げる
- 関連既存チケット: `PP-047`, `PP-048`, `PP-049`, `PP-050`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Services/FormEngine.swift` は `.blueReturn`、`.blueCashBasis`、`.whiteReturn` を扱う。
  - `ProjectProfit/Models/EtaxModels.swift` の `EtaxFormType` には `blueCashBasis` がある。
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/` と `2026/filing/` に各様式 JSON がある。
  - 一方で `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift` は `PPAccount` / `PPJournalEntry` / `PPJournalLine` を受ける互換 API で、form build が完全に canonical projection のみへ統一された状態ではない。

### REL-P1-06 設定 / マスタ UI を再設計する
- 関連既存チケット: `PP-053`
- 状態: **完了**
- 根拠:
  - `ProjectProfit/Features/Settings/Presentation/Screens/SettingsMainView.swift` がある。
  - `ProjectProfit/Views/Settings/ProfileSettingsView.swift` で canonical profile / tax year profile を編集できる。
  - `ProjectProfit/Features/Masters/Accounts/Presentation/Screens/AccountFormView.swift`、`ProjectProfit/Features/Masters/Counterparties/Presentation/Screens/CounterpartyFormView.swift`、`ProjectProfit/Features/Masters/DistributionTemplates/Presentation/Screens/DistributionTemplateListView.swift` がある。

### REL-P1-07 ワークフロー UI を繋ぐ
- 関連既存チケット: `PP-054`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Views/ContentView.swift` の `MainTabView` は `EvidenceInboxView` と `ApprovalQueueView` を本線タブに持つ。
  - `ProjectProfit/Features/Filing/Presentation/Screens/FilingDashboardView.swift` と `ProjectProfit/Features/Journals/Presentation/Screens/JournalBrowserView.swift` がある。
  - 一方で `ProjectProfit/Views/Report/ReportView.swift` と `ProjectProfit/Views/Accounting/AccountingHomeView.swift` の旧導線も残っている。

### REL-P1-08 ExportCoordinator へ出力系を集約する
- 関連既存チケット: `PP-052`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Services/ExportCoordinator.swift` と `ProjectProfit/Views/Components/ExportMenuButton.swift` に共通 export 導線がある。
  - `ProjectProfit/Views/Accounting/ProfitLossView.swift`、`BalanceSheetView.swift`、`TrialBalanceView.swift`、`JournalListView.swift`、`LedgerView.swift`、`FixedAssetListView.swift` は `ExportMenuButton` を使う。
  - 一方で `ProjectProfit/ViewModels/EtaxExportViewModel.swift` は `EtaxXtxExporter` を直接使い、`ProjectProfit/Ledger/Services/` の個別 export service も残っている。

---

## P2（初回正式版の後でもよいが、ロードマップには入れるべきもの）

### REL-P2-01 銀行 / カード照合を実装する
- 関連既存チケット: `PP-038`
- 状態: **未実装**
- 根拠:
  - 銀行明細 / カード明細 / 消込 / 照合 UI に相当するコードを repo 内で確認できなかった。

### REL-P2-02 User Rule Engine とローカル学習メモリを実装する
- 関連既存チケット: `PP-037`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Services/ClassificationLearningService.swift` は存在する。
  - 一方で user rule engine、memory store、candidate feedback loop を main workflow に結びつけた実装は確認できなかった。

### REL-P2-03 源泉徴収 / 支払調書の基礎モデルを入れる
- 関連既存チケット: `PP-021`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Core/Domain/Tax/WithholdingTaxCalculator.swift` と `WithholdingTaxCode.swift` がある。
  - `ProjectProfit/Core/Domain/Counterparties/PayeeInfo.swift`、`CounterpartyEntity.swift`、`JournalLine.swift`、`PostingCandidateLine.swift` に源泉徴収関連属性がある。
  - 一方で支払調書の出力フローや専用 UI は確認できなかった。

### REL-P2-04 Import チャネルの残タスクを詰める
- 関連既存チケット: `PP-023`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Views/Receipt/ReceiptScannerView.swift` に camera / photo / PDF / file import がある。
  - `ProjectProfitShareExtension/ShareViewController.swift` と `ProjectProfit/Services/ShareImportInboxService.swift` に share-in がある。
  - 一方で `ProjectProfit/Ledger/Services/LedgerCSVImportService.swift` は legacy ledger 用で、canonical CSV import を evidence draft に流す実装は確認できなかった。

### REL-P2-05 リリース補助ファイルを repo 管理に寄せる
- 関連既存チケット: 独立追加
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/PrivacyInfo.xcprivacy` は存在し、`ProjectProfit.xcodeproj/project.pbxproj` にも含まれている。
  - 一方で support URL、privacy policy、release checklist を repo 管理している証拠は、この調査では確認できなかった。

### REL-P2-06 CI を e-Tax 以外へ広げる
- 関連既存チケット: `PP-055` の派生
- 状態: **完了**
- 根拠:
  - `.github/workflows/etax-ci.yml` と `.github/workflows/release-quality.yml` がある。
  - `release-quality.yml` は `golden-baseline`、`canonical-e2e`、`migration-rehearsal`、`performance-gate` の lane を持つ。

---

## 未完タスクの優先順（現コード基準）
1. `REL-P0-01` 単一正本の write path 完全統一
2. `REL-P0-02` `DataStore` 直接依存の縮退
3. `REL-P0-05` `lockedYears` 互換依存の縮退
4. `REL-P0-06` legacy tax 表現の縮退
5. `REL-P0-08` posting 周辺の legacy bridge 整理
6. `REL-P0-12` golden baseline の green 確認
7. `REL-P1-03` recurring / distribution の preview → approve 化
8. `REL-P1-04` canonical 帳簿生成一本化
9. `REL-P1-05` form build の canonical 一本化
10. `REL-P1-07` workflow UI の旧導線整理
11. `REL-P1-08` export service 集約の完了
12. `REL-P2-01` 以降のロードマップ項目
