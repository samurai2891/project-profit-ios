# Codex Batch State

最終更新日: 2026-03-18
対象正本: `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
対象 prompt 集: `Docs/release/Codex_バッチ実行プロンプト集_必要書類作成まで.md`

## 完了したタスク ID

- `P0-01`
- `P0-02`（metadata部分）
- `P0-03`
- `P0-04`
- `P0-07`
- `P0-12`（現金主義部分）

## 未完のタスク ID

- `P0-02`
- `P0-05`
- `P0-06`
- `P0-08`
- `P0-09`（青色一般側）
- `P0-09`（白色側）
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
- `git diff -- ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json ProjectProfit/Resources/TaxYearPacks/2026/filing/common.json ProjectProfit/Services/EtaxFieldPopulator.swift ProjectProfit/Services/EtaxXtxExporter.swift ProjectProfitTests/EtaxXtxExporterTests.swift Docs/release/codex_batch_state.md`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch3-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesBlueFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesWhiteFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesCashFixtureWhenEnvIsSet test`
- `git diff -- ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json ProjectProfit/Services/EtaxXtxExporter.swift ProjectProfitTests/EtaxXtxExporterTests.swift Docs/release/codex_batch_state.md`
- `ETAX_XSD_BLUE_EXPORT_XML=/tmp/projectprofit-batch3b-dd/KOA210.export.xml xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch3b-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxSuccess -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesBlueFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueReturnSplitsPagesAndKeepsBalanceSheetOnPage4 -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueReturnOmitsDirectCompositeValueTags -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateCsvSuccess -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateCsvFieldCount test`
- `bash scripts/etax_validate_xsd.sh --xml /tmp/projectprofit-batch3b-dd/KOA210.export.xml --form-key blue_general`
- `python3` により `ETAX_EXPORT_BLUE_BASE64_*` から `/tmp/projectprofit-batch3b-dd/KOA210.export.xml` を復元

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
- `git diff` により common declarant 定義 / declarant populator / exporter / 最小テスト / state 差分を確認済み
- `testGenerateXtxWritesBlueFixtureWhenEnvIsSet` pass
- `testGenerateXtxWritesWhiteFixtureWhenEnvIsSet` pass
- `testGenerateXtxWritesCashFixtureWhenEnvIsSet` pass
- representative XML 3種で `ABA` プレフィックス非混入を確認済み
- declarant/year tag は blue=`AMA/AMB`、white=`AIA/AIB`、cash=`AOA/AOB` に分離済み
- `declarant_birth_date` / `declarant_my_number_flag` は対象3帳票の direct export から除外済み
- Batch 3 (`P0-07`) 完了
- `git diff` により blue_general pack / blue exporter / blue exporter test / state 差分を確認済み
- `testGenerateXtxSuccess` pass
- `testGenerateXtxWritesBlueFixtureWhenEnvIsSet` pass
- `testGenerateXtxBlueReturnSplitsPagesAndKeepsBalanceSheetOnPage4` pass
- `testGenerateXtxBlueReturnOmitsDirectCompositeValueTags` pass
- `testGenerateCsvSuccess` pass
- `testGenerateCsvFieldCount` pass
- 青色一般は `KOA210-1` と `KOA210-4` の page-aware 出力へ変更済み
- `income_total_revenue` / `inventory_cogs` の direct container export は除外済み
- `bash scripts/etax_validate_xsd.sh --xml /tmp/projectprofit-batch3b-dd/KOA210.export.xml --form-key blue_general` は fail
- fail 原因: `AMA00000` / `AMB00030` / `AMB00040` / `AMB00090` / `AMB00100` の `IDREF` 必須属性不足、`AMB00070` の子要素不足、`AMG00740` 配置不整合
- このため `P0-05` / `P0-09`（青色一般側）は未完了のまま停止

## 残っている blocker

- `KOA210-011.xsd` 検証が fail しており、青色一般の declarant/year 構造と `AMG00740` の official 配置調整が必要

## 次バッチが読むべき最小ファイル一覧

- `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- `Docs/release/codex_batch_state.md`
- `ProjectProfit/Models/EtaxModels.swift`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/common.json`
- `ProjectProfitTests/EtaxXtxExporterTests.swift`
