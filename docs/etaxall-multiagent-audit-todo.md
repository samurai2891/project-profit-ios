# e-taxall マルチAgent監査 Todo（30Agent版）

更新日: 2026-02-26  
対象: `project-profit-ios` + `e-taxall`  
調査体制: 30Agent（10 資料調査 / 7 コード調査 / 10 Todo化 / 3 精査）

## 1. 実施サマリ
- 調査証跡: 46件（`docs/etaxall-audit/evidence-index.csv`）
- 参照資料: `e-taxall` 内仕様書・XSD・モジュール文書 + `ProjectProfit` 実装 + `ProjectProfitTests`
- 非破壊検証:
  - `python3 -m unittest discover -s tools/etax/tests -p 'test_*.py'` は 14/14 success
  - `./scripts/run_etax_unit_lane.sh` で overlay適用 + KOA210/KOA110最小XSD検証が成功
  - `ETAX_XSD_REQUIRE_GENERATED_XML=true ./scripts/run_etax_unit_lane.sh` は `No iOS simulator runtime found` により実生成XML未出力でFail（fail-fast動作を確認）
  - `xcodebuild test ... -only-testing:ProjectProfitTests/EtaxXtxExporterTests` は CoreSimulator 不達で失敗（証跡 E040）
  - ローカル実行証跡: `docs/testing/etax-ci-local-evidence-2026-02-26.md`
  - GitHub実行証跡: `e-Tax CI` run `22440157027`（PR）/`22440174004`（workflow_dispatch）/`22443589546`（PR）/`22445208956`（PR）で success。実生成XML（`KOA210.export.xml` / `KOA110.export.xml`）経由の XSD pass を確認
  - run `22443589546` では `cab-input status=skip` 時に `Guard CAB overlay report` を `skipped`、`Skip CAB overlay guard` を `success` として分離し false failure を解消
  - run `22445208956` では `cab-input status=ok`、`input_dir=/tmp/etax-cab-input/extracted/e-taxall`、`Guard CAB overlay report: status=ok` を確認
  - GitHub実行証跡ドキュメント: `docs/testing/etax-ci-gh-evidence-2026-02-26.md`

## 2. 実装進捗（2026-02-26 実装反映後）

| ID | 状態 | 実装済み事実 | 残タスク |
|---|---|---|---|
| T01 | 完了（CI証跡確定） | `run_etax_unit_lane.sh` + `etax-ci.yml` で `ETAX_XSD_REQUIRE_GENERATED_XML=true` を固定し、run `22440157027` / `22440174004` で `KOA210.export.xml` / `KOA110.export.xml` の XSD pass を確認 | なし |
| T02 | 完了（本番CAB監視稼働） | `scripts/etax_generate_cab_overlay.py` を追加し、`帳票フィールド仕様書(所得-申告)Ver11x/12x` の KOA210/KOA110 から `requiredRule/idref/format` overlay を生成。run `22445208956` で `cab-input=ok` + `overlay guard=ok` を確認 | なし |
| T03 | 完了 | `TaxLine/AccountSubtype` に `insurance` を追加。`TaxYear2025.json` / `mapping_rules_2025.json` / `base_taxyear_2025.json` / `required_internal_keys.json` に `expense_insurance(AMF00260)` と `shushi_expense_insurance(AIG00290)` を反映。`cat-insurance -> acct-insurance` で実入力導線を追加 | なし |
| T04 | 完了 | `docs/testing/etax-taxyear-runbook.md` を追加し、2026年以降の TaxYear更新手順・検証手順・受入条件を明文化。implementation-packにも同期 | なし |
| T05 | 完了 | `ProfileSettingsView.saveProfile` の平文フォールバックを削除。`EtaxFieldPopulator` は secure payload のみ参照。`ProfileSettingsViewTests` を含むSwift回帰を run `22443589546` で通過 | なし |
| T06 | 完了（本番CAB定期運用固定） | `ETAX_CAB_SOURCE_URL`/`ETAX_CAB_SOURCE_SHA256`/`ETAX_CAB_ARCHIVE_TYPE` を設定し、run `22445208956` で fetched CAB入力から `抽出→適用→検証→差分→guard` を実行 | なし |
| T07 | 完了 | e-Tax関連Swiftテスト期待値を `AMF/AIG/KOA` 系に更新し、`e-Tax Unit Lane`（run `22443589546`）で安定通過を確認 | なし |
| T08 | 完了 | `TaxYearDefinitionLoader` に `fieldLabel/xmlTag/fieldDefinition` の `formType` 対応を追加 | なし |
| T09 | 完了（仕様/リリース文書反映済み） | スコープは「作成のみ（送信連携は非対応）」で固定し、仕様書とリリースゲートへ明記 | なし |
| T10 | 完了 | `scripts/check_simulator_health.sh` と `.github/workflows/etax-ci.yml`（`simulator-health` / `etax-unit`）を追加。PR #1 で `simulator-health` success / `etax-unit` failure を確認し、`main` の必須チェックに `e-Tax CI / Simulator Health`, `e-Tax CI / e-Tax Unit Lane` を設定 | なし（検出された実装Failは T07/T01/T02 側で解消） |

### 残タスク（優先順）
1. なし（T01〜T10の完了条件を満たした）。

## 3. 原本Todo一覧（監査時点）

| ID | 優先度 | 区分 | タイトル | ブロッカー |
|---|---|---|---|---|
| T01 | P0 | 根本問題 | 生成XMLのXSD自動検証が最小fixture止まり | Yes |
| T02 | P0 | 根本問題 | CAB実データ由来の必須/書式/相関メタ反映不足 | Yes |
| T03 | P1 | 技術的負債 | TaxLine語彙と仕様書の不整合 | No |
| T04 | P1 | 運用問題 | 年分対応戦略（UI/TaxYear/版差分）の未固定 | No |
| T05 | P0 | 根本問題 | 申告者情報の暗号化保存未実装 | Yes |
| T06 | P1 | 運用問題 | CAB本番入力を含むタグ更新パイプライン未整備 | No |
| T07 | P1 | 技術的負債 | Swiftテスト期待値と実リソースのドリフト | Yes |
| T08 | P2 | 技術的負債 | formType非考慮ローダによるラベル解決曖昧性 | No |
| T09 | P1 | 根本問題 | 送信連携スコープ（非対応/対応）の意思決定未固定 | No |
| T10 | P1 | 運用問題 | iOS Simulator依存テスト基盤の不安定性 | Yes |

---

### T01: XSD準拠XML構造の未実装（解消）
- 区分: 根本問題
- 事実:
  - `EtaxXtxExporterTests` が `ETAX_XSD_BLUE_EXPORT_XML` / `ETAX_XSD_WHITE_EXPORT_XML` 指定時に実生成XMLを書き出す。
  - `run_etax_unit_lane.sh` は実生成XMLを優先し、未生成時のみ fixture へfallbackする。
  - `.github/workflows/etax-ci.yml` は lane成果物をartifactとして収集する。
  - `e-Tax CI` run `22440157027` / `22440174004` / `22445208956` で `ETAX_XSD_REQUIRE_GENERATED_XML=true` のまま KOA210/KOA110 実生成XML経由のXSD passを確認した。
- 根拠:
  - `ProjectProfitTests/EtaxXtxExporterTests.swift`
  - `scripts/run_etax_unit_lane.sh`
  - `.github/workflows/etax-ci.yml`
  - `docs/testing/etax-ci-gh-evidence-2026-02-26.md`
- 影響:
  - 最小fixture止まりのリスクは解消し、CI上で実生成XML必須のXSD検証を恒常実行できる状態になった。
- 修正Todo:
  1. 完了: PR run `22440157027` で `KOA210.export.xml` / `KOA110.export.xml` の `reason=xsd validation passed` を確認。
  2. 完了: `workflow_dispatch` run `22440174004` で同一条件の再現成功を確認。
  3. 完了: PR run `22445208956` で本番CAB入力時も同一条件の成功を確認。
- 受入条件:
  - 実データ由来の KOA210/KOA110 XML がCIで毎回XSD検証を通過する（達成）。

### T02: 必須/型/書式/相関バリデーション欠落
- 区分: 根本問題
- 事実:
  - `validateForm` は `requiredRule` / `dataType` / `format` / `idref` / 未定義キー検出を実装済み。
  - `scripts/etax_apply_cab_overlay.py` で `requiredRule/idref/format/dataType` を TaxYearへ反映可能。
  - `run_etax_unit_lane.sh` は overlay適用後に `etax_validate_tags.py` を再実行する。
- 根拠:
  - `ProjectProfit/Services/EtaxCharacterValidator.swift`
  - `ProjectProfit/Models/EtaxModels.swift`
  - `scripts/etax_apply_cab_overlay.py`
  - `scripts/etax_overlay_guard.py`
  - `.github/workflows/etax-ci.yml`
  - `docs/testing/etax-ci-gh-evidence-2026-02-26.md`（run `22445208956`）
- 影響:
  - 必須/書式/相関メタの監視運用は本番CAB入力で稼働済み。
- 修正Todo:
  1. 完了: CAB抽出成果物（TagDictionary/overlay）から `requiredRule/idref/format` を反映し、差分レポートを成果物化した。
  2. 完了: run `22445208956` で `Guard CAB overlay report: status=ok` を確認した（`missingInternalKeysCount=12`, `unresolvedIdrefsCount=0`）。
- 受入条件:
  - CAB実データ反映後、要件違反時にエクスポート不可となり、違反キー一覧が表示される（達成）。

### T03: TaxLine語彙と仕様書の不整合
- 区分: 技術的負債
- 事実:
  - 仕様書の主要経費例に `利子割引料` / `租税公課` を含む（E042）。
  - 実装は `interest/taxes` へ同期済みで、`TaxYear2025/mapping_rules/base fixture/required keys` も同語彙に更新済み。
  - `AccountSubtype` は decode時に旧 `repairExpense/welfareExpense` を `interestExpense/taxesExpense` へ互換吸収する。
- 根拠:
  - `e-taxall/確定申告仕様書/仕様書：e‑Tax「決算書・収支内訳書」データ作成.md:216-227`
  - `ProjectProfit/Models/TaxLineDefinitions.swift`
  - `ProjectProfit/Models/AccountingEnums.swift`
  - `ProjectProfit/Resources/TaxYear2025.json`
- 影響:
  - `white.exp.insurance` が実入力に流れず、KOA110 `AIG00290` へ出力できないリスクがあった。
- 修正Todo:
  1. `TaxLine/AccountSubtype/DefaultAccount/CategoryMapping` を `insurance` 対応へ拡張。
  2. `TaxYear2025` と toolchain定義へ `AMF00260` / `AIG00290` を反映。
- 受入条件:
  - 仕様書側TaxLine一覧と実装一覧の差分がゼロになる。

### T04: 年分対応戦略の未固定
- 区分: 運用問題
- 事実:
  - `TaxYear2025.json` しか存在しない（E025）。
  - UIは複数年を選べる（`currentYear-5 ... currentYear`）（E037）。
  - e-taxall側は多数版の設計書/XSDを持つ（E023, E024）。
- 根拠:
  - `ProjectProfit/Resources/TaxYear2025.json`
  - `ProjectProfit/Views/Accounting/EtaxExportView.swift:90`
- 影響:
  - ユーザー操作年と対応年の不一致でエラーが多発する。
- 修正Todo:
  1. 対応年分を設定値化し、UI選択候補を対応年分に限定。
  2. 年分追加時の運用（取得元、レビュー、反映、検証）をRunbook化。
- 受入条件:
  - 未対応年をUIで選択できない、または明示警告で実行不可。

### T05: 機微情報暗号化未実装
- 区分: 根本問題
- 事実:
  - `ProfileSecureStore`（Keychain）で機微情報を保存し、`saveProfile` の平文フォールバックを削除した。
  - `EtaxFieldPopulator` は secure payload のみを参照し、legacy平文を出力しない。
  - `EtaxFieldPopulatorTests` に平文読取遮断ケースを追加した。
- 根拠:
  - `ProjectProfit/Views/Settings/ProfileSettingsView.swift`
  - `ProjectProfit/Services/EtaxFieldPopulator.swift`
  - `ProjectProfitTests/EtaxFieldPopulatorTests.swift`
  - `ProjectProfitTests/ProfileSettingsViewTests.swift`
  - `docs/testing/etax-ci-gh-evidence-2026-02-26.md`（run `22443589546`）
- 影響:
  - 平文保存リスクと回帰未検証リスクは解消した。
- 修正Todo:
  1. 完了: `e-Tax Unit Lane` に `ProfileSettingsViewTests` を追加し、run `22443589546` で成功を確認。
- 受入条件:
  - 機微情報が平文DBに残らないことをテストで確認できる（達成）。

### T06: CAB本番入力を含むパイプライン未整備
- 区分: 運用問題
- 事実:
  - `run_etax_unit_lane.sh` が `ETAX_TAG_INPUT_DIR` で入力切替可能となり、`抽出→適用→検証→差分` を実行する。
  - `scripts/etax_report_taxyear_diff.py` が overlay差分を JSON/Markdown で出力する。
  - `etax-ci.yml` が `/tmp/etax-unit-lane` をartifact収集する。
- 根拠:
  - `scripts/run_etax_unit_lane.sh`
  - `scripts/fetch_etax_cab_input.sh`
  - `scripts/etax_report_taxyear_diff.py`
  - `.github/workflows/etax-ci.yml`
  - `docs/testing/etax-ci-gh-evidence-2026-02-26.md`（run `22445208956`）
- 影響:
  - 本番CAB入力を使った定期実行経路は固定化され、投入時のFail/skip判定も安定した。
- 修正Todo:
  1. 完了: release asset を `ETAX_CAB_SOURCE_URL` として設定し、SHA検証付きで取得できるようにした。
  2. 完了: run `22445208956` で `cab-input status=ok`、`cab_overlay_2025.generated.report.json` 生成、`overlay-guard` 実行を確認した。
- 受入条件:
  - 新CAB投入で `抽出→検証→反映→差分レポート` が自動実行される（達成）。

### T07: Swiftテスト資産のドリフト
- 区分: 技術的負債
- 事実:
  - Swiftテスト期待値は `AMF/AIG/KOA` 系へ更新済み。
  - `e-Tax Unit Lane`（run `22443589546`）で e-Tax Swift最小セットが成功した。
- 根拠:
  - `ProjectProfitTests/EtaxXtxExporterTests.swift`
  - `ProjectProfitTests/TaxYearDefinitionLoaderTests.swift`
  - `docs/testing/etax-ci-gh-evidence-2026-02-26.md`（run `22443589546`）
  - `ProjectProfit/Resources/TaxYear2025.json:7`
  - `docs/testing/etax-regression-checklist.md`
- 影響:
  - 主要ドリフトは解消し、CI品質指標の信頼性が回復した。
- 修正Todo:
  1. 完了: テスト期待値を現行TaxYearタグに合わせた。
  2. 完了: `e-Tax Unit Lane` でSimulator実行の回帰通過を確認した。
- 受入条件:
  - e-Tax関連Swiftテストが現行定義で安定通過する（達成）。

### T08: formType非考慮ローダの曖昧性
- 区分: 技術的負債
- 事実:
  - `sales_revenue` が blue/shushi 双方で定義（E044）。
  - `fieldLabel(for taxLine:)` は最初の1件だけ返す（E045）。
- 根拠:
  - `ProjectProfit/Resources/TaxYear2025.json:5-17,271-277`
  - `ProjectProfit/Services/TaxYearDefinitionLoader.swift:15-20`
- 影響:
  - フォーム別ラベルが誤表示される可能性。
- 修正Todo:
  1. `fieldLabel(for:formType:fiscalYear:)` を導入しフォーム条件で解決。
  2. `TaxFieldDefinition` に `form` を追加。
- 受入条件:
  - 白色/青色で同一taxLineでも正しいラベルが選択される。

### T09: 送信連携スコープ未固定（解消）
- 区分: 根本問題
- 実施:
  - 送信連携はスコープ外、アプリの責務は `.xtx/.csv` の作成までとする方針を固定。
  - 仕様書に「送信（ログイン/署名/送信操作）は行わない」を明記し、リリースゲート文書にも同方針を反映。
- 根拠:
  - `docs/etaxall-implementation-pack/04_specs/Project Profit iOS：複式簿記コア導入・完全仕様書（外注実装用）.md:6`
  - `docs/etaxall-implementation-pack/04_specs/Project Profit iOS：複式簿記コア導入・完全仕様書（外注実装用）.md:44`
  - `docs/etaxall-multiagent-audit-todo.md:247`
- 受入条件:
  - 仕様書とリリース判定文書でスコープ境界が一致している（達成）。

### T10: テスト実行基盤の不安定性
- 区分: 運用問題
- 事実:
  - `xcodebuild test` が `CoreSimulatorService connection became invalid` で失敗（E040）。
  - unit-lane文書上はSwift laneを前提にする（E037）。
- 実装反映（2026-02-26）:
  - `scripts/check_simulator_health.sh` を追加（`status=ok|warn|error` を機械可読出力）。
  - `scripts/run_etax_unit_lane.sh` が health check に従って Swift lane を実行/skip。
  - `.github/workflows/etax-ci.yml` を追加（`simulator-health` と `etax-unit` の2ジョブ構成）。
- 根拠:
  - 実行ログ（2026-02-26 12:34-12:35）
  - `docs/testing/etax-unit-lane.md:43-51`
- 影響:
  - Swift回帰が継続的に実行できず、リリース判断が不安定。
- 修正Todo:
  1. Simulator非依存のSwift unit laneを分離（macOS対象/純ロジック中心）。
  2. CIで環境異常を自動判別するジョブを追加。
- 受入条件:
  - e-Tax関連の最小Swift回帰が毎回自動実行できる。

## 4. リリースゲート（2026-02-26 実装反映後）
- 判定: **Go（本監査スコープ T01〜T10 は完了）**
- ブロッカー: なし
- 備考: 送信連携はスコープ外（T09方針どおり「作成のみ」）。

## 5. 参照
- Agent別報告: `docs/etaxall-audit/reports/A01.md` 〜 `A30.md`
- 役割表: `docs/etaxall-audit/agent-roster.md`
- 証跡: `docs/etaxall-audit/evidence-index.csv`
