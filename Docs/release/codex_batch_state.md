# Codex Batch State

最終更新日: 2026-03-15
対象正本: `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
対象 prompt 集: `Docs/release/Codex_バッチ実行プロンプト集_必要書類作成まで.md`

## 完了したタスク ID

- `P0-01`

## 未完のタスク ID

- `P0-02`
- `P0-03`
- `P0-04`
- `P0-05`
- `P0-06`
- `P0-07`
- `P0-08`
- `P0-09`
- `P0-10`
- `P0-11`
- `P0-12`
- `P1-01`
- `P1-02`
- `P1-03`
- `P1-04`
- `P1-05`
- `P1-06`

## 変更したファイル一覧

- `ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json`
- `ProjectProfitTests/TaxYearDefinitionLoaderTests.swift`
- `Docs/release/codex_batch_state.md`

## 実行した検証コマンド

- `git diff -- ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json ProjectProfitTests/TaxYearDefinitionLoaderTests.swift Docs/release/codex_batch_state.md`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch1-dd -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests/testFilingDeadline_2025FilingPacksAreMarch16 -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests/testLoadDefinition_2025ReturnsNonNil test`

## 検証結果

- `git diff` により 2025 filing pack 4 ファイルの deadline 差分を確認済み
- `testFilingDeadline_2025FilingPacksAreMarch16` pass
- `testLoadDefinition_2025ReturnsNonNil` pass
- Batch 1 完了

## 残っている blocker

- なし

## 次バッチが読むべき最小ファイル一覧

- `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- `Docs/release/codex_batch_state.md`
- `ProjectProfit/Models/EtaxModels.swift`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_cash_basis.json`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Services/CashBasisReturnBuilder.swift`
- `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
- `ProjectProfit/Services/TaxYearDefinitionLoader.swift`
