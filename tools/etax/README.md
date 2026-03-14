# e-Tax Tag Pipeline

## 目的
- CAB/Excel（またはCSV）から `internalKey -> xmlTag` を機械抽出する。
- `TaxYear*.json` への反映を自動化し、手作業更新を避ける。

## ファイル
- `mapping_rules_2025.json`: 抽出時の列エイリアス・キー対応ルール
- `required_internal_keys.json`: 欠落不可の internalKey 一覧
- `schemas/tag_dictionary.schema.json`: `TagDictionary` 形式
- `fixtures/`: CAB未投入時の検証データ

## 参照資料の置き場所
- `e-taxall/` は repo 管理対象ではありません。
- 既定では `ETAX_REFERENCE_ROOT`、`/Users/yutaro/project-profit-ios/e-taxall`、`/Users/yutaro/project-profit-ios-local/e-taxall` の順で参照します。
- repo 外に退避する場合は `ETAX_REFERENCE_ROOT=/absolute/path/to/e-taxall` を指定してください。

## 実行例
```bash
cd /Users/yutaro/project-profit-ios
python3 scripts/etax_extract_tags.py \
  --input-dir tools/etax/fixtures \
  --tax-year 2025 \
  --mapping-config tools/etax/mapping_rules_2025.json \
  --out-tag-dict /tmp/TagDictionary_2025.json \
  --base-taxyear-json tools/etax/fixtures/base_taxyear_2025.json \
  --out-taxyear-json /tmp/TaxYear2025.applied.json

python3 scripts/etax_validate_tags.py \
  --taxyear-json /tmp/TaxYear2025.applied.json \
  --required-keys tools/etax/required_internal_keys.json

python3 scripts/etax_apply_cab_overlay.py \
  --base-taxyear-json /tmp/TaxYear2025.applied.json \
  --overlay-json tools/etax/fixtures/cab_overlay_2025.json \
  --out-taxyear-json /tmp/TaxYear2025.overlay.applied.json

python3 scripts/etax_generate_cab_overlay.py \
  --taxyear-json ProjectProfit/Resources/TaxYear2025.json \
  --blue-spec-xlsx "$ETAX_REFERENCE_ROOT/09XML構造設計書等【所得税】/帳票フィールド仕様書(所得-申告)Ver11x.xlsx" \
  --blue-sheet KOA210 \
  --white-spec-xlsx "$ETAX_REFERENCE_ROOT/09XML構造設計書等【所得税】/帳票フィールド仕様書(所得-申告)Ver12x.xlsx" \
  --white-sheet KOA110 \
  --out-overlay /tmp/cab_overlay_2025.generated.json \
  --out-report /tmp/cab_overlay_2025.generated.report.json

python3 scripts/etax_report_taxyear_diff.py \
  --before /tmp/TaxYear2025.applied.json \
  --after /tmp/TaxYear2025.overlay.applied.json \
  --out-json /tmp/TaxYear2025.overlay.diff.json \
  --out-md /tmp/TaxYear2025.overlay.diff.md

bash scripts/etax_validate_xsd.sh \
  --xml tools/etax/fixtures/KOA210_minimal.xml \
  --form-key blue_general
```
