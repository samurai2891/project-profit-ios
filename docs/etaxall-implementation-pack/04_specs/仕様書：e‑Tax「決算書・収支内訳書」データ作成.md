# 仕様書：e‑Tax「決算書・収支内訳書」データ作成（Phase A）

- 対象：Project Profit iOS（SwiftData / PPTransaction中心）＋複式簿記コア導入後
- 目的：**青色申告決算書（一般）**・**収支内訳書（白色）**の「作成支援〜e‑Tax提出データ（XML等）生成」まで
- 送信：**ユーザーが公式導線（e‑Tax）で実施**（アプリは送信しない）

> **重要**：国税庁（e‑Tax）の帳票フィールド仕様は CAB 配布（Excel等）です。  
> 本仕様は **「タグ（XMLフィールド）を仕様書から機械抽出して埋める」運用を必須要件化**しています。  
> これにより、年分更新（TaxYear）にも差分追従が可能になります。  
> 参照：e‑Tax仕様書一覧（CAB配布、解凍して使用）  
> - https://www.e-tax.nta.go.jp/shiyo/shiyo3.htm


---

## 1. 目的と範囲

### 1.1 目的
本アプリ内で、プロジェクト別管理会計・複式簿記データを元に、以下を提供する：

- 青色申告決算書（一般）
- 収支内訳書（白色）

の **e‑Tax添付用電子データ（XML）**作成に必要な以下の機能：

- 集計
- 分類（TaxLine/科目の割当）
- チェック（整合性・不足・禁止文字等）
- 帳票プレビュー
- エクスポート（XML / CSV）

送信（提出操作）はユーザー責任で公式導線に委譲する。

> 収支内訳書・青色申告決算書等は電子データ（XML）で提出可能な添付書類として案内され、イメージ提出できない旨の注意がある（年分ページ）。  
> - https://www.e-tax.nta.go.jp/tetsuzuki/shinkoku/shotoku04.htm

### 1.2 Phase Aのアウトプット（実装成果物）
- (A) 帳票作成データモデル（青色一般／白色）
- (B) 年分別（TaxYear）マッピング定義  
  - 内部キー ⇄ e‑Tax XMLタグ（仕様書準拠）
- (C) 集計エンジン（複式簿記→帳票値）
- (D) 帳票プレビュー（フォーム同等レイアウト or 公式様式に準じた表示）
- (E) エクスポート I/F
  - XML（e‑Tax添付想定）
  - CSV（RPA/検証用、項目＝内部キー）
- (F) 自動分類（オンデバイス）＋ルール＋学習反映
- (G) 監査・整合チェック（エラー/警告）

---

## 2. 参照仕様（国税庁・e‑Tax）

### 2.1 参照元（必須）
- e‑Tax仕様書一覧（CAB配布、解凍して使用）  
  - https://www.e-tax.nta.go.jp/shiyo/shiyo3.htm
- ソフトウェア開発業者の方へ（仕様公開の目的・前提）  
  - https://www.e-tax.nta.go.jp/shiyo/index.htm
- 仕様書更新履歴（年分・版差分追従運用に使用）  
  - https://www.e-tax.nta.go.jp/shiyo/shiyo2.htm
- 作成コーナーFAQ：決算書・収支内訳書の作成導線（ユーザーガイド案内）  
  - https://www.e-tax.nta.go.jp/toiawase/faq/gaiyo/07.htm

### 2.2 抽出対象となる仕様（CAB内）
外注/実装者は、仕様書一覧から **所得税関係** のCABを取得し、解凍して以下を抽出する。  
（ファイル名はCAB内で確認。内容が重要）

- 「XML構造設計書」
- 「帳票フィールド仕様書」

> 注意：仕様は更新され得るため、**年分別（TaxYear別）**にマッピングを持つこと。  
> 更新は更新履歴ページをトリガに追従する。  
> - https://www.e-tax.nta.go.jp/shiyo/shiyo2.htm

---

## 3. 前提データ（アプリ側）

### 3.1 現行（PPTransaction中心）
- `PPTransaction`（SwiftData）  
  - `type(income/expense/transfer)`  
  - `amount(Int)`  
  - `date`  
  - `categoryId`  
  - `memo`  
  - `allocations[]`（プロジェクト配分）  
  - `lineItems[]`（レシート明細、任意）

### 3.2 複式簿記コア導入後（前提）
青色一般のB/S生成に必須：

- `Account`（勘定科目）  
  - `code`, `name`, `type(資産/負債/純資産/収益/費用)`, `taxLineDefault`
- `JournalEntry`（仕訳ヘッダ）  
  - `date`, `memo`, `sourceTransactionId?`, `entryType`
- `JournalLine`（借方/貸方行）  
  - `accountId`, `debit`, `credit`, `counterparty?`, `evidence?`

> 白色（収支内訳書）は単式でも作成可能だが、青色一般を同基盤で最大限便利にするため本仕様は複式を前提とする。

---

## 4. 年分（TaxYear）と“版”の扱い

### 4.1 年分別マッピングの原則
- 年分で変わる主要因：**様式IDのVer** と **タグセット**
- よって、年分ごとに以下を固定する：
  - 対象様式ID＋Ver
  - その様式のタグ辞書（内部キー → XMLタグ + 制約）

### 4.2 成果物：年分別マッピングファイル
- `TaxYearDefinition.json`
  - `taxYear`: 2025 等
  - `forms`:
    - `blue_general`: `{ formId, formVer, mappingFile }`
    - `white_shushi`: `{ formId, formVer, mappingFile }`
- `mapping_blue_general_{taxYear}.csv`
- `mapping_white_shushi_{taxYear}.csv`

#### CSV列（固定）
|列|内容|
|---|---|
|`internalKey`|アプリ内フィールドキー（本仕様で定義）|
|`formName`|青色一般 / 収支内訳書|
|`sectionPath`|論理セクション（例：PL.Expenses.通信費）|
|`fieldLabelJP`|帳票表示名（日本語）|
|`xmlTag`|e‑Tax XMLタグ（CABから抽出して埋める）|
|`idref`|IDREF属性（仕様書にある場合）|
|`dataType`|数値/文字/区分 等|
|`format`|書式（桁、符号、小数、ゼロ可否 等）|
|`requiredRule`|必須条件（条件式）|
|`calcRule`|集計式（仕訳→値）|
|`sourceAccounts`|対象勘定科目コード集合（またはTaxLine）|
|`notes`|備考|

---

## 5. タグ埋め（xmlTag列）自動生成手順（必須要件）

### 5.1 CAB取得と解凍
1) 仕様書一覧から所得税関係CABをダウンロード  
2) CABを解凍（例：OS機能 or `cabextract`）  
3) 対象Excelを抽出

参照：CAB配布・解凍して利用  
- https://www.e-tax.nta.go.jp/shiyo/shiyo3.htm

### 5.2 抽出対象（CAB内）
- 帳票フィールド仕様書（Excel）  
- XML構造設計書（Excel）

### 5.3 自動抽出（実装要件）
外注は **Excel→CSV/JSON変換スクリプト**を実装し、以下を機械生成して納品すること：

- `TagDictionary_{taxYear}.json`
  - key: `internalKey`
  - value: `{ xmlTag, idref, type, format, requiredRule }`

#### 受入条件（タグ埋め）
- 青色一般・収支内訳書の **全 internalKey に対し xmlTag が100%埋まること**
- 仕様書の「入力チェック」「値の範囲」「書式」を `format/requiredRule` に反映
- 更新履歴が出た場合、差分抽出して TagDictionary を更新できること（運用は後述）  
  - https://www.e-tax.nta.go.jp/shiyo/shiyo2.htm

---

## 6. 内部キー定義（共通：納税者・基本情報）

|internalKey|fieldLabelJP|dataType|requiredRule|calcRule|
|---|---|---|---|---|
|`common.taxYear`|年分|数値/区分|必須|設定値|
|`common.name`|氏名|文字|必須|ユーザー入力|
|`common.nameKana`|フリガナ|文字|任意|ユーザー入力|
|`common.address`|住所|文字|必須|ユーザー入力|
|`common.phone`|電話番号|文字|任意|ユーザー入力|
|`common.businessName`|屋号|文字|任意|ユーザー入力|
|`common.myNumberFlag`|マイナンバー記載有無|区分|年分/様式に依存|ユーザー入力|

**セキュリティ要件（必須）**
- マイナンバー等の高機微情報は、端末内暗号化・明示同意・エクスポート除外設定を必須とする。

---

## 7. 青色申告決算書（一般）仕様

### 7.1 帳票構成（論理）
- Header（納税者情報）
- P/L（損益計算書）
- B/S（貸借対照表）
- 付表（減価償却、地代家賃内訳、専従者給与、貸倒、借入金等）

Phase A方針：
- 固定資産・借入・在庫が無い場合は付表の一部省略可（ただし省略時は警告）。

### 7.2 P/L（損益計算書）内部キー一覧

#### 収入
|internalKey|fieldLabelJP|calcRule（仕訳→値）|sourceAccounts（例）|
|---|---|---|---|
|`blue.pl.sales`|売上（収入）金額|収益科目の貸方合計（売上系）|売上高/サービス売上|
|`blue.pl.otherIncome`|雑収入|収益科目の貸方合計（雑収入系）|雑収入|
|`blue.pl.totalIncome`|収入金額計|`sales + otherIncome + …`|自動計算|

#### 売上原価（在庫がある場合）
|internalKey|fieldLabelJP|calcRule|
|---|---|---|
|`blue.pl.beginInventory`|期首棚卸高|前期B/S棚卸資産（期末）|
|`blue.pl.purchases`|仕入金額|仕入/材料費など費用科目合計|
|`blue.pl.endInventory`|期末棚卸高|当期棚卸（ユーザー入力 or 在庫モジュール）|
|`blue.pl.cogs`|売上原価|`begin + purchases - end`|

#### 経費（主要TaxLine）
実装では TaxLine マスタを用意し、各勘定科目に `taxLineDefault` を設定する。

|internalKey|fieldLabelJP|calcRule|既定カテゴリ→TaxLine初期割当例|
|---|---|---|---|
|`blue.pl.exp.outsourcing`|外注工賃|外注費借方合計|請負業者→外注工賃|
|`blue.pl.exp.depreciation`|減価償却費|償却費合計|固定資産台帳|
|`blue.pl.exp.rent`|地代家賃|地代家賃借方合計|—|
|`blue.pl.exp.interest`|利子割引料|支払利息借方合計|—|
|`blue.pl.exp.taxes`|租税公課|租税公課借方合計|—|
|`blue.pl.exp.utilities`|水道光熱費|水道光熱費借方合計|—|
|`blue.pl.exp.travel`|旅費交通費|旅費交通費借方合計|交通費→旅費交通費|
|`blue.pl.exp.communication`|通信費|通信費借方合計|通信/ホスティング→通信費（要確認可）|
|`blue.pl.exp.advertising`|広告宣伝費|広告宣伝費借方合計|広告→広告宣伝費|
|`blue.pl.exp.entertainment`|接待交際費|接待交際費借方合計|接待会議→接待交際費（要確認推奨）|
|`blue.pl.exp.supplies`|消耗品費|消耗品費借方合計|消耗品/ツール→消耗品費（少額）|
|`blue.pl.exp.misc`|雑費|雑費借方合計|その他経費→雑費|
|`blue.pl.exp.total`|経費計|上記経費の合計|自動計算|

#### 利益
|internalKey|fieldLabelJP|calcRule|
|---|---|---|
|`blue.pl.grossProfit`|差引金額（粗利等）|`totalIncome - cogs`（在庫型）/ `totalIncome`（役務型）|
|`blue.pl.netProfit`|所得金額|`totalIncome - cogs - exp.total`|

### 7.3 B/S（貸借対照表）内部キー一覧

#### 資産
|internalKey|fieldLabelJP|calcRule|
|---|---|---|
|`blue.bs.assets.cash`|現金|現金勘定残高|
|`blue.bs.assets.bank`|預金|預金残高合計|
|`blue.bs.assets.ar`|売掛金|売掛金残高|
|`blue.bs.assets.inventory`|棚卸資産|棚卸資産残高|
|`blue.bs.assets.prepaid`|前払金|前払金残高|
|`blue.bs.assets.fixed.total`|固定資産計|簿価合計（取得−累計償却）|
|`blue.bs.assets.other`|その他資産|その他資産残高合計|
|`blue.bs.assets.total`|資産合計|資産合計|

#### 負債
|internalKey|fieldLabelJP|calcRule|
|---|---|---|
|`blue.bs.liabilities.ap`|買掛金|買掛金残高|
|`blue.bs.liabilities.loans`|借入金|借入金残高|
|`blue.bs.liabilities.accrued`|未払金/未払費用|該当科目残高|
|`blue.bs.liabilities.advances`|前受金|前受金残高|
|`blue.bs.liabilities.deposit`|預り金|預り金残高|
|`blue.bs.liabilities.total`|負債合計|負債合計|

#### 純資産
|internalKey|fieldLabelJP|calcRule|
|---|---|---|
|`blue.bs.equity.capital`|元入金|期首元入金＋当期変動|
|`blue.bs.equity.drawings`|事業主貸|事業主貸残高|
|`blue.bs.equity.contributions`|事業主借|事業主借残高|
|`blue.bs.equity.currentProfit`|所得金額|`blue.pl.netProfit` と一致|
|`blue.bs.equity.total`|純資産合計|純資産合計|

### 7.4 青色B/S整合チェック（必須）
- `assets.total == liabilities.total + equity.total` → 不一致は **Error（エクスポート不可）**
- `equity.currentProfit == blue.pl.netProfit` → 不一致は **Error**
- 棚卸・固定資産・借入関連が未設定なのに残高がある → **Warning（入力不足）**

### 7.5 青色一般：年分別タグマッピング（成果物）
外注が納品するもの：
- `mapping_blue_general_2023.csv`
- `mapping_blue_general_2024.csv`
- `mapping_blue_general_2025.csv`
（対象年分は要件により増減可）

各CSVは本仕様の internalKey 全てを含み、`xmlTag` 列が全埋めであること。

---

## 8. 白色：収支内訳書 仕様（帳票生成＋自動分類）

### 8.1 帳票生成（論理構成）
- Header（納税者情報）
- 収入金額（売上等）
- 必要経費（科目別）
- 減価償却（ある場合）
- 専従者・地代家賃等（ある場合）

参照：作成コーナーの導線（決算書・収支内訳書の作成）  
- https://www.e-tax.nta.go.jp/toiawase/faq/gaiyo/07.htm

### 8.2 収支内訳書：内部キー一覧

#### 収入
|internalKey|fieldLabelJP|calcRule|
|---|---|---|
|`white.income.sales`|売上（収入）金額|売上系収益科目の貸方合計|
|`white.income.other`|その他の収入|雑収入等の貸方合計|
|`white.income.total`|収入金額計|合計|

#### 必要経費（科目別）
青色と同じ TaxLine を流用し、白色の表示名・必須条件のみ変える。

|internalKey|fieldLabelJP|calcRule|既定カテゴリ→初期割当|
|---|---|---|---|
|`white.exp.outsourcing`|外注工賃|外注費借方合計|請負業者|
|`white.exp.rent`|地代家賃|地代家賃借方合計|—|
|`white.exp.travel`|旅費交通費|旅費交通費借方合計|交通費|
|`white.exp.communication`|通信費|通信費借方合計|通信/ホスティング|
|`white.exp.advertising`|広告宣伝費|広告宣伝費借方合計|広告|
|`white.exp.supplies`|消耗品費|消耗品費借方合計|消耗品/ツール|
|`white.exp.entertainment`|接待交際費|接待交際費借方合計|接待会議（要確認推奨）|
|`white.exp.taxes`|租税公課|租税公課借方合計|—|
|`white.exp.insurance`|損害保険料|損害保険料借方合計|—|
|`white.exp.depreciation`|減価償却費|償却費合計|固定資産台帳|
|`white.exp.misc`|雑費|雑費借方合計|その他経費|
|`white.exp.total`|必要経費計|合計|—|

### 8.3 白色チェック
- `white.income.total - white.exp.total` を「差引金額」として表示
- 科目未分類（TaxLine未割当）が存在 → **Warning**  
  - “雑費へ自動退避した件数/金額” を明示し、内訳修正導線を提供

---

## 9. 自動分類（白色/青色共通で利用）

### 9.1 目的
取引（PPTransaction/仕訳）を TaxLine へ自動分類し、帳票値を自動集計する。  
青色にも同じTaxLineを流用し、学習コストを最小化する。

### 9.2 分類の優先順位（必須）
1) ユーザー固定ルール（最優先）  
2) 辞書ルール（店舗名/振込先/正規表現）  
3) オンデバイス推論（信頼度付き）  
4) フォールバック（雑費 or 未分類ボックス）

### 9.3 ルール定義（UserRule）仕様
- 形式：`if match(...) then assign(taxLine, account?, project?, split?)`
- match条件（複合可）
  - `counterparty contains`
  - `memo regex`
  - `amount range`
  - `recurringId != nil`
- assign
  - `taxLine`
  - `account`
  - `projectAllocation`（配分比率）

### 9.4 初期同梱の辞書ルール（例）
- AWS / Google / Microsoft / GitHub / Vercel → 通信費 or 支払手数料（SaaS）
- Google Ads / Meta Ads → 広告宣伝費
- JR/メトロ/タクシー → 旅費交通費
- 飲食：状況により会議費/交際費/福利厚生費候補（要確認を推奨）

### 9.5 推論（オンデバイス）閾値運用（必須）
- `confidence >= 0.90`：自動確定（初期推奨）
- `0.60..0.90`：要確認（候補提示）
- `<0.60`：未分類（雑費に自動計上しない）

### 9.6 学習反映（端末内）
- ユーザーが修正した分類を `TrainingExample` として保存
- 次回以降：
  - “ルール化”をワンタップで提案
  - 端末内での改善に利用（外部送信なし）

---

## 10. エクスポート仕様（XML / CSV）

### 10.1 CSV（RPA/検証用）
- `export_{formName}_{taxYear}.csv`
- 行＝internalKey
- 列＝`internalKey, fieldLabelJP, value, note`

値の扱い：
- 数値：未入力は空欄（0とは区別）
- 文字：未入力は空欄

### 10.2 XML（e‑Tax用）
- 生成単位：1帳票（青色一般 or 収支内訳書）
- 値は `TagDictionary_{taxYear}` の `xmlTag` に従い出力
- 型・桁・必須条件は `format/requiredRule` を強制
- 条件不充足の場合：**エクスポート不可（Error）**として一覧表示し、修正導線を提供

---

## 11. 年分更新運用（差分追従）

### 11.1 更新検知
- 仕様の更新は更新履歴をトリガに検知し、差分反映する：  
  - https://www.e-tax.nta.go.jp/shiyo/shiyo2.htm

### 11.2 更新手順（標準）
1) 新TaxYearの所得税関係CAB取得  
2) Excel抽出 → TagDictionary生成  
3) internalKeyと突合  
   - 新規タグ：internalKey追加（UI/集計も更新）  
   - 既存タグ変更：マッピング差替え  
4) 回帰テスト  
   - サンプル仕訳 → 帳票値 → XML生成 →（可能なら）スキーマチェック

---

## 12. 受入条件（検収チェックリスト）

### 12.1 青色一般
- P/LとB/Sが生成できる
- 整合チェック（B/S一致、利益一致、入力不足警告）が動作
- 年分別マッピングCSVが生成され、**xmlTagが全埋め**
- XML出力が仕様書の型/桁/必須条件を満たす（違反時はエクスポート不可）

### 12.2 収支内訳書
- 自動分類（ルール→推論→フォールバック）が動作
- 未分類の可視化・一括修正・学習反映が動作
- 帳票プレビューが出る
- 年分別マッピング（xmlTag埋め）＋XML/CSV出力ができる

---

## 13. 正確性と未確定点（明示）

### 13.1 確実な点（参照元あり）
- e‑Tax仕様書は CAB 形式で配布され、ダウンロード後に解凍して利用する  
  - https://www.e-tax.nta.go.jp/shiyo/shiyo3.htm
- e‑Taxは会計ソフト等からのデータ引継ぎによる利便性向上を意図して仕様を公開  
  - https://www.e-tax.nta.go.jp/shiyo/index.htm
- 収支内訳書・青色申告決算書等は電子データ（XML）で提出可能な添付書類として扱われる  
  - https://www.e-tax.nta.go.jp/tetsuzuki/shinkoku/shotoku04.htm

### 13.2 この文書単体では確定できない点
- 青色申告決算書（一般）／収支内訳書の各 internalKey に対応する **xmlTagの具体値**
  - → 本仕様は “CABから機械抽出して埋める”ことを要件化しており、外注は確実に埋められる。

---

## 付録A：参考リンク一覧
- e‑Tax仕様書一覧（CAB配布）  
  https://www.e-tax.nta.go.jp/shiyo/shiyo3.htm
- 仕様書更新履歴  
  https://www.e-tax.nta.go.jp/shiyo/shiyo2.htm
- 開発者向け仕様案内  
  https://www.e-tax.nta.go.jp/shiyo/index.htm
- 収支内訳書・青色申告決算書（XML提出の注意）  
  https://www.e-tax.nta.go.jp/tetsuzuki/shinkoku/shotoku04.htm
- 決算書・収支内訳書の作成導線FAQ  
  https://www.e-tax.nta.go.jp/toiawase/faq/gaiyo/07.htm
