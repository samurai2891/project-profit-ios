# ProjectProfit 機能監査メモ（2026-04-07）

| 機能名 | 状態 | 問題 | ユーザー影響 | 優先度 | 根拠 | 修正方針 | 修正結果 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 税務年 `taxYear` | 修正済み | 一部経路で会計年度 `fiscalYear` を流用していた | 年分別の候補・証憑・支払調書が誤年に入る | P0 | `PostingIntakeUseCase`, `CanonicalPostingSupport`, `AccountingBootstrapService`, `WithholdingStatementViewModel` | `taxYear(for:)` と `currentTaxYear()` に統一 | 候補生成、CSV証憑、支払調書UIを暦年基準へ修正 |
| 支払調書 UI | 修正済み | 初期年と年選択が `currentFiscalYear` 依存だった | 年分選択が暦年仕様とずれる | P1 | `WithholdingStatementView.swift`, `WithholdingStatementViewModel.swift` | 年分ラベルと上限を暦年へ統一 | `年分` 表示へ変更し `currentTaxYear()` を使用 |
| legacy receipt backfill | 修正済み | 既存 document があるだけで legacy image を削除し得た | 書類ファイル欠損時のデータ消失 | P0 | `DataStore.swift` | 実ファイル存在確認後だけ cleanup | 既存 document file 欠損時は legacy image を保持するよう修正 |
| share import queue | 修正済み | shared container 不達時 prune、decode失敗時上書き、consume順序が危険 | 共有取込キュー消失、孤児ファイル化 | P0 | `ShareImportInboxService.swift`, `ShareViewController.swift` | 診断保持、queue保持、削除順序変更 | queue を安易に消さない実装へ変更 |
| BooksWorkspace 帳簿一覧 | 修正済み | 実装とテスト期待値が不一致 | 帳簿一覧の回帰検知が赤化 | P0 | `BooksWorkspaceView.swift`, `BooksWorkspaceViewTests.swift`, `WorkflowNavigationTests.swift` | 実装を正本にしてテスト追従 | `交通費精算書` を含む期待値へ更新 |
| Projects 導線 | 修正済み | `ProjectsView` がメイン導線から到達不能 | 案件管理が実質未公開 | P1 | `ContentView.swift`, `ProjectsView.swift` | MainTab に復帰 | `案件` タブを追加 |
| 棚卸レコード | 修正済み | 同一年複数件で取得が不定 | 棚卸・COGS が登録順依存 | P1 | `PPInventoryRecord.swift`, `InventoryWorkflowUseCase.swift`, `SwiftDataInventoryRepository.swift` | 重複禁止 + deterministic fetch | 同年 duplicate 作成を拒否し fetch を更新日時順に固定 |
| UI 日本語統一 | 修正済み | Approval Queue / Inbox / import result などに英語混在 | UI 品質低下、仕様逸脱 | P1 | `ApprovalQueueView.swift`, `EvidenceInboxView.swift`, `TransactionsView.swift`, `SettingsMainView.swift`, `SettingsView.swift`, `TransactionFormView.swift`, `RecurringFormView.swift` | 日本語表記へ統一 | 主要露出文言を日本語へ修正 |
| UI テスト補強 | 修正済み | 承認・申告偏重で Projects / Books の回帰検知が薄い | 主要導線の破損を見逃す | P2 | `WithholdingApprovalUITests.swift` | 代表導線を追加 | Projects タブと Books 上の交通費精算書確認を追加 |
| 旧 Settings / Category 画面 | 修正済み | 未接続の旧画面が現行画面と別実装で残っていた | 将来の仕様ドリフト | P2 | `SettingsView.swift`, `CategoryManageView.swift` | 互換ラッパーへ集約 | 現行 `SettingsMainView` / `CategoryListView` へ転送 |
| Canonical posting の silent failure | 修正済み | 検索インデックス再構築と監査保存の失敗が表面化しなかった | 承認失敗の原因追跡が困難 | P1 | `CanonicalPostingEngine.swift`, `PostingWorkflowUseCase.swift` | 明示エラーへ昇格 | `searchIndexRebuildFailed` / `auditTrailPersistenceFailed` を追加 |
| golden 帳票スナップショット | 修正済み | 帳票期待値が旧 `雑費` 集約のままだった | 正常な勘定内訳でも baseline が赤化 | P1 | `ProjectProfitTests/Golden/expected/*.json` | 現行の科目内訳へ更新 | `blue_return` `consumption_tax_worksheet` `journal_book` `trial_balance` を更新し `GoldenBaselineTests` green を確認 |

## 最終ルール

- `taxYear` は常に暦年を意味する
- `fiscalYear` は会計年度を意味する
- 共有取込キューは失敗時に保持し、明示的に失敗を診断へ残す
- legacy receipt migration は「既存 document file が存在する」場合のみ legacy image を掃除する

## 追加した回帰確認

- `PostingIntakeUseCaseTests`: `startMonth != 1` でも CSV 証憑が暦年 `taxYear` を使うこと
- `WithholdingStatementQueryUseCaseTests`: `startMonth != 1` でも支払調書集計が暦年で動くこと
- `DocumentAndSubLedgerTests`: existing document file 欠損時に legacy image を保持すること
- `InventoryWorkflowUseCaseTests`: 同一年 duplicate を拒否すること
- `ShareImportInboxServiceTests`: shared container 不達時に queue を保持すること
- `CanonicalUseCasesTests`: 監査イベント保存失敗が明示エラーになること
- `GoldenBaselineTests`: `雑費` 集約ではなく科目別内訳を正本に更新し green を確認
