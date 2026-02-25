# e-Tax Unit Lane（ユニット優先）

最終更新: 2026-02-26

## 目的
- CAB未投入状態でも、e-Taxタグ抽出基盤と年分ガードの品質を検証できるようにする。
- `xcodebuild test` が環境要因で不安定な場合でも、回帰確認を止めない。

## レーン構成
1. `tag-pipeline`（Python）
2. `etax-core`（Swift 単体テスト）
3. `fiscal-link`（開始月連動）

## 事前条件
- ルートディレクトリ: `/Users/yutaro/project-profit-ios`
- Python 3 が利用可能
- CAB/Excel未投入時は fixture で検証

## 実行コマンド

### 1) tag-pipeline（必須）
```bash
cd /Users/yutaro/project-profit-ios
python3 -m unittest discover -s tools/etax/tests -p 'test_*.py'
```

### 2) tag-pipeline 単発（任意）
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

### 3) Swift unit（環境が許す場合）
`xcodebuild` が利用できる環境のみ実行:
```bash
cd /Users/yutaro/project-profit-ios
xcodebuild test \
  -project ProjectProfit.xcodeproj \
  -scheme ProjectProfit \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## 合格条件
- `tools/etax/tests` が全件成功
- `etax_validate_tags.py` が required key 欠落なしで終了コード0
- 未対応年分で `unsupportedTaxYear` を返すテストが成功

## 失敗時の分類ルール
- `CoreSimulatorService` / `swift-plugin-server` 起因: 環境要因
- JSON不整合 / xmlTag重複 / required key欠落: 実装修正要因
