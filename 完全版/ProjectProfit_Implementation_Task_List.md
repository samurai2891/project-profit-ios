# ProjectProfit 実装タスク一覧
## 完全リファクタリング実行版

作成日: 2026-03-01  
対象: `project-profit-ios` 既存コードベース  
目的: 既存コンセプトを維持したまま、個人事業主向け・プロジェクト別管理対応・オンデバイスAI限定の完全会計システムへ到達するための、実装可能な分解済みタスク一覧を定義する。

---

# 0. この文書の使い方

この文書は、前回の「完全リファクタリング指示書」を、実装に落とせる単位まで分解したものです。

この文書の役割は次の4つです。

1. 何を直すかを曖昧にしない
2. どの既存ファイルを差し替えるかを明確にする
3. どの順番で着手すべきかを固定する
4. 完成条件を「動いた」ではなく「会計システムとして成立した」に引き上げる

この文書では、各タスクに以下を付けます。

- **ID**: 管理用識別子
- **優先度**: P0 / P1 / P2 / P3
- **種別**: 追加 / 修正 / 差し替え / 統合 / 削除
- **目的**: なぜやるか
- **対象**: 主に影響を受ける既存ファイル、または新規追加先
- **実装内容**: 実装すべき具体事項
- **完了条件**: Done の定義
- **依存**: 着手前提

---

# 1. 完成形の定義

このリファクタリング完了後の ProjectProfit は、次の状態に到達していなければならない。

> 個人事業主が、証憑を起点に、プロジェクト別の収支・利益を把握しながら、法定帳簿、青色申告決算書、収支内訳書、消費税集計、固定資産、棚卸、e-Tax 用データまで、端末内で安全に作成・保存できる会計システム。

必須要件は次のとおり。

- **コンセプト維持**
  - 個人事業主向け
  - プロジェクトごとに管理できる
  - 会計がノーストレス
  - AI はオンデバイス限定
- **制度対応**
  - 青色申告: 65万 / 55万 / 10万 / 現金主義用
  - 白色申告: 収支内訳書、簡易記帳
  - 消費税: 免税 / 課税、一般課税 / 簡易課税 / 2割特例
  - インボイス: 登録番号、必要記載事項、少額特例、80% / 50% 経過措置
  - 電子帳簿 / 電子取引保存の要件管理
  - e-Tax XML 出力
- **会計要件**
  - 正本は 1 系統
  - 複式簿記の整合
  - 補助簿、総勘定元帳、試算表、P/L、B/S が相互整合
  - 月次締め、年次締め、期首・期末処理
- **運用要件**
  - 年度ロック
  - 証憑削除統制
  - 監査ログ
  - 取引・仕訳・帳簿・帳票のトレーサビリティ
- **汎用性**
  - ユーザー勘定科目追加
  - ユーザージャンル追加
  - プロジェクト配賦の自動化
  - 単月の全プロジェクト一括配賦
  - 定期取引の該当月自動分配
  - 幅広い業種に耐えるカテゴリ / 科目 / 税区分マスタ

---

# 2. 先に確定する非交渉原則

## 2-1. 絶対に維持するもの

- プロジェクト別管理
- オンデバイス AI 限定
- iOS ネイティブのオフライン中心設計
- 個人事業主の実務に直結する帳簿と申告書

## 2-2. 直ちにやめるもの

- `isBlueReturn: Bool` のような薄い制度表現
- 正本を複数持つ設計
- OCR の結果だけを正とする設計
- 消費税を仮受 / 仮払の差額だけで扱う設計
- invoice / non-invoice で帳簿型を二重管理する設計
- UI 画面単位で直接会計事実を更新する設計

## 2-3. 最終的に採る構造

会計の正本は必ず次の流れに統一する。

**証憑 -> 取引候補 -> 仕訳候補 -> 確定仕訳 -> 派生帳簿 / 派生帳票**

法定帳簿・管理会計・PDF・CSV・Excel・e-Tax XML は、すべてこの正本から派生させる。

---

# 3. 最終アーキテクチャ

## 3-1. 新ディレクトリ構成の完成形

```text
ProjectProfit/
  App/
  Domain/
    Business/
    TaxYear/
    Project/
    Counterparty/
    Evidence/
    Transaction/
    Posting/
    Account/
    Tax/
    Inventory/
    FixedAsset/
    Books/
    Reports/
    Filing/
    Recurring/
    Tags/
    Audit/
  Application/
    UseCases/
    Commands/
    Queries/
    Validators/
    Migrations/
  Infrastructure/
    Persistence/
    OCR/
    Parsing/
    Export/
    Search/
    TaxYearPacks/
    FormPacks/
  UI/
    Dashboard/
    Inbox/
    Projects/
    Transactions/
    Books/
    Tax/
    Settings/
  Shared/
  Resources/
    TaxYearPacks/
    BookSpecs/
    FormSpecs/
    Classification/
    IndustryTemplates/
  Tests/
    Domain/
    Application/
    Infrastructure/
    Golden/
    UI/
```

## 3-2. 既存ファイルに対する扱い方針

### 残すが役割変更するもの

- `ReceiptScannerService.swift` -> OCR アダプタとして残す
- `TaxYearDefinitionLoader.swift` -> `TaxYearPackLoader` に昇格
- `AccountingEngine.swift` -> 新 PostingEngine の一部に分解
- `PDFExportService.swift` -> 共通レンダラの出力アダプタにする
- `ClassificationEngine.swift` -> 候補生成器として残す

### 完全差し替え対象

- `PPAccountingProfile.swift`
- `ConsumptionTaxModels.swift`
- `ConsumptionTaxReportService.swift`
- `TaxLineDefinitions.swift`
- `EtaxFieldPopulator.swift`
- `ShushiNaiyakushoBuilder.swift`
- `EtaxXtxExporter.swift`

### 廃止または派生層へ降格するもの

- `LedgerDataStore.swift`
- `LedgerBridge.swift`
- `LedgerExportService.swift`
- `LedgerExcelExportService.swift`
- `LedgerPDFExportService.swift`
- invoice / non-invoice を分けた `LedgerType`

### 巨大ファイル分割対象

- `DataStore.swift`
- `Models.swift`

---

# 4. 優先順位の大原則

## 4-1. 実装順序

1. **安全化**
2. **正本設計**
3. **税務状態設計**
4. **証憑台帳**
5. **仕訳エンジン**
6. **消費税エンジン**
7. **帳簿エンジン**
8. **帳票 / e-Tax**
9. **定期取引 / 自動配賦**
10. **UI 再構築**
11. **移行 / 回帰テスト**
12. **公開判定**

## 4-2. 着手順の誤りとして禁止するもの

- UI を先に作る
- 青色申告決算書 PDF を先に整える
- OCR 精度改善を先にやる
- Ledger 系を先に作り込む

最初に作るべきは、**制度を表現できる正本モデル** です。

---

# 5. フェーズ別実装タスク一覧

---

# Phase 0. リファクタリング前の固定化と安全装置

## P0-001 リファクタリング専用ブランチと baseline tag を切る
- **優先度**: P0
- **種別**: 追加
- **目的**: 現行挙動を比較可能にする
- **対象**: リポジトリ全体
- **実装内容**:
  - `refactor/accounting-core` ブランチを作成
  - 現行の main に baseline tag を付与
  - 現行の PDF / CSV / XML 出力をサンプル保存
- **完了条件**:
  - baseline tag が存在する
  - 既存テストが green
  - golden サンプル出力一式が保存される
- **依存**: なし

## P0-002 ゴールデンデータセットを作る
- **優先度**: P0
- **種別**: 追加
- **目的**: リファクタリング後に制度・帳簿・帳票の正しさを判定できるようにする
- **対象**: `ProjectProfitTests/Golden/`
- **実装内容**:
  - サービス業サンプル
  - 小売業サンプル（8% / 10% 混在）
  - 請負業サンプル（外注、前受、未収）
  - 固定資産ありサンプル
  - 棚卸ありサンプル
  - 白色サンプル
  - 青色65 / 55 / 10 / 現金主義サンプル
  - 一般課税 / 簡易 / 2割特例サンプル
- **完了条件**:
  - すべて JSON fixture / expected books / expected forms を持つ
- **依存**: P0-001

## P0-003 現行モデルへの直接依存を凍結する
- **優先度**: P0
- **種別**: 修正
- **目的**: 以後の作業で UI と永続化層がさらに密結合しないようにする
- **対象**: `Views/*`, `ViewModels/*`, `DataStore.swift`
- **実装内容**:
  - 新規機能で `@Model` を UI から直接編集しないルールを導入
  - Application service 経由以外の更新を禁止
- **完了条件**:
  - UI 直接更新箇所に TODO / deprecation marker が入る
- **依存**: P0-001

## P0-004 出力比較ツールを作る
- **優先度**: P0
- **種別**: 追加
- **目的**: 帳簿 / 帳票 / XML の差分比較を自動化する
- **対象**: `tools/`
- **実装内容**:
  - CSV diff
  - PDF text diff + metadata diff
  - XML canonicalization diff
  - numeric-only diff
- **完了条件**:
  - golden 比較コマンドで差分が見える
- **依存**: P0-002

## P0-005 リファクタリング feature flag を作る
- **優先度**: P0
- **種別**: 追加
- **目的**: 新旧機能を段階的に入れ替える
- **対象**: `App/`, `Settings/`
- **実装内容**:
  - `newDomainEnabled`
  - `newTaxEngineEnabled`
  - `newBooksEnabled`
  - `newFormsEnabled`
- **完了条件**:
  - 設定値に応じて旧実装 / 新実装の分岐が可能
- **依存**: P0-001

---

# Phase 1. 正本モデルの再設計

## P1-001 `PPAccountingProfile` を `BusinessProfile` と `TaxYearProfile` に分離する
- **優先度**: P1
- **種別**: 差し替え
- **目的**: 制度を正しく表現できるようにする
- **対象**: `Models/PPAccountingProfile.swift`
- **新規**:
  - `Domain/Business/BusinessProfile.swift`
  - `Domain/TaxYear/TaxYearProfile.swift`
- **実装内容**:
  - `BusinessProfile`
    - 屋号
    - 氏名
    - 住所
    - 電話
    - 開業日
    - 事業種類
    - デフォルト口座
  - `TaxYearProfile`
    - 対象年分
    - 申告区分 `blue_general / blue_cash_basis / white`
    - 青色控除レベル `65 / 55 / 10 / none`
    - 記帳方式 `single / double / cash_basis`
    - 消費税状態 `exempt / taxable`
    - 消費税方式 `general / simplified / twoTenths`
    - インボイス発行者状態 `registered / unregistered / unknown`
    - 電子帳簿レベル `none / standard / superior`
    - 年度ロック状態
- **完了条件**:
  - `isBlueReturn: Bool` を参照するコードがなくなる
  - 青色 / 白色 / 現金主義の分岐が型安全に表現される
- **依存**: P0-003

## P1-002 `TaxYearPack` を新設する
- **優先度**: P1
- **種別**: 追加
- **目的**: 年分ごとの制度、帳票、e-Tax、税率ルール差分を吸収する
- **対象**: `Services/TaxYearDefinitionLoader.swift`, `Resources/TaxYear2025.json`
- **新規**:
  - `Domain/TaxYear/TaxYearPack.swift`
  - `Infrastructure/TaxYearPacks/TaxYearPackLoader.swift`
  - `Resources/TaxYearPacks/2025/`
  - `Resources/TaxYearPacks/2026/`
- **実装内容**:
  - 年分ごとに次を束ねる
    - フォーム定義
    - XML mapping
    - 税率 / 経過措置有効期間
    - 消費税特例
    - 勘定科目の既定 mapping
    - 帳簿 spec version
- **完了条件**:
  - `TaxYear2025.json` 単体依存を脱却する
- **依存**: P1-001

## P1-003 `Counterparty` 取引先マスタを追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: インボイス、売上先 / 仕入先明細、自動仕訳精度を支える
- **対象**: 新規
- **新規**:
  - `Domain/Counterparty/Counterparty.swift`
  - `Domain/Counterparty/CounterpartyTaxStatus.swift`
- **実装内容**:
  - 名称
  - かな
  - T番号
  - 法人番号
  - インボイス状態
  - 有効開始日 / 終了日
  - 既定勘定科目
  - 既定税区分
  - 既定プロジェクト
  - 国内 / 国外
  - メモ
- **完了条件**:
  - OCR / 取引入力 / 帳票明細で取引先を共通利用できる
- **依存**: P1-001

## P1-004 `GenreDimension` / `GenreTag` を追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 科目とは別に、業種ごとに柔軟な管理分類を持てるようにする
- **対象**: 新規
- **新規**:
  - `Domain/Tags/GenreDimension.swift`
  - `Domain/Tags/GenreTag.swift`
- **実装内容**:
  - `genre`, `channel`, `workType`, `campaign`, `clientSegment` などをユーザー定義可能にする
  - 1取引に複数タグ付与可
  - プロジェクトと独立して管理会計軸を持てるようにする
- **完了条件**:
  - `PPCategory` を会計分類だけに寄せ、ジャンルは別軸で扱える
- **依存**: P1-001

## P1-005 `ProjectAllocation` を昇格させる
- **優先度**: P1
- **種別**: 修正
- **目的**: 既存 `Allocation` を単なる配分情報ではなく、監査可能な配賦事実にする
- **対象**: `Models/Models.swift`
- **新規**:
  - `Domain/Project/ProjectAllocation.swift`
- **実装内容**:
  - projectId
  - ratio
  - amount
  - sourceRuleId
  - basisType `manual / equal / fixed / proRata / ruleBased`
  - locked flag
  - generatedAt
  - explanation
- **完了条件**:
  - 各配賦に「なぜこの金額か」が追跡できる
- **依存**: P1-001

## P1-006 `PPCategory` を UI分類に限定する
- **優先度**: P1
- **種別**: 修正
- **目的**: カテゴリと勘定科目の責務を分離する
- **対象**: `Models/Models.swift`, `Views/Components/CategoryManageView.swift`
- **実装内容**:
  - `PPCategory` はユーザー入力時の分類ラベルとし、会計正本の科目と混同しない
  - `defaultAccountId`, `defaultTaxCodeId`, `defaultTagIds` を持たせる
  - merge / archive / replace を可能にする
- **完了条件**:
  - 「カテゴリ = 勘定科目」ではなくなる
- **依存**: P1-003

## P1-007 `PPAccount` を完成版勘定科目モデルへ拡張する
- **優先度**: P1
- **種別**: 修正
- **目的**: ユーザー科目追加と帳票マッピングの両立
- **対象**: `Models/PPAccount.swift`, `Models/AccountingEnums.swift`
- **実装内容**:
  - system/custom 区分
  - 勘定コード
  - 表示順
  - 帳票マッピング
  - closing behavior
  - 税務上の既定税区分
  - 補助簿出力対象フラグ
  - 非表示 / アーカイブ / merge 先
- **完了条件**:
  - ユーザー追加勘定科目が青色 / 白色 / 補助簿 / P/L / B/S で破綻しない
- **依存**: P1-001

---

# Phase 2. 証憑中心の取り込み基盤

## P2-001 `ReceiptScannerService` を `DocumentIntakeService` に作り直す
- **優先度**: P1
- **種別**: 差し替え
- **目的**: レシート専用から、請求書・領収書・契約書・PDF・電子受領データ全体に対応させる
- **対象**: `Services/ReceiptScannerService.swift`
- **新規**:
  - `Infrastructure/OCR/DocumentIntakeService.swift`
  - `Infrastructure/OCR/OCRAdapter.swift`
  - `Infrastructure/OCR/ExtractionPipeline.swift`
- **実装内容**:
  - カメラ画像
  - 写真ライブラリ
  - ファイルアプリ PDF
  - ShareSheet
  - メール添付PDF取り込み
  - OCR テキスト抽出
  - ルールベース抽出
  - Foundation Models 利用可能時の端末内構造化抽出
- **完了条件**:
  - `Receipt` 前提の命名と制御がなくなり、Document 単位で処理される
- **依存**: P1-003

## P2-002 `EvidenceDocument` を追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 証憑を会計の起点として扱う
- **対象**: `Models/PPDocumentRecord.swift`
- **新規**:
  - `Domain/Evidence/EvidenceDocument.swift`
  - `Domain/Evidence/EvidenceVersion.swift`
  - `Domain/Evidence/EvidenceExtractedField.swift`
- **実装内容**:
  - 原本ファイル
  - ハッシュ
  - OCRテキスト
  - 抽出フィールド
  - ユーザー修正フィールド
  - 取引リンク
  - 仕訳リンク
  - 年度
  - プロジェクト
  - 取引先
  - 保存区分
  - 検索インデックス
- **完了条件**:
  - 証憑が transactionId の添付ではなく、独立した正規エンティティになる
- **依存**: P2-001

## P2-003 保存期間ロジックを全面修正する
- **優先度**: P1
- **種別**: 修正
- **目的**: インボイス保存期間、電子取引保存、帳簿保存を誤らないようにする
- **対象**: `Models/PPDocumentRecord.swift`, `Services/DataStore+Documents.swift`
- **実装内容**:
  - インボイスの保存期間を document type 単純年数で決めない
  - 課税期間、受領日、閉鎖日、申告期限起算を扱う
  - `paperScan` と `electronicTransaction` を分離
  - 削除禁止 / 要承認 / ロック済み不可を追加
- **完了条件**:
  - `invoice -> otherBusinessDocuments -> 5年` という誤った流れが消える
- **依存**: P2-002

## P2-004 訂正削除履歴を EvidenceVersion で持つ
- **優先度**: P1
- **種別**: 追加
- **目的**: 電子帳簿 / 電子取引保存で求められる履歴性に寄せる
- **対象**: 新規
- **実装内容**:
  - 抽出値修正履歴
  - 元ファイル差替履歴
  - 状態変更履歴
  - 誰が / いつ / 何を変えたか
- **完了条件**:
  - 修正後の最終値しか残らない状態を解消する
- **依存**: P2-002

## P2-005 証憑検索インデックスを追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 日付 / 金額 / 取引先検索要件を満たす
- **対象**: 新規
- **新規**:
  - `Infrastructure/Search/EvidenceSearchIndex.swift`
- **実装内容**:
  - 日付
  - 取引金額
  - 取引先名
  - T番号
  - 文書種別
  - キーワード全文
- **完了条件**:
  - 証憑検索画面から要件検索ができる
- **依存**: P2-002

## P2-006 T番号・税率別情報抽出を実装する
- **優先度**: P1
- **種別**: 追加
- **目的**: インボイス対応を OCR パイプラインに組み込む
- **対象**: `ReceiptData.swift`, `ReceiptScannerService.swift`
- **実装内容**:
  - T+13桁検出
  - 税率別合計額抽出
  - 税率別税額抽出
  - 適格 / 適格簡易 / 区分記載相当の推定
  - 信頼度スコア
- **完了条件**:
  - 単に店名・金額・日付だけで終わらない
- **依存**: P2-001, P1-003

## P2-007 証憑重複検知を追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 二重計上を防ぐ
- **対象**: 新規
- **実装内容**:
  - ハッシュ一致
  - 類似金額 + 類似日付 + 類似取引先
  - 同一月内の重複候補
  - 手動マージ / 別物として確定
- **完了条件**:
  - 同一レシートや同一 PDF の多重登録が要確認キューに入る
- **依存**: P2-002

## P2-008 証憑から仕訳候補へつなぐ `PostingCandidate` を新設する
- **優先度**: P1
- **種別**: 追加
- **目的**: OCR から即確定しないようにする
- **対象**: 新規
- **新規**:
  - `Domain/Posting/PostingCandidate.swift`
  - `Domain/Posting/PostingCandidateLine.swift`
- **実装内容**:
  - 勘定科目候補
  - 税コード候補
  - プロジェクト配賦候補
  - 取引先候補
  - 信頼度
  - 要確認理由
- **完了条件**:
  - AI は候補生成まで、確定はルール + ユーザー承認になる
- **依存**: P2-006

---

# Phase 3. 仕訳正本エンジンの再構築

## P3-001 `AccountingEngine` を `PostingEngine` に分解する
- **優先度**: P1
- **種別**: 差し替え
- **目的**: 取引入力中心から、仕訳候補 -> 確定仕訳の二段階へ移行する
- **対象**: `Services/AccountingEngine.swift`
- **新規**:
  - `Application/UseCases/BuildPostingCandidate.swift`
  - `Application/UseCases/ApprovePostingCandidate.swift`
  - `Domain/Posting/PostingEngine.swift`
  - `Domain/Posting/PostingRuleEngine.swift`
- **実装内容**:
  - 取引タイプごとの line builder
  - gross / net 処理
  - multi-line 処理
  - project allocation 展開
  - tax line 展開
  - input / output tax line 自動生成
  - owner draw / owner contribution 処理
- **完了条件**:
  - 現行 `upsertJournalEntry` 一本足から脱却する
- **依存**: P2-008, P1-007

## P3-002 `PPTransaction` を入力イベントとして再定義する
- **優先度**: P1
- **種別**: 修正
- **目的**: `PPTransaction` が会計正本と UI 入力物を兼ねている問題を解く
- **対象**: `Models/Models.swift`
- **実装内容**:
  - `PPTransaction` を `BusinessEvent` または `SourceTransaction` へ改名 / 移行
  - 会計事実の確定は `PostedJournal` に限定
  - `sourceTransactionId` は参照にとどめる
- **完了条件**:
  - 取引削除 = 仕訳削除のような危険な結合がなくなる
- **依存**: P3-001

## P3-003 `isTaxIncluded` と税額計算を厳密化する
- **優先度**: P1
- **種別**: 修正
- **目的**: 税込 / 税抜入力の誤処理を防ぐ
- **対象**: `Models/Models.swift`, `AccountingEngine.swift`
- **実装内容**:
  - `amountInputMode` を `gross / net / taxOnly` で持つ
  - 税額は tax code と rounding rule に基づき計算
  - 文書単位 / 税率単位の丸めに対応
- **完了条件**:
  - `amount - taxAmount` の決め打ちをやめる
- **依存**: P3-001

## P3-004 複合仕訳を第一級の市民にする
- **優先度**: P1
- **種別**: 修正
- **目的**: 1証憑多行、複数税率、固定資産混在、複数プロジェクト配賦を扱えるようにする
- **対象**: `PPJournalEntry.swift`, `AccountingEngine.swift`
- **実装内容**:
  - 1 つの posting candidate に複数 debit / credit line
  - 同一 evidence から複数 line
  - 摘要、証憑、プロジェクトごとの line level metadata
- **完了条件**:
  - 「1証憑 = 1行仕訳」前提が消える
- **依存**: P3-001

## P3-005 開始仕訳 / 締切仕訳 / 決算整理仕訳を独立ユースケースにする
- **優先度**: P1
- **種別**: 修正
- **目的**: opening / closing / adjustment を通常取引と分離する
- **対象**: `AccountingEngine.swift`
- **実装内容**:
  - 期首残高仕訳
  - 決算整理仕訳
  - 損益振替
  - 元入金調整
  - 在庫振替
  - 減価償却仕訳
- **完了条件**:
  - 年次処理が明示的な use case になる
- **依存**: P3-001

## P3-006 `JournalValidationService` を完成版にする
- **優先度**: P1
- **種別**: 修正
- **目的**: 仕訳の妥当性を税務レベルまで引き上げる
- **対象**: `Services/JournalValidationService.swift`
- **実装内容**:
  - 借貸一致
  - 税額 line 整合
  - 期首 / 決算仕訳ルール
  - ロック期間編集禁止
  - 控除根拠不足警告
  - evidence 未紐付け警告
- **完了条件**:
  - validation が UI警告だけでなく保存条件に使える
- **依存**: P3-001

## P3-007 audit trail を仕訳レベルに追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 誰がいつ何を確定 / 修正 / 取消したかを残す
- **対象**: 新規
- **新規**:
  - `Domain/Audit/AuditEvent.swift`
  - `Domain/Audit/AuditActor.swift`
- **完了条件**:
  - 仕訳履歴が監査ログに残る
- **依存**: P3-001

---

# Phase 4. 消費税エンジンの全面再構築

## P4-001 `ConsumptionTaxModels` を総入れ替えする
- **優先度**: P1
- **種別**: 差し替え
- **目的**: 消費税を仮払 / 仮受の単純差額ではなく、制度に沿って扱う
- **対象**: `Models/ConsumptionTaxModels.swift`
- **新規**:
  - `Domain/Tax/ConsumptionTaxWorksheet.swift`
  - `Domain/Tax/ConsumptionTaxBucket.swift`
  - `Domain/Tax/TaxCode.swift`
  - `Domain/Tax/InputTaxCreditMethod.swift`
  - `Domain/Tax/TaxDeterminationReason.swift`
- **実装内容**:
  - 売上 / 仕入
  - 標準税率 / 軽減税率 / 非課税 / 不課税
  - 税率別本体金額
  - 税率別税額
  - 控除根拠
  - 納付税額 / 還付見込
- **完了条件**:
  - 3値 summary で終わらない
- **依存**: P3-001

## P4-002 `TaxCode` マスタを定義する
- **優先度**: P1
- **種別**: 追加
- **目的**: 税区分を enum ではなく制度ルールとして扱う
- **対象**: `Models/AccountingEnums.swift`
- **実装内容**:
  - `sales_standard`
  - `sales_reduced`
  - `purchase_standard_invoice`
  - `purchase_reduced_invoice`
  - `purchase_small_amount`
  - `purchase_transitional_80`
  - `purchase_transitional_50`
  - `purchase_non_deductible`
  - `travel_expense_book_only`
  - `vending_machine_book_only`
  - `stamp_exemption_case`
  - `exempt`, `non_taxable`
- **完了条件**:
  - 既存 `TaxCategory` だけでは足りない処理を全部 `TaxCode` で表せる
- **依存**: P4-001

## P4-003 少額特例、80%、50% 経過措置、2割特例をルール化する
- **優先度**: P1
- **種別**: 追加
- **目的**: 年分・取引時点・事業者状態による控除可否を正しく判定する
- **対象**: 新規
- **実装内容**:
  - 税年 pack に有効期間を持たせる
  - 金額判定単位を取引単位で持つ
  - 一般課税 / 簡易 / 2割特例の分岐を持つ
  - 免税事業者等からの仕入れの経過措置を自動判定
- **完了条件**:
  - `InvoiceType = 〇 / 8割控除 / 少額特例` だけの世界を終了する
  - 50% 経過措置が実装される
- **依存**: P4-001, P1-002

## P4-004 簡易課税対応を入れる
- **優先度**: P1
- **種別**: 追加
- **目的**: 個人事業主の実務で多い簡易課税を扱う
- **対象**: 新規
- **実装内容**:
  - 事業区分管理
  - みなし仕入率テーブルを year pack 化
  - 売上区分ごとの bucket 集計
  - 一般課税との切替
- **完了条件**:
  - `vatMethod = simplified` で正しい集計が出る
- **依存**: P4-001

## P4-005 添付された消費税集計表に一致する worksheet を作る
- **優先度**: P1
- **種別**: 追加
- **目的**: 目標の消費税 UI / 帳票を明確化する
- **対象**: 新規
- **新規**:
  - `Domain/Tax/ConsumptionTaxWorksheetRenderer.swift`
- **実装内容**:
  - 課税売上高 税込 / 税抜
  - 標準税率 / 軽減税率
  - 国税相当額
  - 仕入・経費の控除税額小計
  - 差引税額
  - 根拠リンク
- **完了条件**:
  - 添付イメージの表構造を再現できる
- **依存**: P4-001, P4-003

## P4-006 消費税エラー説明を追加する
- **優先度**: P2
- **種別**: 追加
- **目的**: ユーザーが「なぜ控除できないか」を理解できるようにする
- **対象**: UI, Tax engine
- **実装内容**:
  - インボイス未確認
  - T番号未入力
  - 書類はあるが必要記載事項不足
  - 少額特例対象外
  - 80% / 50% 経過措置対象
  - 2割特例により個別控除計算しない
- **完了条件**:
  - 消費税判定に explanation string がある
- **依存**: P4-001

---

# Phase 5. 帳簿エンジンの統一再構築

## P5-001 `LedgerDataStore` を正本から派生する `BookEngine` に置換する
- **優先度**: P1
- **種別**: 差し替え
- **目的**: 帳簿世界の二重管理をやめる
- **対象**: `Ledger/Services/LedgerDataStore.swift`, `Ledger/Bridge/LedgerBridge.swift`
- **新規**:
  - `Domain/Books/BookEngine.swift`
  - `Domain/Books/BookSpec.swift`
  - `Domain/Books/BookRow.swift`
  - `Domain/Books/DerivedBookRepository.swift`
- **実装内容**:
  - 正本仕訳から帳簿行を派生生成
  - 保存型 ledger をやめ、必要時再生成を基本にする
  - 一部重い集計は cache 可
- **完了条件**:
  - Ledger が正本として更新されるコードがなくなる
- **依存**: P3-001

## P5-002 帳簿フォーマット spec を JSON で定義する
- **優先度**: P1
- **種別**: 追加
- **目的**: 帳簿レイアウトと計算ロジックを分離する
- **対象**: `Ledger/Resources/master_schema.json`
- **新規**:
  - `Resources/BookSpecs/journal.json`
  - `Resources/BookSpecs/general_ledger.json`
  - `Resources/BookSpecs/cash_book.json`
  - `Resources/BookSpecs/bank_book.json`
  - `Resources/BookSpecs/ar_book.json`
  - `Resources/BookSpecs/ap_book.json`
  - `Resources/BookSpecs/expense_book.json`
  - `Resources/BookSpecs/white_simple_book.json`
  - `Resources/BookSpecs/fixed_asset_register.json`
  - `Resources/BookSpecs/inventory_book.json`
  - `Resources/BookSpecs/transportation_expense.json`
  - `Resources/BookSpecs/evidence_register.json`
- **完了条件**:
  - 帳簿列定義がコードに散らばらない
- **依存**: P5-001

## P5-003 仕訳帳 spec を完成させる
- **優先度**: P1
- **種別**: 追加
- **目的**: 複合仕訳に強い正式な仕訳帳を出力する
- **対象**: 新規 BookSpec
- **法定表示列**:
  - 月
  - 日
  - 借方科目
  - 借方金額
  - 貸方科目
  - 貸方金額
  - 摘要
- **内部拡張列**:
  - entryNo
  - evidenceNo
  - sourceType
  - projectSummary
  - taxCodeSummary
- **実装内容**:
  - 複合仕訳時は2行目以降の日付を省略可
  - 行番号管理
  - ソート規則固定
- **完了条件**:
  - 既存 `journal` spec と互換性を維持しつつ拡張列を持てる
- **依存**: P5-002

## P5-004 総勘定元帳 spec を完成させる
- **優先度**: P1
- **種別**: 追加
- **目的**: 正常残高方向で差引残高が正確に出る元帳を出力する
- **法定表示列**:
  - 月
  - 日
  - 摘要
  - 相手科目
  - 借方
  - 貸方
  - 差引残高
- **内部拡張列**:
  - evidenceNo
  - project
  - taxCode
- **完了条件**:
  - 科目属性ごとに残高が正しい
- **依存**: P5-002

## P5-005 現金出納帳 spec を完成させる
- **優先度**: P1
- **種別**: 追加
- **法定表示列**:
  - 月
  - 日
  - 摘要
  - 勘定科目
  - 入金
  - 出金
  - 差引残高
- **実装内容**:
  - carry forward row
  - 期中残高
  - 現金勘定限定抽出
- **完了条件**:
  - 現金取引の増減が一覧化される
- **依存**: P5-002

## P5-006 預金出納帳 spec を完成させる
- **優先度**: P1
- **種別**: 追加
- **法定表示列**:
  - 月
  - 日
  - 摘要
  - 相手科目
  - 預入金額
  - 払出金額
  - 預金残高
- **メタデータ**:
  - 銀行名
  - 支店名
  - 口座種別
  - 口座番号下4桁表示
- **完了条件**:
  - 口座別元帳として成立する
- **依存**: P5-002

## P5-007 売掛帳 spec を完成させる
- **優先度**: P1
- **種別**: 追加
- **法定表示列**:
  - 月
  - 日
  - 相手科目
  - 摘要
  - 数量
  - 単価
  - 売上金額
  - 入金金額
  - 売掛金残高
- **メタデータ**:
  - 得意先名
  - 前期より繰越
- **実装内容**:
  - 取引先別サブレジャー
  - 不明得意先バケット
- **完了条件**:
  - 得意先別売掛残高が一致する
- **依存**: P1-003, P5-002

## P5-008 買掛帳 spec を完成させる
- **優先度**: P1
- **種別**: 追加
- **法定表示列**:
  - 月
  - 日
  - 相手科目
  - 摘要
  - 数量
  - 単価
  - 仕入金額
  - 支払金額
  - 買掛金残高
- **メタデータ**:
  - 仕入先名
  - 前期より繰越
- **完了条件**:
  - 仕入先別買掛残高が一致する
- **依存**: P1-003, P5-002

## P5-009 経費帳 spec を完成させる
- **優先度**: P1
- **種別**: 追加
- **法定表示列**:
  - 月
  - 日
  - 相手科目
  - 摘要
  - 金額
  - 累計
- **内部拡張列**:
  - 軽減税率フラグ
  - 控除方式
  - T番号
  - evidence link
- **完了条件**:
  - 科目別経費帳が正しく出る
- **依存**: P5-002, P4-001

## P5-010 白色申告用簡易帳簿 spec を完成させる
- **優先度**: P1
- **種別**: 追加
- **法定表示列**:
  - 月
  - 日
  - 摘要
  - 売上金額
  - 雑収入等
  - 仕入
  - 給料賃金
  - 外注工賃
  - 減価償却費
  - 貸倒金
  - 地代家賃
  - 利子割引料
  - 租税公課
  - 荷造運賃
  - 水道光熱費
  - 旅費交通費
  - 通信費
  - 広告宣伝費
  - 接待交際費
  - 損害保険料
  - 修繕費
  - 消耗品費
  - 福利厚生費
  - 雑費
- **実装内容**:
  - 1日合計記帳にも対応
  - 白色専用入力導線から直接生成
- **完了条件**:
  - 白色ユーザーがこの帳簿だけで基本運用できる
- **依存**: P5-002, P1-001

## P5-011 固定資産台帳兼減価償却計算表 spec を完成させる
- **優先度**: P1
- **種別**: 追加
- **法定表示列**:
  - 勘定科目
  - 資産コード
  - 資産名
  - 資産の種類
  - 状態
  - 数量
  - 取得日
  - 取得価額
  - 耐用年数
  - 償却方法
  - 償却率
  - 当期償却額
  - 異動数量
  - 異動金額
  - 現在数量
  - 現在金額
  - 事業専用割合
  - 必要経費算入額
  - 備考
- **完了条件**:
  - 青色 / 白色帳票の減価償却明細へ接続できる
- **依存**: P5-002

## P5-012 棚卸表 / 在庫台帳 spec を追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 仕入と売上原価の年末整合を保証する
- **対象**: `PPInventoryRecord.swift`, `InventoryService.swift`
- **表示列**:
  - 商品コード
  - 品名
  - 期首数量 / 金額
  - 仕入数量 / 金額
  - 期末数量 / 金額
  - 単価計算方式
  - 備考
- **完了条件**:
  - 棚卸データから売上原価計算が追跡できる
- **依存**: P5-002

## P5-013 交通費精算書 spec を追加する
- **優先度**: P2
- **種別**: 追加
- **目的**: 交通費の証跡と経費計上を整える
- **表示列**:
  - 日付
  - 行先
  - 目的
  - 交通機関
  - 区間（起点）
  - 区間（終点）
  - 片 / 往
  - 金額
- **完了条件**:
  - 旅費交通費の明細証跡として出力できる
- **依存**: P5-002

## P5-014 証憑台帳 spec を追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 電子取引 / 受領書類 / 証憑保管の一覧を見せる
- **表示列**:
  - 証憑番号
  - 受領日
  - 取引日
  - 取引先
  - 文書種別
  - 金額
  - 税額
  - T番号
  - 保存区分
  - ハッシュ
  - 紐付取引
  - 紐付仕訳
  - 保存期限
  - 状態
- **完了条件**:
  - 証憑保管状況を一覧できる
- **依存**: P2-002, P5-002

## P5-015 `master_schema.json` を新 BookSpec へ移行する
- **優先度**: P1
- **種別**: 統合
- **目的**: 現行帳簿 schema の資産を活かしつつ責務を整理する
- **対象**: `Ledger/Resources/master_schema.json`
- **実装内容**:
  - 既存列定義を BookSpec に吸収
  - invoice_extra_columns は tax context 列へ一般化
  - `invoice_type` の値を更新
- **完了条件**:
  - `master_schema.json` が唯一の帳簿真実ではなくなる
- **依存**: P5-002

## P5-016 帳簿出力サービスを統一する
- **優先度**: P1
- **種別**: 統合
- **対象**:
  - `CSVExportService.swift`
  - `PDFExportService.swift`
  - `LedgerExportService.swift`
  - `LedgerExcelExportService.swift`
  - `LedgerPDFExportService.swift`
- **新規**:
  - `Infrastructure/Export/BookExportService.swift`
  - `Infrastructure/Export/CSVBookExporter.swift`
  - `Infrastructure/Export/PDFBookExporter.swift`
  - `Infrastructure/Export/ExcelBookExporter.swift`
- **完了条件**:
  - 集計ロジックは BookEngine だけに存在し、出力はレンダラだけが担当する
- **依存**: P5-001

---

# Phase 6. 帳票エンジンと e-Tax の再構築

## P6-001 `FormEngine` を新設する
- **優先度**: P1
- **種別**: 追加
- **目的**: 青色申告決算書 / 収支内訳書 / 消費税 worksheet を一貫生成する
- **対象**:
  - `ShushiNaiyakushoBuilder.swift`
  - `EtaxFieldPopulator.swift`
  - `EtaxModels.swift`
- **新規**:
  - `Domain/Filing/FormEngine.swift`
  - `Domain/Filing/FormPack.swift`
  - `Domain/Filing/FormFieldMapping.swift`
  - `Domain/Filing/FormValidation.swift`
- **完了条件**:
  - 帳票 builder が税務 year pack と連動する
- **依存**: P1-002, P5-001

## P6-002 青色申告決算書（一般用）4ページ構成を完全対応する
- **優先度**: P1
- **種別**: 差し替え
- **目的**: 公式様式の主要ページを漏れなく生成する
- **対象**: 新 FormPack
- **必要ページ**:
  - 1ページ: 損益計算書
  - 2ページ: 月別売上 / 仕入、給料賃金、青色申告特別控除計算
  - 3ページ: 減価償却、地代家賃、貸倒引当金、専従者給与等
  - 4ページ: 貸借対照表
- **完了条件**:
  - 合計金額だけでなく明細ページも埋まる
- **依存**: P6-001, P5-011, P5-012

## P6-003 青色申告決算書（現金主義用）pack を追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 現金主義特例の青色申告者に対応する
- **対象**: 新 FormPack
- **完了条件**:
  - `filingStyle = blue_cash_basis` で専用帳票が出る
- **依存**: P1-001, P6-001

## P6-004 収支内訳書（一般用）を完全対応する
- **優先度**: P1
- **種別**: 差し替え
- **目的**: 白色申告や雑所得向け実務に耐えるようにする
- **必要項目**:
  - 総収入金額
  - 売上原価
  - 経費内訳
  - 売上先名 / 所在地 / 収入金額明細
  - 仕入先名 / 所在地 / 仕入金額明細
  - 減価償却費の計算
  - 地代家賃の内訳
  - 利子割引料の内訳
- **完了条件**:
  - 公式様式の太枠必須項目と明細欄が埋まる
- **依存**: P6-001, P5-010, P5-011

## P6-005 white / blue の field mapping を分離する
- **優先度**: P1
- **種別**: 修正
- **目的**: 同じ `TaxLine` を無理に両方へ流さない
- **対象**: `TaxLineDefinitions.swift`, `EtaxFieldPopulator.swift`
- **実装内容**:
  - 帳票ごとに mapping set を持つ
  - field derivation に source formula を持つ
- **完了条件**:
  - form ごとに必要な情報量が不足しない
- **依存**: P6-001

## P6-006 B/S line mapping を完成させる
- **優先度**: P1
- **種別**: 修正
- **目的**: 4ページ目 B/S を資産合計 / 負債合計 / 元入金だけで終わらせない
- **対象**: `EtaxFieldPopulator.swift`, `TaxYear2025.json`
- **実装内容**:
  - 現金
  - 預金
  - 売掛金
  - 棚卸資産
  - 貸付金
  - 建物
  - 車両
  - 工具器具備品
  - 事業主貸
  - 買掛金
  - 借入金
  - 未払金
  - 前受金
  - 事業主借
  - 元入金
- **完了条件**:
  - B/S line を科目別に算出できる
- **依存**: P6-001

## P6-007 e-Tax XML と PDF preview を完全分離する
- **優先度**: P1
- **種別**: 修正
- **目的**: 提出用データと閲覧用データを混同しない
- **対象**: `Views/Accounting/EtaxExportView.swift`, exporters
- **実装内容**:
  - XML = 提出用
  - PDF = 控え / 確認 / 印刷用
  - UI 上で明確に区別
- **完了条件**:
  - 「PDF を出したから提出完了」と誤解しない UI になる
- **依存**: P6-001

## P6-008 `EtaxXtxExporter` を year pack 連動へ変更する
- **優先度**: P1
- **種別**: 差し替え
- **目的**: 年度差分と仕様更新へ追随しやすくする
- **対象**: `Services/EtaxXtxExporter.swift`
- **実装内容**:
  - XML schema version を pack から取得
  - field tag / root tag / form version を pack から取得
  - character validation と missing field validation を事前実行
- **完了条件**:
  - 年度更新時にコード修正ではなく pack 差替中心で対応できる
- **依存**: P1-002, P6-001

## P6-009 `PreflightValidation` を追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 送信前の制度・項目不足を検知する
- **新規**:
  - `Application/Validators/PreflightValidation.swift`
- **実装内容**:
  - 必須項目不足
  - 保存要件不足
  - 証憑未紐付け
  - B/S 不一致
  - 年度ロック未実施
  - 税区分未確定
- **完了条件**:
  - `export` ボタン前に差し止めできる
- **依存**: P6-001

## P6-010 e-Tax 仕様更新対応 runbook を実装する
- **優先度**: P2
- **種別**: 追加
- **目的**: 毎年の仕様更新を回せるようにする
- **対象**: `Docs/`
- **実装内容**:
  - 仕様差分確認手順
  - pack 更新手順
  - regression 実行手順
  - 本番切替手順
- **完了条件**:
  - 年次更新が属人化しない
- **依存**: P1-002

---

# Phase 7. 定期取引・自動分配・汎用性の強化

## P7-001 `PPRecurringTransaction` を `RecurringTemplate` に進化させる
- **優先度**: P1
- **種別**: 修正
- **目的**: 現在の monthly/yearly 固定を、完成版運用に耐える定期取引へ昇格させる
- **対象**: `Models/Models.swift`, `DataStore.swift`, `RecurringViewModel.swift`
- **新規**:
  - `Domain/Recurring/RecurringTemplate.swift`
  - `Domain/Recurring/RecurringOccurrence.swift`
- **実装内容**:
  - 開始日
  - 終了日
  - 頻度 interval
  - day-of-month
  - month set
  - amount rule
  - tax rule
  - project distribution rule
  - evidence template
  - catch-up generation
  - generated occurrence log
- **完了条件**:
  - 「定期取引 = monthly / yearly only」から脱却する
- **依存**: P3-001

## P7-002 定期取引の該当月自動分配ルールを汎化する
- **優先度**: P1
- **種別**: 修正
- **目的**: ユーザー要望である該当月自動分配を完成版にする
- **対象**: `DataStore.swift`, `RecurringFormView.swift`
- **新規**:
  - `Domain/Recurring/DistributionRule.swift`
- **実装内容**:
  - 月単位の active project 全体均等割
  - 完了月のみ含めるオプション
  - アーカイブ除外
  - fixed amount 配分
  - ratio 配分
  - 稼働日按分
  - 売上比例配分（管理会計）
  - 共有経費バケット配分
- **完了条件**:
  - 既存 `equalAll` を超えた一般化されたルールになる
- **依存**: P1-005, P7-001

## P7-003 単月の全プロジェクト自動分配機能を追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 月額固定費を当月の全案件へ一括配賦できるようにする
- **対象**: 新規 UseCase / UI
- **新規**:
  - `Application/UseCases/BulkDistributeForMonth.swift`
- **実装内容**:
  - 対象月指定
  - 対象プロジェクトフィルタ
  - equal / ratio / pro-rata
  - preview
  - commit
  - rollback
- **完了条件**:
  - 1ヶ月分の共通経費をまとめて配賦できる
- **依存**: P1-005, P7-002

## P7-004 自動配賦ルールにジャンル条件を追加する
- **優先度**: P2
- **種別**: 追加
- **目的**: 幅広い業種に対応する
- **対象**: `GenreTag`, `DistributionRule`
- **実装内容**:
  - タグ一致で配賦対象を絞る
  - `開発案件のみ`, `広告案件のみ` のような条件を作る
- **完了条件**:
  - 業種特化の運用が可能
- **依存**: P1-004, P7-002

## P7-005 recurring generation を idempotent job にする
- **優先度**: P1
- **種別**: 修正
- **目的**: 二重生成や削除後再生成の不整合を防ぐ
- **対象**: `DataStore.swift`
- **実装内容**:
  - occurrence key
  - generated log
  - 再実行しても二重生成しない
  - manual delete と rollback の整合
- **完了条件**:
  - 同月二重計上しない
- **依存**: P7-001

## P7-006 recurring preview を追加する
- **優先度**: P2
- **種別**: 追加
- **目的**: 定期ルール登録前に未来の発生予定と配賦結果を見せる
- **対象**: `RecurringFormView.swift`
- **完了条件**:
  - 次 12 か月の生成予定が preview できる
- **依存**: P7-001

## P7-007 ユーザー定義業種テンプレートを追加する
- **優先度**: P2
- **種別**: 追加
- **目的**: 業種ごとに初期設定を早くする
- **対象**: `Resources/IndustryTemplates/`
- **テンプレート例**:
  - ソフトウェア開発
  - デザイン制作
  - コンサルティング
  - 動画 / 配信 / クリエイター
  - 小売 / EC
  - 請負 / 外注中心業
  - 美容 / サロン個人事業
- **含めるもの**:
  - カテゴリ
  - 勘定科目マッピング
  - 税コード既定値
  - よくある定期取引
  - ジャンル例
- **完了条件**:
  - 初期セットアップが大幅に短縮される
- **依存**: P1-004, P1-007

---

# Phase 8. 勘定科目管理・カテゴリ管理・ユーザー拡張性

## P8-001 勘定科目管理画面を全面作り直す
- **優先度**: P1
- **種別**: 差し替え
- **対象**: `ChartOfAccountsView.swift`
- **目的**: ユーザーが科目を追加 / 編集 / 統合 / 無効化できるようにする
- **実装内容**:
  - 追加
  - 編集
  - アーカイブ
  - 代替科目へマージ
  - 税務 mapping 編集
  - 補助簿出力対象指定
  - 既定税コード設定
- **完了条件**:
  - 「システム科目しか使えない」がなくなる
- **依存**: P1-007

## P8-002 カテゴリ管理を「分類ルール管理」に昇格させる
- **優先度**: P2
- **種別**: 修正
- **対象**: `CategoryManageView.swift`, `ClassificationEngine.swift`
- **実装内容**:
  - カテゴリごとの default account
  - default tax code
  - default project rule
  - default tags
  - AI 学習ルール反映
- **完了条件**:
  - カテゴリが単なるラベルではなく候補生成ルールになる
- **依存**: P1-006

## P8-003 ジャンル管理画面を追加する
- **優先度**: P2
- **種別**: 追加
- **対象**: 新規 `UI/Settings/GenreManagementView.swift`
- **完了条件**:
  - ユーザーが自由にジャンル軸を追加 / 並び替え / 無効化できる
- **依存**: P1-004

## P8-004 取引先管理画面を追加する
- **優先度**: P1
- **種別**: 追加
- **対象**: 新規 `UI/Settings/CounterpartyManagementView.swift`
- **完了条件**:
  - T番号・既定税務処理・取引履歴が管理できる
- **依存**: P1-003

## P8-005 account merge / category merge / tag merge の移行処理を作る
- **優先度**: P2
- **種別**: 追加
- **目的**: ユーザー拡張性とデータ整合性を両立する
- **完了条件**:
  - 既存取引を壊さず統合できる
- **依存**: P8-001, P8-002, P8-003

---

# Phase 9. OCR / 分類 / 自動化の完成度向上

## P9-001 AI モジュール境界を固定する
- **優先度**: P1
- **種別**: 追加
- **目的**: AI をオンデバイス限定に固定し、税務最終判定に使わないようにする
- **対象**: OCR / classification services
- **実装内容**:
  - AI が返してよいものを型で固定
  - 候補生成のみ許可
  - final decision は rule engine のみ
- **完了条件**:
  - AI が直接仕訳確定しない
- **依存**: P2-008, P3-001

## P9-002 `ClassificationEngine` を候補生成器へ整理する
- **優先度**: P1
- **種別**: 修正
- **対象**: `ClassificationEngine.swift`, `ClassificationLearningService.swift`
- **実装内容**:
  - 勘定科目候補 top-N
  - tax code 候補 top-N
  - counterparty 候補
  - project 候補
  - genre 候補
  - confidence
- **完了条件**:
  - 自動分類の説明責任が持てる
- **依存**: P9-001

## P9-003 学習ルールをローカル永続化する
- **優先度**: P2
- **種別**: 修正
- **対象**: `PPUserRule.swift`, `ClassificationLearningService.swift`
- **実装内容**:
  - 同じ取引先 / 店舗 / キーワードでの過去修正を反映
  - tax code 学習
  - project 割当学習
  - tag 学習
- **完了条件**:
  - ユーザーの修正が端末内で再利用される
- **依存**: P9-002

## P9-004 要確認キューを追加する
- **優先度**: P1
- **種別**: 追加
- **対象**: 新規 `UI/Inbox/ReviewQueueView.swift`
- **目的**: ノーストレス運用を実現する中心画面を作る
- **キュー理由**:
  - 低信頼度
  - 重複疑い
  - T番号未確認
  - 税率混在
  - プロジェクト未決定
  - 科目未確定
  - 年度ロック対象
- **完了条件**:
  - ユーザーが未処理証憑を一箇所で消化できる
- **依存**: P2-008, P9-002

## P9-005 例外説明パネルを追加する
- **優先度**: P2
- **種別**: 追加
- **目的**: 自動仕訳・消費税判定・分類の根拠を見せる
- **完了条件**:
  - すべての posting candidate に explanation を表示できる
- **依存**: P3-001, P4-001

---

# Phase 10. 月次運用・年次運用 UX の再構築

## P10-001 ナビゲーションを業務フロー型に作り直す
- **優先度**: P1
- **種別**: 修正
- **対象**: `ContentView.swift`, Home / Ledger / Report / Dashboard 関連
- **新構成案**:
  - ダッシュボード
  - 受信箱（証憑 / 要確認）
  - プロジェクト
  - 取引
  - 帳簿
  - 申告 / 税務
  - 設定
- **完了条件**:
  - 業務順に使える構造になる
- **依存**: P2-008, P5-001

## P10-002 初期設定ウィザードを追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 最初の制度設定ミスを防ぐ
- **対象**: 新規 onboarding UI
- **入力内容**:
  - 青色 / 白色
  - 65 / 55 / 10 / 現金主義
  - 消費税状態
  - インボイス登録有無
  - 事業開始日
  - 既定口座
  - 業種テンプレート
- **完了条件**:
  - `TaxYearProfile` がウィザードから安全に生成される
- **依存**: P1-001, P7-007

## P10-003 月次締めウィザードを追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 日々の会計をノーストレスにする
- **対象**: 新規 `UI/Books/MonthlyCloseView.swift`
- **ステップ**:
  - 未処理証憑確認
  - 未確定仕訳確認
  - 残高確認
  - 消費税差異確認
  - プロジェクト損益確認
  - 月次ロック
- **完了条件**:
  - 月締めのやることが明確になる
- **依存**: P4-001, P5-001

## P10-004 年次申告パック画面を追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 年末の導線を最短化する
- **対象**: 新規 `UI/Tax/YearEndFilingView.swift`
- **ステップ**:
  - 年次 preflight
  - 棚卸確認
  - 固定資産確認
  - 月別売上確認
  - 収支内訳書 / 青色申告決算書確認
  - XML export
  - 控え PDF 出力
  - 年度ロック
- **完了条件**:
  - 申告に必要な作業が一本道になる
- **依存**: P6-001, P6-009

## P10-005 取引詳細画面を証憑中心に再設計する
- **優先度**: P1
- **種別**: 修正
- **対象**: `TransactionDetailView.swift`, `ReceiptReviewView.swift`
- **実装内容**:
  - 原本
  - 抽出結果
  - ユーザー修正
  - posting candidate
  - 確定仕訳
  - 関連帳簿
  - 関連プロジェクト
- **完了条件**:
  - 1画面でトレーサビリティが見える
- **依存**: P2-002, P3-001

## P10-006 白色専用 UX を追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 白色を青色の縮小版ではなく独立体験にする
- **対象**: White mode UI
- **実装内容**:
  - 簡易記帳モード
  - 収支内訳書必須項目誘導
  - 1日合計記帳支援
  - 明細不足警告
- **完了条件**:
  - 白色ユーザーが迷わない
- **依存**: P5-010, P6-004

---

# Phase 11. Import / 照合 / 検索 / バックアップ

## P11-001 CSV import profile を導入する
- **優先度**: P1
- **種別**: 追加
- **目的**: 銀行 / カード / EC / 既存帳票の柔軟な取り込みを可能にする
- **対象**: `LedgerCSVImportService.swift`, `LedgerCSVImportView.swift`
- **新規**:
  - `Infrastructure/Import/ImportProfile.swift`
  - `Infrastructure/Import/ImportJob.swift`
- **完了条件**:
  - 列マッピングを保存して再利用できる
- **依存**: P3-002

## P11-002 取引照合エンジンを追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 証憑、入出金、仕訳の突合で負担を減らす
- **新規**:
  - `Domain/Transaction/ReconciliationEngine.swift`
- **照合対象**:
  - 証憑 vs 取引
  - 取引 vs 銀行明細
  - 売上 vs 入金
  - 仕入 vs 支払
- **完了条件**:
  - 既存手入力負担が減る
- **依存**: P2-002, P11-001

## P11-003 グローバル検索を追加する
- **優先度**: P2
- **種別**: 追加
- **目的**: 証憑、取引、仕訳、帳簿、取引先、プロジェクトを横断検索する
- **完了条件**:
  - 日付 / 金額 / 取引先 / 摘要 / T番号 / プロジェクトで横断検索できる
- **依存**: P2-005, P5-001

## P11-004 ローカルバックアップ / リストアを追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 完成版会計システムとして最低限必要な復旧手段を持つ
- **対象**: 新規 backup service
- **内容**:
  - DB export
  - evidence file export
  - settings export
  - restore preflight
- **完了条件**:
  - 端末移行と障害復旧が可能
- **依存**: P2-002, P3-001

---

# Phase 12. データ移行

## P12-001 旧 `PPAccountingProfile` から新 `BusinessProfile` / `TaxYearProfile` へ移行する
- **優先度**: P1
- **種別**: 追加
- **目的**: 既存ユーザーの設定を壊さない
- **対象**: 新規 migration
- **完了条件**:
  - 旧データが型変換される
- **依存**: P1-001

## P12-002 旧 `PPTransaction` から `SourceTransaction` + `PostedJournal` へ移行する
- **優先度**: P1
- **種別**: 追加
- **目的**: 既存会計データを救済する
- **実装内容**:
  - 取引を source transaction へ移行
  - 自動生成仕訳を posting candidate or posted journal へ再構成
  - manual / locked は保存
- **完了条件**:
  - 既存データが参照可能で残高が壊れない
- **依存**: P3-001

## P12-003 `PPDocumentRecord` を `EvidenceDocument` に移行する
- **優先度**: P1
- **種別**: 追加
- **完了条件**:
  - 原本ファイル参照が維持される
  - ハッシュが再計算される
- **依存**: P2-002

## P12-004 `LedgerDataStore` 由来の帳簿データを派生化する
- **優先度**: P1
- **種別**: 追加
- **目的**: 旧 ledger データを参照専用 legacy とし、正本から再生成へ切り替える
- **完了条件**:
  - ledger 直接編集が無効化される
- **依存**: P5-001

## P12-005 migration dry-run モードを追加する
- **優先度**: P1
- **種別**: 追加
- **目的**: 本番移行前に結果確認できるようにする
- **完了条件**:
  - 既存データで差分比較ができる
- **依存**: P12-001 から P12-004

---

# Phase 13. テストと品質保証

## P13-001 ドメイン単体テストの全面増強
- **優先度**: P1
- **種別**: 追加
- **対象**: `ProjectProfitTests/Domain/`
- **最低限のケース**:
  - 青色65 / 55 / 10
  - 現金主義
  - 白色
  - 一般課税 / 簡易 / 2割特例
  - 少額特例
  - 80% / 50% 経過措置
  - 8% / 10% 混在
  - 1証憑多行
  - 固定資産混在
  - owner draw / owner contribution
- **完了条件**:
  - 税務コアの主要分岐が unit test 化される
- **依存**: P4-001, P6-001

## P13-002 帳簿ゴールデンテストを作る
- **優先度**: P1
- **種別**: 追加
- **対象**: `ProjectProfitTests/Golden/Books/`
- **完了条件**:
  - 仕訳帳、元帳、現金出納帳、売掛帳、買掛帳、経費帳、白色簡易帳簿、固定資産台帳、証憑台帳の出力が固定比較できる
- **依存**: P5-001

## P13-003 帳票ゴールデンテストを作る
- **優先度**: P1
- **種別**: 追加
- **対象**: `ProjectProfitTests/Golden/Forms/`
- **完了条件**:
  - 青色申告決算書、収支内訳書、消費税集計表の expected 値が比較できる
- **依存**: P6-001

## P13-004 XML schema regression test を作る
- **優先度**: P1
- **種別**: 追加
- **対象**: e-Tax export tests
- **完了条件**:
  - 年度 pack ごとに XML validation が通る
- **依存**: P6-008

## P13-005 migration regression test を作る
- **優先度**: P1
- **種別**: 追加
- **完了条件**:
  - baseline と refactor 後で残高、P/L、B/S が一致する
- **依存**: P12-001 から P12-005

## P13-006 UI フロー試験を作る
- **優先度**: P2
- **種別**: 追加
- **対象**: `UITests/`
- **重要フロー**:
  - 初期設定
  - 証憑取り込み
  - 要確認キュー処理
  - 月次締め
  - 年次申告パック
  - 勘定科目追加
  - 単月全プロジェクト自動配賦
  - 定期取引作成
- **完了条件**:
  - 主要業務導線が壊れない
- **依存**: P10-001

## P13-007 パフォーマンステストを追加する
- **優先度**: P2
- **種別**: 追加
- **内容**:
  - 10,000証憑検索
  - 5,000仕訳元帳出力
  - 年次帳票生成
  - OCR 連続処理
- **完了条件**:
  - 実用的な速度が保たれる
- **依存**: P2-005, P5-001

---

# 6. 既存ファイルごとの修正指示

## 6-1. すぐに差し替えるべき既存ファイル

### `Models/PPAccountingProfile.swift`
- **現状問題**: 制度状態が薄い
- **対応**: 廃止して `BusinessProfile` + `TaxYearProfile` に移行

### `Models/ConsumptionTaxModels.swift`
- **現状問題**: 集計粒度不足
- **対応**: 完全差し替え

### `Services/ConsumptionTaxReportService.swift`
- **現状問題**: 仮受 / 仮払の単純合計
- **対応**: `ConsumptionTaxWorksheetService` に置換

### `Services/AccountingEngine.swift`
- **現状問題**: 単一取引中心、候補と確定の分離なし
- **対応**: 分解して `PostingRuleEngine`, `PostingCandidateBuilder`, `PostingApprovalService` へ

### `Services/ShushiNaiyakushoBuilder.swift`
- **現状問題**: 白色帳票の情報量不足
- **対応**: `FormEngine` の white pack へ統合

### `Services/EtaxFieldPopulator.swift`
- **現状問題**: 青 / 白 / 年度差分を吸収しきれない
- **対応**: `FormFieldMapper` と `FormDerivationEngine` に分割

### `Services/EtaxXtxExporter.swift`
- **現状問題**: year pack 依存が弱い
- **対応**: schema pack 対応版へ置換

### `Services/ReceiptScannerService.swift`
- **現状問題**: receipt 前提
- **対応**: `DocumentIntakeService` へ昇格

### `Ledger/Services/LedgerDataStore.swift`
- **現状問題**: 正本二重管理
- **対応**: 派生 BookEngine に置換、legacy read-only 化

## 6-2. 分割すべき巨大ファイル

### `Models/Models.swift`
- 分割先:
  - `Project/PPProject.swift`
  - `Transaction/SourceTransaction.swift`
  - `Recurring/RecurringTemplate.swift`
  - `Category/PPCategory.swift`
  - `Tags/GenreTag.swift`
  - `Allocation/ProjectAllocation.swift`

### `Services/DataStore.swift`
- 分割先:
  - `Persistence/ProjectRepository.swift`
  - `Persistence/TransactionRepository.swift`
  - `Persistence/PostingRepository.swift`
  - `Persistence/EvidenceRepository.swift`
  - `UseCases/Recurring/*.swift`
  - `UseCases/Transactions/*.swift`

---

# 7. 帳簿と帳票の最終フォーマット指示

## 7-1. 共通フォーマット原則

- A4 印刷前提の PDF を作る
- 日付は日本の帳簿慣行に沿った年 / 月 / 日表示
- 金額は右寄せ
- 0 は表示方針を統一する
  - 法定帳票は原則空欄優先
  - 内部帳簿は 0 表示可
- ヘッダに以下を必ず持つ
  - 帳簿名
  - 屋号 / 氏名
  - 年分または期間
  - 作成日時
- 監査 / 管理用出力では追加列を許可するが、法定表示では控える
- 科目別帳簿は科目名をヘッダ表示
- 取引先別帳簿は取引先名をヘッダ表示
- carry forward 行と closing balance 行を明示する

## 7-2. PDF 出力ルール

- 法定帳簿レイアウトは印刷で崩れないこと
- 自動改ページ時はヘッダ再掲
- 差引残高はページ跨ぎ後も継続
- 取引行の折返しは摘要だけに限定
- OCR や証憑サムネイルを法定帳簿に埋め込まない

## 7-3. CSV / Excel 出力ルール

- 数値セルは数値として出力
- 並び順は PDF と一致
- 機械読込用 export と閲覧用 export を分ける
- UTF-8 with BOM / Excel 互換性を担保

---

# 8. これをやらないと「完成」と呼べない必須リスト

以下が未完なら、このリファクタリングは完了扱いにしてはいけない。

- `isBlueReturn: Bool` が残っている
- `LedgerDataStore` が入力正本として残っている
- `ConsumptionTaxSummary` が 3 値のまま
- 50% 経過措置が未実装
- 白色簡易帳簿が未完成
- 青色申告決算書 4 ページが埋まらない
- 収支内訳書の明細欄が埋まらない
- 証憑検索が日付 / 金額 / 取引先でできない
- PDF と XML の区別が UI 上曖昧
- 単月の全プロジェクト自動分配がない
- 定期取引の該当月自動分配が idempotent でない
- ユーザー勘定科目追加が帳票に反映できない
- ジャンル追加ができない
- 年度ロックが証憑 / 取引 / 仕訳 / 帳票に一貫して効かない

---

# 9. 完成判定チェックリスト

## 9-1. 制度面
- [ ] 青色 65 / 55 / 10 / 現金主義が分岐できる
- [ ] 白色申告が独立フローで完結する
- [ ] 一般課税 / 簡易課税 / 2割特例が切り替わる
- [ ] 少額特例、80%、50% 経過措置が機能する
- [ ] 電子帳簿 / 電子取引保存の状態管理がある

## 9-2. 会計面
- [ ] 仕訳正本が 1 系統
- [ ] 元帳、補助簿、P/L、B/S が一致する
- [ ] 固定資産、棚卸、期首、決算整理が機能する

## 9-3. 証憑面
- [ ] 原本が保存される
- [ ] OCR 結果と修正履歴が残る
- [ ] 検索できる
- [ ] 証憑 -> 仕訳 -> 帳簿 -> 帳票 が追跡できる

## 9-4. UX 面
- [ ] 未処理証憑を受信箱で処理できる
- [ ] 月次締めウィザードがある
- [ ] 年次申告パックがある
- [ ] 白色専用 UX がある
- [ ] 自動配賦 preview がある

## 9-5. 汎用性
- [ ] 勘定科目を追加できる
- [ ] ジャンルを追加できる
- [ ] 業種テンプレートを切り替えられる
- [ ] 単月全プロジェクト自動配賦ができる
- [ ] 定期取引の月次 / 年次 / 配賦ルールが実用レベル

---

# 10. 最短の実装順序

本当に迷ったら、この順番でやる。

1. Phase 0 全部
2. P1-001 から P1-007
3. P2-001 から P2-008
4. P3-001 から P3-007
5. P4-001 から P4-006
6. P5-001 から P5-016
7. P6-001 から P6-009
8. P7-001 から P7-005
9. P8-001 から P8-004
10. P10-001 から P10-006
11. P11-001 から P11-004
12. P12-001 から P12-005
13. P13-001 から P13-007
14. 残りの P2 / P3 優先度タスク

---

# 11. 実装開始時の最初の 20 タスク

着手順を固定するため、最初の 20 個を明示する。

1. P0-001 baseline tag
2. P0-002 golden dataset
3. P0-004 diff tools
4. P1-001 BusinessProfile / TaxYearProfile
5. P1-002 TaxYearPack
6. P1-003 Counterparty
7. P1-007 PPAccount 完成版化
8. P2-001 DocumentIntakeService
9. P2-002 EvidenceDocument
10. P2-003 保存期間ロジック修正
11. P2-008 PostingCandidate
12. P3-001 PostingEngine
13. P3-003 税込 / 税抜厳密化
14. P3-004 複合仕訳対応
15. P4-001 ConsumptionTaxWorksheet
16. P4-002 TaxCode master
17. P4-003 少額特例 / 80 / 50 / 2割特例
18. P5-001 BookEngine
19. P5-002 BookSpecs
20. P6-001 FormEngine

この 20 個が通るまで、細かな UI 改善や見た目調整は後回しにする。

---

# 12. 制度根拠メモ

この仕様書は、少なくとも次の制度要件を反映している。

- 青色申告特別控除は 65万円 / 55万円 / 10万円の区分があり、現金主義は別帳票系統を要する
- 白色申告者にも記帳と帳簿書類保存、および収支内訳書添付が必要
- インボイスは登録番号、取引日、税率ごとの対価額、税率ごとの税額などの記載が必要
- 適格請求書等の保存期間は原則 7 年
- 少額特例、80% / 50% 経過措置、2割特例は有効期間管理が必要
- 優良な電子帳簿には訂正削除履歴、相互関連性、検索機能が必要
- 収支内訳書 / 青色申告決算書は e-Tax で XML 形式提出対象であり、PDF 画像提出対象ではない
- e-Tax 仕様書は毎年更新されるため、年分 pack 化が必要

---

# 13. 参考資料

- 国税庁 タックスアンサー No.2072 青色申告特別控除
- 国税庁 タックスアンサー No.2080 白色申告者の記帳・帳簿等保存制度
- 国税庁 タックスアンサー No.6496 仕入税額控除をするための帳簿及び請求書等の保存
- 国税庁 タックスアンサー No.6497 仕入税額控除のために保存する帳簿及び請求書等の記載事項
- 国税庁 タックスアンサー No.6625 適格請求書等の記載事項
- 国税庁 インボイス制度 Q&A 問112 少額特例、問113 経過措置、問114 2割特例
- 国税庁 優良な電子帳簿の要件
- 国税庁 電子取引データの保存方法に関する資料
- 国税庁 令和7年分 収支内訳書（一般用）の書き方
- 国税庁 令和7年分 青色申告決算書（一般用）の書き方
- e-Tax 申告手続（所得税確定申告等）
- e-Tax イメージデータによる提出対象の注意事項
- e-Tax 仕様書更新情報（令和8年2月26日更新分）

---



## 13.1 参考URLメモ

- https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/2072.htm
- https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/2080.htm
- https://www.nta.go.jp/taxes/shiraberu/taxanswer/shohi/6625.htm
- https://www.nta.go.jp/taxes/shiraberu/zeimokubetsu/shohi/keigenzeiritsu/pdf/qa/112.pdf
- https://www.nta.go.jp/taxes/shiraberu/zeimokubetsu/shohi/keigenzeiritsu/pdf/qa/113.pdf
- https://www.nta.go.jp/taxes/shiraberu/zeimokubetsu/shohi/keigenzeiritsu/pdf/qa/114.pdf
- https://www.nta.go.jp/law/joho-zeikaishaku/sonota/jirei/05.htm
- https://www.e-tax.nta.go.jp/tetsuzuki/shinkoku/shinkoku01.htm
- https://www.e-tax.nta.go.jp/imagedata/imagedata1.htm
- https://www.e-tax.nta.go.jp/topics/2026/topics_20260226_shiyo.htm
- https://www.nta.go.jp/taxes/shiraberu/shinkoku/tebiki/2025/pdf/034.pdf
- https://www.nta.go.jp/taxes/shiraberu/shinkoku/tebiki/2025/pdf/037.pdf

# 14. 最終メッセージ

このタスクリストの本質は、機能を増やすことではない。

**会計の正本、税務の状態、証憑の保存、帳簿の派生、帳票の提出、プロジェクト配賦の6つを、矛盾なく1本の流れにすること** が本質である。

いまの ProjectProfit は、良い部品をすでに多く持っている。
しかし完成品にするには、

- 正本を 1 つにする
- 制度を `Bool` で持たない
- 消費税を作り直す
- 帳簿を派生化する
- 白色を独立モードにする
- 定期取引と配賦を汎化する

この6点が絶対条件になる。

この文書どおりに実装すれば、
**「個人事業主向け・プロジェクト別管理・オンデバイスAI限定」のコンセプトを壊さずに、完成版会計システムへ到達できる。**
