# e-Tax Regression Checklist

最終更新: 2026-02-26

## タグ抽出
- [x] `etax_extract_tags.py` が fixture から `TagDictionary` を生成できる
- [x] `internalKey` の重複/競合で失敗する
- [x] `xmlTag` 重複で失敗する
- [x] `required internalKey` 欠落で失敗する（`--allow-partial` なし）

## タグ適用
- [x] `etax_apply_tags.py` が base `TaxYear` に `xmlTag/dataType` を反映できる
- [x] `--allow-missing` なしで未反映キーがある場合は失敗する
- [x] 反映後 `xmlTag` が空のフィールドが残らない
- [x] `etax_apply_cab_overlay.py` が `requiredRule/idref/format` を反映できる
- [x] `etax_apply_cab_overlay.py --strict` が未知internalKeyを失敗扱いにする
- [x] `etax_report_taxyear_diff.py` が overlay差分を JSON/Markdown で出力する
- [x] `etax_generate_cab_overlay.py` が KOA210/KOA110 実データから overlay/report を生成できる

## XSD検証
- [x] `etax_resolve_xsd.sh` が `TaxYear*.json` の `formId/formVer` からXSDを解決できる
- [x] `etax_validate_xsd.sh` が KOA210 を検証成功する（実生成XMLまたはfallback）
- [x] `etax_validate_xsd.sh` が KOA110 を検証成功する（実生成XMLまたはfallback）
- [x] CIで `ETAX_XSD_REQUIRE_GENERATED_XML=true` のまま KOA210/KOA110 実生成XML検証が通る

## ガード動作
- [x] 未対応年分でプレビュー生成が失敗し、`unsupportedTaxYear` を返す
- [x] 未対応年分で `.xtx/.csv` エクスポートが失敗する
- [x] 対応年分で `internalKey -> xmlTag` 出力を確認できる

## 文字種検証
- [x] ラベルではなく実際の出力値を検証している
- [x] 禁止文字（例: emoji）で出力前に失敗する

## 会計年度連動
- [x] 開始月変更でレポート期間とe-Taxプレビュー期間が一致する
- [x] 消費税集計が `startMonth` 境界を正しく判定する

## 完了証跡
- [x] `etax-ci.yml` の `simulator-health` ジョブ結果をPRに添付
- [x] `etax-ci.yml` の `etax-unit` ジョブ結果をPRに添付
- [x] `etax-unit` ログに overlay / diff / xsd 検証結果が出力される
- [x] lane成果物（TagDictionary/TaxYear差分/XML）をCI artifactとして収集できる
- [x] `cab-input status=ok` の run では lane成果物に `cab_overlay_2025.generated.report.json` が含まれる
- [x] `cab-input status!=ok` の run では `overlay guard` が `status=skip` で記録される
- [x] 実行コマンド・結果ログをPRに添付
- [x] 監査Todoに完了IDと残リスクを追記

## 更新メモ（2026-02-26）
- `[x]` 項目は `./scripts/run_etax_unit_lane.sh`（Python 14/14 success）と `tools/etax/tests` の追加テストで確認。
- `tools/etax/tests/test_etax_tag_pipeline.py` に `internalKey/xmlTag` 重複検知ケースを追加。
- `ProjectProfitTests/EtaxExportViewModelTests.swift` に `unsupportedTaxYear` の preview/export (`.xtx/.csv`) と `startMonth` 境界ケースを追加。
- `ProjectProfitTests/EtaxXtxExporterTests.swift` の CSV検証で `internalKey -> xmlTag` 出力を確認。
- `ProjectProfitTests/EtaxCharacterValidatorTests.swift` に「ラベルではなく実値を検証」ケースを追加し、emoji値での失敗ケースと併せて確認。
- `ProjectProfitTests/ConsumptionTaxReportServiceTests.swift` の `testGenerateSummary_respectsFiscalStartMonth` で `startMonth` 境界集計を確認。
- `ETAX_XSD_REQUIRE_GENERATED_XML=true ./scripts/run_etax_unit_lane.sh` は `No iOS simulator runtime found` 時に実生成XML欠落でFailすることを確認。
- `scripts/etax_ci_evidence_summary.sh` で `xsd + overlay report + overlay diff` を1つのMarkdown要約として出力可能。
- GitHub Actions `e-Tax CI` run `22440157027`（PR）/`22440174004`（workflow_dispatch）で `success` を確認。
- 上記 run の `Run e-Tax unit lane` で `ETAX_XSD_REQUIRE_GENERATED_XML: true`、`xml_path=/tmp/etax-unit-lane/KOA210.export.xml`、`xml_path=/tmp/etax-unit-lane/KOA110.export.xml`、`reason=xsd validation passed` を確認。
- GitHub Actions `e-Tax CI` run `22443589546`（PR）で `ProfileSettingsViewTests` を含むSwift回帰の成功を確認。
- run `22443589546` で `cab-input status=skip` 時に `Guard CAB overlay report` が `skipped`、`Skip CAB overlay guard` が `success` となることを確認。
- 証跡: `docs/testing/etax-ci-gh-evidence-2026-02-26.md`
