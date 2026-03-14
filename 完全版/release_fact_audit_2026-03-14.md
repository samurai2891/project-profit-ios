# ProjectProfit リリース事実監査レポート
作成日: 2026-03-14  
対象 HEAD: `fe19501`  
対象リポジトリ: `/Users/yutaro/project-profit-ios`

## 1. 監査条件

- 本レポートは repo 内コード、repo 内ドキュメント、repo 内テスト、2026-03-14 の再実行結果だけを根拠に記載する。
- 推測は含めない。
- repo 外の法令適合証明、e-Tax 受理保証、App Store / GitHub 外設定は「未確認/未証明」と扱う。
- 参照した主資料:
  - `完全版/release_remaining_work_breakdown_2026-03-13.md`
  - `完全版/release_ticket_list.md`
  - `完全版/revised_release_ticket_list.md`
  - `Docs/release_checklist.md`
  - `Docs/release_quality/latest.md`
  - `Docs/release_quality/books.md`
  - `Docs/release_quality/forms.md`

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

### 3-2. 部分実装

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
  - `Docs/release_quality/latest.md`
  - `Docs/release_quality/books.md`
  - `Docs/release_quality/forms.md`
  - `Docs/release_checklist.md`
- 根拠テストまたは実行結果:
  - `git rev-parse --short HEAD` -> `fe19501`
- 事実:
  - `latest.md` の curated fully-green snapshot は `86b7b08...` / 2026-03-07 を指している。
  - `books.md` と `forms.md` には 2026-03-14 の green 証跡がある。
  - 現HEAD `fe19501` に対して、checklist 対象 4 lane fully-green の curated 更新は repo 内で確認できない。

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
| 定期取引 | 部分実装 | recurring 本線は存在するが、この監査では release 全面保証までは未証明 |
| 銀行/カード照合 | 実装済み | 導線・import・match・Books 入口を確認 |
| 帳簿/帳票 | 部分実装 | books lane は green だが申告 builder に legacy 依存が残る |
| 固定資産/棚卸 | 未確認/未証明 | 実装とテストファイルは存在するが、今回の再実行対象外 |
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

### 4-4. 銀行/カード照合

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Features/Reconciliation/BankCardReconciliationView.swift`
  - `ProjectProfit/Application/UseCases/Statements/StatementImportUseCase.swift`
  - `ProjectProfit/Application/UseCases/Statements/StatementMatchService.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/StatementImportUseCaseTests.swift`
  - `ProjectProfitTests/BooksWorkspaceViewTests.swift`

### 4-5. 帳簿/帳票

- 2026-03-14 時点の結論: `部分実装`
- 根拠ファイル:
  - `ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift`
  - `ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift`
  - `ProjectProfit/Services/FormEngine.swift`
  - `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
  - `ProjectProfit/Services/CashBasisReturnBuilder.swift`
- 根拠テストまたは実行結果:
  - `Docs/release_quality/books.md`
  - `ProjectProfitTests/BooksWorkspaceViewTests.swift`
- 事実:
  - Books ワークスペース、仕訳ブラウザ、分析導線はある。
  - 一方で申告帳票生成の builder 側には legacy 依存が残る。

### 4-6. 固定資産/棚卸

- 2026-03-14 時点の結論: `未確認/未証明`
- 根拠ファイル:
  - `ProjectProfit/Views/Accounting/FixedAssetListView.swift`
  - `ProjectProfit/Views/Accounting/InventoryInputView.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/FixedAssetWorkflowUseCaseTests.swift`
  - `ProjectProfitTests/InventoryWorkflowUseCaseTests.swift`
- 事実:
  - 実装とテストファイルは存在する。
  - ただし今回の再実行対象に含めていないため、2026-03-14 の動作再確認まではしていない。

### 4-7. 源泉徴収

- 2026-03-14 時点の結論: `実装済み`
- 根拠ファイル:
  - `ProjectProfit/Views/Accounting/WithholdingStatementView.swift`
  - `ProjectProfit/ViewModels/WithholdingStatementViewModel.swift`
  - `ProjectProfit/Application/UseCases/Filing/WithholdingStatementQueryUseCase.swift`
- 根拠テストまたは実行結果:
  - `ProjectProfitTests/WithholdingFlowE2ETests.swift`
  - `ProjectProfitUITests/WithholdingApprovalUITests.swift`
  - 2026-03-14 再実行で E2E 通過

### 4-8. e-Tax / 申告前チェック

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

### 4-9. release artifact

- 2026-03-14 時点の結論: `部分実装`
- 根拠ファイル:
  - `Docs/release_checklist.md`
  - `Docs/release_quality/latest.md`
  - `Docs/release_quality/books.md`
  - `Docs/release_quality/forms.md`
- 根拠テストまたは実行結果:
  - `git rev-parse --short HEAD` -> `fe19501`
- 事実:
  - curated fully-green snapshot は current HEAD を指していない。
  - lane 個票は一部更新されている。

## 5. 追加で確認できたリポジトリ整合性の問題

### 5-1. 外部依存なしという説明と現コードが一致しない

- 2026-03-14 時点の結論: `説明不整合`
- 根拠ファイル:
  - `project.yml`
  - `ProjectProfit/Ledger/Services/LedgerExcelExportService.swift`
- 根拠テストまたは実行結果:
  - 2026-03-14 の `xcodebuild` 実行で `libxlsxwriter @ 1.2.4` を解決
- 事実:
  - `project.yml` に `libxlsxwriter` の SwiftPM package がある。
  - `LedgerExcelExportService.swift` も `xlsxwriter` を import している。
  - 少なくとも現HEADは「外部 package なし」ではない。

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
- repo 内で確認できなかった、または阻害要因がある事実:
  - 仮勘定残高 blocker の担保は現HEADで失敗している。
  - 現金主義の UI 到達性は未証明。
  - current HEAD に対応した fully-green release 証跡は repo 内で揃っていない。
  - e-Tax 実受理や制度適合を示す repo 内証跡はない。

したがって、2026-03-14 時点の repo だけを根拠に「確定申告できる」と断定することはできない。  
断定できるのは「申告データ生成と出力機能は存在するが、release 判定と制度適合の証明は未完了」という範囲までである。
