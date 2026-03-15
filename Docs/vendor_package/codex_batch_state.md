# Codex Batch State

- 更新日: 2026-03-15
- current HEAD: `8f8163eae945f144912ddf15763386318835952d`
- 正本タスク書: `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- vendor 用状態管理ファイル: `Docs/vendor_package/codex_batch_state.md`
- スコープ内:
  - 青色申告決算書（一般）データ作成
  - 白色申告（収支内訳書）データ作成
  - 青色申告決算書（現金主義用）データ作成
  - preview / export / XSD 整合
  - 2025 / 2026 filing pack 整合
  - 共通宣言部（declarant / 年分 / requiredRule / validation）
  - release 用 quality / test / docs 整備
- スコープ外:
  - 利用者識別番号ログイン
  - 電子署名
  - 送受信モジュール
  - 受信通知 / メッセージボックス
  - 直接提出機能
  - API 送信連携

## P0 / P1 タスク ID 一覧

- P0: `P0-01`, `P0-02`, `P0-03`, `P0-04`, `P0-05`, `P0-06`, `P0-07`, `P0-08`, `P0-09`, `P0-10`, `P0-11`, `P0-12`
- P1: `P1-01`, `P1-02`, `P1-03`, `P1-04`, `P1-05`, `P1-06`

## バッチ割り当て

| バッチ | タスク ID | 状態 | 備考 |
| --- | --- | --- | --- |
| Batch 0 | 実行基盤初期化 | 完了 | state / validation matrix / batch index 作成のみ |
| Batch 1 | `P0-01` | 未着手 | 2025 filing pack deadline 修正 |
| Batch 2 | `P0-02`, `P0-03`, `P0-04` | 未着手 | 現金主義の form metadata / export 経路 / 主要金額 |
| Batch 3 | `P0-05`, `P0-07`, `P0-09` | 未着手 | 青色一般 page 構造 / 共通申告者情報 / direct mapping 解消 |
| Batch 4 | `P0-06`, `P0-10` | 未着手 | 白色 2 ページ化と不足明細拡張 |
| Batch 5 | `P0-08`, `P0-11` | 未着手 | 青色 pack 誤マッピング修正と BS 詳細 export |
| Batch 6 | `P0-12`, `P1-03`, `P1-04` | 未着手 | XSD 自動検証・pack coverage・loader test 拡張 |
| Batch 7 | `P1-01`, `P1-02` | 未着手 | 2026 pack 再検証と stale preview/export 防止 |
| Batch 8 | `P1-05`, `P1-06` | 未着手 | release quality 証跡同期と scope 文書固定 |

## タスク状態表

| タスク ID | 優先度 | 状態 | 割当バッチ | 概要 |
| --- | --- | --- | --- | --- |
| `P0-01` | P0 | 未着手 | Batch 1 | 2025 filing pack deadline を `2026-03-16` に修正 |
| `P0-02` | P0 | 未着手 | Batch 2 | 現金主義の帳票 ID / rootTag / version を統一 |
| `P0-03` | P0 | 未着手 | Batch 2 | 現金主義の主要金額と経費行を export 対象へ残す |
| `P0-04` | P0 | 未着手 | Batch 2 | 現金主義 exporter を青色一般から分離 |
| `P0-05` | P0 | 未着手 | Batch 3 | 青色一般 exporter を `KOA210-1..4` 構造へ再構築 |
| `P0-06` | P0 | 未着手 | Batch 4 | 白色 exporter を `KOA110-1/2` 構造へ再構築 |
| `P0-07` | P0 | 未着手 | Batch 3 | 帳票別 declarant / 年分タグへ分離 |
| `P0-08` | P0 | 未着手 | Batch 5 | 青色一般 pack の誤マッピング修正 |
| `P0-09` | P0 | 未着手 | Batch 3 | 複合要素への direct mapping を除去 |
| `P0-10` | P0 | 未着手 | Batch 4 | 白色の必要明細ページ・requiredRule・内訳を追加 |
| `P0-11` | P0 | 未着手 | Batch 5 | 青色貸借対照表の detail key を export 可能にする |
| `P0-12` | P0 | 未着手 | Batch 6 | 3 フォームの official XSD 自動検証を固定 |
| `P1-01` | P1 | 未着手 | Batch 7 | 2026 filing pack を 2025 の単純コピーから切り離す |
| `P1-02` | P1 | 未着手 | Batch 7 | stale preview / stale export を防ぐ |
| `P1-03` | P1 | 未着手 | Batch 6 | builder と pack の coverage 監査追加 |
| `P1-04` | P1 | 未着手 | Batch 6 | `TaxYearDefinitionLoader` を帳票別 coverage まで拡張 |
| `P1-05` | P1 | 未着手 | Batch 8 | release quality 証跡を current HEAD と同期 |
| `P1-06` | P1 | 未着手 | Batch 8 | 書類作成対象の scope を README / release docs に固定 |

## このバッチの結果

- Batch 0 では product code 変更なし。
- 追加したファイル:
  - `Docs/vendor_package/codex_batch_state.md`
  - `Docs/vendor_package/codex_validation_matrix.md`
  - `Docs/vendor_package/codex_batch_index.md`
- 変更した Markdown の要約:
  - task ID とバッチ割り当てを固定
  - 最小検証 / 最終検証のマトリクスを整理
  - 次バッチ以降が最初に読むべきファイルを明文化

## 次バッチが最初に読むべきファイル

- `Docs/release/統合_修正タスク一覧_P0_P1_必要書類作成まで.md`
- `Docs/vendor_package/codex_batch_state.md`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/common.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_general.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/white_shushi.json`
- `ProjectProfit/Resources/TaxYearPacks/2025/filing/blue_cash_basis.json`
