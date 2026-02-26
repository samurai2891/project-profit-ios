# e-taxall マルチAgent監査 Todo（30Agent版）

更新日: 2026-02-26  
対象: `project-profit-ios` + `e-taxall`  
調査体制: 30Agent（10 資料調査 / 7 コード調査 / 10 Todo化 / 3 精査）

## 1. 実施サマリ
- 調査証跡: 46件（`docs/etaxall-audit/evidence-index.csv`）
- 参照資料: `e-taxall` 内仕様書・XSD・モジュール文書 + `ProjectProfit` 実装 + `ProjectProfitTests`
- 非破壊検証:
  - `python3 -m unittest discover -s tools/etax/tests -p 'test_*.py'` は 7/7 success
  - `xcodebuild test ... -only-testing:ProjectProfitTests/EtaxXtxExporterTests` は CoreSimulator 不達で失敗（証跡 E040）

## 2. 実装進捗（2026-02-26 実装反映後）

| ID | 状態 | 実装済み事実 | 残タスク |
|---|---|---|---|
| T01 | 進行中 | `EtaxXtxExporter` が `KOA210/KOA110` ルートと `VR`/`FormAttribute` を出力 | 生成XMLのXSD検証ジョブ追加 |
| T02 | 進行中 | `TaxFieldDefinition` に `requiredRule/format/idref/form` を追加し、`validateForm` で型/書式/相関/未定義キーを検証 | CAB由来の `requiredRule/idref/format` 実データ反映 |
| T03 | 未着手 | なし | `TaxLine` 語彙（interest/taxes など）を仕様と同期 |
| T04 | 進行中 | `EtaxExportView` が `supportedYears(formType:)` で候補年を制限、`TaxYear2025.json` に `forms` 追加 | 複数年 `TaxYear*.json` 整備と年次更新Runbook |
| T05 | 進行中 | `ProfileSecureStore`（Keychain）実装、設定画面に「機微情報を出力」トグル追加、保存時マイグレーション実装 | 平文保持禁止の強制（save失敗時フォールバック方針含む）とSwift実行検証 |
| T06 | 未着手 | なし | CAB本番入力を使うCIパイプライン構築 |
| T07 | 進行中 | e-Tax関連Swiftテスト期待値を `AMF/AIG/KOA` 系に更新 | Simulator実行環境でSwiftテスト実行を完了 |
| T08 | 完了 | `TaxYearDefinitionLoader` に `fieldLabel/xmlTag/fieldDefinition` の `formType` 対応を追加 | なし |
| T09 | 完了（方針固定） | スコープは「作成のみ（送信連携は非対応）」で固定 | 仕様書/リリース判定文書への明記反映 |
| T10 | 完了 | `scripts/check_simulator_health.sh` と `.github/workflows/etax-ci.yml`（`simulator-health` / `etax-unit`）を追加。PR #1 で `simulator-health` success / `etax-unit` failure を確認し、`main` の必須チェックに `e-Tax CI / Simulator Health`, `e-Tax CI / e-Tax Unit Lane` を設定 | なし（検出された実装Failは T07/T01/T02 側で解消） |

### 残タスク（優先順）
1. T01: 生成XMLに対するXSD検証フェーズを追加し、提出可能形式を自動検証する。
2. T02: CAB実データから `requiredRule/idref/format` を取り込み、必須・相関チェックを実効化する。
3. T05: 機微情報の平文保持禁止をコード上で強制し、失敗時の平文フォールバックを解消する。
4. T06: CAB投入から `抽出→適用→検証→差分レポート` までをCIで自動化する。
5. T03: `TaxLine` 語彙と勘定マッピングを仕様書と一致させる。
6. T04: 2026年以降の `TaxYear*.json` 運用（更新手順・レビュー手順）をRunbook化する。

## 3. 原本Todo一覧（監査時点）

| ID | 優先度 | 区分 | タイトル | ブロッカー |
|---|---|---|---|---|
| T01 | P0 | 根本問題 | XSD準拠XML構造の未実装 | Yes |
| T02 | P0 | 根本問題 | 必須/型/書式/相関バリデーション欠落 | Yes |
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
  - e-taxall XSDは `KOA210` / `KOA110` ルート、`VR` 属性、`FormAttribute` を要求（E019, E021, E022）。
  - 実装は `<eTaxData year=... formType=...>` の独自ルートを生成（E028）。
- 根拠:
  - `e-taxall/19XMLスキーマ/shotoku/KOA210-011.xsd:23-52`
  - `e-taxall/19XMLスキーマ/shotoku/KOA110-012.xsd:23-42`
  - `e-taxall/19XMLスキーマ/general/General.xsd:22-27`
  - `ProjectProfit/Services/EtaxXtxExporter.swift:107-118`
- 影響:
  - タグ値が正しくても、提出可能XMLとして受理されないリスクが高い。
- 修正Todo:
  1. `EtaxXtxExporter` をフォーム別（KOA210/KOA110）ビルダーに分離する。
  2. `VR` と `FormAttribute(softNM/sakuseiNM/sakuseiDay)` を必須出力にする。
  3. 生成XMLをXSDで検証するフェーズを追加する（T02連動）。
- 受入条件:
  - KOA210/KOA110形式のXMLが生成され、XSD検証を通過する。

### T02: 必須/型/書式/相関バリデーション欠落
- 区分: 根本問題
- 事実:
  - 仕様は `format/requiredRule` 強制、違反時エクスポート不可を要求（E005）。
  - 実装の `validateForm` は文字種チェックのみ（E030）。
  - `missingRequiredField` / `validationFailed` は未使用（E032）。
  - 未マップフィールドは `continue` で無言破棄（E029）。
- 根拠:
  - `e-taxall/確定申告仕様書/仕様書：e‑Tax「決算書・収支内訳書」データ作成.md:385-390`
  - `ProjectProfit/Services/EtaxCharacterValidator.swift:79-95`
  - `ProjectProfit/Models/EtaxModels.swift:161-179`
  - `ProjectProfit/Services/EtaxXtxExporter.swift:137-140`
- 影響:
  - 必須欠落や形式違反を通したまま出力する可能性がある。
- 修正Todo:
  1. `TaxFieldDefinition` に `requiredRule`, `format`, `idref`, `form` を追加。
  2. 出力前に「必須キー欠落」「型違反」「書式違反」「相関違反」を検証。
  3. 未マップキーは `continue` ではなくエラー化。
- 受入条件:
  - 要件違反時はエクスポート不可となり、違反キー一覧が表示される。

### T03: TaxLine語彙と仕様書の不整合
- 区分: 技術的負債
- 事実:
  - 仕様書の主要経費例に `利子割引料` / `租税公課` を含む（E042）。
  - 実装TaxLineは `repair` / `welfare` を持ち、`interest` / `taxes` を持たない（E043）。
- 根拠:
  - `e-taxall/確定申告仕様書/仕様書：e‑Tax「決算書・収支内訳書」データ作成.md:216-227`
  - `ProjectProfit/Models/TaxLineDefinitions.swift:10-21`
- 影響:
  - 科目→TaxLineの対応が仕様ドキュメントと一致しない可能性。
- 修正Todo:
  1. TaxLine語彙の正をe-taxall仕様に合わせて再定義。
  2. `AccountingEnums` / `TaxYear2025` / マッピングルールを一括同期。
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
  - 仕様は高機微情報の端末内暗号化を必須化（E006）。
  - `PPAccountingProfile` に氏名/住所/電話/生年月日/マイナンバー関連を保持（E039）。
  - `CryptoKit`/`Keychain`/`SecItem` 利用痕跡なし（E038）。
- 根拠:
  - `e-taxall/確定申告仕様書/仕様書：e‑Tax「決算書・収支内訳書」データ作成.md:178-179`
  - `ProjectProfit/Models/PPAccountingProfile.swift:23-29`
- 影響:
  - 端末喪失・バックアップ経路での情報露出リスク。
- 修正Todo:
  1. 申告者情報の保存先を暗号化ストアへ移行。
  2. 平文保持禁止ポリシーをコード/テストで強制。
  3. 同意/表示方針を設定画面に追加。
- 受入条件:
  - 機微情報が平文DBに残らないことをテストで確認できる。

### T06: CAB本番入力を含むパイプライン未整備
- 区分: 運用問題
- 事実:
  - 実行例・unit laneは `tools/etax/fixtures` と `/tmp` 出力中心（E036）。
  - CSV変換・版管理仕様はe-taxallにあるが、本番CAB取り込みの継続運用が未定義（E015, E023）。
- 根拠:
  - `scripts/run_etax_unit_lane.sh:10-22`
  - `tools/etax/README.md:16-26`
- 影響:
  - 本番仕様更新時の追従が手作業化し、取り込み漏れが起きる。
- 修正Todo:
  1. CAB展開入力を前提にしたCIジョブを追加。
  2. `TaxYear*.json` への適用から差分レビューまで自動化。
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
- ブロッカー: `T01`, `T02`, `T05`, `T10`
- 条件付きブロッカー: `T07`（Swiftテストの実行環境不足）

## 5. 参照
- Agent別報告: `docs/etaxall-audit/reports/A01.md` 〜 `A30.md`
- 役割表: `docs/etaxall-audit/agent-roster.md`
- 証跡: `docs/etaxall-audit/evidence-index.csv`
