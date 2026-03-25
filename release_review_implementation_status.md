# accounting_app_release_review_10items 現行実装事実監査レポート

調査対象: `/Users/yutaro/Downloads/accounting_app_release_review_10items.md`  
調査対象コード: `/Users/yutaro/project-profit-ios`  
調査日: 2026-03-25  
監査基準:
- 主基準は `release_review_implementation_status.md` の 10 項目
- 補助根拠は `Docs/release/checklist.md`、`Docs/release/リリース残課題チェックリスト_2026-03-24.md`、必要時のみ `Docs/specs/SPEC.md`
- 対象実体は current working tree と current HEAD `1557241966fe597904eb7971252b261a7dab9e04`
- `Docs/release/quality/latest.md` の `go` 判定対象 HEAD `a2d059d9b9d71ac22148f7b641a83ab03249134d` とは別物として扱う

判定基準:
- `実装済み` = 指摘された主問題が main path と release 導線で解消され、コードと代表テストで裏付けられる
- `部分実装` = 主要経路は解消済みだが、互換経路・UI・集計・export・命名・未検証経路に未統一が残る
- `未実装` = 指摘の主問題が current code 上で残る
- `未確認` = 対象コードはあるが repo 内根拠だけでは断定できない

## 監査前提

- working tree には未コミット変更がある
  - `.github/workflows/etax-ci.yml`
  - `.github/workflows/release-quality.yml`
  - `ProjectProfitTests/EtaxXtxExporterTests.swift`
  - `scripts/etax_resolve_xsd.sh`
  - `scripts/etax_validate_xsd.sh`
  - `scripts/run_etax_unit_lane.sh`
  - `tools/etax/xsd/shotoku/KOA230-010.xsd`
- 本レポートは上記を含む current working tree をそのまま読んでいる
- repo 外の法令適合証明、e-Tax 受理保証、App Store 設定、サーバ設定は調査対象外

## 結論サマリー

| # | 項目 | 判定 | 要約 |
|---|---|---|---|
| 1 | 仕訳帳と元帳/補助簿の参照ソース不一致 | 部分実装 | 画面参照は `projected canonical` 系に寄ったが、`projected` 自体が legacy 補足をマージし、`journal export` と `ledger/subLedger export` の内部経路も未統一 |
| 2 | 取引保存成功と canonical 側反映失敗の乖離 | 部分実装 | main path は candidate 保存→承認→canonical journal ロールバック付きになったが、`#if DEBUG` の legacy 保存後同期経路が残る |
| 3 | プロジェクト別収益管理と税務帳簿の未連結 | 部分実装 | `projectAllocationId` は candidate から canonical line まで到達し検索/集計も使うが、一部 UI と履歴系は `PPTransaction.allocations` 依存のまま |
| 4 | 消費税の簡易課税・2割特例ロジック | 部分実装 | 誤計算の主経路は calculator へ移ったが、判定責務と控除計算責務が二重化し、単体テストも不足 |
| 5 | 個人事業主向けの年度設定 | 部分実装 | filing/e-Tax/preflight は暦年化済みだが、証憑取込・明細 import・命名には fiscal year 起点が残る |
| 6 | 仕様書上の帳簿が release 導線に未掲載 | 部分実装 | Books 導線自体は release 画面にあるが、旧11帳簿は `互換` セクションかつ `readOnly` 導線 |
| 7 | export 機能が帳簿仕様と未整合 | 部分実装 | `ExportCoordinator` で対象は広がったが、仕様書の「全11帳簿」「Excel 原本と完全同一フォーマット」には一致していない |
| 8 | e-Tax UI と年分対応のズレ | 部分実装 | `blueCashBasis` と 2026 年分対応はコード上解消済みだが、UI は対応状況一覧を持たず未対応年の説明も事前表示しない |
| 9 | 書類台帳の削除統制が弱い | 部分実装 | quarantine/restore と保存期間警告はあるが、`confirmDeletion` の防御が薄く、内部 purge/全削除は物理削除を行う |
| 10 | 固定資産帳票区分と export の粗さ | 部分実装 | register と depreciation は別 target/別画面に分離済みだが、減価償却明細は PDF のみで列定義も仕様書と一致していない |

## 詳細

### 1. 仕訳帳と元帳/補助簿の参照ソース不一致

- 判定: `部分実装`
- できていること:
  - 仕訳参照は `projectedCanonicalJournals(...)` を使用している
  - 元帳と補助簿は `ProjectedJournalReadModelQuery.snapshot(...)` を共通利用している
  - 画面側の main path は canonical 読取へ寄っている
- まだ足りていないこと:
  - `projected` は canonical のみではなく `manual:` `opening:` `closing:` `depreciation:` prefix の legacy 補足仕訳をマージしている
  - `journal export` は `context.journals` を投影する独自 `legacyJournalProjection` 経路
  - `ledger/subLedger export` は query use case 経由の `projected` 経路
  - 補足 legacy 仕訳の取り込み規則が export target ごとに一致していない
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingBookReadModelQueries.swift:27`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingBookReadModelQueries.swift:85`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingBookReadModelQueries.swift:183`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/LegacyProjectedJournalAssembler.swift:24`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/LegacyProjectedJournalAssembler.swift:56`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:753`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:842`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:878`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/AccountingReadQueryUseCaseTests.swift:212`
  - `ExportCoordinatorTests` は format/preflight の確認が中心で、`journal` と `ledger/subLedger` のソース整合自体は固定していない
- 未確認事項:
  - 同一 fixture で `journal export` と `ledger export` の実出力差分までは今回未採取
- release 影響:
  - 画面上は参照統一が進んでいるが、出力物まで含めて「同じ正本を見ている」とは current code だけでは言えない

### 2. 取引保存成功と canonical 側反映失敗の乖離

- 判定: `部分実装`
- できていること:
  - 手入力保存は `TransactionFormView` から `PostingIntakeUseCase.saveManualCandidate(...)` に接続されている
  - candidate 保存は draft で止まり、承認時に canonical journal を永続化する
  - canonical 保存失敗時は candidate status を元へ戻すロールバックがある
- まだ足りていないこと:
  - `LegacyTransactionCompatibilityUseCase` が `#if DEBUG` で残っている
  - legacy transaction 保存後に canonical 同期を後追い実行する `enqueueCanonicalSync` が残存する
  - `systemGenerated` mutation は legacy 経路を通しうる
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/App/FeatureFlags.swift:15`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Components/TransactionFormView.swift:303`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Components/TransactionFormView.swift:1261`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Components/TransactionFormView.swift:1275`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/PostingIntakeUseCase.swift:58`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift:111`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift:124`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Legacy/LegacyTransactionCompatibilityUseCase.swift:1`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Legacy/LegacyTransactionCompatibilityUseCase.swift:96`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/PostingIntakeUseCaseTests.swift:59`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/CanonicalUseCasesTests.swift:674`
  - `LegacyTransactionCompatibilityUseCase` 自体の主な参照は test support 側にある
- 未確認事項:
  - Release build で debug-only 経路が完全に死んでいること自体は今回ビルド成果物では再確認していない
- release 影響:
  - release main path の乖離問題は大幅に縮小しているが、repo 全体としては旧「保存後同期」方式が残っている

### 3. プロジェクト別収益管理と税務帳簿の未連結

- 判定: `部分実装`
- できていること:
  - project allocation は candidate line 作成時に `projectAllocationId` へ展開される
  - canonical journal line の借方/貸方双方へ `projectAllocationId` を保存している
  - canonical 集計、案件別 yearly summary、検索 index は `projectAllocationId` を利用している
- まだ足りていないこと:
  - `ProjectDetailSnapshot.recentTransactions` は `PPTransaction.allocations` で抽出している
  - `TransactionHistory` の project filter も `transaction.allocations` 依存
  - 同一 snapshot 内で `summary/yearlyProfitLoss` は canonical、`recentTransactions` は legacy transaction という二重基準が残る
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingSupport.swift:514`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift:214`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift:228`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift:254`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/SwiftDataReportingRepository.swift:157`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/SwiftDataProjectQueryRepository.swift:34`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/SwiftDataProjectQueryRepository.swift:79`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Infrastructure/Search/LocalJournalSearchIndex.swift:138`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/SwiftDataTransactionHistoryRepository.swift:21`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/CanonicalPostingSupportTests.swift:76`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ProjectQueryUseCaseTests.swift:94`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/SearchIndexTests.swift:280`
- 未確認事項:
  - `recentTransactions` を canonical source に寄せる改修予定の有無は repo 内根拠だけでは確認していない
- release 影響:
  - 案件別収支と税務帳簿は主要集計で連結しているが、画面の一部リスト表示では canonical-only データが落ちうる

### 4. 消費税の簡易課税・2割特例ロジック

- 判定: `部分実装`
- できていること:
  - 仕入税額控除方式の判定は `TaxRuleEvaluator` に分離されている
  - 実控除額計算は `InputTaxDeductionCalculator` が `lineBased/simplified/twoTenths` で再計算する
  - `ConsumptionTaxReportService` は worksheet 生成後に控除額を再配分する
  - 簡易課税、2割特例、経過措置の統合テストがある
- まだ足りていないこと:
  - 判定責務は `TaxRuleEvaluator`、最終控除計算は `InputTaxDeductionCalculator.mode()` に分かれており、責務分離が途中
  - `InputTaxCreditMethod.creditRate` の `simplifiedEstimate` / `twoTenthsEstimate` は `0` を返し、「別計算」前提が残る
  - `simplifiedBusinessCategory` 未設定時は `deemedPurchaseRate == 0`
  - evaluator / calculator の単体テストファイルは確認できず、統合テスト依存
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Core/Domain/Tax/TaxRuleEvaluator.swift:16`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Core/Domain/Tax/TaxRuleEvaluator.swift:123`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Core/Domain/Tax/InputTaxDeductionCalculator.swift:16`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Core/Domain/Tax/InputTaxDeductionCalculator.swift:96`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ConsumptionTaxReportService.swift:94`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ConsumptionTaxReportService.swift:203`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ConsumptionTaxReportService.swift:232`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ConsumptionTaxReportServiceTests.swift:159`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ConsumptionTaxReportServiceTests.swift:204`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ConsumptionTaxReportServiceTests.swift:241`
- 未確認事項:
  - `TaxRuleEvaluator` と `InputTaxDeductionCalculator` の単体境界を固定するテストは repo 内で未確認
- release 影響:
  - 主計算経路は改善されているが、責務の二重化と fallback 的な `0` 返却が残るため、ロジックの正本はまだ一枚岩ではない

### 5. 個人事業主向けの年度設定

- 判定: `部分実装`
- できていること:
  - `taxYear(for:)` と `startOfTaxYear/endOfTaxYear` が用意されている
  - e-Tax form build は `startMonth = 1` 固定で暦年抽出
  - preflight も `startMonth: 1` で trial balance を判定
  - e-Tax UI には「申告年分は暦年基準」と表示がある
- まだ足りていないこと:
  - Settings 画面では会計年度開始月を保持できる
  - 証憑取込 `ReceiptEvidenceIntakeUseCase` の `taxYear` 付与は `fiscalYear(...)`
  - Statement import candidate 生成時の `taxYear` 付与も `fiscalYear(...)`
  - e-Tax 系 API 引数や state 名は `fiscalYear` のままで、実処理と命名が一致していない
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Utilities/FiscalYearUtilities.swift:8`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Utilities/FiscalYearUtilities.swift:61`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift:1380`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Filing/FilingPreflightUseCase.swift:85`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/EtaxExportView.swift:159`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Settings/SettingsView.swift:208`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift:109`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Statements/StatementImportUseCase.swift:290`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/ViewModels/EtaxExportViewModel.swift:22`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/FilingPreflightUseCaseTests.swift:95`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/EtaxExportViewModelTests.swift:124`
- 未確認事項:
  - `FiscalYearSettings.startMonth` を変更した状態での receipt intake / statement import の `taxYear` 検証テストは repo 内で確認できない
- release 影響:
  - filing/e-Tax は暦年で進む一方、取り込み・命名・設定 UI に fiscal 起点が残るため、利用者の年分理解と内部表現が完全一致していない

### 6. 仕様書上の帳簿が release 導線に未掲載

- 判定: `部分実装`
- できていること:
  - `BooksWorkspaceView` が release 導線として存在し、`FilingDashboardView` から遷移できる
  - main workflow には照合、仕訳ブラウザ、分析、帳票群、固定資産、申告導線がある
  - 旧帳簿導線は `BooksWorkspaceView` に配置され、`DEBUG` 限定ではない
- まだ足りていないこと:
  - 旧11帳簿は `11帳簿（互換）` セクションとして分離されている
  - 互換帳簿は `LedgerDataStore(accessMode: .readOnly)` で起動される
  - `LedgerHomeView` でも read-only 時は追加 UI を出さず、作成/編集本流ではない
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Features/Filing/Presentation/Screens/FilingDashboardView.swift:200`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift:100`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift:322`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift:324`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift:503`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Ledger/Views/LedgerHomeView.swift:23`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/BooksWorkspaceViewTests.swift:18`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/BooksWorkspaceViewTests.swift:32`
- 未確認事項:
  - 旧11帳簿の個別画面が release UX 上どこまで案内されるかは UI 仕様書の明文化を repo 内で確認していない
- release 影響:
  - 導線自体は存在するが、仕様書上の帳簿群は current 実装では「互換・参照専用」として扱われている

### 7. export 機能が帳簿仕様と未整合

- 判定: `部分実装`
- できていること:
  - `ExportCoordinator` が export target/format 行列を一元管理している
  - `subLedger` は CSV/PDF に対応している
  - `legacyLedgerBook` は CSV/PDF/XLSX を持つ
- まだ足りていないこと:
  - 仕様書は「全11帳簿」「CSV/PDF で Excel 原本と完全同一フォーマット」を要求している
  - current `SubLedgerType` は 4 種で、仕様書の 11 帳簿全体には対応していない
  - `subLedger` CSV は汎用ヘッダ `date,accountCode,accountName...` で、帳簿別 Excel 列定義とは一致しない
  - `transactions` は CSV のみ、`etax` は CSV/XTX のみなど、仕様書帳簿の行列と export target 行列は一致していない
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md:6`
  - `/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md:10`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:28`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:78`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/SubLedgerView.swift:80`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/DataStore+SubLedger.swift:5`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:565`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:104`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:163`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:200`
- 未確認事項:
  - 仕様書と完全同一フォーマットを機械比較する golden test は今回 repo 内で確認できていない
- release 影響:
  - export 導線はあるが、仕様書準拠の帳簿出力完成度としては未達

### 8. e-Tax UI と年分対応のズレ

- 判定: `部分実装`
- できていること:
  - e-Tax UI は `.blueReturn` `.blueCashBasis` `.whiteReturn` を選択できる
  - `TaxYearDefinitionLoader.supportedYears(formType:)` から年候補を出す
  - 未対応年は preview/export 前に block する
  - 2025/2026 pack と `blue_cash_basis` metadata の loader テストがある
- まだ足りていないこと:
  - 画面上の設定セクションは Picker と注記だけで、「年分×様式の対応状況一覧」を持たない
  - 未対応年の説明は事前表示ではなく preview/export エラー経由
  - `EtaxExportView` 自体の UI テストは repo 内で確認できない
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/EtaxExportView.swift:4`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/EtaxExportView.swift:109`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/EtaxExportView.swift:159`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/ViewModels/EtaxExportViewModel.swift:64`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/ViewModels/EtaxExportViewModel.swift:118`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/TaxYearDefinitionLoader.swift:382`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TaxYearDefinitionLoaderTests.swift:155`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TaxYearDefinitionLoaderTests.swift:169`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TaxYearDefinitionLoaderTests.swift:292`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TaxYearDefinitionLoaderTests.swift:302`
- 未確認事項:
  - 現行 UI 文言だけで利用者が対応状況を誤解しないかはコードだけでは評価しない
- release 影響:
  - 対応そのものは進んだが、対応状況の可視化が不足しており、UI 完了とは言い切れない

### 9. 書類台帳の削除統制が弱い

- 判定: `部分実装`
- できていること:
  - `DocumentDeletionStatus` に `active/quarantined` があり、保存期間中は warning を返す
  - `requestDeletion` は保存期間内なら `adminOverrideRequired` を返す
  - `performDeletion` は実ファイルを quarantine へ移動し、restore 導線もある
  - compliance log は `adminOverrideRequested` `adminOverrideApproved` `documentQuarantined` `documentDeleted` `documentRestored` を記録する
- まだ足りていないこと:
  - `confirmDeletion` は「理由が空でない」ことしか見ず、`requestDeletion` 通過済み状態を要求しない
  - `approvedBy` 既定値は `"device-owner"` 固定
  - UI は固定理由文字列で `confirmDeletion` を呼ぶ
  - `purgeDocumentRecords` は record を物理削除する
  - `SettingsMaintenanceUseCase.deleteAllData()` は document file を物理削除する
  - `deleteAllData()` は `quarantineFileName` を削除対象に含めていない
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Models/PPDocumentRecord.swift:79`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Models/PPDocumentRecord.swift:170`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Documents/DocumentWorkflowUseCase.swift:145`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Documents/DocumentWorkflowUseCase.swift:166`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Documents/DocumentWorkflowUseCase.swift:215`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Transactions/TransactionDocumentsView.swift:50`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/DataStore+Documents.swift:74`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Settings/SettingsMaintenanceUseCase.swift:16`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/DocumentWorkflowUseCaseTests.swift:100`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/DocumentWorkflowUseCaseTests.swift:114`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/DocumentWorkflowUseCaseTests.swift:150`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/DocumentAndSubLedgerTests.swift:34`
- 未確認事項:
  - `purgeDocumentRecords` を直接固定する専用テストは repo 内で確認できない
  - `deleteAllData()` の document/quarantine 実ファイル削除差分を検証するテストは確認できない
- release 影響:
  - 日常削除フローは強化されたが、内部 purge と全削除の物理削除経路が残るため、削除統制は完了していない

### 10. 固定資産帳票区分と export の粗さ

- 判定: `部分実装`
- できていること:
  - `ExportCoordinator.ExportTarget` で `fixedAssetRegister` と `fixedAssetDepreciation` が分離されている
  - UI も `FixedAssetListView` と `FixedAssetScheduleView` の別画面
  - `fixedAssetRegister` は CSV/PDF 対応
- まだ足りていないこと:
  - `fixedAssetDepreciation` は `.pdf` のみ
  - 固定資産減価償却 PDF の列は 6 列実装で、仕様書列定義と一致しない
  - 固定資産台帳 CSV は 8 列実装で、仕様書の 13 列定義と一致しない
  - `exportFixedAssetDepreciationPDF` を直接検証するテストは repo 内で確認できない
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md:21`
  - `/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md:147`
  - `/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md:175`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:38`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:82`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/FixedAssetListView.swift:42`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/FixedAssetScheduleView.swift:41`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/PDFExportService.swift:286`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/PDFExportService.swift:292`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/CSVExportService.swift:209`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:160`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/CSVExportServiceTests.swift:403`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/PDFExportServiceTests.swift:200`
- 未確認事項:
  - `fixedAssetDepreciation` PDF の実列を仕様書と直接比較する golden test は repo 内で確認できない
- release 影響:
  - 帳票区分そのものは整理されたが、仕様書粒度と export 完成度はまだ不足している

## 横断的に残る不足実装

- canonical main path へ移行した一方で、`legacy` `compat` `readOnly` `#if DEBUG` 経路が複数領域で残っている
- 画面・集計・export が同じ正本を見ているとは限らず、項目 1・3・7・10 で source/format 差分が残る
- 設定名や引数名は fiscal year を使い続けつつ、実処理だけ tax year に寄った箇所がある
- 一部領域はサービス統合テストで担保されているが、責務境界の単体テストや export parity テストが不足している
- release gate が `go` でも、10 項目の仕様差分・互換経路残存・未検証経路は current working tree 上で残っている

## 今回のテスト確認

- current working tree で以下の代表スイート再実行を試行した
  - `BooksWorkspaceViewTests`
  - `ExportCoordinatorTests`
  - `ConsumptionTaxReportServiceTests`
  - `TaxYearDefinitionLoaderTests`
  - `DocumentWorkflowUseCaseTests`
  - `ProjectQueryUseCaseTests`
- 一括実行は `xcodebuild` 終了コード `65`
  - xcresult: `/Users/yutaro/Library/Developer/Xcode/DerivedData/ProjectProfit-gjethbtnkdvawmdbwjveldxkexsm/Logs/Test/Test-ProjectProfit-2026.03.25_17-28-08-+0900.xcresult`
  - failure summary: `DocumentWorkflowUseCaseTests.testDeleteAfterRetentionMovesRecordToQuarantineAndLogsDocumentDeleted()` が `Test crashed with signal kill.`
- 同一実行ログ内では `DocumentWorkflowUseCaseTests` の他ケース通過も確認できたが、今回の一括再実行は fully green とは記載しない

## 前回レポートとの差分

- 10 項目すべての判定は `部分実装` のままで、`実装済み` へ上げられる項目は current working tree 上で確認できなかった
- ただし今回の監査では、各項目の未達内容を `できていること / まだ足りていないこと / 根拠コード / 根拠テスト / 未確認事項 / release影響` に分解した
- また、監査対象 HEAD が `a2d059d9...` ではなく `1557241966...` であること、working tree に未コミット変更があること、一括再実行テストが green ではないことを明示した
