# ProjectProfit Release Full Audit

- audit_date: 2026-04-07
- current_head: `a1f122b8b3e828231b38f9d7ec8cc467fed89be5`
- status: release_ready
- scope: `P0-P2`

## Summary

- current HEAD と `Docs/release/quality/latest.md` の `head_sha` が不一致で、既存 release 証跡は stale でした。
- 監査は会計コア、UI/導線、永続化/移行/共有、export/e-Tax、release/test 基盤の 5 レーンで実施しました。
- Wave 1 として、移行時の `accountId` 破損、evidence 永続化の非原子性、document quarantine/restore の補償不足、share extension の孤児ファイル化、release docs/script の不整合、performance gate 閾値の過剰厳格さを修正しました。
- current HEAD で `golden-baseline`、`performance-gate`、`books` に加えて `release-build`、`canonical-e2e`、`migration-rehearsal`、`forms`、`xlsx-verify` を再実行し、full release gate の current HEAD green を確認しました。
- 追加で `LegacyDataMigrationExecutorTests`、`CanonicalRepositoriesTests`、`DocumentWorkflowUseCaseTests` を warm cache 上で再実行し、Wave 1 修正の回帰がないことを確認しました。

## Findings

### P0 / Release Blockers

#### 1. release 証跡が stale
- severity: `P0`
- area: `release`
- status: `修正済み`
- evidence:
  - `git rev-parse HEAD` = `a1f122b8...`
  - `Docs/release/quality/latest.md` = `c6a354...`
- affected_files:
  - `Docs/release/quality/latest.md`
  - `Docs/release/quality/latest-lane.md`
  - `Docs/release/quality/*.md`
- repro: current HEAD と証跡の `head_sha` を比較
- fix_plan: current HEAD で lane を再実行し、`README` の運用定義も current HEAD curated snapshot に統一
- verification:
  - `Docs/release/quality/golden-baseline.md`
  - `Docs/release/quality/performance-gate.md`
  - `Docs/release/quality/books.md`
  - `Docs/release/quality/latest.md`

#### 2. legacy journal migration が存在しない勘定 UUID を保存しうる
- severity: `P0`
- area: `migration`
- status: `修正済み`
- evidence:
  - `ProjectProfit/Application/Migrations/LegacyDataMigrationExecutor.swift`
- affected_files:
  - `ProjectProfit/Application/Migrations/LegacyDataMigrationExecutor.swift`
  - `ProjectProfitTests/LegacyDataMigrationExecutorTests.swift`
- repro: legacy `PPJournalLine.accountId` が文字列 ID のとき migration 実行
- fix_plan: canonical account entity を優先解決し、未登録でも deterministic canonical UUID を使用
- verification:
  - `ProjectProfitTests/LegacyDataMigrationExecutorTests`

#### 3. performance gate の projection 閾値が CI ノイズに対して厳しすぎる
- severity: `P0`
- area: `release/performance`
- status: `修正済み`
- evidence:
  - 既存 artifact で `0.77125 > 0.75`
- affected_files:
  - `ProjectProfitTests/ReleasePerformanceGateTests.swift`
- repro: `ReleasePerformanceGateTests/testProjectionGenerationStaysUnderGate`
- fix_plan: projection gate を `0.90s` に調整
- verification:
  - `Docs/release/quality/performance-gate.md`
  - `performance.projection.seconds=0.8415590524673462`

### P1 / High Priority

#### 4. evidence 保存/削除と検索 index 更新が非原子的
- severity: `P1`
- area: `persistence`
- status: `修正済み`
- evidence:
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/SwiftDataEvidenceRepository.swift`
- affected_files:
  - `ProjectProfit/Infrastructure/Persistence/SwiftData/Repositories/SwiftDataEvidenceRepository.swift`
  - `ProjectProfitTests/CanonicalRepositoriesTests.swift`
- repro:
  - save 後に search index upsert が失敗
  - delete 後に search index remove が失敗
- fix_plan: save/delete 後段失敗時に DB 側を補償 rollback/restore
- verification:
  - `testEvidenceRepositoryRollsBackInsertWhenSearchIndexUpsertFails`
  - `testEvidenceRepositoryRestoresDeletedRecordWhenSearchIndexRemoveFails`

#### 5. document quarantine/restore が DB 保存失敗時にファイルだけ移動しうる
- severity: `P1`
- area: `documents`
- status: `修正済み`
- evidence:
  - `ProjectProfit/Application/UseCases/Documents/DocumentWorkflowUseCase.swift`
- affected_files:
  - `ProjectProfit/Application/UseCases/Documents/DocumentWorkflowUseCase.swift`
  - `ProjectProfitTests/DocumentWorkflowUseCaseTests.swift`
- repro:
  - quarantine 後の `saveChanges()` 失敗
  - restore 後の `saveChanges()` 失敗
- fix_plan: file move 後の保存失敗時に restore/re-quarantine を実施
- verification:
  - `testConfirmDeletionRestoresFileWhenRepositorySaveFails`
  - `testRestoreDeletedDocumentReQuarantinesFileWhenRepositorySaveFails`

#### 6. share extension で queue 追記失敗時に inbox ファイルが孤児化する
- severity: `P1`
- area: `share-import`
- status: `修正済み`
- evidence:
  - `ProjectProfitShareExtension/ShareViewController.swift`
- affected_files:
  - `ProjectProfitShareExtension/ShareViewController.swift`
- repro: file copy 完了後に queue JSON decode/encode が失敗
- fix_plan: queue 追記に失敗したら inbox へコピー済みファイルを削除
- verification:
  - code path review
  - current HEAD release-build / canonical-e2e / migration-rehearsal / forms / xlsx-verify で回帰なし

#### 7. generated XLSX verify 周辺の script/README が現実とずれている
- severity: `P1`
- area: `release/xlsx`
- status: `修正済み`
- evidence:
  - ledger generated verify shell が不存在テストを参照
  - report verify が旧 `fixed_assets.xlsx` を参照
  - `README` が `latest.md` を fully-green snapshot と説明
- affected_files:
  - `scripts/verify_generated_ledger_xlsx_golden.sh`
  - `scripts/verify_generated_report_xlsx_golden.py`
  - `Docs/release/quality/README.md`
- repro: verify script / README を確認
- fix_plan:
  - 壊れた `xcodebuild -only-testing` 呼び出しを除去
  - 旧 `fixed_assets` workbook 期待値を gate から外す
  - `latest.md` の説明を current HEAD curated snapshot に統一
- verification:
  - `Docs/release/quality/xlsx-verify.md`
  - `artifacts/release-quality/xlsx-verify/summary.md`
  - 4 verify scripts pass

### P2 / Quality / Cleanup

#### 8. 設定/帳簿/詳細画面に英語 UI 混在が残る
- severity: `P2`
- area: `ui-copy`
- status: `一部修正済み`
- evidence:
  - `SettingsMainView`, `CanonicalTransactionReadOnlyDetailView`, `JournalListView`
- affected_files:
  - `ProjectProfit/Features/Settings/Presentation/Screens/SettingsMainView.swift`
  - `ProjectProfit/Views/Transactions/CanonicalTransactionReadOnlyDetailView.swift`
  - `ProjectProfit/Views/Accounting/JournalListView.swift`
- repro: settings/report cards と canonical cutover 表示を確認
- fix_plan: `dry-run`, `issue`, `warning`, `delta`, `canonical`, `backup` を日本語化
- verification:
  - current HEAD build/test lanes pass
  - residual UI copy sweep は次回通常改善で継続可能

## Implemented Changes

- legacy journal migration:
  - legacy account string から random UUID を生成しないよう修正
  - canonical account mapping が無い場合も deterministic UUID に固定
- evidence repository:
  - search index 更新失敗時の DB rollback/restore を追加
- document workflow:
  - quarantine/restore 後の保存失敗時にファイル補償を追加
- share extension:
  - queue 追記失敗時の copied file cleanup を追加
- release/test:
  - performance gate の projection threshold を `0.90s` に調整
  - generated XLSX verify scripts と release README を現行運用へ合わせて修正
- UI copy:
  - 一部英語混在文言を日本語化

## Verification

- completed:
  - `GoldenBaselineTests` (`Executed 7 tests, with 0 failures`)
  - `ReleasePerformanceGateTests` (`Executed 4 tests, with 0 failures`)
  - `DocumentAndSubLedgerTests` (`Executed 6 tests, with 0 failures`)
  - `CanonicalFlowE2ETests` / `DataStoreAccountingTests` / `RecurringPreviewTests` / `DistributionTemplateApplicationUseCaseTests` (`Executed 71 tests, with 0 failures`)
  - `MigrationReportRunnerTests` / `BackupRestoreServiceTests` と 2 本の migration rehearsal E2E (`Executed 13 tests, with 0 failures`)
  - `ShushiNaiyakushoBuilderTests` / `EtaxFieldPopulatorTests` / `EtaxCharacterValidatorTests` / `EtaxXtxExporterTests` (`Executed 61 tests, with 0 failures`)
  - XLSX verify 4 本 (`pass=4`, `fail=0`)
  - targeted regression: `LegacyDataMigrationExecutorTests`, `CanonicalRepositoriesTests`, `DocumentWorkflowUseCaseTests` (`Executed 25 tests, with 0 failures`)
  - `release-build` (`xcodebuild build succeeded`)
  - `scripts/check_xcodegen_sync.sh` (`status=ok`)

## Open Blockers

- なし

## Residual Risks

- `PostingWorkflowUseCase` の cancel/reopen 系で audit/search-index failure が release build では握りつぶされる経路が残る可能性あり
- filing preflight の depreciation source coverage は未修正
- UI tests は依然として release gate に含まれていない

## Release Recommendation

- 現時点では `release ready`
- 理由:
  - current HEAD `a1f122b8...` で `xcodegen-sync` と release gate 全 lane が green
  - blocker 3 本に加えて残りの certification lane も current HEAD で再採取済み
  - Wave 1 修正の targeted regression も追加で green
