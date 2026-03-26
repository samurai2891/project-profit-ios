# ProjectProfit 12週間 実装スプリント計画
## 個人事業主向け・プロジェクト別会計システム完成までの実行計画

作成日: 2026-03-01  
対象: ProjectProfit 全面リファクタリング  
前提: **コンセプトは維持**

- 個人事業主向け
- プロジェクトごとに管理できる
- 会計と申告をノーストレス化する
- AI はオンデバイス限定
- 青色申告 / 白色申告 / インボイス / 消費税 / e-Tax を扱う
- 定期取引、該当月自動分配、全プロジェクト一括配賦、勘定科目追加、ジャンル追加を標準装備する

> 現況注記（2026-03-07）
> この文書の週次配分は原計画として維持する。現行 repo では Week 7 以降に置かれていた `EvidenceInbox`、`ApprovalQueue`、migration dry-run、backup / restore、golden / canonical E2E、release CI まで前倒しで入っている。
> 一方で、Week 9-11 相当の `Recurring` 承認化、canonical 帳簿一本化、`FormEngine`、`ExportCoordinator` 本線統合は完了していない。
> 現況の優先順位は `release_ticket_list.md` を優先する。

---

# 0. このスプリント計画の目的

この文書は、すでに作成した以下 2 つの成果物を、**12週間で動く実装計画** に落とし込んだものです。

- 完全リファクタリング指示書
- 実装タスク一覧（WBS）

今回のゴールは、「何を作るか」ではなく、**12週間でどう作り切るか** を定義することです。

したがって、この文書では以下を明確にします。

1. 12週間での到達点
2. 週ごとのゴール
3. 各週の必須成果物
4. 依存関係とクリティカルパス
5. 各週の完了条件（Definition of Done）
6. リスクと回避策
7. 週末デモ / レビュー観点
8. どの順番で切ると失敗しないか

---

# 1. 12週間で目指す到達点

## 1-1. 12週終了時の完成定義

12週終了時点で、以下が **実利用レベル** で動いていることを完成条件とする。

### A. 正本設計
- 証憑 → 取引候補 → 仕訳候補 → 確定仕訳 の一本化が完了
- 旧 `DataStore` と `LedgerDataStore` の二重正本が解消
- 帳簿はすべて `PostedJournal` から派生生成

### B. 税務状態
- 青色 65 / 55 / 10 万、青色現金主義、白色を切り替え可能
- 課税 / 免税 / 一般課税 / 簡易課税 / 2割特例を切替可能
- 少額特例、80% / 50% 経過措置を扱える

### C. 証憑基盤
- カメラ / 写真 / PDF / Files / Share Sheet / CSV から証憑・明細を取り込める
- OCR はオンデバイス
- 証憑台帳、検索、訂正削除履歴、ハッシュ、原本保持がある

### D. 会計実務
- 仕訳帳、総勘定元帳、現金出納帳、預金出納帳、売掛帳、買掛帳、経費帳、固定資産台帳、棚卸台帳、プロジェクト別補助元帳を生成できる
- 定期取引の該当月自動分配が動く
- 単月の全プロジェクト一括配賦が動く
- ユーザーが勘定科目 / ジャンル / ルールを追加できる

### E. 帳票・申告
- 収支内訳書（一般用）
- 青色申告決算書（一般用）
- 青色申告決算書（現金主義用）
- 消費税集計表
- e-Tax XML

### F. UX
- 証憑 Inbox → 候補確認 → 確定 → 月締め → 年締め → 帳票生成 の流れが通る
- プロジェクト別管理が主役のまま残る

---

# 2. この12週間の前提条件

## 2-1. スコープ前提

この 12 週間で含める範囲:

- 会計正本設計
- 証憑台帳
- 消費税エンジン
- 主要帳簿
- 青色 / 白色帳票
- e-Tax XML
- 定期取引 + プロジェクト自動分配
- ユーザー拡張マスタ
- 月締め / 年締め
- CSV import / backup / restore

この 12 週間では **原則として含めない** 範囲（Release 1.1 以降候補）:

- 銀行 API 直接連携
- 複数ユーザー承認ワークフロー
- クラウド同期
- Web版
- 請求書発行機能のフル実装
- 給与計算フル機能

> ただし、将来拡張しやすいようにデータモデルは先に用意してよい。

## 2-2. 推奨体制

この計画は **3〜4名の専任体制** を想定すると現実的です。

### 推奨ロール
- Tech Lead / Domain Architect × 1
- iOS / SwiftUI / UX 実装 × 1
- Data / Tax / Books / Export 実装 × 1
- QA / Automation / Tooling × 1（兼務可）

### 2名体制なら
- 12週間はかなりタイト
- UI polish と import/export の一部を後ろ倒しにする必要がある

### 1名体制なら
- 12週間は仕様固め + 核実装までと考えるべき
- 完成版は 20〜28週レンジが現実的

---

# 3. 実装戦略の基本方針

## 3-1. 先に UI を直さない

最初にやるべきは UI ではない。

先にやるべきは以下。

1. 正本一本化
2. 年分プロフィールと税務状態マシン
3. 証憑台帳
4. Posting / Distribution / Tax engine
5. 帳簿 projection
6. Form engine

UI はそのあとに再構成する。

## 3-2. 旧機能は即削除しない

各フェーズで以下の順序を守る。

1. 新規実装
2. 旧機能と並走比較
3. 差分比較
4. 移行
5. 旧コード削除

## 3-3. 税年パックは最初に土台を作る

法改正と e-Tax 仕様更新に耐えるため、`TaxYearPack` の土台を早期に作る。

## 3-4. AI は最後まで補助に留める

AI の役割:
- OCR
- 候補抽出
- 候補分類
- 信頼度付与

AI の役割ではないもの:
- 税務上の最終判定
- 帳簿への確定反映
- 控除可否の最終決定

---

# 4. 12週間の全体マップ

## 4-1. 6スプリント構成（2週間単位）

- **Sprint 1 / Week 1-2**: 基盤凍結・新ドメイン・正本設計着手
- **Sprint 2 / Week 3-4**: 永続化・移行・税務状態マシン・TaxYearPack 骨組み
- **Sprint 3 / Week 5-6**: 証憑台帳・Document Intake・仕訳候補・自動化基盤
- **Sprint 4 / Week 7-8**: 帳簿 projection・定期取引・一括配賦・月締め基盤
- **Sprint 5 / Week 9-10**: 消費税集計表・白色/青色帳票・e-Tax 前処理
- **Sprint 6 / Week 11-12**: UI 統合・回帰・移行・リリース準備

## 4-2. クリティカルパス

以下が遅れると全体が遅れる。

1. `TaxYearProfile` と税務状態マシン
2. `EvidenceDocument` と証憑台帳
3. `PostedJournal` 正本化
4. `ConsumptionTaxWorksheet`
5. `FormEngine`
6. `ETaxExportService`

---

# 5. Sprint 1（Week 1-2）
## テーマ: 現行凍結、正本設計、新ドメインの土台を作る

---

## Week 1 ゴール

### 目的
- 現行システムを壊さないための比較基準を作る
- 新ドメインの骨格を確定する
- 旧正本の二重化ポイントを洗い出す

### 実装タスク

#### W1-T1 現行機能インベントリ作成
- 現行モデル一覧
- サービス一覧
- View / ViewModel 一覧
- 出力物一覧（PDF / CSV / XML）
- テスト一覧
- 既知不具合一覧
- 画面キャプチャ保存

**成果物**
- `docs/refactor-baseline/current-system-inventory.md`
- `docs/refactor-baseline/output-samples/`

**Done**
- 誰が見ても現行機能の全体像が分かる

#### W1-T2 現行データモデルの依存関係図を作る
- `PPAccountingProfile`
- `PPTransaction`
- `PPJournalEntry`
- `PPDocumentRecord`
- `PPFixedAsset`
- `PPInventoryRecord`
- `LedgerDataStore` 系モデル

**成果物**
- `docs/refactor-baseline/data-model-graph.md`

**Done**
- 旧正本がどこで分裂しているか説明できる

#### W1-T3 新 canonical domain のディレクトリだけ先に作る
- `Domain/Business`
- `Domain/Tax`
- `Domain/Evidence`
- `Domain/Posting`
- `Domain/Books`
- `Domain/Forms`
- `Domain/Automation`

**Done**
- 新設先がブレない

#### W1-T4 `BusinessProfile` / `TaxYearProfile` の仕様を固定する
- old `PPAccountingProfile` の置換先を決める
- enum を固定する
- 税務状態の責務分離を確定する

**Done**
- `isBlueReturn: Bool` の終わりを定義できる

#### W1-T5 比較用 Golden Dataset の設計
- 青色 65
- 青色 10
- 青色現金主義
- 白色
- 課税一般
- 2割特例
- 80% / 50%
- 少額特例
- 軽減税率混在
- 定期取引全プロジェクト配賦

**Done**
- 12週を通して比較するサンプル年分が確定する

### Week 1 デモ
- 現行システムインベントリ
- 旧正本分裂図
- 新 canonical domain スケルトン
- 比較用データセット仕様

### Week 1 リスク
- 現行コードに欠落ファイルがある可能性
- UI ファイルの参照と実ファイル不整合
- 旧 ledger 系が意外に多くの責務を持っている可能性

### Week 1 回避策
- xcodeproj 参照一覧も別途比較対象にする
- 足りないファイルは compile target 単位で洗い出す

---

## Week 2 ゴール

### 目的
- 新しいドメインモデルをコード化する
- Migration 方針を決める
- Repository へ向かう土台を作る

### 実装タスク

#### W2-T1 `BusinessProfile` を実装
- 屋号
- 氏名
- 住所
- 開業日
- 基本情報

#### W2-T2 `TaxYearProfile` を実装
- `filingStyle`
- `blueDeductionLevel`
- `bookkeepingBasis`
- `vatStatus`
- `vatMethod`
- `invoiceIssuerStatus`
- `electronicBookLevel`
- `yearLockState`
- `taxYearPackId`

#### W2-T3 `Counterparty` を実装
- T番号
- 法人番号
- 既定勘定科目
- 既定税区分
- aliases

#### W2-T4 `Genre` / `IndustryPreset` を実装
- ジャンル自由追加
- 業種プリセットの土台

#### W2-T5 `EvidenceDocument` / `EvidenceVersion` モデルを実装
- 原本
- OCR 結果
- 修正結果
- 監査情報

#### W2-T6 `PostedJournal` / `PostedJournalLine` モデルを実装
- 候補ではなく確定正本
- reversal 前提の設計

#### W2-T7 `DistributionRule` モデルを実装
- recurring 用
- 月次一括配賦用
- 固定比率 / 売上比 / 均等配分

#### W2-T8 旧→新 migration spec を作成
- `PPAccountingProfile` → `BusinessProfile` + `TaxYearProfile`
- `PPDocumentRecord` → `EvidenceDocument`
- `PPJournalEntry` → `PostedJournal`

### Week 2 Done
- 新ドメインモデルのコンパイルが通る
- enum / state の命名が固まる
- migration specification が文書化される

### Week 2 デモ
- 新 domain models の一覧
- old→new マッピング表
- `TaxYearProfile` が持つべき税務状態の確認

---

# 6. Sprint 2（Week 3-4）
## テーマ: Repository 化、旧正本からの移行、TaxYearPack と税務状態マシン

---

## Week 3 ゴール

### 目的
- `DataStore` を分解し始める
- 正本一本化への移行を開始する
- 旧 `LedgerDataStore` を authoritative store から降ろし始める

### 実装タスク

#### W3-T1 Repository 層のスケルトン実装
- `BusinessProfileRepository`
- `TaxYearProfileRepository`
- `EvidenceRepository`
- `CounterpartyRepository`
- `PostingRepository`
- `RecurringRepository`

#### W3-T2 `DataStore` から読み書きを切り出す
- 旧 UI が壊れないように facade を残す
- 裏では新 repository を通す準備をする

#### W3-T3 `LedgerDataStore` 依存点の棚卸し
- どこで ledger 側を正本として見ているか特定
- projection だけで済む箇所を分類

#### W3-T4 `MigrationRunner` スケルトン実装
- dry-run
- 件数比較
- 孤立データ検知

#### W3-T5 `AuditEvent` / `YearLock` スケルトン実装
- 月次締め
- 年次締め
- 解除理由

### Week 3 Done
- 新 repository 経由の読み書きが一部で動く
- migration dry-run の入口がある
- 旧正本→新正本への経路がコード上に存在する

### Week 3 デモ
- repository 経由保存の確認
- migration dry-run 画面またはログ出力

---

## Week 4 ゴール

### 目的
- TaxYearPack の骨組みを作る
- 税務状態マシンを実装する
- 青色 / 白色 / 消費税方式の分岐を UI ではなくドメインで持たせる

### 実装タスク

#### W4-T1 `TaxYearPack` ローダーを実装
- `TaxYearPack/2025/`
- `TaxYearPack/2026/`
- field map / validation rule / labels をロード

#### W4-T2 `FilingStyleEngine` を実装
- 青色一般
- 青色現金主義
- 白色

#### W4-T3 `BlueDeductionEngine` を実装
- 65 / 55 / 10
- e-Tax / 優良な電子帳簿要件と接続可能な状態を持つ

#### W4-T4 `VATStatus` / `VATMethod` 切替ロジックを実装
- 免税
- 課税一般
- 簡易課税
- 2割特例

#### W4-T5 `TaxCode` マスタ定義
- 売上10 / 売上8
- 仕入10適格 / 8適格
- 80% / 50%
- 少額特例
- 非課税 / 不課税 / 対象外

#### W4-T6 `PurchaseCreditMethod` 列挙を実装
- `qualifiedInvoice`
- `transitional80`
- `transitional50`
- `smallAmountSpecial`
- `noCredit`

### Week 4 Done
- 旧 `PPAccountingProfile` 依存でなく税務状態を保持できる
- TaxYearPack の雛形でフォーム/ルールの年次差分を吸収できる

### Week 4 デモ
- `TaxYearProfile` 設定による UI / rule の切替確認
- 2025 / 2026 pack 切替の skeleton 動作

---

# 7. Sprint 3（Week 5-6）
## テーマ: 証憑台帳・Document Intake・仕訳候補・自動化基盤

---

## Week 5 ゴール

### 目的
- レシート中心実装をやめ、証憑中心へ移す
- OCR と抽出結果を正本とは切り離す

### 実装タスク

#### W5-T1 `DocumentIntakePipeline` を新設
- `DocumentImportService`
- `OnDeviceOCRService`
- `DocumentClassifier`
- `DuplicateDetectionService`

#### W5-T2 import チャネルを整理
- カメラ
- 写真
- PDF
- Files
- Share Sheet
- CSV

#### W5-T3 `EvidenceVersion` 保存実装
- original
- OCR
- corrected
- approved extraction

#### W5-T4 T番号抽出を実装
- `T` + 13 桁抽出
- OCR ノイズ補正
- Counterparty 照合

#### W5-T5 税率別ブロック抽出を実装
- 10%
- 8%
- 税率別税額
- 税込 / 税抜判定補助

#### W5-T6 信頼度スコアリングを実装
- OCR 品質
- 金額一致
- 取引先一致
- T番号一致
- 税率整合

### Week 5 Done
- 証憑原本 + OCR + 修正結果が保存できる
- 証憑から T番号と税率別情報が抽出できる
- AI 非対応時も rule-based にフォールバックする

### Week 5 デモ
- レシート/請求書/PDF の取り込み
- T番号候補抽出
- 重複検知のサンプル

---

## Week 6 ゴール

### 目的
- OCR結果からいきなり仕訳確定しない構造へ移行する
- PostingCandidate ベースの review flow を作る

### 実装タスク

#### W6-T1 `TransactionCandidate` / `PostingCandidate` を実装
- source = evidence / csv / recurring / manual
- state = draft / suggested / needsReview / approved

#### W6-T2 `CandidateBuilder` 実装
- 勘定科目候補
- 税区分候補
- プロジェクト配賦候補
- ジャンル候補
- 取引先候補

#### W6-T3 `UserRuleEngine` 実装
- キーワード
- 取引先
- 金額帯
- 証憑種別
- 既往修正履歴

#### W6-T4 Review Queue を実装
- high confidence 自動承認候補
- low confidence 要確認
- duplicate 疑い
- T番号不整合

#### W6-T5 On-device learning memory 実装
- ユーザー修正履歴を次回候補へ反映

### Week 6 Done
- 候補生成 → 確認 → 承認 の流れが動く
- OCR 結果が即正本にならない

### Week 6 デモ
- 証憑から候補生成
- 候補修正
- 承認後に posted journal へ流れる手前まで確認

---

# 8. Sprint 4（Week 7-8）
## テーマ: 帳簿 projection・定期取引・単月全プロジェクト配賦・締め基盤

---

## Week 7 ゴール

### 目的
- 確定仕訳から帳簿を派生生成する
- ledger 正本を projection へ置き換える

### 実装タスク

#### W7-T1 `PostedJournal` への posting を実装
- manual
- evidence-based
- recurring-based
- CSV-based
- adjustment

#### W7-T2 `BookProjectionEngine` を実装
- general journal
- general ledger
- cash book
- bank book
- expense book
- A/R ledger
- A/P ledger

#### W7-T3 `BookSpecRegistry` を実装
- 列定義
- 表示順
- CSV 順序
- PDF 表示ルール

#### W7-T4 `BookValidationService` 1st version
- 借貸一致
- 元帳残高整合
- 試算表整合

#### W7-T5 `LedgerDataStore` の projection 化
- 旧 ledger 画面には projection を渡す
- 正本保存を止める

### Week 7 Done
- 主要帳簿が `PostedJournal` から生成できる
- `LedgerDataStore` を authoritative に使わない経路が動く

### Week 7 デモ
- 同じ posted journal から複数帳簿を生成
- general ledger と expense book の一致確認

---

## Week 8 ゴール

### 目的
- recurring と project distribution を完成に近づける
- 月締め基盤を作る

### 実装タスク

#### W8-T1 recurring 再設計
- recurring template
- generation timing
- freeze generated month
- stop / resume
- version history

#### W8-T2 該当月自動分配を実装
- recurring に配賦ルールを持たせる
- active projects of month を取得する
- 端数処理を選べる

#### W8-T3 単月の全プロジェクト一括配賦を実装
- 対象月選択
- 対象取引集合選択
- 配賦方式選択
- preview diff
- approval 実行

#### W8-T4 配賦方式を実装
- active project 均等
- 選択 project 均等
- 固定比率
- 売上比
- 予算比
- 手動 + テンプレート化

#### W8-T5 月締め基盤を実装
- 未承認候補確認
- 未照合確認
- recurring 未生成確認
- month lock

### Week 8 Done
- recurring の該当月自動分配が実用レベルで動く
- 単月全プロジェクト一括配賦が preview 付きで実行できる
- 月締めの入口が存在する

### Week 8 デモ
- 毎月家賃を active project 均等配賦
- 当月の共通広告費を全案件へ一括配賦

---

# 9. Sprint 5（Week 9-10）
## テーマ: 消費税集計表・白色/青色帳票・e-Tax 前処理

---

## Week 9 ゴール

### 目的
- 消費税エンジンを完成させる
- 税率別・制度別・根拠別集計を作る

### 実装タスク

#### W9-T1 `ConsumptionTaxWorksheet` 実装
- 標準税率課税売上高
- 軽減税率課税売上高
- 税率別税額
- 仕入税額控除根拠別集計
- 控除税額小計
- 差引税額

#### W9-T2 少額特例判定を実装
- 1万円未満
- 一回の取引単位判定
- 適用期間判定
- 事業者規模判定

#### W9-T3 経過措置 80% / 50% を実装
- 取引日ベース切替
- 非適格仕入の控除率計算

#### W9-T4 2割特例を実装
- 対象者判定
- 対象期間判定
- 計算ロジック

#### W9-T5 消費税集計表 UI を実装
- 標準 / 軽減
- 国税 7.8 / 6.24 参考列
- ユーザー追加経費行
- プロジェクト別参考表示
- 事業全体の申告値表示

### Week 9 Done
- ユーザー添付の消費税集計表に近い粒度のワークシートが出る
- 少額特例・80/50・2割特例を切替できる

### Week 9 デモ
- 8%/10% 混在レシートの税集計
- 80% / 50% / 少額特例の比較
- 2割特例計算プレビュー

---

## Week 10 ゴール

### 目的
- 収支内訳書・青色申告決算書を major pages まで完成させる
- FormEngine と e-Tax 前処理を通す

### 実装タスク

#### W10-T1 `FormEngine` 実装
- legal line registry
- account→tax line mapping
- field mapping
- field completeness check

#### W10-T2 収支内訳書（一般用）実装
- 1ページ目主要欄
- 2ページ目売上先/仕入先/減価償却/地代家賃/利子割引料
- 空欄経費行のユーザー拡張

#### W10-T3 青色申告決算書（一般用）実装
- 1ページ目 損益計算書
- 2ページ目 月別売上・給与等
- 3ページ目 減価償却・地代家賃等
- 4ページ目 貸借対照表

#### W10-T4 青色現金主義用を実装
- 別 form route
- 別 validator

#### W10-T5 `ETaxPreflightValidator` を実装
- 必須項目
- 禁止文字
- 桁数
- 年分 pack 整合

### Week 10 Done
- 白色/青色帳票 preview が出せる
- e-Tax XML 生成前の不足項目が分かる

### Week 10 デモ
- 白色ケースの収支内訳書 preview
- 青色ケースの青色申告決算書 preview
- 欠損項目の preflight エラー表示

---

# 10. Sprint 6（Week 11-12）
## テーマ: UI 統合・回帰・移行・リリース準備

---

## Week 11 ゴール

### 目的
- 新 UX を一本化する
- 出力系・import 系・backup をまとめる

### 実装タスク

#### W11-T1 情報設計を新 IA へ統合
- ホーム
- 証憑 Inbox
- 取引候補
- 帳簿
- プロジェクト
- 申告
- 設定

#### W11-T2 ホームを「やること中心」に再設計
- 未処理証憑
- 要確認候補
- 月締めタスク
- 年締めタスク
- 申告準備状況

#### W11-T3 ExportCoordinator 実装
- PDF
- CSV
- Excel
- XML

#### W11-T4 Backup / Restore UI 実装
- 年分バックアップ
- 全体バックアップ
- dry-run restore

#### W11-T5 CSV Import Profile 実装
- 銀行 CSV
- カード CSV
- 他社形式取り込みの下地

#### W11-T6 ChartOfAccounts / Genre / Counterparty 管理 UI 完成
- 追加/編集/アーカイブ
- legal mapping
- default rules

### Week 11 Done
- UI が新 canonical flow に揃う
- import / export / backup の最低限が揃う

### Week 11 デモ
- Inbox から帳簿・申告までの通し
- backup/export/import の確認

---

## Week 12 ゴール

### 目的
- 回帰・移行・リリース判定を行う
- 旧正本コードの撤去を開始する

### 実装タスク

#### W12-T1 Golden / snapshot / migration テスト全実行
- 帳簿
- 帳票
- XML
- migration
- recurring + distribution
- tax worksheet

#### W12-T2 Parallel Run 実施
- 旧帳簿系と新帳簿系の比較
- 差分ログ作成

#### W12-T3 migration dry-run on real-ish data
- 件数比較
- 金額比較
- 孤立証憑確認
- 孤立仕訳確認

#### W12-T4 リリースブロッカー潰し
- P0 未完了
- 重大 UX 不整合
- 税計算差異
- e-Tax preflight blocker

#### W12-T5 旧 ledger 正本経路を read-only 化
- 新規データの流入停止
- projection 専用 or legacy 閲覧専用へ切替

#### W12-T6 Release Checklist 実施
- backup
- migration
- tax year pack
- XML validation
- month/year close
- on-device AI only guard
- print/export

### Week 12 Done
- 新 canonical flow で主要シナリオが通る
- 旧正本依存が外れる
- リリース可否判断ができる

### Week 12 デモ
- 白色ユーザーシナリオ通し
- 青色 65 万ケース通し
- 消費税対応ケース通し
- recurring + 全プロジェクト配賦通し

---

# 11. 毎週並走させる横断トラック

12 週間の間、以下は毎週並走で進める。

## 11-1. Testing Track
- 新規 domain test
- rule test
- projection test
- form test
- migration test
- snapshot update review

## 11-2. TaxYearPack Track
- 2025 pack
- 2026 pack
- labels / validation rule / field mapping
- spec diff log

## 11-3. Performance Track
- OCR latency
- projection generation speed
- search speed
- export speed

## 11-4. Compliance Track
- evidence retention
- searchability
- revision history
- lock behavior
- XML preflight

## 11-5. Documentation Track
- ADR（Architecture Decision Record）
- migration notes
- account/tax line mapping spec
- distribution rule spec
- form line spec

---

# 12. 週ごとの成果物一覧

## Week 1
- 現行インベントリ
- baseline samples
- 新 domain skeleton

## Week 2
- BusinessProfile / TaxYearProfile / Counterparty / Evidence / Journal domain
- migration spec

## Week 3
- repository skeleton
- migration runner skeleton
- year lock skeleton

## Week 4
- TaxYearPack skeleton
- filing/tax state engine
- tax code master

## Week 5
- DocumentIntakePipeline
- OCR + extraction + T番号 + tax block extraction

## Week 6
- TransactionCandidate / PostingCandidate / Review queue
- local learning rule memory

## Week 7
- BookProjectionEngine
- general journal / ledger / cash / bank / expense / AR / AP

## Week 8
- recurring v2
- monthly distribution batch
- month close foundation

## Week 9
- ConsumptionTaxWorksheet
- 少額特例 / 80% / 50% / 2割特例

## Week 10
- WhiteReturnBuilder
- BlueReturnBuilder
- ETaxPreflightValidator

## Week 11
- 新 IA 統合 UI
- ExportCoordinator
- Backup/Restore
- CSV import

## Week 12
- parallel run
- migration dry-run
- release checklist
- legacy ledger freeze

---

# 13. 重要な設計判断（週内で迷わないためのルール）

## 13-1. 迷ったら証憑を正本に近づける
- 取引から逆算するのではなく、証憑から帳簿へ落とす

## 13-2. 迷ったら税務状態を `TaxYearProfile` に集約する
- UI 条件分岐に埋め込まない

## 13-3. 迷ったら帳簿は projection にする
- 直接編集させない

## 13-4. 迷ったら AI を補助に留める
- 「自動確定」より「高速承認」を目指す

## 13-5. 迷ったらプロジェクトは管理会計軸と考える
- 法定帳票の主キーにしない

---

# 14. リスク一覧と回避策

## R1. 旧 `LedgerDataStore` の責務が大きすぎる
### 回避策
- Week 3 に責務棚卸しを必ずやる
- 並走期間を設ける
- view/export 用だけ残す

## R2. `TaxYear2025.json` からの移行時に form mapping が壊れる
### 回避策
- TaxYearPack を早期に skeleton 化
- Week 10 より前に mapping spec を固める

## R3. OCR 精度の個体差
### 回避策
- OCR と extraction を分離
- low confidence を review queue へ送る
- AI 非依存 fallback を先に作る

## R4. 消費税ロジックが後半で爆発する
### 回避策
- Week 4 で tax code master を先に固める
- Week 9 で worksheet を最優先実装する

## R5. UI を先に作りすぎて手戻りする
### 回避策
- Week 1-8 は UI を最小限に留める
- Week 11 で統合する

## R6. 12週間で多機能すぎる
### 回避策
- 非同期に進めるトラックを分離する
- P0/P1/P2 を厳密運用する
- 銀行 API 等はスコープ外にする

---

# 15. P0 / P1 / P2 の扱い

## P0（12週で必ず終える）
- 正本一本化
- TaxYearProfile / tax state machine
- EvidenceDocument
- PostingCandidate / PostedJournal
- DistributionRule
- ConsumptionTaxWorksheet
- White/Blue form major pages
- ETax preflight
- recurring + monthly distribution
- account / genre / counterparty masters
- backup / migration dry-run

## P1（12週内にできれば必須）
- source withholding support
- 他社会計ソフト import profile
- advanced reconciliation
- 口座/カード UI polish
- performance optimization 追加

## P2（12週後でもよいが準備だけしておく）
- direct bank API
- multi-business support
- cloud sync
- invoice issuing
- payroll full stack

---

# 16. スプリントレビューで毎回確認すべきチェックリスト

## 機能
- 今週追加した新機能は canonical flow に乗っているか
- 旧正本へ逆流していないか

## 税務
- 税務ロジックが UI if 文に埋まっていないか
- year pack に寄せられているか

## 帳簿
- projection で再計算可能か
- 表示だけのローカル state で誤魔化していないか

## UX
- 1 画面で情報過多になっていないか
- 証憑→候補→確定の導線が短いか

## 非機能
- 重い処理を main thread に置いていないか
- 原本ファイルの保護があるか
- audit log が抜けていないか

---

# 17. 12週間終了時のリリース判断基準

リリース可能とみなすのは次を満たしたときのみ。

## 必須
- P0 が完了
- Golden scenario が通る
- 青色 / 白色 / 消費税 major ケースが通る
- migration dry-run が通る
- 旧 ledger 正本への新規書き込みが止まっている
- XML preflight blocker がゼロ

## 条件付きで許容
- 一部 UI polish 未完
- 一部 P1 機能の後ろ倒し
- 一部 preset の不足

## 不可
- posted journal が直接編集される
- 帳簿が projection ではない
- 証憑原本が失われる
- 消費税特例ロジックに未実装分岐がある
- 65/55/10 or 白色 の判定が壊れている

---

# 18. 最終コメント

この 12 週間計画は、単なる「機能の詰め込み」ではありません。  
**ProjectProfit を、本当に使える個人事業主向けプロジェクト型会計システムへ到達させるための最短クリティカルパス** です。

最重要ポイントは次の 5 つです。

1. **正本一本化**
2. **TaxYearProfile と税務状態マシン**
3. **証憑台帳 + On-device Intake**
4. **ConsumptionTaxWorksheet**
5. **帳簿 / 帳票 / e-Tax をすべて canonical data から派生生成**

この順番を崩さない限り、UI は後からいくらでも綺麗にできます。  
逆に、この順番を崩すと、帳簿・税務・証憑・プロジェクト管理のどこかが必ず破綻します。

したがって、この 12 週間では **「UI を先に整える」のではなく、「完成品の内部骨格を先に作る」** ことを徹底してください。

---

# 19. 参考資料（制度・仕様）

- 国税庁 No.2072 青色申告特別控除
- 国税庁 No.2080 白色申告者の記帳・帳簿等保存制度
- 国税庁 No.6496 / No.6498 / No.6625 インボイス制度関係
- 国税庁 インボイス Q&A 問111-115
- 国税庁 優良な電子帳簿の要件
- e-Tax 仕様書一覧
- e-Tax 仕様書の更新履歴等
- ユーザー添付: 青色申告決算書 PDF
- ユーザー添付: 収支内訳書 PDF
- ユーザー添付: 消費税集計表 PNG
