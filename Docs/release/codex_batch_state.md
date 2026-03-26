# Codex Batch State

最終更新日: 2026-03-19
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
- `P0-09`（白色側）
- `P0-10`
- `P0-11`
- `P0-12`（現金主義部分）
- `P0-12`
- `P1-03`
- `P1-04`
- `P1-02`

## 未完のタスク ID

- `P0-02`
- `P0-06`
- `P1-01`
- `P1-05`
- `P1-06`

## 変更したファイル一覧

- `ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/white_shushi.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_cash_basis.json`
- `ProjectProfit/Services/EtaxFieldPopulator.swift`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
- `ProjectProfit/Services/CashBasisReturnBuilder.swift`
- `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
- `ProjectProfit/Views/Accounting/EtaxExportView.swift`
- `ProjectProfitTests/EtaxXtxExporterTests.swift`
- `ProjectProfitTests/EtaxExportViewModelTests.swift`
- `ProjectProfitTests/CanonicalFlowE2ETests.swift`
- `ProjectProfitTests/ReleasePerformanceGateTests.swift`
- `scripts/etax_resolve_xsd.sh`
- `scripts/etax_validate_xsd.sh`
- `scripts/run_etax_unit_lane.sh`
- `ProjectProfitTests/TaxYearDefinitionLoaderTests.swift`
- `ProjectProfit/Services/TaxYearDefinitionLoader.swift`
- `scripts/etax_validate_tags.py`
- `tools/etax/tests/test_etax_tag_pipeline.py`
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
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch7-final-dd build-for-testing`
- `xcodebuild test-without-building -xctestrun /tmp/projectprofit-batch7-final-dd/Build/Products/ProjectProfit_ProjectProfit_iphonesimulator26.2-arm64.xctestrun -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ProjectProfitTests/EtaxExportViewModelTests/testExportRebuildsPreviewWhenDataRevisionChanges -only-testing:ProjectProfitTests/EtaxExportViewModelTests/testExportFailsWhenCurrentDataPreflightBecomesInvalidAfterPreview -only-testing:ProjectProfitTests/EtaxExportViewModelTests/testWhitePreviewAndExportUseSameFieldSet`
- `xcodebuild test-without-building -xctestrun /tmp/projectprofit-batch7-final-dd/Build/Products/ProjectProfit_ProjectProfit_iphonesimulator26.2-arm64.xctestrun -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ProjectProfitTests/EtaxExportViewModelTests`
- `git diff -- ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json ProjectProfit/Resources/TaxYearPacks/2026/filing/common.json ProjectProfit/Services/EtaxFieldPopulator.swift ProjectProfit/Services/EtaxXtxExporter.swift ProjectProfitTests/EtaxXtxExporterTests.swift Docs/release/codex_batch_state.md`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch3-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesBlueFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesWhiteFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesCashFixtureWhenEnvIsSet test`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch5a-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesWhiteFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWhiteReturnSplitsPagesAndMovesAinToPage2 test`
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
- `python3 -m json.tool ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json >/tmp/projectprofit-white-2025.json`
- `python3 -m json.tool ProjectProfit/Resources/TaxYearPacks/2026/filing/white_shushi.json >/tmp/projectprofit-white-2026.json`
- `ETAX_XSD_WHITE_EXPORT_XML=/tmp/projectprofit-batch5b-dd/KOA110.export.xml xcodebuild -quiet -scheme ProjectProfit -destination 'platform=iOS Simulator,id=F14C12AF-7F90-4311-BECD-E70E3031CE9B' -derivedDataPath /tmp/projectprofit-batch5b-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testWhitePackUsesOfficialCoverageFor2025And2026 -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testWhiteValidatorDetectsRequiredFieldsAndAcceptsDefinedDynamicKeys -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesWhiteFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWhiteReturnSplitsPagesAndMovesAinToPage2 -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWhiteReturnProducesXmlForCurrentOfficialXsdValidation test`
- `bash scripts/etax_validate_xsd.sh --xml /tmp/projectprofit-batch5b-dd/KOA110.export.xml --form-key white_shushi`
- `python3` により `/tmp/projectprofit-batch5b-dd/KOA110.export.xml` を一時加工した `/tmp/projectprofit-batch5b-dd/KOA110.manual2.xml` を作成し、`bash scripts/etax_validate_xsd.sh --xml /tmp/projectprofit-batch5b-dd/KOA110.manual2.xml --form-key white_shushi` を実行
- `ETAX_XSD_WHITE_EXPORT_XML=/tmp/projectprofit-batch5b-dd/KOA110.export.xml xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,id=F14C12AF-7F90-4311-BECD-E70E3031CE9B' -derivedDataPath /tmp/projectprofit-batch5b-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesWhiteFixtureWhenEnvIsSet test 2>&1 | tee /tmp/projectprofit-batch5b-white-artifact.log`
- `python3` により `/tmp/projectprofit-batch5b-white-artifact.log` の `ETAX_EXPORT_WHITE_BASE64_*` から一時 XML を復元し、`bash scripts/etax_validate_xsd.sh --xml <temp-xml> --form-key white_shushi` を実行
- `python3 -m unittest tools.etax.tests.test_etax_tag_pipeline`
- `xcodebuild -quiet -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch6-loader-dd -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests test`
- `xcodebuild -quiet -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/projectprofit-batch6-exporter-dd -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesCashFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueCashBasisProducesXmlForCurrentOfficialXsdValidation test`
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
- Batch 5A で白色 exporter の page skeleton を `KOA110-1` / `KOA110-2` に分割済み
- `AIN00000` は `KOA110-1` から `KOA110-2` 配下へ移動済み
- `testGenerateXtxWritesWhiteFixtureWhenEnvIsSet` pass
- `testGenerateXtxWhiteReturnSplitsPagesAndMovesAinToPage2` pass
- 白色 generated XML で `KOA110-2` 出力と `AIN00090` の page 2 配置を再確認済み
- `P0-06` は page 分割部分のみ完了、field coverage 拡張は未完
- Batch 5B で white pack 2025/2026 に `AIG00030/40/50/60`、`AIG00140/AIG00210`、`AIK/AIL/AIM/AIN` を追加し、`AIG00020` 直値定義と `shushi_rent_breakdown` を除去済み
- `ShushiNaiyakushoBuilder.swift` は white の収入 child、棚卸、所得計算、`AIM` 減価償却 detail/totals、`AIK/AIL` totals を生成するよう更新済み
- `EtaxXtxExporter.swift` は white の page 1/2 block を official 構造へ寄せ、`AIN00090` を `AIN00000` row 内 child として出力する実装まで更新済み
- `testWhitePackUsesOfficialCoverageFor2025And2026` pass
- `testWhiteValidatorDetectsRequiredFieldsAndAcceptsDefinedDynamicKeys` pass
- `testGenerateXtxWritesWhiteFixtureWhenEnvIsSet` pass
- `testGenerateXtxWhiteReturnSplitsPagesAndMovesAinToPage2` pass
- `testGenerateXtxWhiteReturnProducesXmlForCurrentOfficialXsdValidation` pass
- `python3 -m json.tool` による 2025/2026 `white_shushi.json` 構文確認 pass
- ただし `/tmp/projectprofit-batch5b-dd/KOA110.export.xml` は `xcodebuild` 再実行後も更新されず、実生成物に対する `bash scripts/etax_validate_xsd.sh --form-key white_shushi` は旧 `AIG00350` / `AIG00360` 並びのまま fail
- 同 XML を current source の期待形に合わせて一時補正した `/tmp/projectprofit-batch5b-dd/KOA110.manual2.xml` では `bash scripts/etax_validate_xsd.sh --form-key white_shushi` pass
- `/tmp/projectprofit-batch5b-white-artifact.log` の `ETAX_EXPORT_WHITE_BASE64_*` から復元した latest white XML で `bash scripts/etax_validate_xsd.sh --form-key white_shushi` pass
- latest white XML では `AIG00350` が `AIG00210` 配下、`AIG00360` が `AIG00140` 直下であることを確認済み
- white の正式検証経路は host 側固定パスではなく、latest xcodebuild log の base64 payload から representative XML を復元する方式に確定
- このため `P0-09`（white側）/ `P0-10` は完了
- `TaxYearDefinitionLoader.validatePackCoverage(for:)` を追加し、`common` / `blue_general` / `white_shushi` / `blue_cash_basis` の form existence、pack coverage、white page 2、requiredRule、leaf-only mapping を検査可能にした
- `TaxYearDefinitionLoaderTests` に `blue_cash_basis` を含む pack coverage テストを追加し、2025/2026 とも loader coverage が clean であることを確認した
- `scripts/etax_validate_tags.py --filing-dir ProjectProfit/Resources/TaxYearPacks/2025/filing` を追加し、builder dynamic key / pack coverage / leaf-only mapping lint を CI 必須化した
- `tools.etax.tests.test_etax_tag_pipeline` で filing pack lint の正常系、leaf-only 違反検知、`blue_cash_basis` coverage 欠落検知を追加し pass
- `EtaxXtxExporterTests` に青色一般の generated XML representative test を追加し、blue / white / cash の 3 フォームすべてで base64 artifact を lane から復元できる状態に揃えた
- `EtaxXtxExporter.swift` の `KOA230` 経路を official XSD に合わせて `AOA00000` と `AOB00030/40/90/100` を `IDREF` 参照化し、電話番号も structured phone で出力するよう修正した
- `scripts/run_etax_unit_lane.sh` は `ETAX_XSD_REQUIRE_GENERATED_XML=true` を既定値に変更し、blue / white fallback と cash skip を禁止した
- `bash scripts/run_etax_unit_lane.sh` pass
- lane 内で recovered generated XML (`KOA210.export.xml` / `KOA110.export.xml` / `KOA230.export.xml`) に対する official XSD 検証が 3 フォームとも pass
- このため `P0-12` / `P1-03` / `P1-04` は完了

## CI で必須になった検証一覧

- `python3 -m unittest tools.etax.tests.test_etax_tag_pipeline`
- `python3 scripts/etax_validate_tags.py --filing-dir ProjectProfit/Resources/TaxYearPacks/2025/filing`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests test`
- `xcodebuild -scheme ProjectProfit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesBlueFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueReturnProducesXmlForCurrentOfficialXsdValidation -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWritesWhiteFixtureWhenEnvIsSet -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxWhiteReturnProducesXmlForCurrentOfficialXsdValidation -only-testing:ProjectProfitTests/EtaxXtxExporterTests/testGenerateXtxBlueCashBasisProducesXmlForCurrentOfficialXsdValidation test`
- `bash scripts/run_etax_unit_lane.sh`

## 残っている blocker

- なし（Batch 6 のスコープは解消済み）

## 次バッチ向けメモ

- white representative XML の検証は host 側固定パスではなく、`ETAX_EXPORT_WHITE_BASE64_*` から復元した latest XML を正本にする
- simulator 実行では `ETAX_XSD_WHITE_EXPORT_XML` の host 反映が不安定なため、state 判定や XSD 確認は log payload 基準で行う
- generated XML の official XSD 検証は blue / white / cash の 3 フォームすべて base64 artifact 復元を正本とし、fixture fallback は使用しない
- `scripts/run_etax_unit_lane.sh` は `ETAX_XSD_REQUIRE_GENERATED_XML=true` を既定値にし、generated XML が無い場合は CI failure として扱う
- preview は snapshot 由来 `dataRevision` を保存し、export 前に current snapshot と必ず再比較する
- `fiscalYear` / `formType` または `dataRevision` が変わったら export 前に form rebuild・preflight・文字検証を再実行する
- preview/export とも `EtaxExportViewModel.exportableForm(from:)` を正本の field 集合として使う
- そのため preview 後に元データが変わっても stale preview は export に使われない
- `P1-02` は `EtaxExportView.swift` / `EtaxExportViewModel.swift` / `EtaxExportViewModelTests.swift` で完了

## 次バッチが読むべき最小ファイル一覧

- `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- `Docs/release/codex_batch_state.md`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/white_shushi.json`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
- `ProjectProfitTests/EtaxXtxExporterTests.swift`
