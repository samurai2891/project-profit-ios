# ProjectProfit リリース残課題 WBS
## 監査反映版 / 2026-03-13

作成日: 2026-03-13  
対象: `/Users/yutaro/project-profit-ios` 現行リポジトリ  
目的: 2026-03-13 の実コード監査結果を正本として、未完了の実装課題だけを、そのまま着手できる粒度まで分解する。

この文書は `revised_release_ticket_list.md` を置き換えるものではない。  
`revised_release_ticket_list.md` は参照資料として残し、本書を**残課題の実装 WBS 正本**として扱う。

---

# 0. 文書の使い方

## 0-1. この文書が扱うもの

- 2026-03-13 監査で `部分実装` と再判定された REL のみ
- 実装に直結するタスク
- 依存関係
- 完了条件
- 必須検証

## 0-2. この文書が扱わないもの

- 監査で `完了` と再判定された REL の再説明
- `revised_release_ticket_list.md` の古い判定の維持
- 実値を repo 内で確定できない外部設定

## 0-3. 状態の前提

2026-03-13 監査時点で、以下の REL は実装対象から除外する。

- `REL-P0-04`
- `REL-P0-07`
- `REL-P0-09`
- `REL-P0-10`
- `REL-P0-11`
- `REL-P1-01`
- `REL-P1-02`
- `REL-P1-06`
- `REL-P2-01`
- `REL-P2-06`

## 0-4. タスク記法

各タスクは以下の項目を必須とする。

- `ID`
- `優先度`
- `REL`
- `目的`
- `実装内容`
- `主対象`
- `依存`
- `完了条件`
- `検証`

補足:

- 本書の正式な着手順は `# 2. 実装順序` を正とする
- `WBS-P0-02-04` は 1 タスクのまま管理し、実行時は `P0-02-04A` と `P0-02-04B` の 2 スライスに分ける

---

# 1. Fresh Status サマリー

## 1-1. 実装対象 REL 一覧

| REL | fresh status | 残課題の主題 |
| --- | --- | --- |
| `REL-P0-01` | 部分実装 | canonical cutover 完了後の legacy 互換層撤去 |
| `REL-P0-02` | 部分実装 | `DataStore` 依存縮退、query/workflow 境界の完成 |
| `REL-P0-03` | 部分実装 | `PPAccountingProfile` 互換経路の完全整理 |
| `REL-P0-05` | 部分実装 | canonical year lock 以外の互換経路撤去 |
| `REL-P0-06` | 部分実装 | `taxCodeId` 正本化と legacy 税属性撤去 |
| `REL-P0-08` | 部分実装 | posting 本線の canonical engine 一本化 |
| `REL-P0-12` | 部分実装 | release gate 証跡ファイルの repo 内整備 |
| `REL-P1-03` | 部分実装 | recurring/distribution 承認 UX の統一 |
| `REL-P1-04` | 部分実装 | 帳簿生成 API の canonical 一本化 |
| `REL-P1-05` | 部分実装 | FormEngine 入力の canonical 一本化 |
| `REL-P1-07` | 部分実装 | workflow UI 旧導線の整理 |
| `REL-P1-08` | 部分実装 | ExportCoordinator の本線統一 |
| `REL-P2-02` | 部分実装 | classification の canonical 入力対応 |
| `REL-P2-03` | 部分実装 | withholding main path と E2E 完成 |
| `REL-P2-04` | 部分実装 | import チャネルの canonical 統一 |
| `REL-P2-05` | 部分実装 | release 補助ファイルの管理境界整理 |

## 1-2. 監査反映で修正済みの前提

- `REL-P2-01` は未実装ではない。銀行/カード照合 UI、取込、照合ロジック、導線、テストが存在する。
- `REL-P2-03` は UI/出力フロー未確認ではない。`WithholdingStatementView`、`WithholdingStatementQueryUseCase`、`ExportCoordinator`、テストが存在する。
- `REL-P2-05` は release checklist 未確認ではない。`Docs/release/checklist.md` が存在する。
- `REL-P0-12` は latest green 根拠が repo にない状態ではない。`Docs/release/quality/latest.md` が存在する。
- `REL-P1-07` の旧導線は `AccountingHomeView` ではない。現 repo で確認できる残存旧導線は `BooksWorkspaceView -> ReportView()` および `BooksWorkspaceView -> JournalListView()` である。
- `REL-P2-02` は approval 時学習が未接続ではない。`PostingWorkflowUseCase.learnFromApprovedCandidateIfPossible(...)` が接続済みである。

---

# 2. 実装順序

## 2-1. 並べ替え方針

- 先に境界を固定し、その後に canonical 入力、posting 本線、帳簿/帳票投影、UI 導線、import/classification/withholding、release artifact の順で進める
- 循環依存があった箇所は、`PostingIntakeStore` の責務分離を先に行い、その成果を `PostingWorkflowUseCase` 統一側が使う形に直す
- docs/release artifact は最後に更新し、実装途中の仮状態を正本にしない

## 2-2. 安全な実装順序

1. `WBS-P0-01-01`
2. `WBS-P0-02-01`
3. `WBS-P0-02-02`
4. `P0-02-04A`
5. `WBS-P0-06-01`
6. `WBS-P0-06-02`
7. `WBS-P0-08-01`
8. `WBS-P0-01-02` -> `WBS-P0-08-02`
9. `WBS-P0-02-05`
10. `WBS-P0-01-03`
11. `WBS-P0-03-01` -> `WBS-P0-03-02` -> `WBS-P0-03-03`
12. `WBS-P0-05-01` -> `WBS-P0-05-02`
13. `WBS-P0-06-03`
14. `WBS-P1-04-01`
15. `WBS-P0-02-03`
16. `WBS-P1-04-02` -> `WBS-P1-04-03`
17. `WBS-P0-08-03`
18. `WBS-P1-05-01` -> `WBS-P1-05-02` -> `WBS-P1-05-03`
19. `P0-02-04B`
20. `WBS-P1-08-01` -> `WBS-P1-08-02` -> `WBS-P1-08-03`
21. `WBS-P1-07-01` -> `WBS-P1-07-02`
22. `WBS-P1-03-01` -> `WBS-P1-03-02` -> `WBS-P1-03-03`
23. `WBS-P2-04-01` -> `WBS-P2-04-02`
24. `WBS-P2-02-01` -> `WBS-P2-02-02` -> `WBS-P2-02-03`
25. `WBS-P2-03-01` -> `WBS-P2-03-02`
26. `WBS-P0-12-01` -> `WBS-P0-12-02` -> `WBS-P2-05-01`

## 2-3. Wave 別の完了条件

### Wave 1: 境界固定と posting 前提整理

- `WBS-P0-01-01`
- `WBS-P0-02-01`
- `WBS-P0-02-02`
- `P0-02-04A`
- `WBS-P0-06-01`
- `WBS-P0-06-02`
- `WBS-P0-08-01`
- `WBS-P0-01-02`
- `WBS-P0-08-02`
- `WBS-P0-02-05`
- `WBS-P0-01-03`

完了条件:

- legacy mutation API が production path から見えない
- posting の入口が `PostingWorkflowUseCase` / `CanonicalPostingEngine` に揃う
- `ContentView` の bootstrap/reload/preview が workflow/query port 化される

### Wave 2: profile / year lock / tax 正本の固定

- `WBS-P0-03-01`
- `WBS-P0-03-02`
- `WBS-P0-03-03`
- `WBS-P0-05-01`
- `WBS-P0-05-02`
- `WBS-P0-06-03`

完了条件:

- profile と year lock の正本が canonical profile に揃う
- legacy 税属性が compat 用途へ閉じる

### Wave 3: 帳簿・帳票・e-Tax 入力の canonical 化

- `WBS-P1-04-01`
- `WBS-P0-02-03`
- `WBS-P1-04-02`
- `WBS-P1-04-03`
- `WBS-P0-08-03`
- `WBS-P1-05-01`
- `WBS-P1-05-02`
- `WBS-P1-05-03`
- `P0-02-04B`

完了条件:

- books/report/form build の入力が canonical projection に揃う
- `EtaxExportView` が `DataStore` direct read なしで成立する

### Wave 4: export / UI / approval workflow の統一

- `WBS-P1-08-01`
- `WBS-P1-08-02`
- `WBS-P1-08-03`
- `WBS-P1-07-01`
- `WBS-P1-07-02`
- `WBS-P1-03-01`
- `WBS-P1-03-02`
- `WBS-P1-03-03`

完了条件:

- export の入口が `ExportCoordinator` に一本化される
- books workflow UI と distribution approval が canonical workflow に揃う

### Wave 5: import / classification / withholding / release artifact 完成

- `WBS-P2-04-01`
- `WBS-P2-04-02`
- `WBS-P2-02-01`
- `WBS-P2-02-02`
- `WBS-P2-02-03`
- `WBS-P2-03-01`
- `WBS-P2-03-02`
- `WBS-P0-12-01`
- `WBS-P0-12-02`
- `WBS-P2-05-01`

完了条件:

- import/classification/withholding が candidate/evidence 本線で閉じる
- release checklist と release evidence の参照先が最終状態で揃う

---

# 3. REL別実装タスク

## REL-P0-01 単一正本への cutover 完了

### `WBS-P0-01-01`

- `優先度`: `P0`
- `REL`: `REL-P0-01`
- `目的`: DEBUG 互換 legacy mutation 層を production 本線から完全に隔離する
- `実装内容`:
  - `LegacyTransactionCompatibilityUseCase` を test/debug 専用境界に閉じる
  - production target から直接参照できない可視性に変更する
  - `TestMutationDriver` 以外の参照元を 0 にする
- `主対象`:
  - `ProjectProfit/Application/UseCases/Legacy/LegacyTransactionCompatibilityUseCase.swift`
  - `ProjectProfitTests/TestMutationDriver.swift`
- `依存`: なし
- `完了条件`:
  - production target で `addTransactionResult`, `updateTransaction`, `deleteTransaction`, `guardLegacyTransactionMutationAllowed` を参照しない
  - legacy mutation API が test/debug 境界外へ export されない
- `検証`:
  - `rg` で production caller が 0 件
  - `ProjectProfitTests/DataStoreAccountingTests.swift`

### `WBS-P0-01-02`

- `優先度`: `P0`
- `REL`: `REL-P0-01`
- `目的`: approved candidate 同期の互換経路を本線から外す
- `実装内容`:
  - `syncCanonicalArtifacts(forTransactionId:)` と `syncApprovedCandidate(...)` の production path 依存を除去する
  - canonical journal 作成後の副作用は `PostingWorkflowUseCase` / `CanonicalPostingEngine` に集約する
  - `DataStore` での互換同期呼び出しを debug/test support に限定する
- `主対象`:
  - `ProjectProfit/Services/DataStore.swift`
  - `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift`
- `依存`: `WBS-P0-01-01`
- `完了条件`:
  - production posting path が `syncApprovedCandidate(...)` を呼ばない
  - canonical 承認後の派生更新が use case 側で完結する
- `検証`:
  - `ProjectProfitTests/CanonicalUseCasesTests.swift`
  - `ProjectProfitTests/DataStoreAccountingTests.swift`

### `WBS-P0-01-03`

- `優先度`: `P0`
- `REL`: `REL-P0-01`
- `目的`: 単一正本への cutover 完了をコンパイル時に保証する
- `実装内容`:
  - legacy mutation API を production compile path から除外する
  - cutover 状態を壊す互換 helper に対して feature flag と target 境界の両方で制約を掛ける
  - 取引作成/更新/削除の本線を candidate workflow のみとする
- `主対象`:
  - `ProjectProfit/App/FeatureFlags.swift`
  - `ProjectProfit/Application/UseCases/Legacy/`
- `依存`: `WBS-P0-01-01`, `WBS-P0-01-02`
- `完了条件`:
  - production path から legacy transaction mutation symbols が見えない
  - main path の create/update/delete が候補 workflow のみを通る
- `検証`:
  - `ProjectProfitTests/PostingIntakeUseCaseTests.swift`
  - `ProjectProfitTests/CanonicalUseCasesTests.swift`

## REL-P0-02 Repository / UseCase 層の完成

### `WBS-P0-02-01`

- `優先度`: `P0`
- `REL`: `REL-P0-02`
- `目的`: `PostingIntakeStore` の責務を persistence adapter に縮める
- `実装内容`:
  - CSV/manual intake の orchestration を `PostingIntakeUseCase` または専用 coordinator に引き上げる
  - `PostingIntakeStore` は repository 呼び出しと entity 保存だけを担当する
  - `LedgerCSVImportService` 依存は `REL-P2-04` 側の canonical importer に渡せる境界へ整理する
- `主対象`:
  - `ProjectProfit/Application/UseCases/Posting/PostingIntakeStore.swift`
  - `ProjectProfit/Application/UseCases/Posting/PostingIntakeUseCase.swift`
- `依存`: なし
- `完了条件`:
  - `PostingIntakeStore` が workflow branching や cross-aggregate orchestration を持たない
  - import / manual save の本線責務が use case 側に揃う
- `検証`:
  - `ProjectProfitTests/PostingIntakeUseCaseTests.swift`
  - `ProjectProfitTests/StatementImportUseCaseTests.swift`

### `WBS-P0-02-02`

- `優先度`: `P0`
- `REL`: `REL-P0-02`
- `目的`: `ProjectWorkflowStore` と `RecurringWorkflowStore` を persistence adapter に縮める
- `実装内容`:
  - project completion / allocation recalculation / recurring preview / approve orchestration を store から use case/coordinator へ移す
  - store は repository 書き込みと transaction 単位の保存に限定する
  - `DataStore` 再計算呼び出しに依存しない workflow 境界を作る
- `主対象`:
  - `ProjectProfit/Application/UseCases/Projects/ProjectWorkflowStore.swift`
  - `ProjectProfit/Application/UseCases/Recurring/RecurringWorkflowStore.swift`
- `依存`: `WBS-P0-02-01`
- `完了条件`:
  - `*WorkflowStore` が aggregate 跨ぎの再計算指示を持たない
  - workflow の主導権が use case に揃う
- `検証`:
  - `ProjectProfitTests/ProjectWorkflowUseCaseTests.swift`
  - `ProjectProfitTests/RecurringWorkflowUseCaseTests.swift`

### `WBS-P0-02-03`

- `優先度`: `P0`
- `REL`: `REL-P0-02`
- `目的`: 会計 read path を query/use case 化し、legacy report input を隔離する
- `実装内容`:
  - report/books 系の read model を `AccountingReadSupport` から screen-specific query/use case に分割する
  - `JournalListView`, `LedgerView`, `SubLedgerView`, `FixedAssetListView`, `ClosingEntryView` の read path を query use case 経由へ統一する
  - legacy `PPJournalEntry` / `PPJournalLine` 依存の read model は adapter 層に押し込む
- `主対象`:
  - `ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift`
  - `ProjectProfit/Views/Accounting/`
- `依存`: `WBS-P1-04-01`
- `完了条件`:
  - 上記画面が `DataStore` read API を直接読まない
  - screen ごとに query/use case を持つ
- `検証`:
  - `ProjectProfitTests/AccountingReadQueryUseCaseTests.swift`
  - `ProjectProfitTests/ReportingQueryUseCaseTests.swift`

### `WBS-P0-02-04`

- `優先度`: `P0`
- `REL`: `REL-P0-02`
- `目的`: bootstrap / export UI の `DataStore` read 依存を外す
- `実装内容`:
  - `P0-02-04A`: `ContentView` の bootstrap, reload, recurring preview を workflow/query port に置き換える
  - `P0-02-04B`: `EtaxExportView` が `DataStore` を直接保持しないように query/use case へ切り替える
  - 画面側に必要な状態は immutable snapshot で受ける
- `主対象`:
  - `ProjectProfit/Views/ContentView.swift`
  - `ProjectProfit/Views/Accounting/EtaxExportView.swift`
- `依存`:
  - `P0-02-04A`: `WBS-P0-02-02`
  - `P0-02-04B`: `WBS-P1-05-03`
- `完了条件`:
  - `P0-02-04A`: `ContentView` の bootstrap/reload/preview が workflow/query 経由で完結する
  - `P0-02-04B`: `EtaxExportView` で `DataStore` の direct read が 0 件になる
- `検証`:
  - `P0-02-04A`: `ProjectProfitTests/AppShellWorkflowUseCaseTests.swift`
  - `P0-02-04B`: `ProjectProfitTests/EtaxExportViewModelTests.swift`

### `WBS-P0-02-05`

- `優先度`: `P0`
- `REL`: `REL-P0-02`
- `目的`: test-only legacy mutation path を support module に集約する
- `実装内容`:
  - `TestMutationDriver` を legacy compat test support の単一入口にする
  - test suite ごとの直接 legacy API 呼び出しを `TestMutationDriver` に寄せる
  - production module 側には test 専用 helper を残さない
- `主対象`:
  - `ProjectProfitTests/TestMutationDriver.swift`
  - `ProjectProfitTests/`
- `依存`: `WBS-P0-01-01`
- `完了条件`:
  - legacy mutation の test caller が `TestMutationDriver` へ統一される
  - production module から test support API が見えない
- `検証`:
  - `ProjectProfitTests/DataStoreCRUDTests.swift`
  - `ProjectProfitTests/RecurringProcessingTests.swift`

## REL-P0-03 `PPAccountingProfile` 互換撤去

### `WBS-P0-03-01`

- `優先度`: `P0`
- `REL`: `REL-P0-03`
- `目的`: `PPAccountingProfile` を migration-only 互換に限定する
- `実装内容`:
  - `PPAccountingProfile` を production read/write 正本として扱う経路を全撤去する
  - profile 正本は `BusinessProfile` / `TaxYearProfile` のみとする
  - migration 実行後に必要な最低限の互換用途だけを定義する
- `主対象`:
  - `ProjectProfit/Models/PPAccountingProfile.swift`
  - `ProjectProfit/Application/UseCases/Masters/ProfileSettingsUseCase.swift`
- `依存`: `P0-02-04A`
- `完了条件`:
  - production profile workflow が `PPAccountingProfile` に依存しない
  - `PPAccountingProfile` の役割が migration-only として明文化される
- `検証`:
  - `ProjectProfitTests/ProfileSettingsUseCaseTests.swift`
  - `ProjectProfitTests/ProfileSettingsWorkflowUseCaseTests.swift`

### `WBS-P0-03-02`

- `優先度`: `P0`
- `REL`: `REL-P0-03`
- `目的`: backup/snapshot schema から legacy profile section を外す
- `実装内容`:
  - backup payload の canonical section を唯一の profile source of truth にする
  - `LegacyAccountingProfileSnapshot` と secure payload 移送ロジックを migration artifact に縮退する
  - 新規 backup に legacy accountingProfiles を含めない
- `主対象`:
  - `ProjectProfit/Infrastructure/FileStorage/BackupService.swift`
  - `ProjectProfit/Infrastructure/FileStorage/AppSnapshotModels.swift`
- `依存`: `WBS-P0-03-01`
- `完了条件`:
  - 新規 backup の profile 正本が canonical section のみ
  - legacy snapshot は旧アーカイブ復元専用に限定される
- `検証`:
  - `ProjectProfitTests/BackupRestoreServiceTests.swift`

### `WBS-P0-03-03`

- `優先度`: `P0`
- `REL`: `REL-P0-03`
- `目的`: restore/migration fallback を canonical 前提へ切り替える
- `実装内容`:
  - `RestoreService+Upserts.restoreCanonicalProfilesFromLegacySnapshots(...)` を旧 archive 用の限定分岐に縮退する
  - `LegacyProfileMigrationRunner` の完了条件を canonical persist 済み前提へ統一する
  - `alreadyMigrated` 経路に不要な legacy fallback を残さない
- `主対象`:
  - `ProjectProfit/Infrastructure/FileStorage/RestoreService+Upserts.swift`
  - `ProjectProfit/Application/Migrations/LegacyProfileMigrationRunner.swift`
- `依存`: `WBS-P0-03-02`
- `完了条件`:
  - current app state の restore は canonical profile のみで成立する
  - legacy snapshot fallback は旧 archive 互換に限定される
- `検証`:
  - `ProjectProfitTests/LegacyProfileMigrationRunnerTests.swift`
  - `ProjectProfitTests/BackupRestoreServiceTests.swift`

## REL-P0-05 税務状態 / year lock の canonical 統一

### `WBS-P0-05-01`

- `優先度`: `P0`
- `REL`: `REL-P0-05`
- `目的`: year lock の正本を `TaxYearProfile.yearLockState` に統一する
- `実装内容`:
  - 旧 `lockedYears` ではなく現コードの `lockedAt` / `yearLockState` を基準用語に統一する
  - migration/snapshot/restore での year lock 変換ロジックを canonical state 前提に書き換える
  - `PPAccountingProfile.lockedAt` の互換読み替えを旧 archive 限定にする
- `主対象`:
  - `ProjectProfit/Application/Migrations/LegacyProfileMigrationRunner.swift`
  - `ProjectProfit/Infrastructure/FileStorage/AppSnapshotModels.swift`
- `依存`: `WBS-P0-03-03`
- `完了条件`:
  - runtime year lock 判定は canonical profile のみで完結する
  - legacy lock 表現は新規データ保存に使われない
- `検証`:
  - `ProjectProfitTests/TaxYearStateUseCaseTests.swift`
  - `ProjectProfitTests/YearLockTests.swift`

### `WBS-P0-05-02`

- `優先度`: `P0`
- `REL`: `REL-P0-05`
- `目的`: year lock 互換復元経路を旧 archive 専用に閉じる
- `実装内容`:
  - `RestoreService+Upserts` での legacy lock 復元を旧 payload compatibility branch に限定する
  - current-format snapshot では canonical year lock 以外を許さない
  - preflight / export / closing が canonical lock state のみを参照する状態を固定する
- `主対象`:
  - `ProjectProfit/Infrastructure/FileStorage/RestoreService+Upserts.swift`
  - `ProjectProfit/Services/ExportCoordinator.swift`
- `依存`: `WBS-P0-05-01`
- `完了条件`:
  - canonical snapshot restore で legacy lock fallback が不要
  - UI / export / closing の lock 判定が 1 系統になる
- `検証`:
  - `ProjectProfitTests/BackupRestoreServiceTests.swift`
  - `ProjectProfitTests/ClosingWorkflowUseCaseTests.swift`

## REL-P0-06 `taxCodeId` 正本化

### `WBS-P0-06-01`

- `優先度`: `P0`
- `REL`: `REL-P0-06`
- `目的`: form input と candidate input を `taxCodeId` 正本へ統一する
- `実装内容`:
  - transaction / receipt / recurring 入力は `taxCodeId` だけを正本として保持する
  - UI 上の税込/税抜表示と税コード選択の整合を `TaxCode` 中心に整理する
  - input DTO から legacy `taxRate` / `taxCategory` を外す
- `主対象`:
  - `ProjectProfit/Views/Components/TransactionFormView.swift`
  - `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`
- `依存`: `WBS-P0-02-01`
- `完了条件`:
  - main path input が `taxCodeId` を唯一の税属性 ID とする
  - form save DTO に legacy 税属性が残らない
- `検証`:
  - `ProjectProfitTests/ReceiptEvidenceIntakeUseCaseTests.swift`
  - `ProjectProfitTests/TaxCodeTests.swift`

### `WBS-P0-06-02`

- `優先度`: `P0`
- `REL`: `REL-P0-06`
- `目的`: bootstrap と posting save path から legacy 税フォールバックを外す
- `実装内容`:
  - `AccountingBootstrapService` の `TaxCode.resolve(legacyCategory:taxRate:)` 依存を migration/compat branch に限定する
  - `DataStore.saveManualPostingCandidate(...)` 系の legacy 税引数を削減する
  - candidate / journal 生成の本線では `taxCodeId` 未設定時の legacy resolve を使わない
- `主対象`:
  - `ProjectProfit/Services/AccountingBootstrapService.swift`
  - `ProjectProfit/Services/DataStore.swift`
- `依存`: `WBS-P0-06-01`
- `完了条件`:
  - posting 本線の税解決が `taxCodeId` 前提で完結する
  - legacy resolve API は migration/compat 限定になる
- `検証`:
  - `ProjectProfitTests/ConsumptionTaxReportServiceTests.swift`
  - `ProjectProfitTests/DataStoreAccountingTests.swift`

### `WBS-P0-06-03`

- `優先度`: `P0`
- `REL`: `REL-P0-06`
- `目的`: domain/model の legacy 税属性を互換用途へ閉じる
- `実装内容`:
  - `PPTransaction` の `taxRate`, `isTaxIncluded`, `taxCategory` を main path から外す
  - `TaxCode.legacyCategory` と legacy resolve API は adapter/migration 用に降格する
  - canonical posting / consumption tax 集計の入力型を `taxCodeId` ベースに統一する
- `主対象`:
  - `ProjectProfit/Models/Models.swift`
  - `ProjectProfit/Core/Domain/Tax/TaxCode.swift`
- `依存`: `WBS-P0-06-02`
- `完了条件`:
  - production path に legacy 税属性が流れない
  - 税集計サービスが canonical tax code のみを前提にする
- `検証`:
  - `ProjectProfitTests/TaxCodeTests.swift`
  - `ProjectProfitTests/ConsumptionTaxReportServiceTests.swift`

## REL-P0-08 posting 本線の canonical engine 統一

### `WBS-P0-08-01`

- `優先度`: `P0`
- `REL`: `REL-P0-08`
- `目的`: manual / CSV / recurring 承認を `PostingWorkflowUseCase` に統一する
- `実装内容`:
  - 手入力、CSV import、定期承認、取消再レビューの入口を `PostingWorkflowUseCase` / `CanonicalPostingEngine` へ統一する
  - `DataStore` の posting orchestration を helper/read に縮退する
  - approval queue と import path が同じ承認エンジンを使うようにする
- `主対象`:
  - `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift`
  - `ProjectProfit/Application/UseCases/Posting/CanonicalPostingEngine.swift`
  - `ProjectProfit/Services/DataStore.swift`
- `依存`: `WBS-P0-02-01`, `WBS-P0-06-02`
- `完了条件`:
  - main posting entrypoints が 1 系統になる
  - `DataStore` が posting orchestration の正本でなくなる
- `検証`:
  - `ProjectProfitTests/CanonicalUseCasesTests.swift`
  - `ProjectProfitTests/DataStoreAccountingTests.swift`

### `WBS-P0-08-02`

- `優先度`: `P0`
- `REL`: `REL-P0-08`
- `目的`: approved candidate 同期互換経路を撤去する
- `実装内容`:
  - `PostingWorkflowUseCase.syncApprovedCandidate(...)` を compat branch に閉じるか削除する
  - `DataStore.syncCanonicalPosting(...)` の production path 依存を除去する
  - approval 後の journal/search/audit 更新は engine/use case 側に寄せる
- `主対象`:
  - `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift`
  - `ProjectProfit/Services/DataStore.swift`
- `依存`: `WBS-P0-08-01`
- `完了条件`:
  - production approval path が sync helper を呼ばない
  - approval 後の副作用が canonical engine 側で閉じる
- `検証`:
  - `ProjectProfitTests/CanonicalUseCasesTests.swift`

### `WBS-P0-08-03`

- `優先度`: `P0`
- `REL`: `REL-P0-08`
- `目的`: summary/report 側の canonical/legacy 二重吸収を解消する
- `実装内容`:
  - `canonicalSupplementalSummaryRecords(...)` の legacy 補完ロジックを削減する
  - summary/report 用 read model が canonical journal を唯一の正本として読むようにする
  - 旧 transaction mirror に依存する補完経路を互換用途へ閉じる
- `主対象`:
  - `ProjectProfit/Services/DataStore.swift`
  - `ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift`
- `依存`: `WBS-P1-04-01`
- `完了条件`:
  - summary/report の本線で legacy mirror 吸収が不要
  - canonical approved journal のみで集計が成立する
- `検証`:
  - `ProjectProfitTests/ReportingQueryUseCaseTests.swift`
  - `ProjectProfitTests/CanonicalAccountingReportTests.swift`

## REL-P1-03 recurring/distribution 承認 UX 統一

### `WBS-P1-03-01`

- `優先度`: `P1`
- `REL`: `REL-P1-03`
- `目的`: recurring と distribution で共通の承認状態モデルを持つ
- `実装内容`:
  - `DistributionTemplateApplicationUseCase.ApprovalPreview` と recurring preview の差分を吸収する共通 approval snapshot を定義する
  - 承認対象の識別子、作成元、反映先、失効条件を共通化する
  - form-local state だけで完結しない persisted approval request モデルを導入する
- `主対象`:
  - `ProjectProfit/Application/UseCases/Distribution/DistributionTemplateApplicationUseCase.swift`
  - `ProjectProfit/Application/UseCases/Recurring/RecurringQueryUseCase.swift`
- `依存`: `WBS-P0-02-02`
- `完了条件`:
  - recurring/distribution が同じ approval state contract を使う
  - distribution approval が再読み込みで消えない
- `検証`:
  - `ProjectProfitTests/DistributionTemplateApplicationUseCaseTests.swift`
  - `ProjectProfitTests/RecurringPreviewTests.swift`

### `WBS-P1-03-02`

- `優先度`: `P1`
- `REL`: `REL-P1-03`
- `目的`: distribution 承認を Approval Queue に統合する
- `実装内容`:
  - `ApprovalQueueView` の表示対象を `PostingCandidate` に加えて distribution approval request まで広げる
  - distribution の承認/却下/再作成フローを queue workflow として追加する
  - form からは queue へ依頼を発行し、即時ローカル反映はしない
- `主対象`:
  - `ProjectProfit/Features/ApprovalQueue/ApprovalQueueView.swift`
  - `ProjectProfit/Views/Components/TransactionFormView.swift`
  - `ProjectProfit/Views/Components/RecurringFormView.swift`
- `依存`: `WBS-P1-03-01`
- `完了条件`:
  - distribution approval が Approval Queue で承認できる
  - form-local approve button は queue request 発行に置き換わる
- `検証`:
  - `ProjectProfitTests/DistributionTemplateApplicationUseCaseTests.swift`
  - 新規 approval queue test

### `WBS-P1-03-03`

- `優先度`: `P1`
- `REL`: `REL-P1-03`
- `目的`: 承認反映後の transaction/recurring 状態更新を workflow に寄せる
- `実装内容`:
  - 承認済み distribution を transaction draft / recurring draft に反映する workflow を用意する
  - 承認前保存禁止ロジックは queue request の存在判定に置き換える
  - 却下/失効時の UI 復元ルールを固定する
- `主対象`:
  - `ProjectProfit/Application/UseCases/Distribution/`
  - `ProjectProfit/Views/Components/TransactionFormView.swift`
  - `ProjectProfit/Views/Components/RecurringFormView.swift`
- `依存`: `WBS-P1-03-02`
- `完了条件`:
  - distribution approval が workflow 完了まで追跡できる
  - form 保存条件が queue state と整合する
- `検証`:
  - `ProjectProfitTests/RecurringWorkflowUseCaseTests.swift`
  - 新規 distribution approval integration test

## REL-P1-04 帳簿生成 API の canonical 一本化

### `WBS-P1-04-01`

- `優先度`: `P1`
- `REL`: `REL-P1-04`
- `目的`: canonical book projection の専用レイヤを導入する
- `実装内容`:
  - `BookProjectionEngine` を新設し、canonical accounts/journals から journal book / general ledger / subsidiary ledger の投影を生成する
  - `BookSpecRegistry` を新設し、帳簿種別ごとの行仕様と出力条件を管理する
  - `DataStore.projectedCanonicalJournals(...)` の legacy 戻り型依存を解消する
- `主対象`:
  - `ProjectProfit/Services/AccountingReportService.swift`
  - `ProjectProfit/Services/CanonicalBookService.swift`
  - `ProjectProfit/Services/DataStore.swift`
- `依存`: `WBS-P0-08-01`
- `完了条件`:
  - canonical 帳簿投影が独立レイヤで成立する
  - 戻り型が `PPJournalEntry/PPJournalLine` 前提でなくなる
- `検証`:
  - `ProjectProfitTests/CanonicalBookServiceTests.swift`

### `WBS-P1-04-02`

- `優先度`: `P1`
- `REL`: `REL-P1-04`
- `目的`: 帳簿画面と export が canonical book projection を唯一の入力にする
- `実装内容`:
  - `JournalListView`, `LedgerView`, `SubLedgerView`, `ExportCoordinator` を canonical book projection 入力へ切り替える
  - legacy report row への adapter は暫定互換層へ分離する
  - query/use case は投影済み canonical rows を返す
- `主対象`:
  - `ProjectProfit/Views/Accounting/JournalListView.swift`
  - `ProjectProfit/Views/Accounting/LedgerView.swift`
  - `ProjectProfit/Views/Accounting/SubLedgerView.swift`
  - `ProjectProfit/Services/ExportCoordinator.swift`
- `依存`: `WBS-P1-04-01`
- `完了条件`:
  - 画面と export の帳簿入力が canonical projection で揃う
  - legacy journal 型を read path で直接使わない
- `検証`:
  - `ProjectProfitTests/CanonicalBookServiceTests.swift`
  - `ProjectProfitTests/ExportCoordinatorTests.swift`

### `WBS-P1-04-03`

- `優先度`: `P1`
- `REL`: `REL-P1-04`
- `目的`: `AccountingReportService` の legacy overload を縮退する
- `実装内容`:
  - `PPAccount / PPJournalEntry / PPJournalLine` 入力 overload を adapter 専用に下げるか削除する
  - canonical report overload を唯一の production API にする
  - caller のシンボル依存を canonical 版へ移す
- `主対象`:
  - `ProjectProfit/Services/AccountingReportService.swift`
  - `ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift`
- `依存`: `WBS-P1-04-02`
- `完了条件`:
  - production caller が legacy overload を参照しない
  - report service の public 本線が canonical 版のみになる
- `検証`:
  - `ProjectProfitTests/AccountingReportServiceTests.swift`
  - `ProjectProfitTests/CanonicalAccountingReportTests.swift`

## REL-P1-05 FormEngine 入力の canonical 一本化

### `WBS-P1-05-01`

- `優先度`: `P1`
- `REL`: `REL-P1-05`
- `目的`: `FormEngine.BuildInput` を canonical input へ再定義する
- `実装内容`:
  - `BuildInput` から `PPAccount / PPJournalEntry / PPJournalLine` を外し、canonical accounts/journals/books/report rows に置き換える
  - business/tax year/fixed asset/inventory/profile 入力との境界を明確化する
  - e-Tax export caller が新 input contract を作れるよう query/use case を整備する
- `主対象`:
  - `ProjectProfit/Services/FormEngine.swift`
  - `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
- `依存`: `WBS-P1-04-01`
- `完了条件`:
  - `BuildInput` が canonical input のみを持つ
  - form build 前に legacy journal 型を集める必要がない
- `検証`:
  - `ProjectProfitTests/FormEngineTests.swift`

### `WBS-P1-05-02`

- `優先度`: `P1`
- `REL`: `REL-P1-05`
- `目的`: `CashBasisReturnBuilder` と `ShushiNaiyakushoBuilder` を canonical 入力へ切り替える
- `実装内容`:
  - 両 builder の入力を canonical profit/loss, canonical ledger summaries, fixed asset schedules に置き換える
  - `ProfitLossReport` legacy 入力依存を除去する
  - field mapping は既存 tax year pack の JSON 定義を優先する
- `主対象`:
  - `ProjectProfit/Services/CashBasisReturnBuilder.swift`
  - `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
- `依存`: `WBS-P1-05-01`
- `完了条件`:
  - builder が legacy account/journal 型を受けない
  - 白色・現金主義様式が canonical input で生成できる
- `検証`:
  - `ProjectProfitTests/FormEngineTests.swift`
  - `ProjectProfitTests/ShushiNaiyakushoBuilderTests.swift`

### `WBS-P1-05-03`

- `優先度`: `P1`
- `REL`: `REL-P1-05`
- `目的`: form build 本線から legacy adapter を除去する
- `実装内容`:
  - `EtaxExportView` / `EtaxExportViewModel` / `ExportCoordinator` の form build caller を canonical query/use case ベースへ統一する
  - legacy adapter は migration/debug 用に閉じる
  - form build の失敗条件と preflight 条件を canonical data 前提に揃える
- `主対象`:
  - `ProjectProfit/Views/Accounting/EtaxExportView.swift`
  - `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
- `依存`: `WBS-P1-05-02`
- `完了条件`:
  - production form build path が canonical input のみ
  - form builder 側に legacy fallback が残らない
- `検証`:
  - `ProjectProfitTests/EtaxExportViewModelTests.swift`
  - `ProjectProfitTests/FormEngineTests.swift`

## REL-P1-07 workflow UI の整理

### `WBS-P1-07-01`

- `優先度`: `P1`
- `REL`: `REL-P1-07`
- `目的`: `FilingDashboardView` と `BooksWorkspaceView` を workflow hub として固定する
- `実装内容`:
  - MainTab の workflow 正本を `FilingDashboardView` と `BooksWorkspaceView` に固定する
  - `BooksWorkspaceView` の案内文、カード順序、ラベルを canonical workflow に合わせる
  - workflow 入口から旧画面を直接連想させる文言を除去する
- `主対象`:
  - `ProjectProfit/Features/Filing/Presentation/Screens/FilingDashboardView.swift`
  - `ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift`
- `依存`: `WBS-P1-04-02`
- `完了条件`:
  - workflow hub が 2 画面に固定される
  - UI 文言と遷移順が canonical workflow に一致する
- `検証`:
  - `ProjectProfitTests/BooksWorkspaceViewTests.swift`
  - 新規 workflow navigation test

### `WBS-P1-07-02`

- `優先度`: `P1`
- `REL`: `REL-P1-07`
- `目的`: `BooksWorkspaceView` に残る旧導線を整理する
- `実装内容`:
  - `BooksWorkspaceView -> JournalListView()` を `JournalBrowserView()` 基準へ置き換える
  - `BooksWorkspaceView -> ReportView()` は analytics 専用導線として再定義するか、専用 `ReportsWorkspace` に置き換える
  - `AccountingHomeView` を前提にした記述や参照は新規に起こさない
- `主対象`:
  - `ProjectProfit/Features/Books/Presentation/Screens/BooksWorkspaceView.swift`
  - `ProjectProfit/Views/Report/ReportView.swift`
- `依存`: `WBS-P1-07-01`
- `完了条件`:
  - books workspace から旧 workflow 入口が消える
  - 残す `ReportView` は analytics 画面として位置づけが明確になる
- `検証`:
  - `ProjectProfitTests/BooksWorkspaceViewTests.swift`

## REL-P1-08 export 本線統一

### `WBS-P1-08-01`

- `優先度`: `P1`
- `REL`: `REL-P1-08`
- `目的`: export の入口を `ExportCoordinator` に一本化する
- `実装内容`:
  - transaction CSV export を `TransactionHistoryUseCase.exportCSV` 直書きから `ExportCoordinator.export(...)` 経由へ切り替える
  - file naming, format matrix, preflight policy は coordinator 側へ集約する
  - export caller ごとの独自分岐を除去する
- `主対象`:
  - `ProjectProfit/ViewModels/TransactionsViewModel.swift`
  - `ProjectProfit/Application/UseCases/Transactions/TransactionHistoryUseCase.swift`
  - `ProjectProfit/Services/ExportCoordinator.swift`
- `依存`: `WBS-P1-04-02`
- `完了条件`:
  - transaction export が coordinator 経由になる
  - export policy が caller 側に重複しない
- `検証`:
  - `ProjectProfitTests/ExportCoordinatorTests.swift`
  - `ProjectProfitTests/TransactionHistoryUseCaseTests.swift`

### `WBS-P1-08-02`

- `優先度`: `P1`
- `REL`: `REL-P1-08`
- `目的`: legacy ledger export service を adapter 層へ閉じる
- `実装内容`:
  - `.legacyLedgerBook` target を互換用途として明示する
  - `LedgerPDFExportService` / `LedgerExcelExportService` / `LedgerExportService` の直接利用を `ExportCoordinator` 内 adapter に限定する
  - 新規 caller は legacy service を直接参照しない
- `主対象`:
  - `ProjectProfit/Services/ExportCoordinator.swift`
  - `ProjectProfit/Ledger/Services/`
- `依存`: `WBS-P1-08-01`
- `完了条件`:
  - legacy export service の caller が coordinator だけになる
  - `legacyLedgerBook` が compat target として分離される
- `検証`:
  - `ProjectProfitTests/ExportCoordinatorTests.swift`

### `WBS-P1-08-03`

- `優先度`: `P1`
- `REL`: `REL-P1-08`
- `目的`: export UI から個別 service 残存を見えなくする
- `実装内容`:
  - export menu / share flow は coordinator だけを呼ぶ
  - 画面側で format matrix や preflight 判断を持たない
  - books/forms/withholding/transactions の export UX を共通化する
- `主対象`:
  - `ProjectProfit/Views/Components/ExportMenuButton.swift`
  - `ProjectProfit/Views/Accounting/`
- `依存`: `WBS-P1-08-01`
- `完了条件`:
  - export UI が coordinator 以外を直接知らない
  - export UX が target 間で揃う
- `検証`:
  - `ProjectProfitTests/ExportCoordinatorTests.swift`

## REL-P2-04 import チャネル統一

### `WBS-P2-04-01`

- `優先度`: `P1`
- `REL`: `REL-P2-04`
- `目的`: statement import と CSV import を candidate/evidence workflow に統一する
- `実装内容`:
  - external import の正本を `EvidenceDocument + PostingCandidate(.needsReview)` に統一する
  - import source ごとの DTO 差分は parser 層に閉じる
  - import 後の review / approval 入口を approval queue に揃える
- `主対象`:
  - `ProjectProfit/Application/UseCases/Statements/StatementImportUseCase.swift`
  - `ProjectProfit/Application/UseCases/Posting/PostingIntakeUseCase.swift`
- `依存`: `WBS-P0-08-01`, `WBS-P1-03-02`
- `完了条件`:
  - statement import と CSV import の保存先が同じ canonical workflow になる
  - import 後の review path が一貫する
- `検証`:
  - `ProjectProfitTests/StatementImportUseCaseTests.swift`
  - `ProjectProfitTests/PostingIntakeUseCaseTests.swift`

### `WBS-P2-04-02`

- `優先度`: `P1`
- `REL`: `REL-P2-04`
- `目的`: `LedgerCSVImportService` 依存を取り除く
- `実装内容`:
  - `PostingIntakeStore.importLedgerCSV(...)` から `LedgerCSVImportService.prepareImport(...)` を外す
  - canonical importer/parser を新設し、candidate/evidence 生成に直結させる
  - 旧 ledger CSV parser は compat adapter へ閉じる
- `主対象`:
  - `ProjectProfit/Application/UseCases/Posting/PostingIntakeStore.swift`
  - `ProjectProfit/Ledger/Services/LedgerCSVImportService.swift`
- `依存`: `WBS-P2-04-01`
- `完了条件`:
  - production import path が `LedgerCSVImportService` を呼ばない
  - legacy ledger CSV parser は compat 用途に限定される
- `検証`:
  - `ProjectProfitTests/LedgerCSVImportServiceTests.swift`
  - 新規 canonical CSV import integration test

## REL-P0-12 release gate 証跡整備

### `WBS-P0-12-01`

- `優先度`: `P2`
- `REL`: `REL-P0-12`
- `目的`: checklist が参照する lane 別 md を repo 内に揃える
- `実装内容`:
  - `Docs/release/checklist.md` が参照する `golden-baseline.md`, `canonical-e2e.md`, `migration-rehearsal.md`, `performance-gate.md`, `books.md`, `forms.md` を管理対象に追加する
  - `latest.md` と同じ固定フォーマットで更新されるように整える
  - `latest-lane.md` をテンプレートのまま放置しない
- `主対象`:
  - `Docs/release/checklist.md`
  - `Docs/release/quality/`
- `依存`: なし
- `完了条件`:
  - checklist 参照先のファイルがすべて repo に存在する
  - latest / latest-lane / lane別 md の役割が一致する
- `検証`:
  - `Docs/release/checklist.md` の参照先 existence check

### `WBS-P0-12-02`

- `優先度`: `P2`
- `REL`: `REL-P0-12`
- `目的`: release gate の最新 green 根拠を追跡可能に保つ
- `実装内容`:
  - evidence 更新手順を `Docs/release/quality/README.md` に合わせて固定する
  - lane 実行後に commit される artifact の最小セットを定義する
  - placeholder 値が残る場合は release 不可と明記する
- `主対象`:
  - `Docs/release/quality/README.md`
  - `Docs/release/quality/latest.md`
  - `Docs/release/quality/latest-lane.md`
- `依存`: `WBS-P0-12-01`
- `完了条件`:
  - latest green snapshot が repo で追跡できる
  - placeholder artifact が release gate から排除される
- `検証`:
  - `Docs/release/quality/latest.md`
  - lane 別 md 全件存在確認

## REL-P2-02 classification の canonical 化

### `WBS-P2-02-01`

- `優先度`: `P2`
- `REL`: `REL-P2-02`
- `目的`: classification の主 API を candidate/evidence 直入力に対応させる
- `実装内容`:
  - `ClassificationEngine` に `PostingCandidate` / `EvidenceDocument` を直接扱う classify API を追加する
  - `PPTransaction` 入力 API は compat adapter に下げる
  - receipt intake / approval review が同じ分類エンジンを使うようにする
- `主対象`:
  - `ProjectProfit/Services/ClassificationEngine.swift`
  - `ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift`
- `依存`: `WBS-P0-06-01`
- `完了条件`:
  - canonical candidate/evidence を直接分類できる
  - `PPTransaction` 専用 API が本線で使われない
- `検証`:
  - `ProjectProfitTests/ClassificationEngineTests.swift`
  - `ProjectProfitTests/ReceiptEvidenceIntakeUseCaseTests.swift`

### `WBS-P2-02-02`

- `優先度`: `P2`
- `REL`: `REL-P2-02`
- `目的`: classification query/UI を canonical review 向けに置き換える
- `実装内容`:
  - `ClassificationQueryUseCase` と `ClassificationViewModel` の入力を transaction ベースから candidate/evidence ベースへ移す
  - 未分類レビュー UI は approval/review workflow と並ぶ位置づけに変更する
  - fallback / learned rule / suggested category の表示を candidate review に持ち込む
- `主対象`:
  - `ProjectProfit/Application/UseCases/App/AccountingReadSupport.swift`
  - `ProjectProfit/ViewModels/ClassificationViewModel.swift`
  - `ProjectProfit/Views/Accounting/UnclassifiedTransactionsView.swift`
- `依存`: `WBS-P2-02-01`
- `完了条件`:
  - classification UI が canonical artifacts を表示する
  - transaction-only 前提が消える
- `検証`:
  - `ProjectProfitTests/AccountingReadQueryUseCaseTests.swift`
  - 新規 classification UI/query test

### `WBS-P2-02-03`

- `優先度`: `P2`
- `REL`: `REL-P2-02`
- `目的`: approval 前後の feedback loop を統一する
- `実装内容`:
  - intake suggestion, manual correction, approval learning の 3 経路で同じ user rule repository を使う
  - approval 前レビューでの修正結果を rule learning に反映する
  - candidate/evidence に対する feedback から rule を更新できるようにする
- `主対象`:
  - `ProjectProfit/Services/ClassificationLearningService.swift`
  - `ProjectProfit/Application/UseCases/Posting/PostingWorkflowUseCase.swift`
- `依存`: `WBS-P2-02-02`
- `完了条件`:
  - classification learning が intake / review / approval で一貫する
  - user rule 更新経路が 1 repository に揃う
- `検証`:
  - `ProjectProfitTests/ClassificationLearningServiceTests.swift`
  - `ProjectProfitTests/CanonicalUseCasesTests.swift`

## REL-P2-03 withholding main path 完成

### `WBS-P2-03-01`

- `優先度`: `P2`
- `REL`: `REL-P2-03`
- `目的`: withholding 属性を main posting path 全体で確実に流す
- `実装内容`:
  - manual input, receipt intake, recurring, import の各 path で withholding 属性が candidate/journal に載ることを揃える
  - counterparty payee info と tax code 解決を main path で統一する
  - withholding 対象かどうかを review/approval 画面で可視化する
- `主対象`:
  - `ProjectProfit/Application/UseCases/Evidence/ReceiptEvidenceIntakeUseCase.swift`
  - `ProjectProfit/Views/Components/TransactionFormView.swift`
  - `ProjectProfit/Features/ApprovalQueue/ApprovalQueueView.swift`
- `依存`: `WBS-P0-06-01`, `WBS-P0-08-01`
- `完了条件`:
  - 全 posting path で withholding 属性が一貫して保存される
  - review/approval で withholding が確認できる
- `検証`:
  - `ProjectProfitTests/ReceiptEvidenceIntakeUseCaseTests.swift`
  - 新規 approval UI test

### `WBS-P2-03-02`

- `優先度`: `P2`
- `REL`: `REL-P2-03`
- `目的`: 支払調書生成の E2E を完成させる
- `実装内容`:
  - candidate 作成 -> approval -> annual summary -> CSV/PDF export の E2E シナリオを追加する
  - payee ごとの grouping, code 別 grouping, export artifact を固定する
  - filing dashboard からの導線を regression 対象に含める
- `主対象`:
  - `ProjectProfit/Application/UseCases/Filing/WithholdingStatementQueryUseCase.swift`
  - `ProjectProfit/Views/Accounting/WithholdingStatementView.swift`
  - `ProjectProfit/Services/ExportCoordinator.swift`
- `依存`: `WBS-P2-03-01`
- `完了条件`:
  - 支払調書の main path が E2E テストで保証される
  - CSV/PDF export まで含めて失敗しない
- `検証`:
  - `ProjectProfitTests/WithholdingStatementQueryUseCaseTests.swift`
  - 新規 withholding E2E test

## REL-P2-05 release 補助ファイル管理境界の整理

### `WBS-P2-05-01`

- `優先度`: `P2`
- `REL`: `REL-P2-05`
- `目的`: repo 管理対象と repo 外設定対象を明文化する
- `実装内容`:
  - `PrivacyInfo.xcprivacy`, `privacy_policy.md`, `release_checklist.md`, `release_quality/*.md` を repo 管理物として固定する
  - `support URL` は repo 内で実値を持てない外部設定として明文化する
  - release 判定に必要なファイルの最小セットを文書化する
- `主対象`:
  - `Docs/release/checklist.md`
  - `Docs/release/quality/README.md`
- `依存`: `WBS-P0-12-01`
- `完了条件`:
  - 補助ファイルの source of truth が曖昧でない
  - `support URL` が「未実装コード課題」ではなく「外部設定管理課題」として定義される
- `検証`:
  - docs diff review

---

# 4. 横断テスト計画

## 4-1. Wave 1 必須

- `ProjectProfitTests/DataStoreAccountingTests.swift`
- `ProjectProfitTests/PostingIntakeUseCaseTests.swift`
- `ProjectProfitTests/CanonicalUseCasesTests.swift`
- `ProjectProfitTests/AppShellWorkflowUseCaseTests.swift`
- `ProjectProfitTests/TaxCodeTests.swift`
- `ProjectProfitTests/ReceiptEvidenceIntakeUseCaseTests.swift`

## 4-2. Wave 2 必須

- `ProjectProfitTests/ProfileSettingsWorkflowUseCaseTests.swift`
- `ProjectProfitTests/LegacyProfileMigrationRunnerTests.swift`
- `ProjectProfitTests/BackupRestoreServiceTests.swift`
- `ProjectProfitTests/TaxYearStateUseCaseTests.swift`
- `ProjectProfitTests/YearLockTests.swift`
- `ProjectProfitTests/ConsumptionTaxReportServiceTests.swift`

## 4-3. Wave 3 必須

- `ProjectProfitTests/CanonicalBookServiceTests.swift`
- `ProjectProfitTests/AccountingReportServiceTests.swift`
- `ProjectProfitTests/AccountingReadQueryUseCaseTests.swift`
- `ProjectProfitTests/ReportingQueryUseCaseTests.swift`
- `ProjectProfitTests/FormEngineTests.swift`
- `ProjectProfitTests/ShushiNaiyakushoBuilderTests.swift`
- `ProjectProfitTests/EtaxExportViewModelTests.swift`

## 4-4. Wave 4 必須

- `ProjectProfitTests/ExportCoordinatorTests.swift`
- `ProjectProfitTests/TransactionHistoryUseCaseTests.swift`
- `ProjectProfitTests/RecurringWorkflowUseCaseTests.swift`
- `ProjectProfitTests/DistributionTemplateApplicationUseCaseTests.swift`

## 4-5. Wave 5 必須

- `ProjectProfitTests/ClassificationEngineTests.swift`
- `ProjectProfitTests/ClassificationLearningServiceTests.swift`
- `ProjectProfitTests/WithholdingStatementQueryUseCaseTests.swift`
- `ProjectProfitTests/StatementImportUseCaseTests.swift`
- `ProjectProfitTests/StatementMatchServiceTests.swift`

## 4-6. 監査時に実行確認済みの reference test

2026-03-13 監査では、現在の host で `iPhone 16` simulator が存在せず、`iPhone 17` simulator で以下を実行して green を確認した。

- `ProjectProfitTests/StatementImportUseCaseTests.swift`
- `ProjectProfitTests/StatementMatchServiceTests.swift`
- `ProjectProfitTests/WithholdingStatementQueryUseCaseTests.swift`
- `ProjectProfitTests/ExportCoordinatorTests.swift`

この 4 本は、`REL-P2-01`, `REL-P2-03`, `REL-P2-04`, `REL-P1-08` の監査再現用 reference test として扱う。

## 4-7. release artifact 系確認

- `Docs/release/checklist.md`
- `Docs/release/quality/latest.md`
- `Docs/release/quality/latest-lane.md`
- lane 別 md:
  - `golden-baseline.md`
  - `canonical-e2e.md`
  - `migration-rehearsal.md`
  - `performance-gate.md`
  - `books.md`
  - `forms.md`

---

# 5. 完了判定

## 5-1. REL 共通の Done

- production caller に legacy symbol が残らない
- 対応 UseCase / Query / Workflow テストが green
- 旧導線、互換経路、placeholder artifact が repo 内で整理済み
- 監査で使った根拠ファイルで逆証明できる

## 5-2. リリース再監査の合格条件

- `fresh status` が `部分実装` の 16 REL がすべて `完了` になる
- `revised_release_ticket_list.md` の誤判定が実装計画へ混入していない
- `Docs/release/checklist.md` の参照先がすべて存在し、placeholder が残らない
- canonical profile / posting / tax / books / forms / import / export の正本が 1 系統になる

## 5-3. 実装時の固定前提

- `AccountingHomeView` は現 repo に存在しないため、削除対象として扱わない
- `support URL` は repo 管理対象外とし、実値の実装タスクは起こさない
- 新規実装は canonical 正本を増やす方向にのみ行い、正本を増やさない
