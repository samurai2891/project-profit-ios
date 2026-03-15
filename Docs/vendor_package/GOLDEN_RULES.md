# ProjectProfit Golden Rules - 全Agent必読

> この文書は全Agentがセッション開始時に必ず読む。
> Compact後も ANCHOR タグ内のルールは保持される。
> 判断に迷ったらこの文書に立ち返ること。

---

## 絶対不変の4原則

1. **個人事業主向け**であること
2. **プロジェクトごとに管理できる**こと
3. **会計と税務をノーストレスにする**こと
4. **AI はオンデバイス限定**であること

---

## 正本設計ルール

- 正本は **Evidence → Candidate → PostedJournal** の1系統のみ
- 帳簿（元帳、出納帳、経費帳等）は全て PostedJournal からの**派生生成**
- **LedgerDataStore を正本として使わない**（projection のみ）
- 帳票（青色決算書、収支内訳書等）も派生生成
- 帳簿を直接編集する API は作らない

---

## 型と計算のルール

- 金額は **Decimal 型のみ**（Double 禁止）
- TaxCode は **enum/struct**（String ベタ書き禁止）
- 年度差分は **TaxYearPack**（if文連鎖禁止）
- ID は UUID
- 日付は Date（表示時のみ Calendar 変換）

---

## アーキテクチャルール

- **4層**: Domain / Application / Infrastructure / UI
- UI → Application → Domain（逆方向の依存禁止）
- UI から persistence を直接叩かない（**Repository Protocol 経由**）
- ViewModel から SwiftData の ModelContext を触らない
- Services に何でも追加しない（責務に応じた層に配置）
- 巨大な DataStore / Models.swift を作らない

---

## 証憑・候補・仕訳のルール

- OCR 結果をそのまま確定仕訳にしない
- 必ず **Candidate** を経由する
- high confidence でも**自動確定はしない**（自動提案のみ）
- 1 証憑 = N 仕訳を許容する（1:1固定にしない）
- 証憑原本は**削除不可**（アーカイブのみ）
- 全操作に **AuditEvent** を記録

---

## 税務対応範囲

- 青色: 65万 / 55万 / 10万 / 現金主義
- 白色: 収支内訳書
- 消費税: 免税 / 課税一般 / 簡易課税 / 2割特例
- インボイス: T番号、少額特例、80%/50%経過措置
- e-Tax XML出力
- 消費税計算: 仮払/仮受の単純差額ではなく**根拠別集計**
- 国税/地方税の分離保持（7.8%/2.2%, 6.24%/1.76%）

---

## プロジェクト管理のルール

- プロジェクトは**管理会計軸**（法定帳票の主キーにしない）
- 税務申告は「事業者 × 年分」で作る
- プロジェクト別収益管理は維持する
- legal view と management view を分離する

---

## テスト基準

- **Golden Test**: 帳簿・帳票の期待値と完全一致
- **Migration Test**: 旧→新の件数・金額・整合性
- **Tax Scenario Test**: 各申告類型のシナリオ
- **Book Validation**: 借貸一致・元帳残高整合・試算表整合

---

## 仕様の優先順位

判断に迷った場合：

1. **法令・国税庁・e-Tax の公式仕様**
2. **公式帳票サンプル（青色決算書/収支内訳書/消費税集計表）**
3. ProjectProfit_Complete_Refactor_Spec.md
4. ProjectProfit_Implementation_Task_List.md
5. ProjectProfit_Outsource_Architecture_Detail_Spec.md
6. 既存コード
7. Agent 独自判断

**既存コードは正解ではない。**

---

## 禁止事項サマリー

| カテゴリ | 禁止 |
|---------|------|
| 型 | Double で金額計算 |
| 型 | String ベタ書きで tax code |
| 構造 | Services に何でも追加 |
| 構造 | 巨大 DataStore / Models.swift |
| 構造 | UI から persistence 直接 |
| 会計 | OCR → 即確定仕訳 |
| 会計 | 1証憑 = 1仕訳固定 |
| 会計 | 帳簿の直接編集 |
| 会計 | 仮払/仮受の単純差額のみの消費税 |
| 税務 | if文連鎖で年度差分 |
| 安全 | 証憑を外部AIへ送信 |
| 安全 | 原本の気軽な削除 |
| 安全 | year lock 後の自由更新 |
| 安全 | audit log なし |
