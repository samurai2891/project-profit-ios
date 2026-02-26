# e-taxall マルチAgent監査 Todo（30Agent版）

更新日: 2026-02-26  
対象: `project-profit-ios` + `e-taxall`  
調査体制: 30Agent（10 資料調査 / 7 コード調査 / 10 Todo化 / 3 精査）

## 1. 実施サマリ
- 調査証跡: 46件（`docs/etaxall-audit/evidence-index.csv`）
- 参照資料: `e-taxall` 内仕様書・XSD・モジュール文書 + `ProjectProfit` 実装 + `ProjectProfitTests`
- 非破壊検証:
  - `python3 -m unittest discover -s tools/etax/tests -p 'test_*.py'` は 12/12 success
  - `./scripts/run_etax_unit_lane.sh` で overlay適用 + KOA210/KOA110最小XSD検証が成功
  - `ETAX_XSD_REQUIRE_GENERATED_XML=true ./scripts/run_etax_unit_lane.sh` は `No iOS simulator runtime found` により実生成XML未出力でFail（fail-fast動作を確認）
  - `xcodebuild test ... -only-testing:ProjectProfitTests/EtaxXtxExporterTests` は CoreSimulator 不達で失敗（証跡 E040）
  - `gh auth status` は default token invalid（`gh auth login -h github.com` が必要）
  - ローカル実行証跡: `docs/testing/etax-ci-local-evidence-2026-02-26.md`

## 2. 実装進捗（2026-02-26 実装反映後）

| ID | 状態 | 実装済み事実 | 残タスク |
|---|---|---|---|
| T01 | 実装完了（CI証跡待ち） | `run_etax_unit_lane.sh` に `ETAX_XSD_REQUIRE_GENERATED_XML` を追加し、CIでは実生成XML欠落時にFailする構成へ更新。`etax-ci.yml` は `ETAX_XSD_REQUIRE_GENERATED_XML=true` を固定 | PR上でKOA210/KOA110実生成XMLのXSD passログを添付 |
| T02 | 実装完了（運用監視） | `scripts/etax_generate_cab_overlay.py` を追加し、`帳票フィールド仕様書(所得-申告)Ver11x/12x` の KOA210/KOA110 から `requiredRule/idref/format` overlay を生成。laneで自動生成overlayを優先適用 | report の `missingInternalKeys/unresolvedIdrefs` を継続監視 |
| T03 | 完了 | `TaxLine/AccountSubtype` に `insurance` を追加。`TaxYear2025.json` / `mapping_rules_2025.json` / `base_taxyear_2025.json` / `required_internal_keys.json` に `expense_insurance(AMF00260)` と `shushi_expense_insurance(AIG00290)` を反映。`cat-insurance -> acct-insurance` で実入力導線を追加 | なし |
| T04 | 完了 | `docs/testing/etax-taxyear-runbook.md` を追加し、2026年以降の TaxYear更新手順・検証手順・受入条件を明文化。implementation-packにも同期 | なし |
| T05 | 進行中 | `ProfileSettingsView.saveProfile` の平文フォールバックを削除。`EtaxFieldPopulator` は secure payload のみ参照。平文読取遮断のテストを追加 | Simulator実行環境でSwift回帰を通し受入証跡を確定 |
| T06 | 進行中 | `run_etax_unit_lane.sh` に `ETAX_TAG_INPUT_DIR`/overlay diff生成（JSON+MD）を追加。`etax-ci.yml` で lane成果物をartifact収集 | CAB本番入力ディレクトリを使った定期実行運用を固定 |
| T07 | 進行中 | e-Tax関連Swiftテスト期待値を `AMF/AIG/KOA` 系に更新 | Simulator実行環境でSwiftテスト実行を完了 |
| T08 | 完了 | `TaxYearDefinitionLoader` に `fieldLabel/xmlTag/fieldDefinition` の `formType` 対応を追加 | なし |
| T09 | 完了（方針固定） | スコープは「作成のみ（送信連携は非対応）」で固定 | 仕様書/リリース判定文書への明記反映 |
| T10 | 完了 | `scripts/check_simulator_health.sh` と `.github/workflows/etax-ci.yml`（`simulator-health` / `etax-unit`）を追加。PR #1 で `simulator-health` success / `etax-unit` failure を確認し、`main` の必須チェックに `e-Tax CI / Simulator Health`, `e-Tax CI / e-Tax Unit Lane` を設定 | なし（検出された実装Failは T07/T01/T02 側で解消） |

### 残タスク（優先順）
1. `gh auth login -h github.com` を実施し、`etax-ci` をPR/`workflow_dispatch`で実行可能にする。
2. T01/T02: PR上で `etax-ci` の実行証跡（実生成XMLのXSD pass、overlay report）を添付する。
3. T06: CAB投入から `抽出→適用→検証→差分レポート` を本番入力で定期運用化する。
4. T05: Keychain保存失敗時のUI運用とSwift回帰証跡をCIで確定する。
5. T07: Simulator実行環境でSwiftテスト実行を完了する。

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

### T01: XSD準拠XML構造の未実装
- 区分: 根本問題
- 事実:
  - `EtaxXtxExporterTests` が `ETAX_XSD_BLUE_EXPORT_XML` / `ETAX_XSD_WHITE_EXPORT_XML` 指定時に実生成XMLを書き出す。
  - `run_etax_unit_lane.sh` は実生成XMLを優先し、未生成時のみ fixture へfallbackする。
  - `.github/workflows/etax-ci.yml` は lane成果物をartifactとして収集する。
- 根拠:
  - `ProjectProfitTests/EtaxXtxExporterTests.swift`
  - `scripts/run_etax_unit_lane.sh`
  - `.github/workflows/etax-ci.yml`
- 影響:
  - 仕組みは実装済みだが、CoreSimulator不達環境では実生成XMLが未出力のため最終検証が未確定。
- 修正Todo:
  1. Simulator利用可能なCI実行ログで、実生成XML経由のXSD passを証跡化する。
  2. 様式別（blue/white）で最低1ケースずつ実データ検証の結果をPRに添付する。
- 受入条件:
  - 実データ由来の KOA210/KOA110 XML がCIで毎回XSD検証を通過する。

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
  - `tools/etax/fixtures/cab_overlay_2025.json`
- 影響:
  - overlayはfixture中心で、CAB本番抽出由来の全面反映が未完。
- 修正Todo:
  1. CAB抽出成果物（TagDictionary/overlay）から全internalKeyの `requiredRule/idref/format` を取り込む。
  2. overlay反映結果の差分レポートをCI成果物として保存する。
  3. `requiredRule` 条件式の実データケースをテストへ追加する。
- 受入条件:
  - CAB実データ反映後、要件違反時にエクスポート不可となり、違反キー一覧が表示される。

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
- 影響:
  - 平文保存リスクは低減したが、Simulator実行環境でのSwift回帰証跡が未取得。
- 修正Todo:
  1. CI実行で追加テストを通し、受入証跡を固定化する。
- 受入条件:
  - 機微情報が平文DBに残らないことをテストで確認できる。

### T06: CAB本番入力を含むパイプライン未整備
- 区分: 運用問題
- 事実:
  - `run_etax_unit_lane.sh` が `ETAX_TAG_INPUT_DIR` で入力切替可能となり、`抽出→適用→検証→差分` を実行する。
  - `scripts/etax_report_taxyear_diff.py` が overlay差分を JSON/Markdown で出力する。
  - `etax-ci.yml` が `/tmp/etax-unit-lane` をartifact収集する。
- 根拠:
  - `scripts/run_etax_unit_lane.sh`
  - `scripts/etax_report_taxyear_diff.py`
  - `.github/workflows/etax-ci.yml`
- 影響:
  - パイプライン枠は整備されたが、本番CAB入力を定期投入する運用ルールは未確定。
- 修正Todo:
  1. 本番CABの配置先と投入タイミングを定義し、`ETAX_TAG_INPUT_DIR` でCI定期実行する。
- 受入条件:
  - 新CAB投入で `抽出→検証→反映→差分レポート` が自動実行される。

### T07: Swiftテスト資産のドリフト
- 区分: 技術的負債
- 事実:
  - Swiftテストは `BlueRevenueSales` 等を期待（E033, E034）。
  - 実リソースは `AMF00100` 系（E035）。
  - 回帰チェックリストは未チェック状態（E046）。
- 根拠:
  - `ProjectProfitTests/EtaxXtxExporterTests.swift:42-44`
  - `ProjectProfitTests/TaxYearDefinitionLoaderTests.swift:43-44`
  - `ProjectProfit/Resources/TaxYear2025.json:7`
  - `docs/testing/etax-regression-checklist.md:6-31`
- 影響:
  - テスト実行可能環境で大量失敗の可能性、品質指標の信頼低下。
- 修正Todo:
  1. テスト期待値を現行TaxYearタグに合わせる。
  2. タグ変更多発箇所は固定文字列比較から定義参照型へ移行。
- 受入条件:
  - e-Tax関連Swiftテストが現行定義で安定通過する。

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

### T09: 送信連携スコープ未固定
- 区分: 根本問題
- 事実:
  - 現仕様は送信非スコープ（E007）。
  - e-taxallにはAPI/署名/送受信モジュールの詳細要件がある（E008-E014）。
- 根拠:
  - `e-taxall/確定申告仕様書/Project Profit iOS：複式簿記コア導入・完全仕様書（外注実装用）.md:6`
  - `docs/etaxall-audit/extracted/api_spec.txt:89-92`
- 影響:
  - リリース定義（どこまで提供するか）が不明確なままでは評価軸が揺れる。
- 修正Todo:
  1. プロダクトとして「作成のみ」か「提出連携まで」かを意思決定。
  2. 決定内容に合わせて受入条件とテスト範囲を再定義。
- 受入条件:
  - リリース判定文書にスコープ境界が明記される。

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
- 判定: **No-Go**
- ブロッカー: `T01`, `T02`, `T06`
- 条件付きブロッカー: `T05`, `T07`（Swiftテストの実行環境不足）

## 5. 参照
- Agent別報告: `docs/etaxall-audit/reports/A01.md` 〜 `A30.md`
- 役割表: `docs/etaxall-audit/agent-roster.md`
- 証跡: `docs/etaxall-audit/evidence-index.csv`
