# e-Tax CI Local Evidence (2026-02-26)

対象リポジトリ: `/Users/yutaro/project-profit-ios`  
実行日: 2026-02-26

## 実行コマンドと結果

1. `python3 -m unittest discover -s tools/etax/tests -p 'test_*.py'`
   - 結果: `Ran 12 tests ... OK`

2. `ETAX_XSD_REQUIRE_GENERATED_XML=false ./scripts/run_etax_unit_lane.sh`
   - 結果: success
   - 主要事実:
     - `overlayItemCount=39`
     - `touchedInternalKeyCount=39`（`expense_insurance` / `shushi_expense_insurance` を含む）
     - `xsd require generated xml: false`
     - KOA210/KOA110 のXSD検証は `status=ok`（fallback XML）

3. `ETAX_XSD_REQUIRE_GENERATED_XML=true ./scripts/run_etax_unit_lane.sh`
   - 結果: fail（期待どおり）
   - 失敗理由:
     - `status=error`
     - `reason=No iOS simulator runtime found`
     - `error: blue generated xml is required but missing: /tmp/etax-unit-lane/KOA210.export.xml`

4. `./scripts/check_simulator_health.sh`
   - 結果:
     - `status=error`
     - `reason=No iOS simulator runtime found`

5. `xcodebuild -project ProjectProfit.xcodeproj -scheme ProjectProfit -destination 'generic/platform=iOS Simulator' build`
   - 結果: `BUILD SUCCEEDED`

6. `xcodebuild test ... -only-testing:ProjectProfitTests/EtaxXtxExporterTests`（iOS系宛先）
   - 結果: fail
   - 主要理由:
     - CoreSimulatorService 不達
     - iOS署名証明書/プロビジョニングプロファイル不足

7. `gh auth status`
   - 結果: fail
   - 主要理由:
     - `The token in default is invalid.`
     - 再認証が必要: `gh auth login -h github.com`

## 要約
- T03（`white.exp.insurance` 導線）は実装反映済みで、lane上のoverlay/touched keyに反映されることを確認。
- T01の受入条件である「実生成XML経由XSD pass」は、ローカル環境ではCoreSimulator runtime不足により未確定。
- T01/T02の最終証跡確定は、`etax-ci` をGitHub Actions上で実行し、artifact + summaryをPRへ添付して完了。
