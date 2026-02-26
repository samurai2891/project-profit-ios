# e-Tax CI Local Evidence (2026-02-26)

対象リポジトリ: `/Users/yutaro/project-profit-ios`  
実行日: 2026-02-26

## 実行コマンドと結果

1. `python3 -m unittest discover -s tools/etax/tests -p 'test_*.py'`
   - 結果: `Ran 14 tests ... OK`

2. `ETAX_ARTIFACTS_DIR=/tmp/etax-unit-lane-final ETAX_TAG_INPUT_DIR=e-taxall ./scripts/run_etax_unit_lane.sh`
   - 結果: success
   - 主要事実:
     - `overlayItemCount=39`
     - `touchedInternalKeyCount=39`（`expense_insurance` / `shushi_expense_insurance` を含む）
     - `changedFieldCount=39`（`requiredRule/format/dataType` 反映）
     - `missingFieldCount=12`
     - `unresolvedIdrefCount=0`
     - `status=error` / `reason=CoreSimulatorService is unavailable` のため Swift lane は skip
     - KOA210/KOA110 のXSD検証は `status=ok`（fallback XML）

3. `python3 scripts/etax_overlay_guard.py --report /tmp/etax-unit-lane-final/cab_overlay_2025.generated.report.json --max-missing-internal-keys 12 --max-unresolved-idrefs 0 ...`
   - 結果: success
   - 主要事実:
     - `status=ok`
     - `missingInternalKeysCount=12`
     - `unresolvedIdrefsCount=0`

4. `ETAX_XSD_REQUIRE_GENERATED_XML=true ETAX_ARTIFACTS_DIR=/tmp/etax-unit-lane-generated-required ETAX_TAG_INPUT_DIR=e-taxall ./scripts/run_etax_unit_lane.sh`
   - 結果: fail（期待どおり）
   - 失敗理由:
     - `status=error`
     - `reason=CoreSimulatorService is unavailable`
     - `error: blue generated xml is required but missing: /tmp/etax-unit-lane-generated-required/KOA210.export.xml`

5. `./scripts/check_simulator_health.sh`
   - 結果:
     - `status=error`
     - `reason=CoreSimulatorService is unavailable`

6. `gh auth status`
   - 結果: fail
   - 主要理由:
     - `The token in default is invalid.`
     - 再認証が必要: `gh auth login -h github.com`

## 要約
- 公式CAB/Excel（`e-taxall/09XML構造設計書等【所得税】` の Ver11x/12x）由来で overlay を再生成し、`requiredRule/format/dataType` 39項目反映を確認。
- `TaxYear2025` について `xmlTag` 差分は 0 件であることを確認。
- ローカルでは `CoreSimulatorService` 不達のため、実生成XML必須モード（`ETAX_XSD_REQUIRE_GENERATED_XML=true`）は失敗する。
- 実生成XML経由の最終証跡は GitHub Actions `e-Tax CI` で継続確認する運用を維持する。
