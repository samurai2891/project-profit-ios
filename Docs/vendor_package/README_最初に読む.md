# README_最初に読む

## このフォルダの目的

このフォルダは、**ProjectProfit の全面リファクタリングを外注先へ依頼するための発注パッケージ**です。  
この案件は単なる画面改修ではなく、**個人事業主向け・プロジェクト別管理を維持したまま、会計・税務・帳簿・申告を一体化する再設計案件**です。

外注先は、必ずこの README を最初に読み、その後に指定順で資料を確認してください。  
既存コードだけを読んで実装を始めることは禁止です。

> 現況注記（2026-03-07）
> このフォルダ内の設計書・計画書は原本として維持しているため、現行 repo ではすでに進捗した項目も含まれる。
> 現在の実装棚卸しと優先順位の確認は `release_ticket_list.md` を優先する。
> release 修正の実行順・確認論点は [../release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md](../release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md) を参照する。
> Codex で段階実行する場合は [../release/Codex_バッチ実行プロンプト集_必要書類作成まで.md](../release/Codex_バッチ実行プロンプト集_必要書類作成まで.md) を参照する。

---

## まず最初に理解してほしいこと

この案件で **絶対に変えてはいけないもの** は次の 4 点です。

1. **個人事業主向け**であること  
2. **プロジェクトごとに管理できる**こと  
3. **会計と税務をノーストレスにする**こと  
4. **AI はオンデバイス限定**であること  

また、この案件は「とりあえず既存コードに足す」方式ではなく、**正本設計・証憑設計・帳簿設計・税務状態設計を組み直す**前提です。

---

## このフォルダで外注先が受け取るもの

### 必須資料
- `ProjectProfit_Complete_Refactor_Spec.md`
- `ProjectProfit_Implementation_Task_List.md`
- `ProjectProfit_Outsource_Architecture_Detail_Spec.md`

### 参考帳票
- `収支内訳書.pdf`
- `青色申告決算書.pdf`
- `消費税集計表.png`

### 現行コード
- `project-profit-ios-clean.zip`

### あると望ましい補足資料
- `画面一覧.md`
- `主要画面キャプチャ/`
- `sample-evidence/`
- `sample-transactions/`
- `expected-books/`
- `expected-filing/`
- `既知課題一覧.md`
- `ビルド手順.md`
- `受け入れ条件チェックリスト.md`
- `../release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- `../release/Codex_バッチ実行プロンプト集_必要書類作成まで.md`

---

## 読む順番

外注先は必ず次の順番で資料を読んでください。

### 1. この README
この案件の全体像、優先順位、成果物、禁止事項を理解するため。

### 2. `ProjectProfit_Complete_Refactor_Spec.md`
何を作るべきか、どの機能を完成形にするべきかを理解するため。

### 3. `ProjectProfit_Implementation_Task_List.md`
どの順番で、どこまで分解して実装するかを理解するため。

### 4. `ProjectProfit_Outsource_Architecture_Detail_Spec.md`
どのディレクトリ構成・命名規則・責務分離で実装するかを理解するため。

### 5. `収支内訳書.pdf` / `青色申告決算書.pdf` / `消費税集計表.png`
帳票粒度、列構成、明細構成、必要な会計情報の粒度を理解するため。

### 6. `project-profit-ios-clean.zip`
最後に現行コードを確認し、**何を流用し、何を廃止し、何を移行するか** を判断するため。

---

## 仕様の優先順位

資料や実装の解釈が衝突した場合、優先順位は次のとおりです。

1. **法令・国税庁・e-Tax の公式仕様**
2. **クライアントが渡した公式帳票サンプル**
3. `ProjectProfit_Complete_Refactor_Spec.md`
4. `ProjectProfit_Implementation_Task_List.md`
5. `ProjectProfit_Outsource_Architecture_Detail_Spec.md`
6. 既存コード
7. 外注先独自判断

つまり、**既存コードは正解ではありません**。  
既存コードはあくまで現状資産であり、設計上の問題を含んでいます。

---

## この案件の成功条件

以下を満たした場合に「完成へ向かっている」と判断します。

- 証憑 → 取引候補 → 仕訳候補 → 確定仕訳 → 帳簿 → 帳票 の正本系列ができている
- プロジェクト別管理が維持されている
- 帳簿が二重正本ではなく 1 系統から派生生成される
- 青色 / 白色 / 消費税 / インボイス / e-Tax を扱える
- 定期取引の該当月自動分配ができる
- 単月の全プロジェクト一括配賦ができる
- ユーザーが勘定科目やジャンルを追加できる
- UI が多少変わっても、入力負担は軽くなっている
- AI はオンデバイスだけで使われる

---

## この案件の最重要方針

### 1. 正本は 1 つだけ
会計の正本は、最終的に **Evidence / Candidate / Journal** の系列に統一してください。  
帳簿や PDF を正本にしてはいけません。

### 2. 帳簿は派生物
総勘定元帳、現金出納帳、経費帳、固定資産台帳、棚卸台帳、消費税集計表などは、**確定仕訳から再生成可能** にしてください。

### 3. プロジェクトは管理会計軸
税務申告は「事業者 × 年分」で行いますが、プロジェクト別収益管理は維持してください。  
この軸を削ってはいけません。

### 4. AI は提案だけ
OCR・候補提案・分類補助に AI を使ってよいですが、**税務上の最終決定を AI に任せてはいけません**。

### 5. 年度差分は pack 化
税制や e-Tax 仕様は年次更新されるため、年度ごとの違いは `TaxYearPack` / `FormPack` / `BookSpec` に切り出してください。

---

## 外注先が最初にやるべきこと

実装開始前に、まず以下を行ってください。

### Step 1. 現行資産監査
- 現行モデル一覧
- 現行サービス一覧
- 現行画面一覧
- 現行帳簿/帳票出力一覧
- 既存の永続化方式
- 既存の OCR / Ledger / Export 実装
- 既存の recurring / allocation / tax 実装

### Step 2. 差し替え対象の明確化
- 完全廃止するもの
- 互換維持しつつ移行するもの
- そのまま活かせるもの
- migration が必要なもの

### Step 3. 新アーキテクチャ skeleton の作成
- 新 directory structure
- Domain / Application / Infrastructure / UI の雛形
- repository protocol
- tax packs / book specs / form packs の loader 雛形
- build が通る最小構成

### Step 4. Vertical Slice の実装
最初に 1 本、次の流れが通る最小実装を出してください。

**証憑 1 件取り込み → 候補生成 → 承認 → 仕訳確定 → 帳簿 1 種出力**

これを通さずに大量実装へ進まないでください。

---

## 外注先が勝手に変えてはいけないもの

以下は、外注先が独自判断で変更してはいけません。

- プロジェクト別管理の存在
- オンデバイス AI 限定方針
- custom account / genre の必要性
- recurring + 自動配賦の必要性
- 単月全プロジェクト配賦の必要性
- 帳簿の完全生成方針
- 帳票の年次 pack 方針
- legal view と management view の分離方針
- year lock / audit log / 証憑履歴の必要性

---

## 外注先がやってはいけない実装

次の実装は禁止です。

### 構造面
- `Services` に何でも追加する
- 新しい巨大 `DataStore` を作る
- 新しい巨大 `Models.swift` を作る
- `Utilities` に会計ロジックを置く
- `LedgerDataStore` を新正本として延命する

### 会計面
- OCR 結果をそのまま確定仕訳にする
- 1 証憑 = 1 仕訳で固定する
- 配賦を 1 project 固定にする
- custom account を帳票に落ちないまま許可する
- 消費税集計を仮払/仮受の単純差額だけで済ませる

### 技術面
- `Double` で金額計算する
- `String` ベタ書きで tax code を回す
- 年度差を if 文の連鎖で処理する
- UI から persistence を直接叩く
- foundation model 非対応端末で動かない前提にする

### セキュリティ面
- 証憑本文を外部 AI へ送る
- 原本ファイルを気軽に削除できる
- year lock 後でも自由に更新できる
- audit log を残さない

---

## 外注先への納品依頼の単位

この案件は一括納品ではなく、最低でも次の単位でレビューを挟んでください。

### 第1納品: 構造設計
- ディレクトリ構成
- dependency ルール
- legacy → target のマッピング
- migration 方針
- build 可能な雛形

### 第2納品: 正本中核の縦切り
- Business / TaxYear / Project / Evidence / Journal の core
- 1 本の証憑処理 vertical slice
- 監査ログの最小実装

### 第3納品: 配賦と recurring
- DistributionRule
- MonthWideDistribution
- recurring generation
- preview / approval

### 第4納品: 帳簿エンジン
- 仕訳帳
- 総勘定元帳
- 現金出納帳
- 経費帳
- プロジェクト元帳
- 消費税集計表

### 第5納品: 帳票 / e-Tax
- 青色申告決算書
- 収支内訳書
- preflight
- XML export
- PDF preview

### 第6納品: migration / QA / docs
- migration
- golden tests
- performance test
- handover docs

---

## 外注先が提出すべき成果物

コードだけでは納品完了になりません。  
次も合わせて提出してください。

### 必須
- 実装コード
- migration 実装
- test suite
- golden fixtures
- build 手順
- migration 実行手順
- 既知制約一覧
- 最新 architecture 図
- current → target mapping 表
- pack schema 説明書

### 強く推奨
- 各 feature の簡易 README
- screen inventory
- review で使う sample data
- audit / lock / export の検証結果

---

## 質問・確認の出し方

疑義がある場合は、次の形式で確認してください。

```text
[Issue Title]
背景:
現状理解:
衝突している資料:
選択肢 A:
選択肢 B:
推奨案:
影響範囲:
着手期限:
```

「実装都合でこうしました」は不可です。  
着手前に確認してください。

---

## このフォルダの推奨構成

```text
ProjectProfit_ExternalVendor_Package/
  README_最初に読む.md
  ProjectProfit_Complete_Refactor_Spec.md
  ProjectProfit_Implementation_Task_List.md
  ProjectProfit_Outsource_Architecture_Detail_Spec.md
  project-profit-ios-clean.zip
  収支内訳書.pdf
  青色申告決算書.pdf
  消費税集計表.png
  画面一覧.md
  主要画面キャプチャ/
  sample-evidence/
  sample-transactions/
  expected-books/
  expected-filing/
  既知課題一覧.md
  ビルド手順.md
  受け入れ条件チェックリスト.md
```

---

## 最後に

この案件は、**既存コードを延命する案件ではありません**。  
また、**UI を少し整える案件でもありません**。  
本質は、**プロジェクト別管理を維持したまま、証憑・帳簿・税務・申告を一貫した設計へ組み直すこと** にあります。

外注先は、まず構造を正しく理解し、その後に実装してください。  
最初に大量実装へ入ると必ず手戻りが発生します。

最優先は **構造の正しさ** です。  
速度より、責務分離と将来保守性を重視してください。
