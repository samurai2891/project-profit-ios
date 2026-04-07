# project-profit-ios リリース完了チェックリスト（進捗可視化版 / 2026-04-06）

対象リポジトリ: `samurai2891/project-profit-ios`  
レビュー対象 HEAD: `cad9516`（`feat: release export matrixとxlsx verifyを整備`）

## この文書の見方

- `[x]` = public repo 上で完了を確認できた項目
- `[ ]` = 未完了、または current HEAD に対する完了証跡を public repo 上で確認できない項目
- 状態欄の意味
  - `完了` = 実装前提として閉じてよい
  - `一部完了` = 基盤はあるが release-ready の完了条件を満たしていない
  - `未完了` = 実装または証跡更新が必要

この文書は、**実装担当がそのままチェックを進められる形**に寄せています。  
「完了済み前提」と「release までに閉じるべき残タスク」を分けています。

---

## 一目で分かる全体チェック

- [x] xlsx の source-of-truth template 群は repo に入っている
- [x] xlsx exporter の基盤（`libxlsxwriter` / resource bundling / exporter 実装）は入っている
- [x] xlsx golden fixture / verify script の基盤は入っている
- [ ] current HEAD 向けの release quality 証跡は更新されていない
- [x] `SPEC.md` と official export matrix の `xlsx` 範囲は一致している
- [x] legacy 互換導線の visible export format は実装と一致している
- [x] xlsx verify script の portable 化と CI gate 組み込みは完了
- [x] xlsx parity 検証の粒度は release claim に見合う水準まで引き上げた
- [x] stale な監査文書は current repo state に追随している
- [x] repo root README は追加済み

---

## 進捗サマリー

- 完了: **9件**
- 一部完了で要収束: **0件**
- 未完了: **1件**

| ID | 項目 | 優先度 | 現在状態 |
|---|---|---|---|
| BASE-01 | source-of-truth Excel template 同梱 | 基盤 | 完了 |
| BASE-02 | xlsx exporter 基盤追加 | 基盤 | 完了 |
| BASE-03 | xlsx golden verification 基盤追加 | 基盤 | 完了 |
| P0-01 | current HEAD 向け release quality 証跡更新 | P0 | 未完了 |
| P0-02 | `SPEC.md` と official export matrix の `xlsx` 範囲収束 | P0 | 完了 |
| P0-03 | legacy export の visible format 実装収束 | P0 | 完了 |
| P0-04 | xlsx verify script の portable 化 + CI gate 組み込み | P0 | 完了 |
| P0-05 | xlsx parity 検証の粒度引き上げ | P0 | 完了 |
| P1-01 | stale 監査文書の current main 追随 | P1 | 完了 |
| P1-02 | repo root README 追加 | P1 | 完了 |

---

## 完了済み前提（ここは閉じてよい）

### [x] BASE-01 source-of-truth Excel template 群を repo に同梱済み

- 現在状態: **完了**
- repo 上で確認できた事実:
  - `f6e4130` で `xlsx template assets and golden verification` が追加されている
  - `ProjectProfit/Ledger/Resources/excel_templates/README.md` が、このディレクトリを `source-of-truth Excel originals` と明記している
  - standalone workbook 群の置き場所として `ledgers/*.xlsx` と `reports/*.xlsx` を説明している
- 実装担当メモ:
  - この項目は追加実装タスクではなく、以後の parity / export / release 判定の前提として扱う
- 根拠ファイル:
  - `ProjectProfit/Ledger/Resources/excel_templates/README.md`
  - main commit `f6e4130`

### [x] BASE-02 xlsx exporter 基盤を追加済み

- 現在状態: **完了**
- repo 上で確認できた事実:
  - `project.yml` に `libxlsxwriter` package 依存がある
  - `ProjectProfit/Ledger/Resources` が bundle resource に入っている
  - `ProjectProfit/Ledger/Services/LedgerExcelExportService.swift` が存在する
- 実装担当メモ:
  - ここで言う完了は「基盤が repo に入っている」という意味であり、公開範囲や parity の完了とは別
- 根拠ファイル:
  - `project.yml`
  - `ProjectProfit/Ledger/Services/LedgerExcelExportService.swift`

### [x] BASE-03 xlsx golden verification 基盤を追加済み

- 現在状態: **完了**
- repo 上で確認できた事実:
  - `.golden-generated-ledger-xlsx/` と `.golden-generated-xlsx/` が repo root に存在する
  - `verify_ledger_xlsx_golden.py`
  - `verify_report_xlsx_golden.py`
  - `verify_generated_ledger_xlsx_golden.py`
  - `verify_generated_report_xlsx_golden.py`
    が存在する
- 実装担当メモ:
  - ここで言う完了は「検証資産がある」という意味であり、portable 実行や CI gate 組み込みまで済んでいる意味ではない
- 根拠ファイル:
  - repo root file list
  - `scripts/verify_ledger_xlsx_golden.py`
  - `scripts/verify_report_xlsx_golden.py`
  - `scripts/verify_generated_ledger_xlsx_golden.py`
  - `scripts/verify_generated_report_xlsx_golden.py`

---

## P0: リリース前に必ず閉じるタスク

### [ ] P0-01 current HEAD (`cad9516`) 向けの release quality 証跡を更新する

- 優先度: **P0**
- 現在状態: **未完了**
- repo 上で確認できた事実:
  - main HEAD は `cad9516`
  - `Docs/release/quality/latest.md` の `head_sha` は `a2d059d...`
  - `release-build.md` と `xlsx-verify.md` は current repo state の `cad9516...` へ更新済み
  - `books.md` / `forms.md` / `golden-baseline.md` / `canonical-e2e.md` / `migration-rehearsal.md` / `performance-gate.md` は `a2d059d...` のまま
  - `Docs/release/checklist.md` では、`latest.md` が current HEAD と不一致なら lane 個票を current HEAD の正本として扱うと明記している
- 実装チェックリスト:
  - [ ] `xcodegen-sync` を current HEAD で再実行して green を残す
  - [ ] `simulator-health` を current HEAD で再実行して結果を残す
  - [ ] `release-build` を current HEAD で再採取する
  - [ ] `golden-baseline` を current HEAD で再採取する
  - [ ] `canonical-e2e` を current HEAD で再採取する
  - [ ] `migration-rehearsal` を current HEAD で再採取する
  - [ ] `performance-gate` を current HEAD で再採取する
  - [ ] `books` を current HEAD で再採取する
  - [ ] `forms` を current HEAD で再採取する
  - [ ] `Docs/release/quality/*.md` の `head_sha` を current HEAD に揃える
  - [ ] `artifacts/release-quality/**` を current HEAD 証跡へ揃える
- 完了条件:
  - [ ] public repo だけで current HEAD の release 可否を判定できる
  - [ ] 必要 lane の `status` が current HEAD に対して `ok`
  - [ ] `summary_path / log_path / xcresult_path / metrics_path` が current HEAD 証跡を指している
- 根拠ファイル:
  - `Docs/release/quality/latest.md`
  - `Docs/release/quality/release-build.md`
  - `Docs/release/quality/books.md`
  - `Docs/release/quality/forms.md`
  - `Docs/release/quality/golden-baseline.md`
  - `Docs/release/quality/canonical-e2e.md`
  - `Docs/release/quality/migration-rehearsal.md`
  - `Docs/release/quality/performance-gate.md`
  - `Docs/release/checklist.md`

### [x] P0-02 `SPEC.md` と official export matrix の `xlsx` 範囲を収束させる

- 優先度: **P0**
- 現在状態: **完了**
- repo 上で確認できた事実:
  - `Docs/specs/SPEC.md` は official export matrix として、11 帳簿ワークスペース target と 7 帳票 target の `.xlsx` 正式対応を明記している
  - `ExportCoordinator.ExportTarget.supportedFormats` は `cashBook` から `whiteTaxBookkeeping` まで official 帳簿 target の `.xlsx` を公開している
  - `WhiteTaxBookkeepingView` は hand-written menu ではなく official export menu を使い、UI 表示が matrix と一致している
  - `ProjectProfitTests/ExportCoordinatorTests.swift` は `testSupportedFormatMatrixMatchesCurrentUIFlow()` と帳簿系 `.xlsx` 成功テストで matrix を固定している
- 実装チェックリスト:
  - [x] `xlsx` 公開範囲の正本を 1 つに決める
    - [x] A. current UI / supportedFormats を `SPEC.md` に合わせる
    - [x] B. `SPEC.md` を current UI / supportedFormats に合わせる
  - [x] `ProjectProfit/Services/ExportCoordinator.swift` の matrix を更新する
  - [x] `ProjectProfitTests/ExportCoordinatorTests.swift` の matrix テストを更新する
  - [x] ユーザー向け export UI 表示をコードと同じ matrix に揃える
  - [x] 文書・実装・UI の三者不一致をなくす
- 完了条件:
  - [x] `SPEC.md` / `ExportCoordinator.swift` / `ExportCoordinatorTests.swift` / UI が同じ export matrix になる
  - [x] 選べるのに unsupported、または仕様に書いてあるのに UI で出せない、という導線が残らない
- 根拠ファイル:
  - `Docs/specs/SPEC.md`
  - `ProjectProfit/Services/ExportCoordinator.swift`
  - `ProjectProfitTests/ExportCoordinatorTests.swift`
  - `ProjectProfit/Views/Accounting/WhiteTaxBookkeepingView.swift`

### [x] P0-03 legacy export の visible format を全件実装し、UI と一致させる

- 優先度: **P0**
- 現在状態: **完了**
- repo 上で確認できた事実:
  - `ExportCoordinator.supportedFormats(for legacyLedgerOptions:)` が legacy format matrix の公開正本になっている
  - legacy adapter 側で `expenseBook / whiteTaxBookkeeping / fixedAssetDepreciation / fixedAssetRegister / transportationExpense` の `csv / xlsx` 未実装が解消されている
  - `LedgerBookDetailView` は legacy capability を参照して `CSV / Excel / PDF` メニューを出し分ける
  - `ExportCoordinatorTests` が legacy matrix と追加 format の成功を固定している
- 実装チェックリスト:
  - [x] legacy visible format の matrix を実装ベースで一本化する
  - [x] 到達可能経路に `unsupportedFormat(.legacyLedgerBook, .csv/.xlsx)` を残さない
  - [x] UI 表示を capability 参照に切り替える
  - [x] 関連テストを成功ケース基準へ更新する
- 完了条件:
  - [x] reachable path に「選べるのに落ちる」導線がない
  - [x] `supportedFormats` と実装実態が一致する
  - [x] テストが現実の仕様を固定している
- 根拠ファイル:
  - `ProjectProfit/Services/ExportCoordinator.swift`
  - `ProjectProfitTests/ExportCoordinatorTests.swift`

### [x] P0-04 xlsx verify script を portable 化し、release gate に組み込む

- 優先度: **P0**
- 現在状態: **完了**
- repo 上で確認できた事実:
  - `verify_ledger_xlsx_golden.py`
  - `verify_report_xlsx_golden.py`
  - `verify_generated_ledger_xlsx_golden.py`
  - `verify_generated_report_xlsx_golden.py`
    は `__file__` 基準で repo root を解決する
  - generated verify 2 本も committed fixture 基準の expectation に同期されている
  - `.github/workflows/release-quality.yml` に blocking job `xlsx-verify` が追加されている
  - `Docs/release/quality/xlsx-verify.md` が current HEAD の証跡として追加されている
- 実装チェックリスト:
  - [x] 4 本すべて repo 相対パスで動くように直す
  - [x] ローカル絶対パス依存をなくす
  - [x] `git clone` 直後の別端末で追加設定なしに実行できるようにする
  - [x] `release-quality.yml` または同等の必須 gate に xlsx verification を追加する
  - [x] verification failure で gate が落ちる運用にする
  - [x] current HEAD の release 証跡に xlsx verification 成功を残す
- 完了条件:
  - [x] 作者ローカル以外でも verify script が動く
  - [x] CI で xlsx verification が自動実行される
  - [x] release gate から xlsx 検証が漏れない
- 根拠ファイル:
  - `scripts/verify_ledger_xlsx_golden.py`
  - `scripts/verify_report_xlsx_golden.py`
  - `scripts/verify_generated_ledger_xlsx_golden.py`
  - `scripts/verify_generated_report_xlsx_golden.py`
  - `.github/workflows/release-quality.yml`

### [x] P0-05 xlsx parity 検証を release claim に耐える粒度へ引き上げる

- 優先度: **P0**
- 現在状態: **完了**
- repo 上で確認できた事実:
  - `excel_templates/README.md` では、workbook parity で比較する項目と比較しない項目を明記している
  - `inspect_xlsx_layout.py` は workbook 全体の snapshot を JSON 化する
  - `scripts/golden_xlsx/templates/*.json` と `scripts/golden_xlsx/generated/*.json` に committed expected snapshot が追加されている
  - 4 本の verify script は workbook snapshot 同士を比較する
- 実装チェックリスト:
  - [x] 全 worksheet を比較対象に広げる
  - [x] `20 行まで` の制限をやめ、各 worksheet の全使用範囲を snapshot 化する
  - [x] merged cells を比較する
  - [x] 数式を比較する
  - [x] number format を比較する
  - [x] 主要セル書式（font / border / fill / alignment の必要範囲）を比較する
  - [x] page setup / print titles / print area / 改ページを比較する
  - [x] freeze panes / named ranges（使っている場合）を比較する
  - [x] 「何を比較していて、何を比較していないか」を README に明記する
- 完了条件:
  - [x] `Excel原本と同一書式` という release claim に見合う検証粒度になる
  - [x] 比較範囲が README / script から明確に追える
  - [x] fixed asset 系を含む対象 workbook で current HEAD の parity green を残せる
- 根拠ファイル:
  - `ProjectProfit/Ledger/Resources/excel_templates/README.md`
  - `scripts/inspect_xlsx_layout.py`
  - `scripts/golden_xlsx/templates/`
  - `scripts/golden_xlsx/generated/`
  - `scripts/verify_ledger_xlsx_golden.py`
  - `scripts/verify_report_xlsx_golden.py`
  - `scripts/verify_generated_ledger_xlsx_golden.py`
  - `scripts/verify_generated_report_xlsx_golden.py`

---

## P1: リリース前に終わらせたい収束タスク

### [x] P1-01 `release_review_implementation_status.md` を current main に追随させる

- 優先度: **P1**
- 現在状態: **完了**
- repo 上で確認できた事実:
  - 文書ヘッダと前提を current repo state / current main `cad9516` 基準へ更新した
  - `working tree に未コミット変更がある` 前提を除去した
  - source-of-truth Excel template が repo 内にある現在の事実へ合わせた
  - official/legacy export matrix と `xlsx-verify` gate の追加後状態に合わせて export 周辺の記述を更新した
- 実装チェックリスト:
  - [x] 監査対象 SHA を current main に更新する
  - [x] `working tree に未コミット変更がある` 前提を除去する
  - [x] `原本 Excel が repo 外` の前提を除去する
  - [x] xlsx 追加後の事実に合わせて各項目ステータスを再判定する
  - [x] 総合結論を current repo と矛盾しない内容へ更新する
- 完了条件:
  - [x] この監査文書を current main の監査レポートとしてそのまま読める
  - [x] stale な SHA / stale な前提が残らない
- 根拠ファイル:
  - `release_review_implementation_status.md`

### [x] P1-02 repo root に README を追加する

- 優先度: **P1**
- 現在状態: **完了**
- repo 上で確認できた事実:
  - repo root に `README.md` を追加した
  - アプリ概要、official export matrix、source-of-truth docs、release gate の見方、repo 外管理項目をまとめた
  - `SPEC.md` / `Docs/release/checklist.md` / `ProjectProfit/Ledger/Resources/excel_templates/README.md` への導線を root から辿れる
- 実装チェックリスト:
  - [x] アプリ概要を書く
  - [x] 対応帳簿 / 対応帳票を書く
  - [x] current official export matrix を書く
  - [x] source-of-truth doc / template の場所を書く
  - [x] release gate の見方を書く
  - [x] repo 外で管理している項目を書く
- 完了条件:
  - [x] 新規参画者が repo root だけでプロジェクト全体像を把握できる
  - [x] README と `SPEC.md` / `Docs/release/checklist.md` / template README が矛盾しない
- 根拠ファイル:
  - `README.md`
  - `Docs/specs/SPEC.md`
  - `Docs/release/checklist.md`
  - `ProjectProfit/Ledger/Resources/excel_templates/README.md`

---

## この順番で実装すると戻りが少ない

1. **P0-05** で parity 検証の粒度を引き上げる
2. **P0-01** で current HEAD の release quality 証跡を再採取する

---

## リリース判定ライン

以下がすべてチェック済みになれば、public repo ベースではかなり強く release-ready と言いやすくなります。

- [ ] current HEAD の release quality 証跡が current HEAD に揃っている
- [x] `SPEC.md` と official export matrix の `xlsx` 範囲が一致している
- [x] legacy visible export format が UI / 実装 / テストで一致している
- [x] xlsx verify script が portable で CI gate に入っている
- [x] xlsx parity 検証の粒度が release claim に見合っている
- [x] stale 監査文書が current main に追随している
- [x] root README から全体導線を追える
