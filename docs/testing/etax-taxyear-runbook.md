# e-Tax TaxYear 年次運用 Runbook（2026+）

最終更新: 2026-02-26

## 目的
- `TaxYear*.json` の年次追加を、仕様差分と検証証跡を残して実施する。
- KOA210/KOA110 の実生成XML XSD検証を毎回通し、提出前の定義ドリフトを防ぐ。
- CAB overlay report の `missingInternalKeys/unresolvedIdrefs` を継続監視し、差分を早期検知する。

## 対象ファイル
- `ProjectProfit/Resources/TaxYear<YEAR>.json`
- `tools/etax/mapping_rules_<YEAR>.json`（現行は 2025）
- `tools/etax/fixtures/base_taxyear_<YEAR>.json`（必要時）
- `tools/etax/fixtures/cab_overlay_<YEAR>.json`（必要時）

## 年次更新の標準手順
1. 年分追加ブランチを作成する。
2. `TaxYear<前年>.json` を複製して `TaxYear<新年>.json` を作成する。
3. `forms.blue_general.formVer` / `forms.white_shushi.formVer` を e-taxall の該当版に更新する。
4. KOA210/KOA110 の帳票フィールド仕様書（e-taxall）を指定し、overlay を再生成する。
5. lane を実行し、`TagDictionary -> overlay -> diff -> XSD` の証跡を確認する。
6. `missingInternalKeys` / `whiteInsuranceFacts` など report の差分をレビューする。
7. `scripts/etax_overlay_guard.py` で `missingInternalKeys/unresolvedIdrefs` が閾値内（既定: 0）であることを確認する。
8. Swift最小回帰（5テスト）を通し、実生成XMLのXSD通過を確認する。
9. 変更内容と検証ログをPRへ添付する。

## 定期運用（CAB本番入力）
- CI `e-Tax CI` は平日1回（UTC `0 3 * * 1-5`）で実行する。
- CAB本番入力は `ETAX_CAB_SOURCE_URL`（GitHub Actions secrets）から取得する。
- `ETAX_CAB_SOURCE_REQUIRED=true` のため、schedule実行時にURL未設定・取得失敗・SHA不一致はFailにする。
- 設定済み入力（2026-02-26 時点）:
  - release tag: `etax-cab-input-20260226`
  - asset URL: `https://github.com/samurai2891/project-profit-ios/releases/download/etax-cab-input-20260226/etax-cab-input-20260226.tar.gz`
  - SHA-256: `5688ababef7177cf5d31171b272504eaf96783bcd8f45133fcefd2d226498a37`
  - archive type: `tar.gz`

## 実行コマンド（例: 2026年分の準備）
```bash
cd /Users/yutaro/project-profit-ios

ETAX_CAB_BLUE_FIELD_SPEC_XLSX='e-taxall/09XML構造設計書等【所得税】/帳票フィールド仕様書(所得-申告)Ver11x.xlsx' \
ETAX_CAB_WHITE_FIELD_SPEC_XLSX='e-taxall/09XML構造設計書等【所得税】/帳票フィールド仕様書(所得-申告)Ver12x.xlsx' \
ETAX_XSD_REQUIRE_GENERATED_XML=true \
./scripts/run_etax_unit_lane.sh

python3 scripts/etax_overlay_guard.py \
  --report /tmp/etax-unit-lane/cab_overlay_2025.generated.report.json \
  --max-missing-internal-keys 0 \
  --max-unresolved-idrefs 0
```

## 受入条件
- `scripts/check_simulator_health.sh` が `status=ok|warn` を返し、Swift lane が実行される。
- `/tmp/etax-unit-lane/KOA210.export.xml` と `KOA110.export.xml` が生成される。
- `xsd_blue_validation.log` / `xsd_white_validation.log` が `status=ok|warn` で終了する。
- `cab_overlay_2025.generated.report.json` の `missingFieldCount` / `missingInternalKeys` / `unresolvedIdrefs` / `whiteInsuranceFacts` をレビュー済みである。
- `overlay_guard_summary.txt` が `status=ok` である。

## white insurance 差分の扱い
- `帳票フィールド仕様書(所得-申告)Ver12x.xlsx` の `KOA110` には `損害保険料`（`AIG00290`）が存在する。
- 現行 `TaxYear2025.json` は `expense_insurance` / `shushi_expense_insurance` を `AMF00260` / `AIG00290` で実装済み。
- `cab_overlay_2025.generated.report.json` の `whiteInsuranceFacts` は、仕様書差分監査ログとして継続確認する。
