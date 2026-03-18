# Codex Batch State

最終更新日: 2026-03-18
対象正本: `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
対象 prompt 集: `Docs/release/Codex_バッチ実行プロンプト集_必要書類作成まで.md`

## 完了したタスク ID

- `P0-01`
- `P0-02`（metadata部分）
- `P0-03`
- `P0-04`
- `P0-05`
- `P0-08`
- `P0-07`
- `P0-09`（青色一般側）
- `P0-11`
- `P0-12`（現金主義部分）

## 未完のタスク ID

- `P0-02`
- `P0-06`
- `P0-09`（白色側）
- `P0-10`
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
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_cash_basis.json`
- `ProjectProfit/Services/EtaxFieldPopulator.swift`
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
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,id=C553F40E-C8CF-420A-AFC4-1853102A9BD0' -derivedDataPath /tmp/projectprofit-p005-16e-dd2 build-for-testing`
- `xcodebuild test-without-building -xctestrun /tmp/projectprofit-p005-16e-dd2/Build/Products/ProjectProfit_ProjectProfit_iphonesimulator26.2-arm64.xctestrun -destination 'platform=iOS Simulator,id=C553F40E-C8CF-420A-AFC4-1853102A9BD0' -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateCsvSuccess`
- `xcodebuild test-without-building -xctestrun /tmp/projectprofit-p005-16e-dd2/Build/Products/ProjectProfit_ProjectProfit_iphonesimulator26.2-arm64.xctestrun -destination 'platform=iOS Simulator,id=C553F40E-C8CF-420A-AFC4-1853102A9BD0' -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxSuccess -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesBlueFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueReturnSplitsPagesAndKeepsBalanceSheetOnPage4 -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueReturnOmitsDirectCompositeValueTags -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateCsvSuccess -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateCsvFieldCount`
- `python3` により `ETAX_EXPORT_BLUE_BASE64_*` から `/tmp/projectprofit-p005-16e-dd2/KOA210.export.xml` を復元
- `bash scripts/etax_validate_xsd.sh --xml /tmp/projectprofit-p005-16e-dd2/KOA210.export.xml --form-key blue_general`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch4a-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxSuccess -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueReturnSplitsPagesAndKeepsBalanceSheetOnPage4 test`
- `ETAX_XSD_BLUE_EXPORT_XML=/tmp/projectprofit-batch4b-dd/KOA210.export.xml xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch4b-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testBlueGeneralPackUsesOfficialMappingsFor2025And2026 -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxSuccess -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesBlueFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueReturnSplitsPagesAndKeepsBalanceSheetOnPage4 -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueReturnOmitsDirectCompositeValueTags -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateCsvSuccess -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateCsvFieldCount -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateCsvBlueReturnKeepsBalanceSheetDetailKeys test`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch4b-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesBlueFixtureWhenEnvIsSet test 2>&1 | tee /tmp/projectprofit-batch4b-blue-xcode.log`
- `python3` により `/tmp/projectprofit-batch4b-blue-xcode.log` の `ETAX_EXPORT_BLUE_BASE64_*` から `/tmp/projectprofit-batch4b-dd/KOA210.export.xml` を復元
- `bash scripts/etax_validate_xsd.sh --xml /tmp/projectprofit-batch4b-dd/KOA210.export.xml --form-key blue_general`

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
- `git diff` により blue exporter / blue exporter test / state 差分を再確認済み
- `xcodebuild ... build-for-testing` は iPhone 16e simulator で pass
- `testGenerateCsvSuccess` pass（`test-without-building` smoke）
- `testGenerateXtxSuccess` pass（再実行）
- `testGenerateXtxWritesBlueFixtureWhenEnvIsSet` pass（再実行）
- `testGenerateXtxBlueReturnSplitsPagesAndKeepsBalanceSheetOnPage4` pass（再実行）
- `testGenerateXtxBlueReturnOmitsDirectCompositeValueTags` pass（再実行）
- `testGenerateCsvFieldCount` pass（再実行）
- `ETAX_EXPORT_BLUE_BASE64_*` から復元した XML で `bash scripts/etax_validate_xsd.sh --xml /tmp/projectprofit-p005-16e-dd2/KOA210.export.xml --form-key blue_general` pass
- 青色一般の `AMA00000` / `AMB00030` / `AMB00040` / `AMB00090` / `AMB00100` は official `IDREF` 参照形へ修正済み
- `AMB00070` は `gen:tel1` / `gen:tel2` / `gen:tel3` を持つ複合要素として修正済み
- `AMF00110` 配下の棚卸ブロック、および `AMG00450 > AMG00620 > AMG00740/AMG00760` の official 配置を反映済み
- このため `P0-05` / `P0-09`（青色一般側）は完了
- Batch 4A で青色一般の page skeleton を `KOA210-1..4` に拡張し、`KOA210-2` / `KOA210-3` の空 page を追加済み
- `testGenerateXtxSuccess` pass
- `testGenerateXtxBlueReturnSplitsPagesAndKeepsBalanceSheetOnPage4` pass
- 青色一般の generated XML で `KOA210-4` 出力と `AMG00000` の page 4 配下配置を再確認済み
- `testBlueGeneralPackUsesOfficialMappingsFor2025And2026` pass
- `testGenerateXtxSuccess` pass
- `testGenerateXtxWritesBlueFixtureWhenEnvIsSet` pass
- `testGenerateXtxBlueReturnSplitsPagesAndKeepsBalanceSheetOnPage4` pass
- `testGenerateXtxBlueReturnOmitsDirectCompositeValueTags` pass
- `testGenerateCsvSuccess` pass
- `testGenerateCsvFieldCount` pass
- `testGenerateCsvBlueReturnKeepsBalanceSheetDetailKeys` pass
- 青色一般の bad mapping を `expense_interest -> AMF00330`、`expense_taxes -> AMF00190` に修正済み
- `income_total_revenue` / `inventory_cogs` の direct `xmlTag` は 2025/2026 pack から除去済み
- 青色一般の `bs_asset_*` / `bs_liability_*` / `bs_equity_*` は stable key と追加科目スロットへ正規化され、export payload に残ることを確認済み
- `KOA210-4` は fixed/detail/additional を含む detail-aware 出力へ変更済み
- `AMG00740` は元入金、`AMG00760` は負債・資本の部 期末合計として representative XML に出力されることを確認済み
- `/tmp/projectprofit-batch4b-dd/KOA210.export.xml` で `bash scripts/etax_validate_xsd.sh --form-key blue_general` pass
- このため `P0-08` / `P0-11` は完了

## 残っている blocker

- なし（Batch 4B のスコープは解消済み）

## 次バッチ向けメモ

- blue の具体的誤マッピング候補: `AMF00538/AMF00540..AMF00560` を含む page 2 の declarant/year 再掲未対応
- blue の具体的誤マッピング候補: `AMF00580` 配下の月別売上・仕入ブロックが未対応
- blue の具体的誤マッピング候補: `AMF02220` / `AMF02320` を含む page 3 明細ブロックが未対応

## 次バッチが読むべき最小ファイル一覧

- `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- `Docs/release/codex_batch_state.md`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json`
- `ProjectProfitTests/EtaxXtxExporterTests.swift`
