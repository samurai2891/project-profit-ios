# e-Tax Tag Pipeline

## 目的
- CAB/Excel（またはCSV）から `internalKey -> xmlTag` を機械抽出する。
- `TaxYear*.json` への反映を自動化し、手作業更新を避ける。

## ファイル
- `mapping_rules_2025.json`: 抽出時の列エイリアス・キー対応ルール
- `required_internal_keys.json`: 欠落不可の internalKey 一覧
- `schemas/tag_dictionary.schema.json`: `TagDictionary` 形式
- `fixtures/`: CAB未投入時の検証データ

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
```
