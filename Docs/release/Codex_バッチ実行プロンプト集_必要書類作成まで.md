# Codex バッチ実行プロンプト集（必要書類作成まで）

更新日: 2026-03-15  
対象 repo: `project-profit-ios`  
正本タスク書: `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`

---

## 0. この prompt 集の目的

この prompt 集は、`統合_修正タスク一覧_P0_P1_必要書類作成まで.md` を正本として、Codex に **コンテキストウインドウを意識した複数バッチ実行**をさせるためのものです。

狙いは次の 4 点です。

1. 1 本の巨大 prompt で途中から品質が落ちるのを防ぐ。  
2. 各バッチの対象ファイルと完了条件を固定し、サボり・飛ばし・勝手な拡張を防ぐ。  
3. 各バッチを **新しい Codex スレッド**で実行し、前バッチの成果は **状態ファイル**で引き継ぐ。  
4. バッチごとに検証し、失敗したら次へ進ませない。

---

## 1. 実行方式（重要）

### 1-1. 1 バッチ = 1 スレッド
- **1 本の Codex スレッドで最後までやらせない。**
- **各バッチごとに新しい Codex スレッド**を開始する。
- 次バッチは、前バッチの変更が作業ツリーに反映され、必要なら commit された状態で開始する。

### 1-2. 毎回読むファイルを制限する
各バッチで Codex に読ませるのは原則として次の 3 種類だけにする。

1. 正本タスク書  
   `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
2. 状態ファイル  
   `Docs/release/codex_batch_state.md`
3. そのバッチ専用の対象ファイル群

**禁止:**
- repo 全体を最初に総なめすること
- 無関係な `Docs/` 全体を読み始めること
- そのバッチの対象外ファイルへ勝手に手を広げること

### 1-3. 状態ファイルを唯一の進捗引継ぎ手段にする
各バッチ終了時に、必ず次を更新する。

- `Docs/release/codex_batch_state.md`

このファイルに記録する内容:
- 完了したタスク ID
- 未完のタスク ID
- 変更したファイル一覧
- 実行した検証コマンド
- 検証結果
- 残っている blocker
- 次バッチが読むべき最小ファイル一覧

### 1-4. バッチをまたぐ共通ルール
- 正本は常に `統合_修正タスク一覧_P0_P1_必要書類作成まで.md`。
- 推測で仕様を補わない。
- bundled official XSD / 帳票フィールド仕様書 / 現行コードで確認できる事実だけを使う。
- 既存スクリプトや既存テストがある場合、**新しい独自運用を作る前に既存の流れに合わせる**。
- テストは **最小 relevant validation** → **バッチ末尾の必須 validation** の順で行う。
- バッチ完了条件を満たせなければ、次バッチへ進まない。

---

## 2. 共通 prompt（毎バッチの先頭に必ず付ける）

以下を **毎バッチの最初に必ず貼る共通 prompt** とする。

```text
あなたは Codex です。今回の作業は、repo 内の正本ドキュメント
`Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
に従って、必要書類作成までの修正を段階的に進めるものです。

重要ルール:
1. 今回は「提出機能」は対象外です。必要書類の正しい作成までがスコープです。
2. このスレッドでは、与えられたバッチだけを実施してください。勝手に次バッチへ進まないでください。
3. 最初に読むのは次の 2 ファイルだけです。
   - Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
   - Docs/release/codex_batch_state.md
4. その後、このバッチで指定された対象ファイルだけを読んでください。repo 全体を走査しないでください。
5. 修正前に「このバッチの実施計画」を 5〜12 行で出してください。
6. 変更はこのバッチの対象に限定してください。対象外の改善、リファクタ、命名変更、整形拡大は禁止です。
7. 実装後は、このバッチで指定された検証を必ず実行してください。
8. 完了時は `Docs/release/codex_batch_state.md` を更新してください。
9. バッチ完了条件を満たせない場合、推測で進めず「未完了」として停止してください。
10. 出力の最後は必ず以下の見出し順にしてください。
   - 実施した変更
   - 実行した検証
   - 完了条件の判定
   - 未解決事項
   - 次バッチが読むべきファイル
```

---

## 3. バッチ 0: 実行基盤の初期化（状態ファイル作成のみ）

### 目的
以後のバッチがコンテキストを失わずに進められるように、**状態ファイルと検証マトリクスだけを作る**。  
このバッチでは product code を変更しない。

### このバッチで読むファイル
- `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- `Docs/vendor_package/release_fact_audit_2026-03-14.md`（存在する場合のみ）
- `scripts/run_etax_unit_lane.sh`
- `ProjectProfitTests/EtaxXtxExporterTests.swift`
- `ProjectProfitTests/TaxYearDefinitionLoaderTests.swift`

### このバッチで変更してよいファイル
- `Docs/release/codex_batch_state.md`（新規作成）
- `Docs/vendor_package/codex_validation_matrix.md`（新規作成）
- `Docs/vendor_package/codex_batch_index.md`（新規作成）

### 実施内容
1. `codex_batch_state.md` を新規作成する。
2. `codex_validation_matrix.md` を新規作成し、各タスクに対する検証方法を表形式で整理する。
3. `codex_batch_index.md` を新規作成し、以後のバッチ順序を固定する。
4. product code は変更しない。

### 必須で書く項目（state）
- current HEAD
- 正本タスク書のパス
- スコープ内 / スコープ外
- P0 / P1 の全タスク ID 一覧
- 各バッチに割り当てるタスク ID
- 未着手 / 進行中 / 完了 の状態欄

### 検証
- 追加した Markdown のみを目視確認する。
- このバッチではビルドやテストは不要。

### 完了条件
- 状態ファイル 3 本ができている。
- 以後のバッチが読むべき対象ファイルが各バッチ単位で整理されている。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ0: 実行基盤の初期化」です。

このバッチの対象ファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/vendor_package/release_fact_audit_2026-03-14.md （存在する場合のみ）
- scripts/run_etax_unit_lane.sh
- ProjectProfitTests/EtaxXtxExporterTests.swift
- ProjectProfitTests/TaxYearDefinitionLoaderTests.swift

このバッチで変更してよいのは次だけです。
- Docs/release/codex_batch_state.md
- Docs/vendor_package/codex_validation_matrix.md
- Docs/vendor_package/codex_batch_index.md

目的:
- 以後のバッチ実行で使う durable project memory を作る。
- product code は一切変更しない。

必須要件:
- codex_batch_state.md に、P0/P1 全タスクの状態表を作ること。
- codex_batch_index.md に、バッチ1〜バッチ8の順序・対象タスク・対象ファイル・完了条件を簡潔に書くこと。
- codex_validation_matrix.md に、各タスクごとの最小検証と最終検証を表で整理すること。

禁止事項:
- source code を変更しない。
- 新しいタスクを勝手に増やさない。
- 次バッチの実装に入らない。

完了したら、変更した Markdown の要約と、次バッチが最初に読むべきファイル一覧を state に書き込んで終了してください。
```

---

## 4. バッチ 1: 期限修正 + filing pack 基本整合（P0-01）

### 対応タスク
- `P0-01`

### このバッチで読むファイル
- `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- `Docs/release/codex_batch_state.md`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json`
- 期限表示に使う UI / loader / model ファイル（state に書かれた最小対象だけ）

### このバッチで変更してよいファイル
- 上記 4 つの 2025 filing JSON
- 期限検証に必要な最小限のテストファイル
- `Docs/release/codex_batch_state.md`

### 実施内容
1. 2025年分 filing pack 4 ファイルの `filingDeadline` を正本タスク書の値に修正する。
2. 既存テストに近い場所へ deadline 検証を追加する。
3. 期限表示が pack 参照で動くなら、その値が変わることを確認する。

### 必須検証
- 変更した JSON の差分確認
- 期限検証テスト
- 既存の pack ロードが壊れていない最小 relevant test

### 完了条件
- 2025 filing pack 4 ファイルの deadline が統一されている。
- CI で将来ずれを検出できるテストがある。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ1: 期限修正 + filing pack 基本整合」です。
対応タスク ID: P0-01

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json
- ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json
- ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json
- ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json

必要に応じて追加で読んでよいのは、state に書かれた「deadline 表示に関係する最小ファイル」のみです。

このバッチで変更してよい範囲:
- 2025 filing pack の4 JSON
- deadline 検証の最小限のテスト
- Docs/release/codex_batch_state.md

目的:
- 2025年分 deadline を修正する。
- deadline ずれが再発しない最小テストを追加する。

禁止事項:
- 2026 pack を触らない。
- 他の P0/P1 を進めない。
- XML 構造の修正に入らない。

必須検証:
- 変更した JSON を確認する。
- 追加した deadline テストを実行する。
- pack ロードの既存最小テストを 1 本以上実行する。

完了条件を満たした場合のみ state を更新して終了してください。
```

---

## 5. バッチ 2A: 現金主義の帳票 ID / metadata / pack 定義を揃える（P0-02, P0-03 の前半）

### 対応タスク
- `P0-02` のうち metadata / pack 側
- `P0-03` のうち pack 側

### このバッチで読むファイル
- `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- `Docs/release/codex_batch_state.md`
- `ProjectProfit/Models/EtaxModels.swift`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_cash_basis.json`
- `ProjectProfit/Services/TaxYearDefinitionLoader.swift`
- `ProjectProfit/Views/Accounting/EtaxExportView.swift`
- `ProjectProfit/Services/FormEngine.swift`
- local bundled official current XSD / workbook のうち現金主義識別に必要なもの

### このバッチで変更してよいファイル
- `ProjectProfit/Models/EtaxModels.swift`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_cash_basis.json`
- `ProjectProfit/Services/TaxYearDefinitionLoader.swift`（必要最小限）
- `Docs/release/codex_batch_state.md`

### 実施内容
1. 現金主義用の official current 帳票 ID / rootTag / version を確認する。
2. `EtaxFormType` と pack の form metadata を同じ 1 系統へ揃える。
3. 主要 3 項目の `xmlTag` を定義する。
4. ここでは exporter 実装まではやらない。

### 必須検証
- pack / model / loader の最小 unit test
- 現金主義 form metadata を確認するテスト

### 完了条件
- `blueCashBasis` の metadata が UI / model / pack で揃う。
- 主要 3 項目に `xmlTag` が付く。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ2A: 現金主義の帳票 ID / metadata / pack 定義を揃える」です。
対応タスク ID: P0-02（metadata部分）, P0-03（pack部分）

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfit/Models/EtaxModels.swift
- ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json
- ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_cash_basis.json
- ProjectProfit/Services/TaxYearDefinitionLoader.swift
- ProjectProfit/Views/Accounting/EtaxExportView.swift
- ProjectProfit/Services/FormEngine.swift

必要に応じて、bundled official current XSD / workbook のうち現金主義帳票 ID の確認に必要な最小ファイルだけ読んでよいです。

このバッチで変更してよい範囲:
- ProjectProfit/Models/EtaxModels.swift
- ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json
- ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_cash_basis.json
- ProjectProfit/Services/TaxYearDefinitionLoader.swift（必要最小限）
- Docs/release/codex_batch_state.md

目的:
- 現金主義の official current 帳票 ID / version / rootTag を model と pack に反映する。
- 主要3項目の xmlTag null を解消する。
- exporter 実装にはまだ入らない。

禁止事項:
- EtaxXtxExporter.swift を変更しない。
- cash_basis_expense_* の exporter 実装まで進めない。
- 青色一般 / 白色の XML 修正に入らない。

必須検証:
- form metadata を確認する最小 unit test
- pack 読み込みテスト
- 主要3項目の xmlTag が null でないことを確認するテストまたは assertion

完了したら state に、残っている cash basis 実装タスク（exporter / dynamic rows / XSD test）を未完として明記してください。
```

---

## 6. バッチ 2B: 現金主義専用 exporter 経路と dynamic row 実装（P0-03 後半, P0-04, P0-12 一部）

### 対応タスク
- `P0-03` の exporter 部分
- `P0-04`
- `P0-12` の現金主義部分

### このバッチで読むファイル
- `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- `Docs/release/codex_batch_state.md`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Services/CashBasisReturnBuilder.swift`
- `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
- `ProjectProfit/Services/FormEngine.swift`
- `ProjectProfitTests/EtaxXtxExporterTests.swift`
- `scripts/run_etax_unit_lane.sh`
- current bundled official 現金主義 XSD

### このバッチで変更してよいファイル
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Services/CashBasisReturnBuilder.swift`
- `ProjectProfit/ViewModels/EtaxExportViewModel.swift`（必要最小限）
- `ProjectProfitTests/EtaxXtxExporterTests.swift`
- `scripts/run_etax_unit_lane.sh`
- `Docs/release/codex_batch_state.md`

### 実施内容
1. 現金主義専用の exporter 経路を追加する。
2. `.blueCashBasis` を青色一般ビルダーから分離する。
3. `cash_basis_expense_*` を official schema に沿って出力する。
4. 現金主義の生成 XML を official XSD に通すテストを追加する。
5. lane に現金主義 XSD 検証を追加する。

### 完了条件
- `.blueCashBasis` が専用経路を通る。
- 現金主義の generated XML が official current XSD に通る。
- lane で現金主義検証が実行される。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ2B: 現金主義専用 exporter 経路と dynamic row 実装」です。
対応タスク ID: P0-03（exporter部分）, P0-04, P0-12（現金主義部分）

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfit/Services/EtaxXtxExporter.swift
- ProjectProfit/Services/CashBasisReturnBuilder.swift
- ProjectProfit/ViewModels/EtaxExportViewModel.swift
- ProjectProfit/Services/FormEngine.swift
- ProjectProfitTests/EtaxXtxExporterTests.swift
- scripts/run_etax_unit_lane.sh

必要に応じて読む追加ファイル:
- 現金主義対象の bundled official current XSD
- バッチ2Aで変更された pack / model ファイル

このバッチで変更してよい範囲:
- ProjectProfit/Services/EtaxXtxExporter.swift
- ProjectProfit/Services/CashBasisReturnBuilder.swift
- ProjectProfit/ViewModels/EtaxExportViewModel.swift（必要最小限）
- ProjectProfitTests/EtaxXtxExporterTests.swift
- scripts/run_etax_unit_lane.sh
- Docs/release/codex_batch_state.md

目的:
- 現金主義を青色一般 exporter から分離する。
- dynamic expense rows を official current schema に沿って出力する。
- generated XML を XSD に通す。

禁止事項:
- 青色一般 / 白色の XML を変更しない。
- common declarant tag 修正に入らない。

必須検証:
- 現金主義の unit test
- generated XML の XSD 検証
- run_etax_unit_lane.sh に現金主義が入ったことの確認

完了条件を満たさない場合、現金主義の残課題を state に明記して停止してください。
```

---

## 7. バッチ 3: 帳票別 declarant / year tag への分離（P0-07）

### 対応タスク
- `P0-07`

### このバッチで読むファイル
- 正本タスク書
- 状態ファイル
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/common.json`
- `ProjectProfit/Services/EtaxFieldPopulator.swift`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Models/EtaxModels.swift`（必要なら）
- official `KOA020 / KOA110 / KOA210 / 現金主義帳票` の declarant / year 部分

### このバッチで変更してよいファイル
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/common.json`
- `ProjectProfit/Services/EtaxFieldPopulator.swift`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- 必要なら最小限のテスト
- `Docs/release/codex_batch_state.md`

### 実施内容
1. `ABA...` 共通流用をやめる。
2. 青色一般 / 白色 / 現金主義ごとの declarant/year mapping を持たせる。
3. exporter から `ABA` ベタ出力ロジックを除去する。
4. white / blue / cash の少なくとも 1 ケースずつで declarant/year が official タグで出ることを確認する。

### 完了条件
- current target forms で `ABA...` 混入が無くなる。
- 年分 field を帳票別 official tag で出せる。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ3: 帳票別 declarant / year tag への分離」です。
対応タスク ID: P0-07

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json
- ProjectProfit/Resources/TaxYearPacks/2026/filing/common.json
- ProjectProfit/Services/EtaxFieldPopulator.swift
- ProjectProfit/Services/EtaxXtxExporter.swift

必要に応じて読む追加ファイル:
- official KOA020 / KOA110 / KOA210 / 現金主義帳票の declarant / year セクション

このバッチで変更してよい範囲:
- common.json（2025/2026）
- EtaxFieldPopulator.swift
- EtaxXtxExporter.swift
- declarant/year を確認する最小テスト
- Docs/release/codex_batch_state.md

目的:
- `ABA...` の共通流用をやめ、帳票別 official declarant/year tags に分離する。

禁止事項:
- 青色一般 / 白色の page 構造変更には入らない。
- mapping 全面修正には入らない。

必須検証:
- 青色一般 / 白色 / 現金主義の declarant/year 出力確認
- representative XML の declarant block が official tag 体系になっていること

完了後、次バッチで blue/white の page 構造を触る前提で、変更済み declarant/year tags を state に明記してください。
```

---

## 8. バッチ 4A: 青色一般の page 構造を official に合わせる（P0-05 前半）

### 対応タスク
- `P0-05` の page 分割部分

### このバッチで読むファイル
- 正本タスク書
- 状態ファイル
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json`
- official `KOA210-011.xsd` の page 構造部分
- 必要なら青色関連 tests

### このバッチで変更してよいファイル
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfitTests/EtaxXtxExporterTests.swift`（青色関連のみ）
- `Docs/release/codex_batch_state.md`

### 実施内容
1. `KOA210-1..4` の page 分割を実装する。
2. `AMG00000` を `KOA210-4` 側へ移す。
3. ただし、このバッチでは **個別 field mapping 修正** までは行わない。
4. page skeleton と大枠の parent path までで止める。

### 完了条件
- 青色一般の generated XML に `KOA210-4` が出る。
- `AMG00000` が page 4 側に移る。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ4A: 青色一般の page 構造を official に合わせる」です。
対応タスク ID: P0-05（page分割部分）

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfit/Services/EtaxXtxExporter.swift
- ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json
- ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json
- official KOA210-011.xsd の page 構造部分

このバッチで変更してよい範囲:
- ProjectProfit/Services/EtaxXtxExporter.swift
- 青色関連の最小テスト
- Docs/release/codex_batch_state.md

目的:
- 青色一般を KOA210-1..4 の page-aware 構造へ分割する。
- AMG00000 を page 4 に移す。
- このバッチでは mapping 個別修正まではやらない。

禁止事項:
- blue_general.json の field マッピング変更に入らない。
- white / cash basis を触らない。

必須検証:
- 青色 generated XML に KOA210-4 が出ること
- AMG00000 が KOA210-4 側にあることを確認するテスト

完了したら、次のバッチで修正すべき blue の具体的誤マッピング候補を state に箇条書きで残してください。
```

---

## 9. バッチ 4B: 青色一般の誤マッピング・container/leaf・貸借対照表詳細を修正する（P0-08, P0-09, P0-11）

### 対応タスク
- `P0-08`
- `P0-09` の blue 部分
- `P0-11`

### このバッチで読むファイル
- 正本タスク書
- 状態ファイル
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json`
- `ProjectProfit/Services/EtaxFieldPopulator.swift`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- official blue workbook/XSD の該当タグ部分

### このバッチで変更してよいファイル
- `blue_general.json`（2025/2026）
- `EtaxFieldPopulator.swift`
- `EtaxXtxExporter.swift`
- 青色関連の最小テスト
- `Docs/release/codex_batch_state.md`

### 実施内容
1. 誤マッピング 4 件を修正する。
2. `income_total_revenue -> AMF00970`、`inventory_cogs -> AMF00110` を解消する。
3. `bs_asset_* / bs_liability_* / bs_equity_*` の受け皿を与える。
4. official `KOA210-4` へ detail keys を出力できるようにする。

### 完了条件
- blue の known bad mappings が解消される。
- blue detail keys が export payload に残る。
- blue representative XML が XSD に通る。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ4B: 青色一般の誤マッピング・container/leaf・貸借対照表詳細を修正する」です。
対応タスク ID: P0-08, P0-09（blue部分）, P0-11

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json
- ProjectProfit/Resources/TaxYearPacks/2026/filing/blue_general.json
- ProjectProfit/Services/EtaxFieldPopulator.swift
- ProjectProfit/Services/EtaxXtxExporter.swift

必要に応じて読む追加ファイル:
- official blue workbook / XSD の該当タグ部分

このバッチで変更してよい範囲:
- blue_general.json（2025/2026）
- EtaxFieldPopulator.swift
- EtaxXtxExporter.swift
- 青色関連の最小テスト
- Docs/release/codex_batch_state.md

目的:
- known bad mappings を直す。
- container tag への direct value を解消する。
- balance sheet detail keys を export へ残す。

禁止事項:
- white / cash basis を触らない。
- release docs を触らない。

必須検証:
- blue mappings 修正テスト
- balance sheet detail keys が残ることの確認
- blue generated XML の XSD 検証

完了後、state に blue でまだ未対応の field coverage が残る場合のみ列挙してください。
```

---

## 10. バッチ 5A: 白色の page 構造を official に合わせる（P0-06 前半）

### 対応タスク
- `P0-06` の page 分割部分

### このバッチで読むファイル
- 正本タスク書
- 状態ファイル
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/white_shushi.json`
- `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
- official `KOA110-012.xsd` の page 構造部分

### このバッチで変更してよいファイル
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfitTests/EtaxXtxExporterTests.swift`（white関連のみ）
- `Docs/release/codex_batch_state.md`

### 実施内容
1. white exporter を `KOA110-1` / `KOA110-2` に分割する。
2. `AIN` は page 2 側へ移す。
3. このバッチではまだ `AIK / AIL / AIM / AIN` の field coverage を埋めきらなくてよい。
4. page skeleton と parent path の枠組みまでで止める。

### 完了条件
- white generated XML に `KOA110-2` が出る。
- `AIN00000` が page 2 側の構造へ移る。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ5A: 白色の page 構造を official に合わせる」です。
対応タスク ID: P0-06（page分割部分）

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfit/Services/EtaxXtxExporter.swift
- ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json
- ProjectProfit/Resources/TaxYearPacks/2026/filing/white_shushi.json
- ProjectProfit/Services/ShushiNaiyakushoBuilder.swift
- official KOA110-012.xsd の page 構造部分

このバッチで変更してよい範囲:
- EtaxXtxExporter.swift
- white 関連の最小テスト
- Docs/release/codex_batch_state.md

目的:
- 白色を KOA110-1 / KOA110-2 の page-aware 構造へ分割する。
- AIN を page 2 側へ移す。
- このバッチでは field coverage 拡張まではやらない。

禁止事項:
- white_shushi.json に大量 field 追加をしない。
- blue / cash basis を触らない。

必須検証:
- white generated XML に KOA110-2 が出ること
- AIN00000 が page 2 側に配置されることの確認

完了後、白色で page 2 に未追加の block（AIK/AIL/AIM/AIN child）を state に列挙してください。
```

---

## 11. バッチ 5B: 白色の field coverage / requiredRule / page 2 明細を追加する（P0-10, P0-09 white 部分）

### 対応タスク
- `P0-10`
- `P0-09` の white 部分

### このバッチで読むファイル
- 正本タスク書
- 状態ファイル
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json`
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/white_shushi.json`
- `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`
- `ProjectProfit/Services/EtaxXtxExporter.swift`
- `ProjectProfit/Services/EtaxCharacterValidator.swift`
- official `KOA110-012.xsd` と該当 workbook / 手引きの white 部分

### このバッチで変更してよいファイル
- `white_shushi.json`（2025/2026）
- `ShushiNaiyakushoBuilder.swift`
- `EtaxXtxExporter.swift`
- `EtaxCharacterValidator.swift`（必要最小限）
- white 関連の最小テスト
- `Docs/release/codex_batch_state.md`

### 実施内容
1. `AIG00020` direct value を廃止し、収入 child を作る。
2. 経費 block の parent path を official に合わせる。
3. 欠落経費項目を追加する。
4. `AIN` 内訳行を total ではなく detail row として実装する。
5. `AIK / AIL / AIM` を追加する。
6. `requiredRule` を入れる。
7. `shushi_depreciation_*` を `AIM` と接続する。

### 完了条件
- white pack が `KOA110-2` の主要 block を持つ。
- `AIG00020` / `AIN00090` の誤用が消える。
- white generated XML が XSD に通る。
- white required fields を validator が検出できる。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ5B: 白色の field coverage / requiredRule / page 2 明細を追加する」です。
対応タスク ID: P0-10, P0-09（white部分）

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json
- ProjectProfit/Resources/TaxYearPacks/2026/filing/white_shushi.json
- ProjectProfit/Services/ShushiNaiyakushoBuilder.swift
- ProjectProfit/Services/EtaxXtxExporter.swift
- ProjectProfit/Services/EtaxCharacterValidator.swift

必要に応じて読む追加ファイル:
- official KOA110-012.xsd
- bundled white workbook / 手引きの必要部分

このバッチで変更してよい範囲:
- white_shushi.json（2025/2026）
- ShushiNaiyakushoBuilder.swift
- EtaxXtxExporter.swift
- EtaxCharacterValidator.swift（必要最小限）
- white 関連の最小テスト
- Docs/release/codex_batch_state.md

目的:
- 白色の簡易実装をやめ、必要書類として不足している page 2 明細を追加する。
- `AIG00020` / `AIN00090` の誤用を解消する。
- requiredRule を設定する。

禁止事項:
- blue / cash basis を触らない。
- release docs を触らない。

必須検証:
- white pack の新規 field coverage 確認
- white validator の requiredRule テスト
- white generated XML の XSD 検証

このバッチは白色の中心タスクです。完了条件を満たせない場合、どの block（AIK/AIL/AIM/AIN/AIG child）が未完かを state に明示して停止してください。
```

---

## 12. バッチ 6: cross-form lint / loader coverage / generated XML XSD CI 固定（P0-12, P1-03, P1-04）

### 対応タスク
- `P0-12`
- `P1-03`
- `P1-04`

### このバッチで読むファイル
- 正本タスク書
- 状態ファイル
- `ProjectProfitTests/EtaxXtxExporterTests.swift`
- `ProjectProfitTests/TaxYearDefinitionLoaderTests.swift`
- `ProjectProfit/Services/TaxYearDefinitionLoader.swift`
- `scripts/run_etax_unit_lane.sh`
- 必要なら `tools/etax/fixtures/*.xml`

### このバッチで変更してよいファイル
- 上記テスト / script / loader
- 必要なら最小 lint utility
- `Docs/release/codex_batch_state.md`

### 実施内容
1. 3 フォーム全部に generated XML ベースの XSD テストを追加する。
2. `blue_cash_basis` を loader / existence / CI の必須対象に入れる。
3. builder dynamic key / pack coverage / leaf-only mapping を検出する lint を追加する。
4. white の fixture fallback 依存を無くす、または CI で禁止する。

### 完了条件
- 3 フォーム全部で generated XML XSD 検証がある。
- loader tests が `blue_cash_basis` を含む。
- pack coverage / dynamic key / leaf-only lint が CI で走る。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ6: cross-form lint / loader coverage / generated XML XSD CI 固定」です。
対応タスク ID: P0-12, P1-03, P1-04

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfitTests/EtaxXtxExporterTests.swift
- ProjectProfitTests/TaxYearDefinitionLoaderTests.swift
- ProjectProfit/Services/TaxYearDefinitionLoader.swift
- scripts/run_etax_unit_lane.sh

必要に応じて読む追加ファイル:
- tools/etax/fixtures/*.xml
- 各 builder / pack の最小必要ファイル

このバッチで変更してよい範囲:
- 上記テストファイル
- loader
- lane script
- 必要なら最小 lint utility
- Docs/release/codex_batch_state.md

目的:
- generated XML ベースの XSD 検証を 3 フォーム全部へ広げる。
- `blue_cash_basis` を loader / CI 対象に入れる。
- pack coverage lint を追加する。

禁止事項:
- product XML 構造そのものを大きく触らない（必要最小限の補助を除く）。
- release docs を触らない。

必須検証:
- 3 フォーム XSD テスト
- loader tests
- lane script dry-run または relevant check

完了後、state に「CI で必須になった検証一覧」を明記してください。
```

---

## 13. バッチ 7: preview / export 整合と stale 防止（P1-02）

### 対応タスク
- `P1-02`
- 必要なら `P1-01` の preview/export 同期部分

### このバッチで読むファイル
- 正本タスク書
- 状態ファイル
- `ProjectProfit/Views/Accounting/EtaxExportView.swift`
- `ProjectProfit/ViewModels/EtaxExportViewModel.swift`
- `ProjectProfit/Services/ExportCoordinator.swift`
- 関連 preflight / form build file

### このバッチで変更してよいファイル
- 上記 UI / VM / coordinator
- 最小の integration test
- `Docs/release/codex_batch_state.md`

### 実施内容
1. export 時に stale preview が使われないようにする。
2. data revision ベースで rebuild / preflight 再実行する。
3. preview と export の field セットが一致するようにする。

### 完了条件
- preview 後に元データが変わった場合、export 前に再 build される。
- preview で見えた field と export 対象 field が一致する。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ7: preview / export 整合と stale 防止」です。
対応タスク ID: P1-02（および必要なら P1-01 の preview/export 同期部分）

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfit/Views/Accounting/EtaxExportView.swift
- ProjectProfit/ViewModels/EtaxExportViewModel.swift
- ProjectProfit/Services/ExportCoordinator.swift

必要に応じて読む追加ファイル:
- form build / preflight の最小必要ファイル

このバッチで変更してよい範囲:
- 上記 UI / VM / coordinator
- 最小の integration test
- Docs/release/codex_batch_state.md

目的:
- stale preview を使った export を防ぐ。
- preview と export の field セットを一致させる。

禁止事項:
- pack / XSD / mapping 修正を再度触らない。
- release docs を触らない。

必須検証:
- preview→元データ変更→export の再 build 確認
- preview/export parity の integration test

完了後、state に preview/export 再計算トリガの仕様を 5 行以内で要約してください。
```

---

## 14. バッチ 8: 2026 pack 照合・release docs 同期・最終 review（P1-01, P1-05, P1-06）

### 対応タスク
- `P1-01`
- `P1-05`
- `P1-06`
- 最終横断 review

### このバッチで読むファイル
- 正本タスク書
- 状態ファイル
- `ProjectProfit/Resources/TaxYearPacks/2026/filing/*.json`
- `Docs/release/quality/latest.md`
- `Docs/release/checklist.md`
- `Docs/release/quality/*.md`
- 必要なら `README.md`

### このバッチで変更してよいファイル
- 2026 pack の差分是正に必要な最小ファイル
- `Docs/release/...`
- `README.md`（必要なら）
- `Docs/release/codex_batch_state.md`
- `Docs/vendor_package/codex_final_report.md`（新規作成）

### 実施内容
1. 2026 pack が 2025 の単純コピーのまま残っていないか確認し、必要な差分のみ反映する。
2. release quality docs の SHA / 状態を current HEAD と同期する。
3. scope を「必要書類の作成まで」と明文化する。
4. 最終横断 review を実施し、`codex_final_report.md` を作成する。

### 必須検証
- 3 フォーム generated XML XSD 検証
- 追加した unit / integration / lint / lane checks
- release docs の整合確認
- 必要なら `/review` 相当のセルフレビュー

### 完了条件
- 2026 pack に未整理の複製状態が残らない。
- release docs が current HEAD と一致する。
- final report に「完了 / 未完 / 残リスク」が整理される。

### Codex に渡す prompt
```text
[共通 prompt を先頭に貼る]

今回のバッチは「バッチ8: 2026 pack 照合・release docs 同期・最終 review」です。
対応タスク ID: P1-01, P1-05, P1-06

最初に読むファイル:
- Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md
- Docs/release/codex_batch_state.md
- ProjectProfit/Resources/TaxYearPacks/2026/filing/*.json
- Docs/release/quality/latest.md
- Docs/release/checklist.md
- Docs/release/quality/*.md

必要に応じて読む追加ファイル:
- README.md
- 2025 pack 対応ファイル

このバッチで変更してよい範囲:
- 2026 pack の必要最小差分
- Docs/release/... 
- README.md（必要なら）
- Docs/release/codex_batch_state.md
- Docs/vendor_package/codex_final_report.md

目的:
- 2026 pack の複製状態を確認して必要な差分だけ整理する。
- release docs を current HEAD に同期する。
- 最終 report を作成する。

禁止事項:
- 新しい product 機能を追加しない。
- 既に完了した P0 を勝手に再設計しない。

必須検証:
- 3 フォーム generated XML XSD 検証
- unit / integration / lint / lane checks の relevant セット
- final report の作成

最終出力では必ず以下を含めてください。
- 完了したタスク ID 一覧
- 未完のタスク ID 一覧（あれば）
- 残リスク
- リリース前に人が確認すべき事項
```

---

## 15. バッチごとの commit / handoff ルール

各バッチが終わったら、Codex の報告とは別に人間側で次を徹底する。

1. 差分をレビューする。  
2. そのバッチだけで commit する。  
3. 次バッチは **新しい Codex スレッド**で始める。  
4. 次バッチの最初に読むファイルは、常に以下から始める。  
   - `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
   - `Docs/release/codex_batch_state.md`
5. 前スレッドの会話は引き継がない。**引き継ぐのは状態ファイルだけ**にする。

推奨 commit メッセージ例:
- `batch1: fix 2025 filing deadlines and add guard tests`
- `batch2a: align cash-basis metadata and pack tags`
- `batch2b: add dedicated cash-basis exporter and xsd tests`
- `batch5b: expand white return page2 coverage and required rules`

---

## 16. 最終的に人が見るべき完了条件

全バッチ完了後、人間レビューで最低限確認するもの:

- 3 フォーム（青色一般 / 白色 / 現金主義）の representative XML が bundled official XSD に通っているか
- 2025 filing deadline が全 pack で統一されているか
- white が `KOA110-1` / `KOA110-2` 構造で出ているか
- blue が `KOA210-1..4` 構造で出ているか
- `ABA...` が current target forms に混入していないか
- generated XML tests が fixture fallback に依存していないか
- release docs が current HEAD と一致しているか

---

## 17. この prompt 集の使い方（短縮版）

- **最初にバッチ0**を実行する。  
- 以後は **1 バッチ 1 スレッド**。  
- 各バッチで必ず `codex_batch_state.md` を更新させる。  
- 次バッチは前バッチの state だけを引き継ぐ。  
- 途中で広がったら **そのスレッドは止める**。  
- 予定外の変更が出たら、そのバッチは未完として終わらせ、次バッチへ持ち込まない。

