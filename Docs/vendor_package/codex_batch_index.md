# Codex Batch Index

## Batch 0

- 目的: durable project memory の初期化
- 対象タスク: 実行基盤初期化のみ
- 対象ファイル:
  - `Docs/vendor_package/codex_batch_state.md`
  - `Docs/vendor_package/codex_validation_matrix.md`
  - `Docs/vendor_package/codex_batch_index.md`
- 完了条件:
  - 状態ファイル 3 本が存在する
  - バッチ 1〜8 の順序、対象タスク、対象ファイル、完了条件が整理されている

## Batch 1

- 対象タスク: `P0-01`
- 主対象ファイル:
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json`
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json`
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json`
- 完了条件: 2025 filing pack の deadline が全件 `2026-03-16` で、CI 検知手段がある

## Batch 2

- 対象タスク: `P0-02`, `P0-03`, `P0-04`
- 主対象ファイル:
  - `ProjectProfit/Models/EtaxModels.swift`
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json`
  - `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_cash_basis.json`
  - `ProjectProfit/Services/EtaxXtxExporter.swift`
  - `ProjectProfit/Services/CashBasisReturnBuilder.swift`
  - `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
  - `ProjectProfit/Services/TaxYearDefinitionLoader.swift`
- 完了条件: 現金主義の form metadata、主要金額、専用 exporter 経路が整合する

## Batch 3

- 対象タスク: `P0-05`, `P0-07`, `P0-09`
- 主対象ファイル:
  - `ProjectProfit/Services/EtaxXtxExporter.swift`
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
  - `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json`
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json`
  - `ProjectProfit/Resources/TaxYearPacks/2026/filing/common.json`
  - `ProjectProfit/Services/EtaxFieldPopulator.swift`
- 完了条件: 青色一般が page-aware になり、帳票別 declarant と direct mapping 解消が揃う

## Batch 4

- 対象タスク: `P0-06`, `P0-10`
- 主対象ファイル:
  - `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json`
  - `ProjectProfit/Resources/TaxYearPacks/2026/filing/white_shushi.json`
  - `ProjectProfit/Services/EtaxXtxExporter.swift`
  - `scripts/run_etax_unit_lane.sh`
- 完了条件: 白色が `KOA110-1/2` の必要書類構造で出力され、不足明細と requiredRule を持つ

## Batch 5

- 対象タスク: `P0-08`, `P0-11`
- 主対象ファイル:
  - `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
  - `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json`
  - `ProjectProfit/Services/EtaxFieldPopulator.swift`
  - `ProjectProfit/Services/EtaxXtxExporter.swift`
- 完了条件: 青色 pack の誤マッピングが解消し、貸借対照表 detail が export payload に残る

## Batch 6

- 対象タスク: `P0-12`, `P1-03`, `P1-04`
- 主対象ファイル:
  - `ProjectProfitTests/EtaxXtxExporterTests.swift`
  - `ProjectProfitTests/TaxYearDefinitionLoaderTests.swift`
  - `scripts/run_etax_unit_lane.sh`
  - `tools/etax/fixtures/KOA210_minimal.xml`
  - `tools/etax/fixtures/KOA110_minimal.xml`
  - 新規 lint / coverage test files
- 完了条件: 3 フォームの generated XML XSD 検証と pack coverage 監査が CI で固定される

## Batch 7

- 対象タスク: `P1-01`, `P1-02`
- 主対象ファイル:
  - `ProjectProfit/Resources/TaxYearPacks/2026/filing/*.json`
  - `ProjectProfit/Views/Accounting/EtaxExportView.swift`
  - `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
  - `ProjectProfit/Services/ExportCoordinator.swift`
  - 必要なら `Docs/release/...`
- 完了条件: 2026 pack の証跡が残り、stale preview/export が防止される

## Batch 8

- 対象タスク: `P1-05`, `P1-06`
- 主対象ファイル:
  - `Docs/release/quality/latest.md`
  - `Docs/release/quality/golden-baseline.md`
  - `Docs/release/quality/canonical-e2e.md`
  - `Docs/release/quality/migration-rehearsal.md`
  - `Docs/release/quality/performance-gate.md`
  - `Docs/release/checklist.md`
  - `README.md`
- 完了条件: quality 証跡が current HEAD と一致し、scope が release docs に固定される
