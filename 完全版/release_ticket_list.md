# ProjectProfit リリース向け修正チケット一覧（repo監査ベース）

作成日: 2026-03-06  
前提: この一覧は `project-profit-ios` の静的レビュー結果をもとに、既存の `完全版/ProjectProfit_GitHub_Linear_Tickets.md` を実装状態に合わせて再優先度付けしたもの。  
目的: 正式リリースに必要な未実装・未統合項目を、実行順に落とす。

---

## P0（リリースブロッカー）

### REL-P0-01 単一正本へカットオーバーする
- 関連既存チケット: `PP-003`, `PP-056`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/ProjectProfitApp.swift` は `ModelContainerFactory.makeAppContainer()` を使っている。
  - `ProjectProfit/Views/ContentView.swift` は `DataStore` を起動し、`EvidenceInboxView` と `ApprovalQueueView` を本線タブに持つ。
  - `ProjectProfit/App/FeatureFlags.swift` は `useLegacyLedger` などのフラグを持ち、legacy ledger UI 側で参照されている。
  - `LedgerDataStore` と legacy ledger 画面群は repo 内に残っている。
- 対象ファイル:
  - `ProjectProfit/ProjectProfitApp.swift`
  - `ProjectProfit/Views/ContentView.swift`
  - `ProjectProfit/App/FeatureFlags.swift`
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Store/ModelContainerFactory.swift`
  - `ProjectProfit/Services/DataStore.swift`
  - `ProjectProfit/Ledger/Services/LedgerDataStore.swift`
- 実装内容:
  - 起動経路を canonical path に切り替える。
  - legacy ledger を read-only に落とすか、完全に projection 層へ降格する。
  - `FeatureFlags` を bootstrap から実際に使う。
- 完了条件:
  - 新規作成/更新/削除が `DataStore`/`LedgerDataStore` へ直接書き込まれない。
  - 旧 ledger への新規 write が止まる。
  - 同一データで旧帳簿と新帳簿の差分比較ができる。

### REL-P0-02 Repository / UseCase 層を完成させる
- 関連既存チケット: `PP-010`
- 状態: **部分実装**
- 根拠:
  - `SwiftDataBusinessProfileRepository.swift`, `SwiftDataAuditRepository.swift`, `SwiftDataTaxYearProfileRepository.swift`, `SwiftDataEvidenceRepository.swift`, `SwiftDataCounterpartyRepository.swift`, `SwiftDataPostingCandidateRepository.swift`, `SwiftDataCanonicalJournalEntryRepository.swift` が存在する。
  - `Application/UseCases` には masters / evidence / filing / journals / posting / distribution の UseCase 実装がある。
  - 一方で広い本線では `DataStore` 依存が残っている。
- 対象ファイル:
  - `ProjectProfit/Core/Domain/*Repository.swift`
  - `ProjectProfit/Application/UseCases/`（拡張）
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/`（拡張）
  - `ProjectProfit/Application/Mappers/`（拡張）
- 実装内容:
  - Evidence / TaxYear / Counterparty / PostingCandidate / Journal の mapper と repository を追加。
  - UI から domain 更新する経路を UseCase へ寄せる。
  - 新規コードの `DataStore` 直接依存を禁止する。
- 完了条件:
  - canonical path の保存・読込が repository 経由に統一される。
  - 新規画面・新規ロジックで `DataStore` を直接呼ばない。

### REL-P0-03 `PPAccountingProfile` 依存を切って `BusinessProfile` / `TaxYearProfile` に移行する
- 関連既存チケット: `PP-005`
- 状態: **部分実装**
- 根拠:
  - `BusinessProfile` / `TaxYearProfile`、対応 entity、migration mapper、`ProfileSettingsUseCase` は存在する。
  - `ProfileSettingsView.swift` は canonical profile 保存経路に接続されている。
  - 一方で `DataStore.reloadProfileSettings()` と secure payload fallback は `PPAccountingProfile` をまだ参照している。
- 対象ファイル:
  - `ProjectProfit/Models/PPAccountingProfile.swift`
  - `ProjectProfit/Views/Settings/ProfileSettingsView.swift`
  - `ProjectProfit/Core/Domain/BusinessProfile/*`
  - `ProjectProfit/Core/Domain/TaxYear/*`
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/TaxYearProfileEntity.swift`
- 実装内容:
  - legacy profile → canonical profile への migration adapter を追加。
  - 申告種別、青色控除、VAT 状態、電子帳簿レベル、年ロック状態を UI から編集可能にする。
  - `isBlueReturn` / `bookkeepingMode` の legacy 分岐を段階削除する。
- 完了条件:
  - 主要画面が `PPAccountingProfile` を参照しない。
  - 税務判定が `TaxYearProfile` ベースになる。

### REL-P0-04 TaxYearPack を本番経路に接続し、2026年分を埋める
- 関連既存チケット: `PP-015`
- 状態: **部分実装**
- 根拠:
  - `BundledTaxYearPackProvider.swift` は `TaxYearDefinitionLoader.swift`、`ProfileSettingsUseCase.swift`、`DataStore.swift` から参照されている。
  - `ProjectProfit/Resources/TaxYearPacks/2025/profile.json` と `2026/profile.json` は存在する。
  - 一方で `TaxYearPacks/*/filing` と `TaxYearPacks/*/consumption_tax` は `.gitkeep` のみで、`TaxYearDefinitionLoader.swift` は field 定義を旧 `TaxYear{year}.json` から読んでいる。
- 対象ファイル:
  - `ProjectProfit/Infrastructure/TaxYearPack/BundledTaxYearPackProvider.swift`
  - `ProjectProfit/Services/TaxYearDefinitionLoader.swift`
  - `ProjectProfit/Resources/TaxYearPacks/2025/*`
  - `ProjectProfit/Resources/TaxYearPacks/2026/*`
- 実装内容:
  - 旧単一 JSON ローダを pack ローダへ置換。
  - 2025/2026 の filing / consumption tax / form metadata を pack 化。
  - e-Tax 出力・税ルール・表示ラベルを同じ pack から読む。
- 完了条件:
  - 年度差分が if 文ではなく pack で切り替わる。
  - 2025/2026 のどちらでも同じコード経路で動く。

### REL-P0-05 税務状態エンジンを UI / 出力 / ロックに接続する
- 関連既存チケット: `PP-017`
- 状態: **部分実装**
- 根拠:
  - `TaxStatusMachine.swift` に加えて `TaxYearStateUseCase.swift` と `FilingPreflightUseCase.swift` が存在する。
  - `ClosingEntryView.swift` と `EtaxExportViewModel.swift` は税務状態/preflight を呼んでいる。
  - 一方で `PPAccountingProfile.lockedYears` は model / migration / snapshot / restore / tests に残っている。
- 対象ファイル:
  - `ProjectProfit/Core/Domain/Tax/TaxStatusMachine.swift`
  - `ProjectProfit/Services/DataStore+YearLock.swift`
  - `ProjectProfit/Views/Accounting/ClosingEntryView.swift`
  - `ProjectProfit/Views/Settings/ProfileSettingsView.swift`
- 実装内容:
  - `YearLockState` を canonical に統一。
  - filing style / VAT status / VAT method / lock state の遷移バリデーションを保存時に必須化。
  - 月締め/年締めの状態を `TaxYearProfile` と連動させる。
- 完了条件:
  - ロック/解除/申告済み/最終確定の状態が一貫して保存・参照される。
  - legacy `lockedYears` への依存が消える。

### REL-P0-06 TaxCode master と消費税ルールを canonical 側へ統合する
- 関連既存チケット: `PP-018`, `PP-019`, `PP-045`
- 状態: **部分実装**
- 根拠:
  - `TaxCode.swift`、`TaxRuleEvaluator.swift`、`ConsumptionTaxWorksheet.swift` が存在する。
  - `ConsumptionTaxReportService.swift` は canonical journal から worksheet / summary を生成できる。
  - 一方で `ConsumptionTaxModels.swift` / `AccountingEnums.swift` の legacy tax 表現は残っている。
  - `ReceiptReviewView.swift` は intake request 構築時に `TaxCategory`, `taxRate`, `isTaxIncluded` の bridge 値をまだ持っている。
- 対象ファイル:
  - `ProjectProfit/Core/Domain/Tax/TaxRuleEvaluator.swift`
  - `ProjectProfit/Services/ConsumptionTaxReportService.swift`
  - `ProjectProfit/Models/ConsumptionTaxModels.swift`
  - `ProjectProfit/Models/AccountingEnums.swift`
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift`
- 実装内容:
  - 税区分マスタを定義し、取引・候補・仕訳行に tax code を保持させる。
  - 少額特例、80%/50% 経過措置、2割特例、簡易課税を tax engine へ集約。
  - `ConsumptionTaxWorksheet` を canonical journal から再生成する。
- 完了条件:
  - 消費税集計が tax code / invoice status / tax year pack から決まる。
  - 代表シナリオの golden test が通る。

### REL-P0-07 Evidence intake パイプラインを作り、Receipt 直登録をやめる
- 関連既存チケット: `PP-022`, `PP-023`, `PP-029`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfit/Features/EvidenceInbox/EvidenceInboxView.swift` は実装済み。
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift` は `ReceiptEvidenceIntakeUseCase.intake(...)` を呼ぶ。
  - `EvidenceDocument` / `EvidenceRecordEntity` / intake UseCase は接続済み。
  - 一方で `ReceiptScannerView.swift` で確認できる本線 intake UI は camera / photo library で、PDF import / share sheet import は未完のまま。
- 対象ファイル:
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift`
  - `ProjectProfit/Services/ReceiptScannerService.swift`
  - `ProjectProfit/Core/Domain/Evidence/*`
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/EvidenceRecordEntity.swift`
  - `ProjectProfit/Features/EvidenceInbox/`（拡張）
- 実装内容:
  - カメラ/写真/PDF/Share Sheet から evidence draft を作る。
  - 原本保存、OCR、抽出、重複検知、ステータス管理を evidence 基盤に集約。
  - receipt review 完了後は transaction ではなく evidence/candidate を生成する。
- 完了条件:
  - すべての原本取り込み経路が evidence draft に統一される。
  - 1件の証憑が transaction へ直行しない。

### REL-P0-08 PostingCandidate フローと PostingEngine を実装する
- 関連既存チケット: `PP-030`, `PP-031`, `PP-032`
- 状態: **部分実装**
- 根拠:
  - `PostingCandidate` / `CanonicalJournalEntry` は repository / use case / tests を持ち、`ReceiptEvidenceIntakeUseCase` と `PostingWorkflowUseCase` から使われている。
  - `ProjectProfit/Features/ApprovalQueue/ApprovalQueueView.swift` は実装済み。
  - 一方で `AccountingEngine.swift` は `DataStore.swift` と `AccountingBootstrapService.swift` からまだ呼ばれている。
- 対象ファイル:
  - `ProjectProfit/Services/AccountingEngine.swift`
  - `ProjectProfit/Core/Domain/Posting/*`
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/PostingCandidateEntity.swift`
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/JournalEntryEntity.swift`
  - `ProjectProfit/Features/ApprovalQueue/`（拡張）
- 実装内容:
  - evidence → candidate 生成、candidate 編集、approve/post、複数行/複数税率/複数プロジェクト配賦を実装。
  - `AccountingEngine` を candidate/posting engine に分解。
- 完了条件:
  - 1証憑から candidate を経て posted journal が作成される。
  - 帳簿は posted journal から再生成される。

### REL-P0-09 承認・取消・監査ログ・締め前チェックを一つのフローにする
- 関連既存チケット: `PP-033`, `PP-046`, `PP-051`
- 状態: **部分実装**
- 根拠:
  - `AuditEvent` は `ReceiptEvidenceIntakeUseCase` と `PostingWorkflowUseCase` の evidence / candidate / journal フローで保存されている。
  - `FilingPreflightUseCase.swift` が存在し、`ClosingEntryView.swift` と `EtaxExportViewModel.swift` が呼んでいる。
  - 一方で `EtaxCharacterValidator.swift` 自体は文字/必須項目 validator のままで、全出力系の統一 blocker ではない。
- 対象ファイル:
  - `ProjectProfit/Core/Domain/Audit/*`
  - `ProjectProfit/Views/Accounting/ClosingEntryView.swift`
  - `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
  - `ProjectProfit/Services/EtaxCharacterValidator.swift`
  - `ProjectProfit/Services/EtaxXtxExporter.swift`
- 実装内容:
  - approve / reject / reverse / reopen の状態遷移を追加。
  - preflight に貸借一致、未マッピングカテゴリ、仮勘定残、未承認候補、年ロック不整合を追加。
  - preflight NG 時は XML/CSV/PDF 出力をブロックする。
- 完了条件:
  - 申告前チェックが UI と export の両方で強制される。
  - 取消・再承認が監査ログに残る。

### REL-P0-10 Evidence / Journal 検索インデックスを実装する
- 関連既存チケット: `PP-012`
- 状態: **部分実装**
- 根拠:
  - `EvidenceSearchCriteria.swift` は拡張済みで、`EvidenceSearchIndexEntity.swift`、`JournalSearchIndexEntity.swift`、`SearchIndexRebuilder.swift` が存在する。
  - `SwiftDataEvidenceRepository.swift` と `JournalSearchUseCase.swift` は index 経由の検索を持つ。
  - `LegalDocumentLedgerView.swift`、`EvidenceInboxView.swift`、`JournalListView.swift` に検索/再索引導線がある。
- 対象ファイル:
  - `ProjectProfit/Core/Domain/Evidence/EvidenceSearchCriteria.swift`
  - `ProjectProfit/Infrastructure/Search/`（拡張）
  - `ProjectProfit/Views/Accounting/LegalDocumentLedgerView.swift`
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/EvidenceRecordEntity.swift`
- 実装内容:
  - 日付、金額、取引先、T番号、プロジェクト、ファイルハッシュで検索できる index を追加。
  - evidence / journal の再索引ジョブを追加。
- 完了条件:
  - 電子取引保存を意識した検索導線が実装される。
  - 1,000件規模でも実用速度で検索できる。

### REL-P0-11 Migration Runner と backup/restore を先に入れる
- 関連既存チケット: `PP-013`, `PP-014`
- 状態: **部分実装**
- 根拠:
  - `MigrationReportRunner.swift`、`BackupService.swift`、`RestoreService.swift` は存在する。
  - `SettingsView.swift` から backup / restore / migration dry-run を実行できる。
  - 一方で execute migration は profile migration と snapshot restore が中心で、legacy transaction / journal / document の本移行 execute は別課題のまま。
- 対象ファイル:
  - `ProjectProfit/Application/Migrations/`（拡張）
  - `ProjectProfit/Infrastructure/FileStorage/`（拡張）
  - `ProjectProfit/Views/Settings/SettingsView.swift`
- 実装内容:
  - legacy → canonical の dry-run、差分レポート、孤児データ検出を実装。
  - スナップショット export / import / checksum / rollback 手順を実装。
- 完了条件:
  - 実データで dry-run ができる。
  - 復元テストが通る。

### REL-P0-12 Golden / E2E / 性能ゲートを閉じる
- 関連既存チケット: `PP-055`
- 状態: **部分実装**
- 根拠:
  - `ProjectProfitTests/Golden/GoldenBaselineTests.swift` は journal / trial balance / blue return / consumption tax worksheet / migration dry-run の snapshot を持つ。
  - `ProjectProfitTests/CanonicalFlowE2ETests.swift` と `ProjectProfitTests/ReleasePerformanceGateTests.swift` が存在する。
  - `.github/workflows/release-quality.yml` が golden / canonical-e2e / migration-rehearsal / performance-gate を持つ。
- 対象ファイル:
  - `ProjectProfitTests/Golden/GoldenBaselineTests.swift`
  - `ProjectProfitTests/Core/*`
  - `.github/workflows/*`
  - `scripts/*`
- 実装内容:
  - 帳簿、帳票、消費税 worksheet、migration dry-run の golden test を追加。
  - canonical path E2E と性能測定を CI に追加。
- 完了条件:
  - 主要シナリオの golden baseline が green。
  - リリース判定をテストで自動化できる。

---

## P1（正式リリース前に入れたい重要機能）

### REL-P1-01 取引先マスタと T番号照合を実装する
- 関連既存チケット: `PP-006`, `PP-025`
- 状態: **完了**
- 根拠:
  - `SwiftDataCounterpartyRepository.swift`、`CounterpartyMasterUseCase.swift`、`CounterpartyListView.swift`、`CounterpartyFormView.swift` は存在する。
  - `ReceiptEvidenceIntakeUseCase.swift` は OCR 抽出名から取引先候補解決を行っている。
  - 一方で現行 transaction は `Models.swift` 上の `counterparty: String?` 保持も残っている。
- 対象ファイル:
  - `ProjectProfit/Core/Domain/Counterparties/*`
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Entities/CounterpartyEntity.swift`
  - `ProjectProfit/Features/Masters/Counterparties/`（拡張）
  - `ProjectProfit/Services/ReceiptScannerService.swift`
- 完了条件:
  - OCR から取引先候補を引ける。
  - T番号と登録状態を evidence/candidate/journal に引き継げる。

### REL-P1-02 Chart of Accounts v2 と custom account CRUD を実装する
- 関連既存チケット: `PP-007`
- 状態: **部分実装**
- 根拠:
  - `ChartOfAccountsView.swift` から `AccountFormView.swift` を開く CRUD 導線がある。
  - `ChartOfAccountsUseCase.swift` と `SwiftDataChartOfAccountsRepository.swift` は存在する。
  - 一方で `defaultLegalReportLineId` を UI から完結編集できる証拠は確認できていない。
- 対象ファイル:
  - `ProjectProfit/Views/Accounting/ChartOfAccountsView.swift`
  - `ProjectProfit/Core/Domain/Accounts/*`
  - `ProjectProfit/Features/Masters/Accounts/`（拡張）
- 完了条件:
  - 勘定科目追加/編集/無効化ができる。
  - すべての科目が法定帳票 line と対応付く。

### REL-P1-03 Recurring / Distribution を preview → approve 方式へ再設計する
- 関連既存チケット: `PP-034`, `PP-035`, `PP-036`
- 状態: **未完成**
- 根拠:
  - `ContentView.swift` で起動時に `processRecurringTransactions()` が即実行される。
  - `Features/Recurring/RecurringPreviewView.swift` は存在する。
  - 一方で `DataStore.swift` では project / recurring 更新時にも `processRecurringTransactions()` が呼ばれている。
- 対象ファイル:
  - `ProjectProfit/Services/DataStore.swift`
  - `ProjectProfit/Core/Domain/Distribution/*`
  - `ProjectProfit/Views/Recurring/*`
  - `ProjectProfit/Features/Recurring/`（再設計）
- 完了条件:
  - 定期取引と一括配賦が preview → approve → apply で動く。
  - 自動生成結果が監査可能になる。

### REL-P1-04 canonical 帳簿生成エンジンに統一する
- 関連既存チケット: `PP-039`, `PP-041`, `PP-044`
- 状態: **未完成**
- 根拠:
  - `AccountingReportService.swift` には legacy と canonical の両経路が並存している。
  - `AccountingEngine.swift` は `DataStore.swift` と `AccountingBootstrapService.swift` からまだ呼ばれている。
  - `BookProjectionEngine` / `BookSpecRegistry` は存在しない。
- 対象ファイル:
  - `ProjectProfit/Services/AccountingReportService.swift`
  - `ProjectProfit/Ledger/Services/*`
  - `ProjectProfit/Features/Reports/`（新規）
- 完了条件:
  - 仕訳帳/総勘定元帳/現金/預金/売掛/買掛/経費/プロジェクト別補助元帳が canonical journal から再生成される。

### REL-P1-05 FormEngine を完成させ、現金主義様式まで広げる
- 関連既存チケット: `PP-047`, `PP-048`, `PP-049`, `PP-050`
- 状態: **未完成**
- 根拠:
  - `EtaxFormType` は `.blueReturn`, `.whiteReturn` の2種のみ。
  - `ShushiNaiyakushoBuilder.swift` はあるが `FormEngine` は未実装。
  - `TaxYearPacks/*/filing` は `.gitkeep` のみで、`TaxYearDefinitionLoaderTests.swift` では 2026 年の `blueReturn` が未対応になっている。
- 対象ファイル:
  - `ProjectProfit/Models/EtaxModels.swift`
  - `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
  - `ProjectProfit/Services/EtaxFieldPopulator.swift`
  - `ProjectProfit/Features/Filing/`（拡張）
- 完了条件:
  - 白色、青色一般、青色現金主義の各 builder が分離される。
  - form build が TaxYearPack から駆動される。

### REL-P1-06 設定 / マスタ UI を再設計する
- 関連既存チケット: `PP-053`
- 状態: **未完成**
- 根拠:
  - `SettingsView.swift` から `ProfileSettingsView.swift`、`CounterpartyListView.swift`、`DistributionTemplateSettingsView.swift` を開ける。
  - `Features/Masters/Accounts` と `Features/Masters/Counterparties` には screen 実装がある。
  - 一方で `Features/Settings/Presentation/Screens` は `.gitkeep` のみで、設定/マスタ再編は完了していない。
- 対象ファイル:
  - `ProjectProfit/Views/Settings/SettingsView.swift`
  - `ProjectProfit/Features/Masters/*`
  - `ProjectProfit/Features/Settings/*`
- 完了条件:
  - マスタ変更が UI から完結する。
  - 設定画面で canonical profile と tax year profile を編集できる。

### REL-P1-07 ワークフロー UI を繋ぐ
- 関連既存チケット: `PP-054`
- 状態: **部分実装**
- 根拠:
  - `MainTabView` は `EvidenceInboxView` と `ApprovalQueueView` を本線タブに持つ。
  - `Features/Filing/Presentation/Screens` と `Features/Journals/Presentation/Screens` は `.gitkeep` のみ。
  - `ReportView.swift` は `AccountingHomeView` 経由の旧導線をまだ持つ。
- 対象ファイル:
  - `ProjectProfit/Views/ContentView.swift`
  - `ProjectProfit/Features/EvidenceInbox/*`
  - `ProjectProfit/Features/ApprovalQueue/*`
  - `ProjectProfit/Features/Filing/*`
  - `ProjectProfit/Features/Journals/*`
- 完了条件:
  - 証憑 → 候補 → 帳簿 → 申告の導線がタブ/ワークスペースとして完成する。

### REL-P1-08 ExportCoordinator へ出力系を集約する
- 関連既存チケット: `PP-052`
- 状態: **部分実装**
- 根拠:
  - `PDFExportService.swift`, `CSVExportService.swift`, `LedgerExportService.swift`, `LedgerExcelExportService.swift`, `LedgerPDFExportService.swift`, `EtaxXtxExporter.swift` が分散。
  - `ExportCoordinator.swift` と `ExportCoordinatorTests.swift` は存在する。
  - 一方で UI 側は各 export service を個別に呼んでおり、出力元データも旧/新/ledger 系で分かれている。
- 対象ファイル:
  - `ProjectProfit/Services/PDFExportService.swift`
  - `ProjectProfit/Services/CSVExportService.swift`
  - `ProjectProfit/Ledger/Services/*`
  - `ProjectProfit/Services/EtaxXtxExporter.swift`
- 完了条件:
  - 出力ロジックが projection/form エンジンからのみ呼ばれる。
  - ファイル命名、保存先、共有導線が統一される。

---

## P2（初回正式版の後でもよいが、ロードマップには入れるべきもの）

### REL-P2-01 銀行 / カード照合を実装する
- 関連既存チケット: `PP-038`
- 状態: **未実装**
- 根拠: 銀行/カード明細の取り込み・照合画面・一致判定基盤がリポジトリ内に無い。
- 完了条件: 明細取込、候補一致、未照合一覧、消込ができる。

### REL-P2-02 User Rule Engine とローカル学習メモリを実装する
- 関連既存チケット: `PP-037`
- 状態: **部分実装**
- 根拠: `ClassificationLearningService.swift` はあるが rule engine / memory store / candidate feedback loop までは無い。
- 完了条件: ユーザーの承認結果が次回候補生成へ反映される。

### REL-P2-03 源泉徴収 / 支払調書の基礎モデルを入れる
- 関連既存チケット: `PP-021`
- 状態: **部分実装**
- 根拠: 源泉対象支払や支払調書に必要な payee 属性・税額保持モデルが無い。
- 完了条件: 源泉対象支払の記帳に必要な属性を保持できる。

### REL-P2-04 Import チャネルの残タスクを詰める
- 関連既存チケット: `PP-023`
- 状態: **部分実装**
- 根拠:
  - camera/photo は既存 receipt フローである程度ある。
  - PDF import / share sheet import / canonical CSV import は未完成。
  - `LedgerCSVImportService.swift` は legacy ledger 用で、固定資産系は `unsupportedType`。
- 完了条件: すべての import チャネルが evidence draft を作れる。

### REL-P2-05 リリース補助ファイルを repo 管理に寄せる
- 関連既存チケット: 独立追加
- 状態: **不足**
- 根拠:
  - `PrivacyInfo.xcprivacy` が見当たらない。
  - support URL / privacy policy / release checklist の repo 同梱がない。
- 完了条件:
  - App Store 提出に必要な補助ファイルと手順書が repo に入る。

### REL-P2-06 CI を e-Tax 以外へ広げる
- 関連既存チケット: `PP-055` の派生
- 状態: **部分実装**
- 根拠:
  - `.github/workflows/etax-ci.yml` に加えて `.github/workflows/release-quality.yml` が存在する。
  - `release-quality.yml` は golden / canonical E2E / migration / performance の lane を持つ。
- 完了条件: books / forms / migration / performance の CI lane が揃う。

---

## 実行順（この順で切るのが安全）
1. `REL-P0-01` 単一正本カットオーバー
2. `REL-P0-02` Repository / UseCase 完成
3. `REL-P0-03` Profile canonical 化
4. `REL-P0-04` TaxYearPack 接続
5. `REL-P0-05` 税務状態エンジン統合
6. `REL-P0-06` TaxCode / 消費税ルール統合
7. `REL-P0-07` Evidence intake
8. `REL-P0-08` PostingCandidate / PostingEngine
9. `REL-P0-09` 承認 / 監査 / preflight
10. `REL-P0-10` 検索インデックス
11. `REL-P0-11` Migration + backup/restore
12. `REL-P0-12` Golden / E2E / 性能ゲート
13. P1 群
14. P2 群

## ここまで終われば「正式リリース判定」をしてよい条件
- canonical path が write path として唯一になる
- 帳簿 / 帳票 / XML / 消費税集計が同一正本から再生成される
- e-Tax preflight blocker が 0 件になる
- migration dry-run と restore rehearsal が完了している
- golden / E2E / 主要性能測定が green
