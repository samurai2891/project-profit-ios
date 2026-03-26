# iOS会計アプリ - 台帳データモデル仕様書

## 概要

Excelテンプレート16ファイルから抽出した、個人事業主向け会計アプリの台帳データモデル定義。
CSVおよびPDFで**Excel原本と完全同一フォーマット**で出力可能。

---

## 台帳一覧（全11種 × インボイス対応 = 16バリエーション）

| # | 台帳名 | ファイルキー | インボイス版 | 元Excelファイル |
|---|--------|-------------|-------------|----------------|
| 1 | 現金出納帳 | `cash_book` | ✅ | cash_book_001_self-employed.xlsx |
| 2 | 預金出納帳 | `bank_account_book` | ✅ | bank_account_book_001_self-employed.xlsx |
| 3 | 売掛帳 | `accounts_receivable_book` | ❌ | accounts_receivable_book_001_self-employed.xlsx |
| 4 | 買掛帳 | `accounts_payable_book` | ❌ | accounts_payable_book_001_self-employed.xlsx |
| 5 | 経費帳 | `expense_book` | ✅ | expense_book_001_self-employed.xlsx |
| 6 | 総勘定元帳 | `general_ledger` | ✅ | general_ledger_001_self-employed.xlsx |
| 7 | 仕訳帳 | `journal` | ❌ | journal_001_self-employed.xlsx |
| 8 | 固定資産台帳 兼 減価償却計算表 | `fixed_asset_depreciation` | ❌ | koteishisandaicho-genkashokyakukeisansho.xlsx |
| 9 | 固定資産台帳 | `fixed_asset_register` | ❌ | koteishisandaicho.xlsx |
| 10 | 交通費精算書 | `transportation_expense` | ❌ | koutsuhiseisansyo.xlsx |
| 11 | 白色申告用 簡易帳簿 | `white_tax_bookkeeping` | ✅ | white-tax-return-bookkeeping.xlsx |

---

## 各台帳の列定義

### 1. 現金出納帳（`cash_book`）

**メタデータ:** 前期より繰越（integer, default: 0）

| 列キー | 日本語名 | 型 | 必須 | 備考 |
|--------|---------|-----|------|------|
| month | 月 | integer | ✅ | 1-12 |
| day | 日 | integer | ✅ | 1-31 |
| description | 摘要 | string | ✅ | |
| account | 勘定科目 | string | ✅ | マスター参照 |
| *reduced_tax* | *軽減税率* | *boolean* | | *インボイス版のみ* |
| *invoice_type* | *インボイス* | *string* | | *インボイス版のみ（〇/8割控除/少額特例）* |
| income | 入金 | integer | | |
| expense | 出金 | integer | | |
| balance | 残高 | integer | 🔄自動計算 | 前行残高 + 入金 - 出金 |

### 2. 預金出納帳（`bank_account_book`）

**メタデータ:** 銀行名, 本支店名, 口座種類, 前期より繰越

| 列キー | 日本語名 | 型 | 必須 | 備考 |
|--------|---------|-----|------|------|
| month | 月 | integer | ✅ | |
| day | 日 | integer | ✅ | |
| description | 摘要 | string | ✅ | |
| account | 勘定科目 | string | ✅ | マスター参照 |
| *reduced_tax* | *軽減税率* | *boolean* | | *インボイス版のみ* |
| *invoice_type* | *インボイス* | *string* | | *インボイス版のみ* |
| deposit | 入金 | integer | | |
| withdrawal | 出金 | integer | | |
| balance | 残高 | integer | 🔄自動計算 | |

### 3. 売掛帳（`accounts_receivable_book`）

**メタデータ:** 得意先名, 前期より繰越

| 列キー | 日本語名 | 型 | 必須 | 備考 |
|--------|---------|-----|------|------|
| month | 月 | integer | ✅ | |
| day | 日 | integer | ✅ | |
| counter_account | 相手科目 | string | ✅ | 売掛帳用マスター |
| description | 摘要 | string | ✅ | |
| quantity | 数量 | integer | | |
| unit_price | 単価 | integer | | |
| sales_amount | 売上金額 | integer | | |
| received_amount | 入金金額 | integer | | |
| ar_balance | 売掛金残高 | integer | 🔄自動計算 | 前行残高 + 売上 - 入金 |

### 4. 買掛帳（`accounts_payable_book`）

**メタデータ:** 仕入先名, 前期より繰越

| 列キー | 日本語名 | 型 | 必須 | 備考 |
|--------|---------|-----|------|------|
| month | 月 | integer | ✅ | |
| day | 日 | integer | ✅ | |
| counter_account | 相手科目 | string | ✅ | 買掛帳用マスター |
| description | 摘要 | string | ✅ | |
| quantity | 数量 | integer | | |
| unit_price | 単価 | integer | | |
| purchase_amount | 仕入金額 | integer | | |
| payment_amount | 支払金額 | integer | | |
| ap_balance | 買掛金残高 | integer | 🔄自動計算 | 前行残高 + 仕入 - 支払 |

### 5. 経費帳（`expense_book`）

**メタデータ:** 勘定科目名（例：消耗品費）

| 列キー | 日本語名 | 型 | 必須 | 備考 |
|--------|---------|-----|------|------|
| month | 月 | integer | ✅ | |
| day | 日 | integer | ✅ | |
| counter_account | 相手科目 | string | ✅ | |
| description | 摘要 | string | ✅ | |
| *reduced_tax* | *軽減税率* | *boolean* | | *インボイス版のみ（摘要の後に挿入）* |
| *invoice_type* | *インボイス* | *string* | | *インボイス版のみ（軽減税率の後に挿入）* |
| amount | 金額 | integer | ✅ | |
| running_total | 金額合計 | integer | 🔄自動計算 | 累積合計 |

### 6. 総勘定元帳（`general_ledger`）

**メタデータ:** 勘定科目名, 科目の属性（資産/負債/資本/売上/売上原価/経費）, 前期より繰越

| 列キー | 日本語名 | 型 | 必須 | 備考 |
|--------|---------|-----|------|------|
| month | 月 | integer | ✅ | |
| day | 日 | integer | ✅ | |
| counter_account | 相手科目 | string | ✅ | |
| description | 摘要 | string | ✅ | |
| *reduced_tax* | *軽減税率* | *boolean* | | *インボイス版のみ（摘要の後に挿入）* |
| *invoice_type* | *インボイス* | *string* | | *インボイス版のみ（軽減税率の後に挿入）* |
| debit | 借方 | integer | | |
| credit | 貸方 | integer | | |
| balance | 差引残高 | integer | 🔄自動計算 | 属性に応じた加減算 |

**残高計算ロジック:**
- 資産・経費・売上原価 → 残高 = 前行残高 + 借方 - 貸方
- 負債・資本・売上 → 残高 = 前行残高 - 借方 + 貸方

### 7. 仕訳帳（`journal`）

| 列キー | 日本語名 | 型 | 必須 | 備考 |
|--------|---------|-----|------|------|
| month | 月 | integer | ✅ | 複合仕訳の続行行は空 |
| day | 日 | integer | ✅ | 複合仕訳の続行行は空 |
| debit_account | 借方科目 | string | | |
| debit_amount | 借方金額 | integer | | |
| credit_account | 貸方科目 | string | | |
| credit_amount | 貸方金額 | integer | | |
| description | 摘要 | string | ✅ | |

**特殊:** 1つの取引で借方・貸方が複数ある場合（複合仕訳）、月・日は最初の行のみ記入。

### 8. 固定資産台帳 兼 減価償却計算表（`fixed_asset_depreciation`）

**メタデータ:** 年分

| 列キー | 日本語名 | 型 | 必須 | 備考 |
|--------|---------|-----|------|------|
| account | 勘定科目 | string | ✅ | |
| asset_code | 資産コード | string | ✅ | |
| asset_name | 資産名 | string | ✅ | |
| asset_type | 資産の種類 | string | ✅ | |
| status | 状態 | string | ✅ | |
| quantity | 数量 | integer | | |
| acquisition_date | 取得日 | string | ✅ | |
| acquisition_cost | 取得価額 | integer | ✅ | |
| depreciation_method | 償却方法 | string | ✅ | 定額法 / 定率法 |
| useful_life | 耐用年数 | integer | ✅ | |
| depreciation_rate | 償却率 | number | ✅ | |
| depreciation_months | 償却月数 | integer | ✅ | |
| opening_book_value | 期首帳簿価額 | integer | | |
| mid_year_change | 期中増減 | integer | | |
| depreciation_expense | 減価償却費 | integer | 🔄自動計算 | |
| special_depreciation | 特別(割増)償却費 | integer | | |
| total_depreciation | 償却費合計 | integer | 🔄自動計算 | |
| business_use_ratio | 事業専用割合 | number | ✅ | 0.0〜1.0 |
| deductible_amount | 必要経費算入額 | integer | 🔄自動計算 | |
| year_end_balance | 本年末残高 | integer | 🔄自動計算 | |
| remarks | 摘要 | string | | |

### 9. 固定資産台帳（`fixed_asset_register`）

**メタデータ:** 名称, 番号, 種類, 取得年月日, 所在, 耐用年数, 償却方法, 償却率

| 列キー | 日本語名 | 型 | 必須 | 備考 |
|--------|---------|-----|------|------|
| date | 年月日 | string | ✅ | |
| description | 摘要 | string | ✅ | |
| acquired_quantity | 取得数量 | integer | | |
| acquired_unit_price | 取得単価 | integer | | |
| acquired_amount | 取得金額 | integer | | |
| depreciation_amount | 償却額 | integer | | |
| disposal_quantity | 異動数量 | integer | | |
| disposal_amount | 異動金額 | integer | | |
| current_quantity | 現在数量 | integer | 🔄自動計算 | |
| current_amount | 現在金額 | integer | 🔄自動計算 | |
| business_use_ratio | 事業専用割合 | number | | |
| deductible_amount | 必要経費算入額 | integer | 🔄自動計算 | |
| remarks | 備考 | string | | |

### 10. 交通費精算書（`transportation_expense`）

**メタデータ:** 年, 月度, 所属, 氏名, 申請日, 精算日

| 列キー | 日本語名 | 型 | 必須 | 備考 |
|--------|---------|-----|------|------|
| date | 日付 | string | ✅ | |
| destination | 行先 | string | ✅ | |
| purpose | 目的（用件） | string | ✅ | |
| transport_method | 交通機関（手段） | string | ✅ | |
| route_from | 区間（起点） | string | ✅ | |
| route_to | 区間（終点） | string | ✅ | |
| trip_type | 片/往 | string | ✅ | 片道 / 往復 |
| amount | 金額 | integer | ✅ | |

### 11. 白色申告用 簡易帳簿（`white_tax_bookkeeping`）

**メタデータ:** 年

| 列キー | 日本語名 | カテゴリ | 型 | 備考 |
|--------|---------|---------|-----|------|
| month | 月 | - | integer | |
| day | 日 | - | integer | |
| description | 摘要 | - | string | |
| *reduced_tax* | *軽減税率* | - | *boolean* | *インボイス版のみ* |
| *invoice_type* | *インボイス* | - | *string* | *インボイス版のみ* |
| sales_amount | 売上金額 | 収入金額 | integer | |
| misc_income | 雑収入等 | 収入金額 | integer | |
| purchases | 仕入 | 売上原価 | integer | |
| salaries | 給料賃金 | 経費 | integer | |
| outsourcing | 外注工賃 | 経費 | integer | |
| depreciation | 減価償却費 | 経費 | integer | |
| bad_debts | 貸倒金 | 経費 | integer | |
| rent | 地代家賃 | 経費 | integer | |
| interest_discount | 利子割引料 | 経費 | integer | |
| taxes_duties | 租税公課 | その他の経費 | integer | |
| packing_shipping | 荷造運賃 | その他の経費 | integer | |
| utilities | 水道光熱費 | その他の経費 | integer | |
| travel_transport | 旅費交通費 | その他の経費 | integer | |
| communication | 通信費 | その他の経費 | integer | |
| advertising | 広告宣伝費 | その他の経費 | integer | |
| entertainment | 接待交際費 | その他の経費 | integer | |
| insurance | 損害保険料 | その他の経費 | integer | |
| repairs | 修繕費 | その他の経費 | integer | |
| supplies | 消耗品費 | その他の経費 | integer | |
| welfare | 福利厚生費 | その他の経費 | integer | |
| miscellaneous | 雑費 | その他の経費 | integer | |

---

## 勘定科目マスター

### 現金出納帳 / 預金出納帳 / 仕訳帳 / 総勘定元帳 / 経費帳 共通

| 区分 | 勘定科目 |
|------|---------|
| 資産 | 現金, 普通預金, 定期預金, 受取手形, 売掛金, 商品, 貯蔵品, 仮払金, 建物, 建物附属設備, 機械装置, 車両運搬具, 工具器具備品, 土地, 電話加入権, 敷金, 差入保証金, 預託金, 開業費, 事業主貸 |
| 負債 | 支払手形, 買掛金, 未払金, 前受金, 預り金, 事業主借 |
| 資本 | 元入金 |
| 売上 | 売上高, 雑収入 |
| 売上原価 | 期首商品棚卸高, 仕入高, 期末商品棚卸高 |
| 経費 | 租税公課, 荷造運賃, 水道光熱費, 旅費交通費, 通信費, 広告宣伝費, 接待交際費, 損害保険料, 修繕費, 消耗品費, 外注工賃, 地代家賃, 減価償却費, 福利厚生費, 手形売却損, 支払手数料, 車両費, 雑費, 専従者給与 |

### インボイス区分

| 値 | 説明 |
|----|------|
| 〇 | 適格請求書（インボイス）あり |
| 8割控除 | 経過措置（8割控除対象） |
| 少額特例 | 少額特例（1万円未満） |

---

## ファイル構成

```
output/
├── LedgerModels.swift              # Swiftデータモデル定義
├── LedgerExportService.swift       # CSV/PDFエクスポートサービス
├── LedgerExcelExportService.swift  # Excel(.xlsx)エクスポートサービス ← NEW
├── SPEC.md                         # この仕様書
├── json_schemas/
│   └── master_schema.json          # 全台帳の完全JSON定義
└── csv_templates/
    ├── account_categories.csv      # 勘定科目マスター
    ├── cash_book.csv               # 現金出納帳
    ...（17ファイル）
```

---

## iOSアプリでの使い方

### Excel(.xlsx)出力 ← NEW
- `LedgerExcelExportService` で **Excel原本と同一書式** の .xlsx を生成
- 依存: `libxlsxwriter`（SwiftPM対応、軽量C言語ライブラリ）
- セル結合・罫線・数式・印刷設定・勘定科目シート全対応
- 残高は **Excel数式** で記入（`=+E6+G5-F6` 等）→ Excel上で再計算可能
- `UIActivityViewController` でシェア

```swift
// Package.swift
.package(url: "https://github.com/jmcnamara/libxlsxwriter", from: "1.1.5")
```

### CSV出力
- `CSVExportService` の各 `export*` メソッドを呼び出し
- UTF-8 BOM付きで出力（Excel互換）
- `UIActivityViewController` でシェア

### CSV読み込み
- `CSVImportService.parseCSV()` でパース
- ヘッダー行（英語キー or 日本語名）を自動判別
- 各台帳の Entry モデルにマッピング

### PDF出力
- `PDFLedgerConfig` でA4サイズ・列幅を定義
- `UIGraphicsPDFRenderer` で描画
- Excel原本と同一のヘッダー・フッター構造を再現

### 出力形式比較

| 形式 | 数式 | 書式 | 印刷設定 | ファイルサイズ | 用途 |
|------|------|------|---------|-------------|------|
| Excel(.xlsx) | ✅ 残高自動計算 | ✅ 罫線・フォント完全 | ✅ A4横 | 中 | 編集・会計ソフト連携 |
| CSV | ❌ 値のみ | ❌ なし | ❌ なし | 小 | データ連携・インポート |
| PDF | ❌ 値のみ | ✅ 原本再現 | ✅ A4横 | 大 | 印刷・提出用 |
