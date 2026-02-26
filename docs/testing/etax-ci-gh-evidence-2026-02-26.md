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
- T01 の受入条件（実生成XMLベースのXSD pass証跡化）は達成。
