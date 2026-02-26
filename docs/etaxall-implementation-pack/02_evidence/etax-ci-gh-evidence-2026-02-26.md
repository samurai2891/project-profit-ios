# e-Tax CI GitHub Evidence (2026-02-26)

対象リポジトリ: `/Users/yutaro/project-profit-ios`  
確認日: 2026-02-26

## 成功run

1. `pull_request` run
   - Run ID: `22440157027`
   - URL: `https://github.com/samurai2891/project-profit-ios/actions/runs/22440157027`
   - 結果: `success`（7m0s）

2. `workflow_dispatch` run
   - Run ID: `22440174004`
   - URL: `https://github.com/samurai2891/project-profit-ios/actions/runs/22440174004`
   - 結果: `success`（8m12s）

3. `pull_request` run（overlay guard skip分離 + Keychain UI回帰含む）
   - Run ID: `22443589546`
   - URL: `https://github.com/samurai2891/project-profit-ios/actions/runs/22443589546`
   - 結果: `success`（7m11s）

4. `pull_request` run（本番CAB入力取得 + overlay guard実行）
   - Run ID: `22445208956`
   - URL: `https://github.com/samurai2891/project-profit-ios/actions/runs/22445208956`
   - 結果: `success`（7m58s）

## 実生成XML経由のXSD pass証跡（抜粋）

`Run e-Tax unit lane` ログから確認:

- `ETAX_XSD_REQUIRE_GENERATED_XML: true`
- `info: recovered ETAX export xml for BLUE: /tmp/etax-unit-lane/KOA210.export.xml`
- `info: recovered ETAX export xml for WHITE: /tmp/etax-unit-lane/KOA110.export.xml`
- `xsd require generated xml: true (mode=true)`
- `xml_path=/tmp/etax-unit-lane/KOA210.export.xml`
- `reason=xsd validation passed`
- `xml_path=/tmp/etax-unit-lane/KOA110.export.xml`
- `reason=xsd validation passed`
- `xcodebuild ... -only-testing:ProjectProfitTests/ProfileSettingsViewTests`

## CAB入力未取得時のguard分離証跡（run `22443589546`）

- `Fetch CAB input source`: `status=skip`
- `Run e-Tax unit lane`: `skip: cab overlay generation skipped (spec file not found: ...)`
- ジョブステップ:
  - `Guard CAB overlay report`: `skipped`
  - `Skip CAB overlay guard`: `success`
- 生成ログ:
  - `status=skip`
  - `reason=overlay guard skipped (cab-input status=skip)`

## CAB入力取得時のguard実行証跡（run `22445208956`）

- `Fetch CAB input source`: `status=ok`
- `reason=CAB input fetched successfully`
- `input_dir=/tmp/etax-cab-input/extracted/e-taxall`
- `Run e-Tax unit lane`:
  - `info: resolved blue spec xlsx: /tmp/etax-cab-input/extracted/e-taxall/...Ver11x.xlsx`
  - `info: resolved white spec xlsx: /tmp/etax-cab-input/extracted/e-taxall/...Ver12x.xlsx`
- `Guard CAB overlay report`:
  - `status=ok`
  - `reason=overlay guard passed`
  - `missingInternalKeysCount=12`
  - `unresolvedIdrefsCount=0`

## 収集成果物（抜粋）

- `/tmp/etax-unit-lane/KOA210.export.xml`
- `/tmp/etax-unit-lane/KOA110.export.xml`
- `/tmp/etax-unit-lane/TaxYear2025.overlay.diff.json`
- `/tmp/etax-unit-lane/TaxYear2025.overlay.diff.md`
- `/tmp/etax-unit-lane/xcodebuild_etax.log`
- `/tmp/etax-unit-lane/xsd_blue_validation.log`
- `/tmp/etax-unit-lane/xsd_white_validation.log`

## 要約

- `ETAX_XSD_REQUIRE_GENERATED_XML=true` のまま、KOA210/KOA110 の実生成XML経由XSD検証が CI 上で恒常的に通ることを確認。
- `cab-input=skip` の場合は overlay guard を `status=skip` で分離し、false failure を抑止できることを確認。
- `cab-input=ok` の場合は fetched CAB を入力に overlay を生成し、`overlay guard` を実行できることを確認。
- `ProfileSettingsViewTests` を e-Tax laneに含め、Keychain失敗時UI運用のSwift回帰証跡をCIで確定。
- T01 の受入条件（実生成XMLベースのXSD pass証跡化）は達成。
