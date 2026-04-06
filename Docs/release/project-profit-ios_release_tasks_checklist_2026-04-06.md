# project-profit-ios リリース完了チェックリスト（進捗可視化版 / 2026-04-06）

対象リポジトリ: `samurai2891/project-profit-ios`  
レビュー対象 HEAD: `f6e4130`（`feat: add xlsx template assets and golden verification (#7)`）

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
- [ ] `SPEC.md` と official export matrix の `xlsx` 範囲は未収束
- [ ] legacy `xlsx` export の partial support は未収束
- [ ] xlsx verify script の portable 化と CI gate 組み込みは未収束
- [ ] xlsx parity 検証の粒度は release claim に対してまだ不足
- [ ] stale な監査文書は current main に追随していない
- [ ] repo root README は未追加

---

## 進捗サマリー

- 完了済み前提: **3件**
- 一部完了で要収束: **4件**
- 未完了: **3件**

| ID | 項目 | 優先度 | 現在状態 |
|---|---|---|---|
| BASE-01 | source-of-truth Excel template 同梱 | 基盤 | 完了 |
| BASE-02 | xlsx exporter 基盤追加 | 基盤 | 完了 |
| BASE-03 | xlsx golden verification 基盤追加 | 基盤 | 完了 |
| P0-01 | current HEAD 向け release quality 証跡更新 | P0 | 未完了 |
| P0-02 | `SPEC.md` と official export matrix の `xlsx` 範囲収束 | P0 | 一部完了 |
| P0-03 | legacy `xlsx` partial support 解消 | P0 | 一部完了 |
| P0-04 | xlsx verify script の portable 化 + CI gate 組み込み | P0 | 一部完了 |
| P0-05 | xlsx parity 検証の粒度引き上げ | P0 | 一部完了 |
| P1-01 | stale 監査文書の current main 追随 | P1 | 未完了 |
| P1-02 | repo root README 追加 | P1 | 未完了 |

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

### [ ] P0-01 current HEAD (`f6e4130`) 向けの release quality 証跡を更新する

- 優先度: **P0**
- 現在状態: **未完了**
- repo 上で確認できた事実:
  - main HEAD は `f6e4130`
  - `Docs/release/quality/latest.md` の `head_sha` は `a2d059d...`
  - `release-build.md` / `books.md` / `forms.md` / `golden-baseline.md` / `canonical-e2e.md` / `migration-rehearsal.md` / `performance-gate.md` も `a2d059d...` のまま
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

### [ ] P0-02 `SPEC.md` と official export matrix の `xlsx` 範囲を収束させる

- 優先度: **P0**
- 現在状態: **一部完了**
- repo 上で確認できた事実:
  - `Docs/specs/SPEC.md` は、11 帳簿について template 準拠の `.xlsx` 出力対応を説明している
  - `ExportCoordinator.ExportTarget.supportedFormats` は current UI flow の正本として、`xlsx` を一部 target にしか公開していない
  - `ProjectProfitTests/ExportCoordinatorTests.swift` の `testSupportedFormatMatrixMatchesCurrentUIFlow()` がその matrix を固定している
- 実装チェックリスト:
  - [ ] `xlsx` 公開範囲の正本を 1 つに決める
    - [ ] A. current UI / supportedFormats を `SPEC.md` に合わせる
    - [ ] B. `SPEC.md` を current UI / supportedFormats に合わせる
  - [ ] `ProjectProfit/Services/ExportCoordinator.swift` の matrix を更新する
  - [ ] `ProjectProfitTests/ExportCoordinatorTests.swift` の matrix テストを更新する
  - [ ] ユーザー向け export UI 表示をコードと同じ matrix に揃える
  - [ ] 文書・実装・UI の三者不一致をなくす
- 完了条件:
  - [ ] `SPEC.md` / `ExportCoordinator.swift` / `ExportCoordinatorTests.swift` / UI が同じ export matrix になる
  - [ ] 選べるのに unsupported、または仕様に書いてあるのに UI で出せない、という導線が残らない
- 根拠ファイル:
  - `Docs/specs/SPEC.md`
  - `ProjectProfit/Services/ExportCoordinator.swift`
  - `ProjectProfitTests/ExportCoordinatorTests.swift`

### [ ] P0-03 legacy `xlsx` export の partial support を解消するか、到達不能にする

- 優先度: **P0**
- 現在状態: **一部完了**
- repo 上で確認できた事実:
  - `legacyLedgerBook.supportedFormats` は `.csv / .pdf / .xlsx` を返す
  - ただし legacy adapter 側では `expenseBook / fixedAssetDepreciation / fixedAssetRegister / transportationExpense / whiteTaxBookkeeping` で `unsupportedFormat(.legacyLedgerBook, .xlsx)` を throw している
  - `testLegacyLedgerRejectsUnsupportedXlsxForExpenseBook()` がその未対応動作を固定している
- 実装チェックリスト:
  - [ ] legacy `xlsx` を残すか、縮退するかを決める
    - [ ] 残す場合: 未対応 target の legacy `xlsx` を実装する
    - [ ] 縮退する場合: `legacyLedgerBook` の `.xlsx` 公開をやめる、または compat 導線から到達不能にする
  - [ ] 到達可能経路に `unsupportedFormat(.legacyLedgerBook, .xlsx)` を残さない
  - [ ] 実装方針に合わせて関連テストを更新する
- 完了条件:
  - [ ] reachable path に「選べるのに `.xlsx` で落ちる」導線がない
  - [ ] `supportedFormats` と実装実態が一致する
  - [ ] テストが現実の仕様を固定している
- 根拠ファイル:
  - `ProjectProfit/Services/ExportCoordinator.swift`
  - `ProjectProfitTests/ExportCoordinatorTests.swift`

### [ ] P0-04 xlsx verify script を portable 化し、release gate に組み込む

- 優先度: **P0**
- 現在状態: **一部完了**
- repo 上で確認できた事実:
  - `verify_ledger_xlsx_golden.py`
  - `verify_report_xlsx_golden.py`
  - `verify_generated_ledger_xlsx_golden.py`
  - `verify_generated_report_xlsx_golden.py`
    は存在する
  - ただし 4 本とも `ROOT = Path("/Users/yutaro/project-profit-ios")` をハードコードしている
  - `.github/workflows/release-quality.yml` 内には、`xlsx` verify script 実行を示す step 名や script 呼び出しが見当たらない
- 実装チェックリスト:
  - [ ] 4 本すべて repo 相対パスで動くように直す
  - [ ] ローカル絶対パス依存をなくす
  - [ ] `git clone` 直後の別端末で追加設定なしに実行できるようにする
  - [ ] `release-quality.yml` または同等の必須 gate に xlsx verification を追加する
  - [ ] verification failure で gate が落ちる運用にする
  - [ ] current HEAD の release 証跡に xlsx verification 成功を残す
- 完了条件:
  - [ ] 作者ローカル以外でも verify script が動く
  - [ ] CI で xlsx verification が自動実行される
  - [ ] release gate から xlsx 検証が漏れない
- 根拠ファイル:
  - `scripts/verify_ledger_xlsx_golden.py`
  - `scripts/verify_report_xlsx_golden.py`
  - `scripts/verify_generated_ledger_xlsx_golden.py`
  - `scripts/verify_generated_report_xlsx_golden.py`
  - `.github/workflows/release-quality.yml`

### [ ] P0-05 xlsx parity 検証を release claim に耐える粒度へ引き上げる

- 優先度: **P0**
- 現在状態: **一部完了**
- repo 上で確認できた事実:
  - `excel_templates/README.md` では、現在の golden verification を `sheet names / key header rows / column widths` 比較と説明している
  - `inspect_xlsx_layout.py` は `先頭 worksheet / 最大 20 行 / A〜Z 列幅 / print_area` を JSON 化している
- 実装チェックリスト:
  - [ ] 全 worksheet を比較対象に広げる
  - [ ] `20 行まで` の制限をやめる、または帳票ごとに必要な全使用範囲へ広げる
  - [ ] merged cells を比較する
  - [ ] 数式を比較する
  - [ ] number format を比較する
  - [ ] 主要セル書式（font / border / fill / alignment の必要範囲）を比較する
  - [ ] page setup / print titles / print area / 改ページを比較する
  - [ ] freeze panes / named ranges（使っている場合）を比較する
  - [ ] 「何を比較していて、何を比較していないか」を README に明記する
- 完了条件:
  - [ ] `Excel原本と同一書式` という release claim に見合う検証粒度になる
  - [ ] 比較範囲が README / script から明確に追える
  - [ ] fixed asset 系を含む対象 workbook で current HEAD の parity green を残せる
- 根拠ファイル:
  - `ProjectProfit/Ledger/Resources/excel_templates/README.md`
  - `scripts/inspect_xlsx_layout.py`
  - `scripts/verify_ledger_xlsx_golden.py`
  - `scripts/verify_report_xlsx_golden.py`
  - `scripts/verify_generated_ledger_xlsx_golden.py`
  - `scripts/verify_generated_report_xlsx_golden.py`

---

## P1: リリース前に終わらせたい収束タスク

### [ ] P1-01 `release_review_implementation_status.md` を current main に追随させる

- 優先度: **P1**
- 現在状態: **未完了**
- repo 上で確認できた事実:
  - この文書は current working tree / `155724...` を対象にしている
  - `Docs/release/quality/latest.md` の `a2d059d...` を別物として扱う前提が残っている
  - `原本 Excel が repo 外` という旧前提も残っている
  - 現在の main HEAD `f6e4130` と前提が一致していない
- 実装チェックリスト:
  - [ ] 監査対象 SHA を current main に更新する
  - [ ] `working tree に未コミット変更がある` 前提を除去する
  - [ ] `原本 Excel が repo 外` の前提を除去する
  - [ ] xlsx 追加後の事実に合わせて各項目ステータスを再判定する
  - [ ] 総合結論を current repo と矛盾しない内容へ更新する
- 完了条件:
  - [ ] この監査文書を current main の監査レポートとしてそのまま読める
  - [ ] stale な SHA / stale な前提が残らない
- 根拠ファイル:
  - `release_review_implementation_status.md`

### [ ] P1-02 repo root に README を追加する

- 優先度: **P1**
- 現在状態: **未完了**
- repo 上で確認できた事実:
  - repo root の file list に `README.md` が見当たらない
  - current public repo の全体像は `SPEC.md`、release docs、template README に分散している
- 実装チェックリスト:
  - [ ] アプリ概要を書く
  - [ ] 対応帳簿 / 対応帳票を書く
  - [ ] current official export matrix を書く
  - [ ] source-of-truth doc / template の場所を書く
  - [ ] release gate の見方を書く
  - [ ] repo 外で管理している項目を書く
- 完了条件:
  - [ ] 新規参画者が repo root だけでプロジェクト全体像を把握できる
  - [ ] README と `SPEC.md` / `Docs/release/checklist.md` / template README が矛盾しない
- 根拠ファイル:
  - repo root file list
  - `Docs/specs/SPEC.md`
  - `Docs/release/checklist.md`
  - `ProjectProfit/Ledger/Resources/excel_templates/README.md`

---

## この順番で実装すると戻りが少ない

1. **P0-02** で `xlsx` の official support matrix を決める
2. **P0-03** で legacy `xlsx` を残すか縮退するか決める
3. **P0-04** で verify script を portable 化し CI gate に組み込む
4. **P0-05** で parity 検証の粒度を引き上げる
5. **P0-01** で current HEAD の release quality 証跡を再採取する
6. **P1-01** で stale 監査文書を更新する
7. **P1-02** で root README を追加して導線を一本化する

---

## リリース判定ライン

以下がすべてチェック済みになれば、public repo ベースではかなり強く release-ready と言いやすくなります。

- [ ] current HEAD の release quality 証跡が current HEAD に揃っている
- [ ] `SPEC.md` と official export matrix の `xlsx` 範囲が一致している
- [ ] legacy `xlsx` partial support が解消、または到達不能化されている
- [ ] xlsx verify script が portable で CI gate に入っている
- [ ] xlsx parity 検証の粒度が release claim に見合っている
- [ ] stale 監査文書が current main に追随している
- [ ] root README から全体導線を追える
