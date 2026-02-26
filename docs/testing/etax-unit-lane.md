# e-Tax Unit Lane（ユニット優先）

最終更新: 2026-02-26

関連Runbook: `docs/testing/etax-taxyear-runbook.md`

## 目的
- CAB未投入状態でも、e-Taxタグ抽出基盤と年分ガードの品質を検証できるようにする。
- CAB本番入力をSecrets URLから取得し、平日定期実行で監視を固定化する。
- CAB由来オーバーレイ（`requiredRule/idref/format`）を段階適用できるようにする。
- KOA210/KOA110 の実生成XMLをXSD検証し、様式バージョンとの整合を継続確認する（CIは実生成XML必須）。
- `xcodebuild test` が環境要因で不安定な場合でも、回帰確認を止めない。
- CI上で「環境異常」と「実装修正要因」を分離して判定する。
- `missingInternalKeys/unresolvedIdrefs` をCIで閾値監視し、非0をFailとして検出する。

## レーン構成
1. `cab-input-fetch`（Secrets URL / fallback切替）
2. `tag-pipeline`（Python）
3. `cab-overlay-generate`（Python, e-taxall実データ由来）
4. `cab-overlay-apply`（Python, 任意）
5. `overlay-diff`（Python, 差分レポート）
6. `simulator-health`（環境異常判定）
7. `etax-core`（Swift 単体テスト + 実生成XML出力）
8. `xsd-validate`（xmllint: CIは実生成XML必須）
9. `overlay-guard`（`missingInternalKeys/unresolvedIdrefs` 閾値監視）
10. `artifact-summary`（CI収集用）

## 事前条件
- ルートディレクトリ: `/Users/yutaro/project-profit-ios`
- Python 3 が利用可能
- CAB/Excel未投入時は fixture で検証

## CI（分離運用）
- ワークフロー: `.github/workflows/etax-ci.yml`
- トリガー:
  - `push/pull_request/workflow_dispatch`
  - `schedule`（平日1回、UTC `0 3 * * 1-5`）
- ジョブ:
  - `simulator-health`: `scripts/check_simulator_health.sh` を実行し、runtime/device異常時にFail
  - `etax-unit`: `needs: simulator-health`
    - `scripts/fetch_etax_cab_input.sh` で CAB入力を取得（`ETAX_CAB_SOURCE_URL` 未設定時は fixture fallback）
    - Python lane + CAB overlay生成/適用 + 実生成XML XSD検証 + e-Tax最小Swiftテストを実行
    - `cab-input status=ok` の場合のみ `scripts/etax_overlay_guard.py` を実行し、`missingInternalKeys/unresolvedIdrefs` を閾値監視
    - `cab-input status!=ok` の場合は `overlay guard` を `status=skip` で記録（failさせない）
  - `ETAX_XSD_REQUIRE_GENERATED_XML=true` を固定し、実生成XML欠落時はFail
  - `scripts/etax_ci_evidence_summary.sh` で `xsd + overlay report + overlay diff + overlay guard` を `GITHUB_STEP_SUMMARY` へ集約

## 実行コマンド

### 0) まとめて実行（推奨）
```bash
cd /Users/yutaro/project-profit-ios
./scripts/run_etax_unit_lane.sh
./scripts/etax_ci_evidence_summary.sh /tmp/etax-unit-lane
```
- Python（tag抽出/検証）と XSD検証は常時実行
- `tools/etax/fixtures/cab_overlay_2025.json` が存在する場合は overlay を適用
- `e-taxall` 実データ（KOA210/KOA110の帳票フィールド仕様書）が存在する場合は、lane内で overlay を自動生成して優先適用
- overlay適用時に `TaxYear2025.overlay.diff.json/.md` を生成
- Swift unit は `scripts/check_simulator_health.sh` の `status=ok|warn` の場合のみ実行
- `status=error` の場合は `skip: swift lane skipped (simulator-health ...)` を出力
- Swift実行時は `ETAX_XSD_*_EXPORT_XML` に実生成XMLを出力し、XSD検証へ接続
- `ETAX_XSD_REQUIRE_GENERATED_XML=true` の場合、実生成XMLがないと lane は失敗する
- CIでは `scripts/fetch_etax_cab_input.sh` の出力 `input_dir` を `ETAX_TAG_INPUT_DIR` として採用する

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

### 3) CAB overlay（任意）
```bash
cd /Users/yutaro/project-profit-ios
python3 scripts/etax_apply_cab_overlay.py \
  --base-taxyear-json /tmp/TaxYear2025.applied.json \
  --overlay-json tools/etax/fixtures/cab_overlay_2025.json \
  --out-taxyear-json /tmp/TaxYear2025.overlay.applied.json
```

### 4) XSD検証（CIは実生成XML必須）
```bash
cd /Users/yutaro/project-profit-ios
bash scripts/etax_validate_xsd.sh \
  --xml tools/etax/fixtures/KOA210_minimal.xml \
  --form-key blue_general

bash scripts/etax_validate_xsd.sh \
  --xml tools/etax/fixtures/KOA110_minimal.xml \
  --form-key white_shushi
```

### 5) Swift unit（環境が許す場合）
`xcodebuild` が利用できる環境のみ実行:
```bash
cd /Users/yutaro/project-profit-ios
xcodebuild test \
  -project ProjectProfit.xcodeproj \
  -scheme ProjectProfit \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:ProjectProfitTests/TaxYearDefinitionLoaderTests \
  -only-testing:ProjectProfitTests/EtaxCharacterValidatorTests \
  -only-testing:ProjectProfitTests/EtaxXtxExporterTests \
  -only-testing:ProjectProfitTests/EtaxFieldPopulatorTests \
  -only-testing:ProjectProfitTests/ProfileSettingsViewTests
```

## 合格条件
- `tools/etax/tests` が全件成功
- `etax_validate_tags.py` が required key 欠落なしで終了コード0
- `etax_apply_cab_overlay.py` 適用後も required key 検証が終了コード0
- `etax_validate_xsd.sh` が KOA210/KOA110 を検証成功（CIは実生成XMLのみ）
- `etax_overlay_guard.py` が `missingInternalKeys/unresolvedIdrefs` 閾値内で終了コード0
- 未対応年分で `unsupportedTaxYear` を返すテストが成功
- CIで `simulator-health` と `etax-unit` の失敗原因が分類される

## 失敗時の分類ルール
- `cab-input` 失敗: 入力ソース要因（Secrets URL未設定・取得失敗・SHA不一致）
- `simulator-health` 失敗: 環境要因（CoreSimulatorService / runtime欠落 / device欠落）
- `overlay-guard` 失敗: 監視要因（`missingInternalKeys/unresolvedIdrefs` 閾値超過、または report 欠落）
- `overlay-guard` skip: 入力未取得要因（`cab-input status!=ok`）
- `etax-unit` 失敗: 実装修正要因（overlay不整合 / XSD不整合 / JSON不整合 / xmlTag重複 / required key欠落 / Swiftテスト失敗）

## 環境変数（任意）
- `ETAX_ARTIFACTS_DIR`: lane成果物出力先（default: `/tmp/etax-unit-lane`）
- `ETAX_TAG_INPUT_DIR`: タグ抽出入力ディレクトリ（default: `tools/etax/fixtures`）
- `ETAX_CAB_OVERLAY_JSON`: overlay入力ファイル（未指定時は `tools/etax/fixtures/cab_overlay_2025.json`）
- `ETAX_CAB_BLUE_FIELD_SPEC_XLSX`: KOA210帳票フィールド仕様書（default: Ver11x）
- `ETAX_CAB_BLUE_FIELD_SPEC_SHEET`: KOA210シート名（default: `KOA210`）
- `ETAX_CAB_WHITE_FIELD_SPEC_XLSX`: KOA110帳票フィールド仕様書（default: Ver12x）
- `ETAX_CAB_WHITE_FIELD_SPEC_SHEET`: KOA110シート名（default: `KOA110`）
- `ETAX_XSD_REQUIRE_GENERATED_XML`: `auto|true|false`（CIは `true`）
- `ETAX_XSD_BLUE_EXPORT_XML`: Swift生成KOA210 XML出力先
- `ETAX_XSD_WHITE_EXPORT_XML`: Swift生成KOA110 XML出力先
- `ETAX_XSD_BLUE_SAMPLE_XML`: 青色XSD検証入力（未指定時は export xml）
- `ETAX_XSD_WHITE_SAMPLE_XML`: 白色XSD検証入力（未指定時は export xml）
- `ETAX_XSD_BLUE_FALLBACK_XML`: 青色fallback XML（default: fixture）
- `ETAX_XSD_WHITE_FALLBACK_XML`: 白色fallback XML（default: fixture）
- `ETAX_SIMULATOR_DEVICE`: Swift lane実行Simulator名
- `ETAX_CAB_SOURCE_URL`: CAB入力アーカイブURL（CI secrets）
- `ETAX_CAB_SOURCE_SHA256`: CAB入力アーカイブSHA-256（任意）
- `ETAX_CAB_SOURCE_REQUIRED`: `true|false`（scheduleは `true`）
- `ETAX_CAB_ARCHIVE_TYPE`: `auto|zip|tar|tgz|tar.gz`
- `ETAX_CAB_FETCH_ROOT_DIR`: CAB展開先ルート（default: `/tmp/etax-cab-input`）
