# Codex Batch State

最終更新日: 2026-03-15
対象正本: `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
対象 prompt 集: `Docs/release/Codex_バッチ実行プロンプト集_必要書類作成まで.md`

## 完了したタスク ID

- `P0-01`
- `P0-02`（metadata部分）
- `P0-03`
- `P0-04`
- `P0-12`（現金主義部分）

## 未完のタスク ID

- `P0-02`
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
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_cash_basis.json`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Services/CashBasisReturnBuilder.swift`
- `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
- `ProjectProfitTests/EtaxXtxExporterTests.swift`
- `scripts/etax_resolve_xsd.sh`
- `scripts/etax_validate_xsd.sh`
- `scripts/run_etax_unit_lane.sh`
- `ProjectProfitTests/TaxYearDefinitionLoaderTests.swift`
- `Docs/release/codex_batch_state.md`

## 実行した検証コマンド

- `git diff -- ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json ProjectProfitTests/TaxYearDefinitionLoaderTests.swift Docs/release/codex_batch_state.md`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch1-dd -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests/testFilingDeadline_2025FilingPacksAreMarch16 -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests/testLoadDefinition_2025ReturnsNonNil test`
- `git diff -- ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_cash_basis.json ProjectProfitTests/TaxYearDefinitionLoaderTests.swift Docs/release/codex_batch_state.md`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch2a-dd -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests/testLoadDefinition_2025ReturnsNonNil -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests/testLoadDefinition_2026ReturnsNonNil -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests/testBlueCashBasisMetadata_2025UsesKOA230CurrentSpec -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests/testBlueCashBasisMetadata_2026UsesKOA230CurrentSpec -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests/testBlueCashBasisXmlTags_2025ArePresent -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests/testBlueCashBasisXmlTags_2026ArePresent test`
- `git diff -- ProjectProfit/Services/EtaxXtxExporter.swift ProjectProfit/Services/CashBasisReturnBuilder.swift ProjectProfit/ViewModels/EtaxExportViewModel.swift ProjectProfitTests/EtaxXtxExporterTests.swift scripts/run_etax_unit_lane.sh`
- `ETAX_XSD_CASH_EXPORT_XML=/tmp/projectprofit-batch2b-dd/KOA230.export.xml xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch2b-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueCashBasisUsesDedicatedKOA230Route -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesCashFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueCashBasisProducesXmlForCurrentOfficialXsdValidation -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateCsvBlueCashBasisKeepsDynamicExpenseRows test`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch2b-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesCashFixtureWhenEnvIsSet test 2>&1 | tee /tmp/projectprofit-batch2b-xcode.log`
- `python3` により `/tmp/projectprofit-batch2b-xcode.log` から `ETAX_EXPORT_CASH_BASE64_*` を抽出して `/tmp/projectprofit-batch2b-dd/KOA230.export.xml` を復元
- `bash scripts/etax_validate_xsd.sh --xml /tmp/projectprofit-batch2b-dd/KOA230.export.xml --form-key blue_cash_basis`
- `bash scripts/etax_resolve_xsd.sh --taxyear-json ProjectProfit/Resources/TaxYear2025.json --schema-dir /Users/yutaro/project-profit-ios-local/e-taxall/19XMLスキーマ/shotoku --form-key blue_cash_basis`
- `bash scripts/run_etax_unit_lane.sh`

## 検証結果

- `git diff` により 2025 filing pack 4 ファイルの deadline 差分を確認済み
- `testFilingDeadline_2025FilingPacksAreMarch16` pass
- `testLoadDefinition_2025ReturnsNonNil` pass
- Batch 1 完了
- `git diff` により現金主義 pack metadata と主要 3 項目 `xmlTag` の差分を確認済み
- `testLoadDefinition_2025ReturnsNonNil` pass
- `testLoadDefinition_2026ReturnsNonNil` pass
- `testBlueCashBasisMetadata_2025UsesKOA230CurrentSpec` pass
- `testBlueCashBasisMetadata_2026UsesKOA230CurrentSpec` pass
- `testBlueCashBasisXmlTags_2025ArePresent` pass
- `testBlueCashBasisXmlTags_2026ArePresent` pass
- Batch 2A は `P0-02` metadata 部分 / `P0-03` pack 部分まで完了
- `git diff` により現金主義 exporter 経路 / dynamic row / lane 差分を確認済み
- `testGenerateXtxBlueCashBasisUsesDedicatedKOA230Route` pass
- `testGenerateXtxWritesCashFixtureWhenEnvIsSet` pass
- `testGenerateXtxBlueCashBasisProducesXmlForCurrentOfficialXsdValidation` pass
- `testGenerateCsvBlueCashBasisKeepsDynamicExpenseRows` pass
- `scripts/etax_resolve_xsd.sh --form-key blue_cash_basis` pass
- `scripts/etax_validate_xsd.sh --form-key blue_cash_basis` pass
- `scripts/run_etax_unit_lane.sh` pass
- Batch 2B 完了

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
