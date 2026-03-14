# ProjectProfit リリース事実監査レポート
作成日: 2026-03-14  
対象 HEAD: `a32682c`  
固定資産/棚卸 再検証追記 HEAD: `8b525b6811f90a99610eb4b713972478ee60fbc1`  
対象リポジトリ: `/Users/yutaro/project-profit-ios`

## 1. 監査条件

- 本レポートは repo 内コード、repo 内ドキュメント、repo 内テスト、2026-03-14 の再実行結果だけを根拠に記載する。
- 推測は含めない。
- repo 外の法令適合証明、e-Tax 受理保証、App Store / GitHub 外設定は「未確認/未証明」と扱う。
- 参照した主資料:
  - `Docs/vendor_package/release_remaining_work_breakdown_2026-03-13.md`
  - `Docs/vendor_package/release_ticket_list.md`
  - `Docs/vendor_package/revised_release_ticket_list.md`
  - `Docs/release/checklist.md`
  - `Docs/release/quality/latest.md`
  - `Docs/release/quality/books.md`
  - `Docs/release/quality/forms.md`

## 2. 再実行した代表テスト

実行コマンド:

```bash
xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ProjectProfitTests/FilingPreflightUseCaseTests \
  -only-testing:ProjectProfitTests/EtaxExportViewModelTests \
  -only-testing:ProjectProfitTests/WithholdingFlowE2ETests \
  -only-testing:ProjectProfitTests/DistributionApprovalIntegrationTests \
  -only-testing:ProjectProfitTests/ProjectWorkflowUseCaseTests \
  -only-testing:ProjectProfitTests/ProRataDataStoreTests \
  test
```

結果:

- 実行テスト数: 52
- 失敗: 1
- 失敗テスト: `ProjectProfitTests/FilingPreflightUseCaseTests/testExportPreflightDetectsSuspenseBalance`
- 成功テスト群:
  - `EtaxExportViewModelTests` 11件
  - `WithholdingFlowE2ETests` 1件
  - `DistributionApprovalIntegrationTests` 3件
  - `ProjectWorkflowUseCaseTests` 6件
  - `ProRataDataStoreTests` 25件

結論:

- `仮勘定残高があると申告出力を止める` 挙動は、現HEADでは再現テストが落ちており、release blocker と扱うのが妥当。

### 2-1. 定期取引専用の再実行

実行コマンド:

```bash
xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ProjectProfitTests/RecurringWorkflowUseCaseTests \
  -only-testing:ProjectProfitTests/RecurringPreviewTests \
  -only-testing:ProjectProfitTests/RecurringProcessingTests \
  -only-testing:ProjectProfitTests/RecurringQueryUseCaseTests \
  test
```

結果:

- 実行テスト数: 56
- 失敗: 0
- skip: 1
- 成功テスト群:
  - `RecurringPreviewTests` 7件
  - `RecurringProcessingTests` 37件実行 / 1件 skip / 0件失敗
  - `RecurringQueryUseCaseTests` 3件
  - `RecurringWorkflowUseCaseTests` 9件
- xcresult:
  - `/Users/yutaro/Library/Developer/Xcode/DerivedData/ProjectProfit-gjethbtnkdvawmdbwjveldxkexsm/Logs/Test/Test-ProjectProfit-2026.03.14_20-46-18-+0900.xcresult`

補足:

- `RecurringProcessingTests/testDeleteMonthlyRecurringTransaction_allowsRegeneration` は skip。
- skip 理由は `processRecurringTransactions()` が canonical recurring journal のみを生成し、`deleteTransaction(id:)` が legacy `PPTransaction` 前提のため、旧前提テストが current 実装に追随していないため。
- この skip は current recurring main path の失敗ではなく、legacy bridge 残存に関する注記として扱う。

## 3. REL軸の判定

### 3-1. 実装済み

#### `REL-P2-01` 銀行 / カード照合

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Features/Reconciliation/BankCardReconciliationView.swift`
  - `ProjectProfit/Application/UseCases/Statements/StatementImportUseCase.swift`
  - `ProjectProfit/Application/UseCases/Statements/StatementMatchService.swift`
  - `ProjectProfit/Application/UseCases/Statements/StatementReconciliationQueryUseCase.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/StatementImportUseCaseTests.swift`
  - `ProjectProfitTests/BooksWorkspaceViewTests.swift`
- 補足:
  - 明細取込 UI、未照合サマリー、候補/仕訳マッチ候補生成、Books 導線が repo 内で確認できた。

#### `REL-P2-03` 源泉徴収 / 支払調書

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Views/Accounting/WithholdingStatementView.swift`
  - `ProjectProfit/ViewModels/WithholdingStatementViewModel.swift`
  - `ProjectProfit/Application/UseCases/Filing/WithholdingStatementQueryUseCase.swift`
  - `ProjectProfit/Features/Filing/Presentation/Screens/FilingDashboardView.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/WithholdingFlowE2ETests.swift`
  - `ProjectProfitUITests/WithholdingApprovalUITests.swift`
  - 2026-03-14 再実行で `WithholdingFlowE2ETests` 通過
- 補足:
  - 年次一覧、支払先別明細、CSV/PDF出力、Filing 導線は repo 内で確認できた。

#### `REL-P1-03` Distribution approval workflow

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Application/UseCases/Distribution/DistributionTemplateApplicationUseCase.swift`
  - `ProjectProfit/Features/ApprovalQueue/ApprovalQueueView.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/DistributionApprovalIntegrationTests.swift`
  - 2026-03-14 再実行で 3件通過

#### `REL-P1-03` Recurring preview / approve workflow（recurring 単体）

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Views/ContentView.swift`
  - `ProjectProfit/Features/Recurring/RecurringPreviewView.swift`
  - `ProjectProfit/Application/UseCases/Recurring/RecurringWorkflowUseCase.swift`
  - `ProjectProfit/Application/UseCases/Recurring/RecurringPostingCoordinator.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/RecurringPreviewTests.swift`
  - `ProjectProfitTests/RecurringProcessingTests.swift`
  - `ProjectProfitTests/RecurringQueryUseCaseTests.swift`
  - `ProjectProfitTests/RecurringWorkflowUseCaseTests.swift`
  - 2026-03-14 / current HEAD `a32682c` で 56件実行、0 failures、1 skip
- 事実:
  - 起動時に `ContentView` が `loadRecurringPreview()` を呼び、pending があれば `RecurringPreviewView` sheet を表示する。
  - `RecurringPreviewView` は `approveRecurringItems(...)` を呼び、選択済み recurring を一括承認する。
  - `RecurringPostingCoordinator` は承認時に canonical posting を永続化し、approval request を更新する。
  - `RecurringWorkflowUseCaseTests/testPreviewRecurringTransactionsReturnsDueItems`、
    `testApproveRecurringItemsCreatesCanonicalJournalAndUpdatesBookkeeping`、
    `testProcessDueRecurringTransactionsCreatesCanonicalJournalAndUpdatesBookkeeping`
    で main path の代表挙動を再確認した。

### 3-2. 部分実装

#### `REL-P1-03` Recurring / Distribution を preview → approve 方式へ再設計する（チケット全体）

- 2026-03-14 時点の結論: `部分実装`
- 根拠ファイル:
  - `ProjectProfit/Features/Recurring/RecurringPreviewView.swift`
  - `ProjectProfit/Application/UseCases/Distribution/DistributionTemplateApplicationUseCase.swift`
  - `ProjectProfit/Views/Components/RecurringFormView.swift`
  - `ProjectProfit/Views/Components/TransactionFormView.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/RecurringWorkflowUseCaseTests.swift`
  - `ProjectProfitTests/RecurringPreviewTests.swift`
  - `ProjectProfitTests/DistributionApprovalIntegrationTests.swift`
- 事実:
  - recurring 側の preview → approve 本線は current HEAD で再実行して green を確認した。
  - 一方で distribution 側はフォーム内で `DistributionTemplateApplicationUseCase` を直接適用する経路が残る。
  - したがって recurring 単体は release 観点で再確認できたが、既存チケット `REL-P1-03` 全体は完了とは言えない。

#### `REL-P1-05` FormEngine の canonical 一本化

- 2026-03-14 時点の結論: `部分実装`
- 根拠ファイル:
  - `ProjectProfit/Services/FormEngine.swift`
  - `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
  - `ProjectProfit/Services/CashBasisReturnBuilder.swift`
  - `ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/FormEngineTests.swift`
  - `ProjectProfitTests/ShushiNaiyakushoBuilderTests.swift`
  - 2026-03-14 再実行で `EtaxExportViewModelTests` 通過
- 事実:
  - `FormEngine.BuildInput` に `legacyAccountsById` が残る。
  - `FormEngine.build(filingStyle:dataStore:fiscalYear:)` と `makeBuildInput(dataStore:fiscalYear:)` が残る。
  - `ShushiNaiyakushoBuilder` は `legacyAccountsById` で TaxLine / 地代家賃判定を行う。
  - `CashBasisReturnBuilder` は `candidate.legacySnapshot` を読む。

#### `REL-P0-12` release green 証跡

- 2026-03-14 時点の結論: `部分実装`
- 根拠ファイル:
  - `Docs/release/quality/latest.md`
  - `Docs/release/quality/books.md`
  - `Docs/release/quality/forms.md`
  - `Docs/release/checklist.md`
- 根拠テストまたは実行結果:
  - `git rev-parse --short HEAD` -> `a32682c`
- 事実:
  - `latest.md` の curated fully-green snapshot は `86b7b08...` / 2026-03-07 を指している。
  - `books.md` と `forms.md` には 2026-03-14 の green 証跡がある。
  - 現HEAD `a32682c` に対して、checklist 対象 4 lane fully-green の curated 更新は repo 内で確認できない。

### 3-3. 不具合再現

#### `REL-P0-09` 申告前チェック

- 2026-03-14 時点の結論: `不具合再現`
- 根拠ファイル:
  - `ProjectProfit/Application/UseCases/Filing/FilingPreflightUseCase.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/FilingPreflightUseCaseTests.swift`
  - 2026-03-14 再実行で `testExportPreflightDetectsSuspenseBalance` 失敗
- 事実:
  - `journalBalanceIssues` は投影 snapshot を見る。
  - 仮勘定判定は canonical `trialBalance` の `suspenseRow.balance` だけを見ている。
  - テスト側の手動補助仕訳ケースを現HEADが拾えていない。

### 3-4. 未確認 / 未証明

#### `REL-P1-05` 現金主義の UI 到達性

- 2026-03-14 時点の結論: `未証明`
- 根拠ファイル:
  - `ProjectProfit/Views/Accounting/EtaxExportView.swift`
  - `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
  - `ProjectProfit/Views/Settings/ProfileSettingsView.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/FormEngineTests.swift`
- 事実:
  - ViewModel / FormEngine / ProfileSettings には `.blueCashBasis` が存在する。
  - ただし `EtaxExportView` の申告種類 Picker は `青色申告` と `白色申告` しか表示しない。
  - 現金主義を UI から選んで export できる証跡は、この repo 内では確認できない。

## 4. 機能軸の判定

| 機能領域 | 判定 | 2026-03-14 時点の結論 |
| --- | --- | --- |
| 証憑取込 | 実装済み | receipt / share extension / statement import / evidence inbox を repo 内で確認 |
| 承認 | 実装済み | approval queue, candidate approve/reject, distribution approval を確認 |
| プロジェクト配賦/按分 | 実装済み | project workflow と pro-rata 再計算系テストが通過 |
| 定期取引 | 実装済み | recurring 単体の preview / approve main path と代表テストを current HEAD で再確認 |
| 銀行/カード照合 | 実装済み | 導線・import・match・Books 入口を確認 |
| 帳簿/帳票 | 部分実装 | books lane は green だが申告 builder に legacy 依存が残る |
| 固定資産/棚卸 | representative tests 再確認済み | workflow use case の 2 スイートを current HEAD で再実行し、11件 green を確認 |
| 源泉徴収 | 実装済み | 年次一覧・支払先別・CSV/PDF・UI/E2E を確認 |
| e-Tax/申告前チェック | 不具合再現 | preflight の仮勘定検知テスト失敗、現金主義 UI 到達性も不足 |
| release artifact | 部分実装 | books/forms の個票は更新済みだが fully-green curated snapshot は current HEAD と不一致 |

### 4-1. 証憑取込

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Views/Receipt/ReceiptScannerView.swift`
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift`
  - `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`
  - `ProjectProfit/Features/EvidenceInbox/EvidenceInboxView.swift`
  - `ProjectProfitShareExtension/ShareViewController.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/ReceiptEvidenceIntakeUseCaseTests.swift`

### 4-2. 承認

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Features/ApprovalQueue/ApprovalQueueView.swift`
  - `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift`
  - `ProjectProfit/Application/UseCases/Posting/ApprovalQueueWorkflowUseCase.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/DistributionApprovalIntegrationTests.swift`
  - `ProjectProfitUITests/WithholdingApprovalUITests.swift`

### 4-3. プロジェクト配賦/按分

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Application/UseCases/Projects/ProjectWorkflowUseCase.swift`
  - `ProjectProfit/Application/UseCases/Projects/ProjectAllocationReprocessor.swift`
  - `ProjectProfit/Application/UseCases/Distribution/DistributionTemplateApplicationUseCase.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/ProjectWorkflowUseCaseTests.swift`
  - `ProjectProfitTests/ProRataDataStoreTests.swift`
  - 2026-03-14 再実行で両方通過

### 4-4. 定期取引

- 2026-03-14 時点の結論: `実装済み（recurring 単体） / 部分実装（REL-P1-03 全体）`
- 根拠ファイル:
  - `ProjectProfit/Views/ContentView.swift`
  - `ProjectProfit/Features/Recurring/RecurringPreviewView.swift`
  - `ProjectProfit/Application/UseCases/Recurring/RecurringWorkflowUseCase.swift`
  - `ProjectProfit/Application/UseCases/Recurring/RecurringPostingCoordinator.swift`
  - `ProjectProfit/Views/Components/RecurringFormView.swift`
  - `ProjectProfit/Views/Components/TransactionFormView.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/RecurringPreviewTests.swift`
  - `ProjectProfitTests/RecurringProcessingTests.swift`
  - `ProjectProfitTests/RecurringQueryUseCaseTests.swift`
  - `ProjectProfitTests/RecurringWorkflowUseCaseTests.swift`
  - 2026-03-14 / current HEAD `a32682c` で 56件実行、0 failures、1 skip
- 事実:
  - 起動時 preview 読込、pending recurring の sheet 表示、一括承認、canonical journal 作成までの recurring main path は repo 内コードと current HEAD の再実行結果で確認できた。
  - `RecurringWorkflowUseCaseTests` の代表テストで preview 生成、approve 後の canonical journal 作成、bookkeeping 更新を確認した。
  - skip 1件は legacy `PPTransaction` 削除前提テストであり、current recurring main path の失敗ではない。
  - ただし distribution preview → approve はフォーム内直接適用経路が残るため、`REL-P1-03` チケット全体では `部分実装` のままである。

### 4-5. 銀行/カード照合

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Features/Reconciliation/BankCardReconciliationView.swift`
  - `ProjectProfit/Application/UseCases/Statements/StatementImportUseCase.swift`
  - `ProjectProfit/Application/UseCases/Statements/StatementMatchService.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/StatementImportUseCaseTests.swift`
  - `ProjectProfitTests/BooksWorkspaceViewTests.swift`

### 4-6. 帳簿/帳票

- 2026-03-14 時点の結論: `部分実装`
- 根拠ファイル:
  - `ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift`
  - `ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift`
  - `ProjectProfit/Services/FormEngine.swift`
  - `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
  - `ProjectProfit/Services/CashBasisReturnBuilder.swift`
- 根拠テストまたは実行結果:
  - `Docs/release/quality/books.md`
  - `ProjectProfitTests/BooksWorkspaceViewTests.swift`
- 事実:
  - Books ワークスペース、仕訳ブラウザ、分析導線はある。
  - 一方で申告帳票生成の builder 側には legacy 依存が残る。

### 4-7. 固定資産/棚卸

- 2026-03-14 時点の結論: `representative tests 再確認済み`
- 根拠ファイル:
  - `ProjectProfit/Views/Accounting/FixedAssetListView.swift`
  - `ProjectProfit/Views/Accounting/InventoryInputView.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/FixedAssetWorkflowUseCaseTests.swift`
  - `ProjectProfitTests/InventoryWorkflowUseCaseTests.swift`
  - 2026-03-14 / current HEAD `8b525b6811f90a99610eb4b713972478ee60fbc1` で再実行
  - 実行コマンド:

```bash
xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ProjectProfitTests/FixedAssetWorkflowUseCaseTests \
  -only-testing:ProjectProfitTests/InventoryWorkflowUseCaseTests \
  test
```

  - 結果:
    - 実行テスト数: 11
    - 失敗: 0
    - simulator: `iPhone 17 Pro`
- 事実:
  - 実装とテストファイルは存在する。
  - `FixedAssetWorkflowUseCaseTests` 7件が current HEAD で通過した。
  - create / save / dispose / delete cascade / depreciation posting / post all / locked year block を再確認した。
  - `InventoryWorkflowUseCaseTests` 4件が current HEAD で通過した。
  - create / update / locked year create block / locked year update block を再確認した。
  - 今回確認したのは workflow use case レベルであり、固定資産帳票や棚卸の決算書反映までを全面保証する証跡ではない。

### 4-8. 源泉徴収

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Views/Accounting/WithholdingStatementView.swift`
  - `ProjectProfit/ViewModels/WithholdingStatementViewModel.swift`
  - `ProjectProfit/Application/UseCases/Filing/WithholdingStatementQueryUseCase.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/WithholdingFlowE2ETests.swift`
  - `ProjectProfitUITests/WithholdingApprovalUITests.swift`
  - 2026-03-14 再実行で E2E 通過

### 4-9. e-Tax / 申告前チェック

- 2026-03-14 時点の結論: `不具合再現 + 部分実装`
- 根拠ファイル:
  - `ProjectProfit/Views/Accounting/EtaxExportView.swift`
  - `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
  - `ProjectProfit/Application/UseCases/Filing/FilingPreflightUseCase.swift`
  - `ProjectProfit/Application/UseCases/Filing/FilingDashboardQueryUseCase.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/EtaxExportViewModelTests.swift`
  - `ProjectProfitTests/FilingPreflightUseCaseTests.swift`
  - 2026-03-14 再実行で `EtaxExportViewModelTests` は通過、`FilingPreflightUseCaseTests` は1件失敗
- 事実:
  - e-Tax preview / export 自体は実装されている。
  - 申告前チェックの仮勘定検知は現HEADで失敗している。
  - 現金主義は ViewModel / FormEngine に存在するが、UI picker では選択肢が見えない。

### 4-10. release artifact

- 2026-03-14 時点の結論: `部分実装`
- 根拠ファイル:
  - `Docs/release/checklist.md`
  - `Docs/release/quality/latest.md`
  - `Docs/release/quality/books.md`
  - `Docs/release/quality/forms.md`
- 根拠テストまたは実行結果:
  - `git rev-parse --short HEAD` -> `a32682c`
- 事実:
  - curated fully-green snapshot は current HEAD を指していない。
  - lane 個票は一部更新されている。

## 5. 追加で確認できたリポジトリ整合性の問題

### 5-1. 外部依存の説明は `AGENTS.md` 修正で整合した

- 2026-03-14 時点の結論: `解消済み`
- 根拠ファイル:
  - `AGENTS.md`
  - `project.yml`
  - `ProjectProfit/Ledger/Services/LedgerExcelExportService.swift`
- 根拠テストまたは実行結果:
  - 2026-03-14 の `xcodebuild` 実行で `libxlsxwriter @ 1.2.4` を解決
- 事実:
  - `project.yml` に `libxlsxwriter` の SwiftPM package がある。
  - `LedgerExcelExportService.swift` も `xlsxwriter` を import している。
  - `AGENTS.md` を `libxlsxwriter` 利用前提の説明へ更新した。

## 6. 最重要 blocker

1. `仮勘定残高の preflight 検知不全`
   - 再現済み
   - failing test がある
2. `現金主義 export UI 欠落`
   - ViewModel / builder はある
   - 画面入口が repo 内で確認できない
3. `申告系の legacy 依存残存`
   - FormEngine / 白色 / 現金主義 builder に残る
4. `current HEAD に対応する fully-green release 証跡不足`
   - curated latest と HEAD が一致しない

## 7. 「確定申告できる」についての事実ベース結論

- repo 内で確認できた事実:
  - 申告データ生成機能はある。
  - e-Tax preview / `.xtx` / `.csv` 出力機能はある。
  - 源泉徴収の年次一覧 / 支払先別出力機能はある。
  - recurring 単体の preview / approve main path は current HEAD の代表再実行で green を確認した。
- repo 内で確認できなかった、または阻害要因がある事実:
  - 仮勘定残高 blocker の担保は現HEADで失敗している。
  - 現金主義の UI 到達性は未証明。
  - current HEAD に対応した fully-green release 証跡は repo 内で揃っていない。
  - e-Tax 実受理や制度適合を示す repo 内証跡はない。

したがって、2026-03-14 時点の repo だけを根拠に「確定申告できる」と断定することはできない。  
断定できるのは「申告データ生成と出力機能は存在するが、release 判定と制度適合の証明は未完了」という範囲までである。
