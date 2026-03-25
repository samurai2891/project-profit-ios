# accounting_app_release_review_10items 現行実装事実監査レポート

調査対象: `/Users/yutaro/Downloads/accounting_app_release_review_10items.md`  
調査対象コード: `/Users/yutaro/project-profit-ios`  
調査日: 2026-03-26  
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
| 1 | 仕訳帳と元帳/補助簿の参照ソース不一致 | 実装済み | 帳簿画面と `journal / ledger / subLedger export` が共通の canonical-only export source に統一され、orphan legacy supplemental / legacy-only depreciation を除外する parity テストも追加された |
| 2 | 取引保存成功と canonical 側反映失敗の乖離 | 実装済み | 手入力は candidate-only 保存へ統一され、承認時 canonical journal 保存と失敗時ロールバックが main path / release 導線で裏付けられた。未使用の `DEBUG` 補助同期コードも除去された |
| 3 | プロジェクト別収益管理と税務帳簿の未連結 | 実装済み | project/history の表示系も canonical read model に統一され、`projectAllocationId` を案件別集計・履歴・詳細表示まで一貫利用する |
| 4 | 消費税の簡易課税・2割特例ロジック | 実装済み | 判定と控除計算は decision object ベースに一本化され、簡易課税のみなし仕入率も `TaxYearPack` 正本へ統一、単体/統合テストで境界が固定された |
| 5 | 個人事業主向けの年度設定 | 実装済み | filing/e-Tax/preflight に加えて、証憑取込・statement import・Approval Queue・e-Tax 命名も暦年 `taxYear` 基準へ統一された |
| 6 | 仕様書上の帳簿が release 導線に未掲載 | 実装済み | `BooksWorkspaceView` が canonical 本流の帳簿一覧へ再編され、仕様対象帳簿は release UI から到達できる。legacy ledger は `旧台帳アーカイブ` に限定された |
| 7 | export 機能が帳簿仕様と未整合 | 実装済み | `ExportCoordinator` が 11帳簿の official target を持ち、release 導線と CSV/PDF export が揃った。repo 内では fixture ベースの golden 検証も追加された |
| 8 | e-Tax UI と年分対応のズレ | 実装済み | `blueCashBasis` と 2025/2026 年分対応に加え、e-Tax 画面へ年分×様式の対応状況一覧と事前理由表示、UI テスト根拠が追加された |
| 9 | 書類台帳の削除統制が弱い | 部分実装 | quarantine/restore と保存期間警告はあるが、`confirmDeletion` の防御が薄く、内部 purge/全削除は物理削除を行う |
| 10 | 固定資産帳票区分と export の粗さ | 部分実装 | register と depreciation は別 target/別画面に分離され、双方とも CSV/PDF 対応になった。一方で列定義と数値の原本一致はなお追加確認が必要 |

## 実装チェックリスト

### 項目別チェック一覧

| # | 項目 | main path 実装 | release 導線 | export/帳票整合 | テスト根拠 | 残課題あり |
|---|---|---|---|---|---|---|
| 1 | 仕訳帳と元帳/補助簿の参照ソース不一致 | [x] | [x] | [x] | [x] | [ ] |
| 2 | 取引保存成功と canonical 側反映失敗の乖離 | [x] | [x] | [x] | [x] | [ ] |
| 3 | プロジェクト別収益管理と税務帳簿の未連結 | [x] | [x] | [x] | [x] | [ ] |
| 4 | 消費税の簡易課税・2割特例ロジック | [x] | [x] | [x] | [x] | [ ] |
| 5 | 個人事業主向けの年度設定 | [x] | [x] | [x] | [x] | [ ] |
| 6 | 仕様書上の帳簿が release 導線に未掲載 | [x] | [x] | [ ] | [x] | [ ] |
| 7 | export 機能が帳簿仕様と未整合 | [x] | [x] | [x] | [x] | [ ] |
| 8 | e-Tax UI と年分対応のズレ | [x] | [x] | [x] | [x] | [ ] |
| 9 | 書類台帳の削除統制が弱い | [x] | [x] | [x] | [x] | [x] |
| 10 | 固定資産帳票区分と export の粗さ | [x] | [x] | [ ] | [x] | [x] |

凡例:
- `main path 実装` = 主機能の中心経路は実装済み
- `release 導線` = release UI / main workflow から到達できる
- `export/帳票整合` = 仕様書や帳票要件まで含めて整合している
- `テスト根拠` = 主要論点を直接支えるテスト根拠がある
- `残課題あり` = current working tree で未統一・未達・未検証が残る

## 詳細

### 1. 仕訳帳と元帳/補助簿の参照ソース不一致

- 判定: `実装済み`
- 実装チェック:
  - [x] 仕訳帳・元帳・補助簿の画面参照は canonical/projected 系へ寄っている
  - [x] main path の読取 query は存在する
  - [x] canonical のみを単一正本とする export source helper に統一された
  - [x] `journal export` と `ledger/subLedger export` の内部経路は一致している
  - [x] export parity を固定するテスト根拠がある
- できていること:
  - 仕訳参照は `ProjectedJournalReadModelQuery.snapshot(...)` を使用している
  - 元帳と補助簿は同じ projected canonical snapshot family を使う read query に乗っている
  - `ExportCoordinator` は `AccountingBookExportSource` を通して `journal / ledger / subLedger` を共通の canonical-only source から出力する
  - canonical manual/opening/closing は legacy 表示互換の `sourceKey` を保ったまま export に出る
  - orphan legacy supplemental entry と legacy-only depreciation entry は read/export の双方で除外される
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingBookReadModelQueries.swift:5`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingBookReadModelQueries.swift:54`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingBookReadModelQueries.swift:152`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:72`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:665`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:783`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:822`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:853`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/AccountingReadQueryUseCaseTests.swift:107`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/AccountingReadQueryUseCaseTests.swift:244`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:243`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:326`
- 未確認事項:
  - `FilingPreflightUseCase` の supplemental merge は今回の統一対象外
- release 影響:
  - 画面と 3 帳簿 export が同じ canonical-only source rule を見る状態になり、「同じ正本を見ている」と説明できる

### 2. 取引保存成功と canonical 側反映失敗の乖離

- 判定: `実装済み`
- 実装チェック:
  - [x] 手入力保存は candidate 作成経路へ接続されている
  - [x] 承認時に canonical journal を保存する
  - [x] 保存失敗時のロールバックがある
  - [x] main path を支えるテストがある
  - [x] `#if DEBUG` の旧保存後同期経路は除去された
- できていること:
  - 手入力保存は `TransactionFormView` から `PostingIntakeUseCase.saveManualCandidate(...)` に接続されている
  - candidate 保存は draft で止まり、承認時に canonical journal を永続化する
  - canonical 保存失敗時は candidate status を元へ戻すロールバックがある
- 補足:
  - `ProjectProfitApp` 起動時に `FeatureFlags.switchToCanonical()` が実行され、release は canonical cutover 前提で動作する
  - `systemGenerated` は `TestMutationDriver` に閉じた test support であり、本番保存経路の分岐ではない
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/ProjectProfitApp.swift:19`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Components/TransactionFormView.swift:303`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Components/TransactionFormView.swift:1261`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Components/TransactionFormView.swift:1275`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/PostingIntakeUseCase.swift:58`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift:158`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift:111`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift:124`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/PostingIntakeUseCaseTests.swift:59`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/CanonicalUseCasesTests.swift:674`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/PostingIntakeUseCaseTests.swift:332`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TestMutationDriver.swift:5`
- 未確認事項:
  - なし
- release 影響:
  - release 導線では「取引保存成功なのに canonical 反映失敗が後から起こる」構造的乖離は解消済みと説明できる

### 3. プロジェクト別収益管理と税務帳簿の未連結

- 判定: `実装済み`
- 実装チェック:
  - [x] project allocation が candidate line に反映される
  - [x] canonical journal line に `projectAllocationId` が保存される
  - [x] canonical 集計・検索は `projectAllocationId` を使う
  - [x] project detail / history の表示系が canonical read model に統一されている
  - [x] main path を支えるテストがある
- できていること:
  - project allocation は candidate line 作成時に `projectAllocationId` へ展開される
  - canonical journal line の借方/貸方双方へ `projectAllocationId` を保存している
  - canonical 集計、案件別 yearly summary、検索 index は `projectAllocationId` を利用している
  - `ProjectDetailSnapshot.recentTransactions` は canonical journal 起点の read model を返し、focused project の `projectAmount / projectRatio` を表示できる
  - `TransactionHistory` の project filter・金額比較・一覧詳細遷移は canonical read model を正本として扱い、canonical-only 行も表示される
  - project detail / transaction history の詳細画面は canonical read-only detail に統一されている
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingSupport.swift:514`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift:214`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift:228`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift:254`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Core/Domain/Transactions/CanonicalTransactionDisplayItem.swift:1`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/CanonicalTransactionDisplayBuilder.swift:1`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/SwiftDataProjectQueryRepository.swift:27`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/SwiftDataTransactionHistoryRepository.swift:14`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/ViewModels/TransactionsViewModel.swift:103`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Transactions/CanonicalTransactionReadOnlyDetailView.swift:1`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/CanonicalPostingSupportTests.swift:76`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ProjectQueryUseCaseTests.swift:94`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ProjectQueryUseCaseTests.swift:117`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TransactionHistoryUseCaseTests.swift:27`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TransactionHistoryUseCaseTests.swift:73`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TransactionsViewModelTests.swift:169`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/SearchIndexTests.swift:280`
- 未確認事項:
  - なし
- release 影響:
  - 案件別収支、税務帳簿、案件詳細、取引履歴が同じ canonical project allocation を参照する状態になり、canonical-only データも UI 上で欠落しない

### 4. 消費税の簡易課税・2割特例ロジック

- 判定: `実装済み`
- 実装チェック:
  - [x] 控除方式判定ロジックがある
  - [x] 実控除額計算ロジックがある
  - [x] 簡易課税 / 2割特例の統合テストがある
  - [x] 判定責務と控除計算責務が一本化されている
  - [x] evaluator / calculator の単体テストがある
- できていること:
  - `TaxRuleEvaluator` は `InputTaxDeductionDecision` を返し、控除方式判定と控除率・計算モード解決を同じ決定オブジェクトへ集約した
  - `InputTaxDeductionCalculator` は profile 再判定を持たず、decision を入力に控除額計算と worksheet 合計再配分のみを担当する
  - 簡易課税のみなし仕入率は `TaxYearPack.simplifiedDeemedPurchaseRates` を正本として `rules.json` から decode される
  - `simplifiedBusinessCategory` 未設定時は `requiresReview + 控除額 0` の fail-safe に統一された
  - `ConsumptionTaxReportService` と `AccountingBootstrapService` は同じ decision API を使って控除額を計算する
  - 簡易課税、2割特例、経過措置の統合テストに加え、evaluator / calculator の単体テストが追加された
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Core/Domain/Tax/TaxRuleEvaluator.swift`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Core/Domain/Tax/InputTaxDeductionCalculator.swift`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Core/Domain/TaxYear/TaxYearPack.swift`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Infrastructure/TaxYearPack/BundledTaxYearPackProvider.swift`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ConsumptionTaxReportService.swift`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/AccountingBootstrapService.swift`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/Core/TaxRuleEvaluatorTests.swift`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/Core/InputTaxDeductionCalculatorTests.swift`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ConsumptionTaxReportServiceTests.swift`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TaxYearDefinitionLoaderTests.swift`
- 未確認事項:
  - `xcodebuild` のフル完走はこの監査時点では未確認
- release 影響:
  - 簡易課税・2割特例・経過措置の main path は同一 decision model を通るため、release 上は「判定と控除計算の正本が一致している」と説明できる

### 5. 個人事業主向けの年度設定

- 判定: `実装済み`
- 実装チェック:
  - [x] filing/e-Tax/preflight は暦年処理を使う
  - [x] e-Tax UI は暦年基準を明記している
  - [x] receipt intake / statement import の `taxYear` 付与は暦年 `taxYear(for:)` に統一された
  - [x] Approval Queue の年ロック判定も暦年 `taxYear` 基準へ整合した
  - [x] e-Tax 系 API 引数や state 名は対象範囲で `taxYear` に整理された
  - [x] 暦年 main path と regression を支えるテストがある
- できていること:
  - `taxYear(for:)` と `startOfTaxYear/endOfTaxYear` が用意されている
  - e-Tax form build は `startMonth = 1` 固定で暦年抽出
  - preflight も `startMonth: 1` で trial balance を判定
  - `ReceiptEvidenceIntakeUseCase` は evidence / posting candidate / 分類プレビュー用ダミー候補の `taxYear` を暦年で付与する
  - `StatementImportUseCase` は imported evidence / posting candidate の `taxYear` を暦年で付与する
  - `ApprovalQueueQueryUseCase.isYearLocked(date:)` は暦年 `taxYear` でロック状態を判定する
  - `EtaxExportViewModel`、`EtaxExportContextQueryUseCase`、`EtaxFormBuildQueryUseCase`、`EtaxFormBuildSnapshot` の対象範囲命名は `taxYear` に整理された
  - e-Tax UI は「申告年分」表記に揃えつつ「申告年分は暦年（1月〜12月）基準」と表示する
- 補足:
  - Settings 画面の「会計年度開始月」保持機能自体は維持されており、会計年度設定と申告年分が別概念であることを前提にしている
  - `EtaxForm` 本体や `FormEngine` 全域、tax pack JSON フィールド名までは今回の整理対象外
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Utilities/FiscalYearUtilities.swift:61`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift:178`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift:1364`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift:1384`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Filing/FilingPreflightUseCase.swift:85`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift:109`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift:626`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Statements/StatementImportUseCase.swift:65`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Statements/StatementImportUseCase.swift:286`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/Posting/ApprovalQueueQueryUseCase.swift:53`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/ViewModels/EtaxExportViewModel.swift:22`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/EtaxExportView.swift:110`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/FilingPreflightUseCaseTests.swift:88`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/EtaxExportViewModelTests.swift:112`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ReceiptEvidenceIntakeUseCaseTests.swift:709`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/StatementImportUseCaseTests.swift:123`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/StatementImportUseCaseTests.swift:149`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ApprovalQueueQueryUseCaseTests.swift:40`
- 未確認事項:
  - 関連スイート中心の確認は実施したが、repo 全体フルテストの完走まではこの更新では再確認していない
- release 影響:
  - filing/e-Tax/preflight、証憑取込、statement import、Approval Queue、e-Tax 命名が同じ暦年 `taxYear` を前提に揃い、利用者の年分理解と内部表現のズレは解消された

### 6. 仕様書上の帳簿が release 導線に未掲載

- 判定: `実装済み`
- 実装チェック:
  - [x] BooksWorkspace から帳簿導線に到達できる
  - [x] 仕様対象帳簿が canonical 本流セクションに載っている
  - [x] 導線存在を支えるテストがある
  - [x] 旧11帳簿は互換セクションから本流導線へ移された
  - [x] legacy ledger は `旧台帳アーカイブ` に縮小され、本流 UI ではない
- できていること:
  - `BooksWorkspaceView` が release 導線として存在し、`FilingDashboardView` から遷移できる
  - `BooksWorkspaceView` は `帳簿ワークフロー` と別に `帳簿・台帳` セクションを持ち、`仕訳帳` `総勘定元帳` `現金出納帳` `預金出納帳` `売掛帳` `買掛帳` `経費帳` `固定資産台帳` `棚卸台帳` `白色簡易帳簿` を release 本流として案内する
  - `仕訳帳` は `JournalBrowserView`、`総勘定元帳` は `LedgerView`、補助簿群は canonical `SubLedgerView`、`固定資産台帳` は `FixedAssetListView`、`棚卸台帳` は `InventoryInputView` に接続される
  - `SubLedgerType` と read model は `depositBook` を追加し、預金系勘定を canonical 側から読める
  - `白色簡易帳簿` は新規 `WhiteTaxBookkeepingQueryUseCase` / `WhiteTaxBookkeepingView` により canonical read-only 画面として追加された
  - legacy ledger は `旧台帳アーカイブ` に縮小され、`交通費精算書（互換）` と `旧台帳一覧` の参照導線のみを残す
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Features/Filing/Presentation/Screens/FilingDashboardView.swift:200`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift:18`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift:56`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift:138`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/DataStore+SubLedger.swift:5`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/AccountingBookReadModelQueries.swift:176`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Application/UseCases/App/WhiteTaxBookkeepingReadSupport.swift:27`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/WhiteTaxBookkeepingView.swift:1`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/BooksWorkspaceViewTests.swift:32`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/BooksWorkspaceViewTests.swift:54`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/WorkflowNavigationTests.swift:28`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/AccountingReadQueryUseCaseTests.swift:441`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/WhiteTaxBookkeepingQueryUseCaseTests.swift:26`
- 未確認事項:
  - 項目 6 の release 導線コードと対象テストは更新済みだが、この更新時点では repo 全体フルテスト完走までは再確認していない
- release 影響:
  - 仕様対象の帳簿群は release UI の canonical 本流から到達できる状態になり、「仕様書上の帳簿が release 導線に未掲載」という指摘には current working tree 上で対応できている

### 7. export 機能が帳簿仕様と未整合

- 判定: `実装済み`
- 実装チェック:
  - [x] ExportCoordinator で export target/format を管理している
  - [x] 補助簿や主要帳票の export 導線はある
  - [x] format 行列のテストがある
  - [x] 仕様書の全11帳簿に official target がある
  - [x] repo 内正本に基づく fixture / golden 検証がある
- できていること:
  - `ExportCoordinator.ExportTarget` に `cashBook`、`bankAccountBook`、`accountsReceivableBook`、`accountsPayableBook`、`expenseBook`、`generalLedger`、`journalBook`、`transportationExpense`、`whiteTaxBookkeeping`、`fixedAssetRegister`、`fixedAssetDepreciation` の 11帳簿 target が追加された
  - 11帳簿は official target 側で原則 CSV/PDF を持ち、`legacyLedgerBook` は互換 adapter として残されている
  - `SubLedgerView`、`JournalListView`、`LedgerView`、`WhiteTaxBookkeepingView`、`BooksWorkspaceView` の公開導線は official target に接続された
  - `transportationExpense`、`whiteTaxBookkeeping`、固定資産2帳簿も `ExportCoordinator` 経由で CSV/PDF export できる
  - fixture ベースの ledger export 検証が追加され、11帳簿の CSV ヘッダ・主要本文・PDF テキスト断片を repo 内で比較できる
- 補足:
  - 仕様書の「Excel 原本と完全同一フォーマット」は repo 内に原本 Excel が同梱されていないため、current working tree では `Docs/specs/SPEC.md` と bundled template / fixture を正本にした検証へ置き換えている
  - `transactions` と `etax` は 11帳簿の仕様対象外の互換 target として残る
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md:6`
  - `/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md:10`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:28`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:105`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/SubLedgerView.swift:146`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/WhiteTaxBookkeepingView.swift:47`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift:103`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Ledger/Services/LedgerExportService.swift:353`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:107`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:184`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:266`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:324`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/Golden/GoldenBaselineTests.swift:61`
- 未確認事項:
  - Xcode 上での full test 完走はこの更新時点では再確認できていない
  - repo 外の Excel 原本との機械比較は、原本不在のためこの repo 単独では断定できない
- release 影響:
  - current working tree では 11帳簿の export 正本が `ExportCoordinator` に統一され、release UI から到達できるため、「帳簿仕様と export 行列が未整合」という主指摘には対応できている

### 8. e-Tax UI と年分対応のズレ

- 判定: `実装済み`
- 実装チェック:
  - [x] `blueCashBasis` を UI から選択できる
  - [x] 2025/2026 年分定義が loader で読める
  - [x] 未対応年は preview/export 前に block する
  - [x] loader / ViewModel テストがある
  - [x] UI 上の対応状況一覧と事前理由表示がある
- できていること:
  - e-Tax UI は `.blueReturn` `.blueCashBasis` `.whiteReturn` を選択できる
  - `TaxYearDefinitionLoader.supportedYears(formType:)` から年候補を出す
  - `TaxYearDefinitionLoader.etaxSupportStatusRows()` が年分×様式の対応状況一覧を UI へ供給する
  - 設定セクションに 2025/2026 年分の対応状況一覧と「税制パック未収録のため選択不可」の事前説明が表示される
  - `EtaxExportView` に画面識別子と対応状況識別子が追加され、UI テストから検証できる
  - 未対応年は preview/export 前に block する
  - 2025/2026 pack と `blue_cash_basis` metadata の loader テスト、ViewModel の表示状態テスト、`EtaxExportView` の UI テストがある
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/EtaxExportView.swift:4`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/EtaxExportView.swift:97`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/EtaxExportView.swift:164`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/ViewModels/EtaxExportViewModel.swift:27`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/ViewModels/EtaxExportViewModel.swift:80`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/TaxYearDefinitionLoader.swift:382`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TaxYearDefinitionLoaderTests.swift:155`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TaxYearDefinitionLoaderTests.swift:169`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TaxYearDefinitionLoaderTests.swift:292`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/TaxYearDefinitionLoaderTests.swift:302`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/EtaxExportViewModelTests.swift:236`
  - `/Users/yutaro/project-profit-ios/ProjectProfitUITests/WithholdingApprovalUITests.swift:58`
- 未確認事項:
  - Xcode 上での full test 完走はこの更新時点では再確認できていない
- release 影響:
  - release UI 上で「どの年分がどの様式に対応しているか」と「一覧外年分を選べない理由」を事前に説明できるため、e-Tax UI と年分対応のズレは current working tree で解消された

### 9. 書類台帳の削除統制が弱い

- 判定: `部分実装`
- 実装チェック:
  - [x] 保存期間中の警告と admin override 要求がある
  - [x] quarantine / restore 導線がある
  - [x] compliance log が残る
  - [x] 主削除フローを支えるテストがある
  - [ ] `confirmDeletion` の防御は十分でない
  - [ ] 内部 purge / 全削除の物理削除経路が残る
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
- 実装チェック:
  - [x] register / depreciation は別 target
  - [x] UI も別画面
  - [x] register は CSV/PDF export がある
  - [x] depreciation は CSV/PDF export がある
  - [ ] 実装列定義は仕様書と一致していない
  - [x] depreciation export を直接支えるテスト根拠は追加された
- できていること:
  - `ExportCoordinator.ExportTarget` で `fixedAssetRegister` と `fixedAssetDepreciation` が分離されている
  - UI も `FixedAssetListView` と `FixedAssetScheduleView` の別画面
  - `fixedAssetRegister` と `fixedAssetDepreciation` はともに CSV/PDF 対応
- まだ足りていないこと:
  - 固定資産減価償却 CSV/PDF の列定義は改善されたが、仕様書原本 Excel との完全一致は repo 外原本なしでは断定できない
  - 固定資産台帳 / 減価償却明細の値計算には推定値を含む項目があり、原本 comparison までは未確認
- 根拠コード:
  - `/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md:21`
  - `/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md:147`
  - `/Users/yutaro/project-profit-ios/Docs/specs/SPEC.md:175`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:47`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Services/ExportCoordinator.swift:105`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/FixedAssetListView.swift:42`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Views/Accounting/FixedAssetScheduleView.swift:41`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Ledger/Services/LedgerPDFExportService.swift:311`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Ledger/Services/LedgerPDFExportService.swift:332`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Ledger/Services/LedgerExportService.swift:394`
  - `/Users/yutaro/project-profit-ios/ProjectProfit/Ledger/Services/LedgerExportService.swift:460`
- 根拠テスト:
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:129`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/ExportCoordinatorTests.swift:339`
  - `/Users/yutaro/project-profit-ios/ProjectProfitTests/Golden/GoldenBaselineTests.swift:61`
- 未確認事項:
  - 固定資産帳票を原本 Excel と直接機械比較する検証は repo 外原本なしでは確認できない
- release 影響:
  - 帳票区分と export 形式の不足は縮小したが、固定資産帳票の数値・列完全一致については追加確認余地が残る

## 横断的に残る不足実装

- canonical main path へ移行した一方で、`legacy` `compat` `readOnly` `#if DEBUG` 経路が複数領域で残っている
- 項目 1 の帳簿 source 差分は解消したが、項目 3・7・10 では依然として source/format 差分が残る
- 設定名や引数名は fiscal year を使い続けつつ、実処理だけ tax year に寄った箇所がある
- 一部領域はサービス統合テストで担保されているが、責務境界の単体テストはなお不足する
- release gate が `go` でも、10 項目の仕様差分・互換経路残存・未検証経路は current working tree 上で残っている

## 今回のテスト確認

- current working tree で帳簿 source 統一の代表確認として以下を再実行した
  - `ExportCoordinatorTests/testCanonicalOnlyBookExportsExcludeOrphanLegacySupplementals`
  - `ExportCoordinatorTests/testBookExportsMatchCanonicalReadModelsOnSharedFixture`
- 上記 2 件は専用 `DerivedData` で green を確認した
  - xcresult: `/tmp/projectprofit-codex-export-tests/Logs/Test/Test-ProjectProfit-2026.03.25_19-29-45-+0900.xcresult`
  - xcresult: `/tmp/projectprofit-codex-export-tests/Logs/Test/Test-ProjectProfit-2026.03.25_19-35-02-+0900.xcresult`
- `AccountingReadQueryUseCaseTests` の代表 2 件は追加再実行を開始したが、このターンでは専用 `DerivedData` 初回ビルドが長く、完走確認までは記録していない

## 前回レポートとの差分

- 項目 1 は `実装済み` へ更新した
- ただし今回の監査では、各項目の未達内容を `できていること / まだ足りていないこと / 根拠コード / 根拠テスト / 未確認事項 / release影響` に分解した
- また、監査対象 HEAD が `a2d059d9...` ではなく `1557241966...` であること、working tree に未コミット変更があることを明示した
