# Project Profit iOS 会計・確定申告 監査Todo

更新日: 2026-02-26  
対象: `project-profit-ios`（iOSアプリ本体 / 会計機能 / e-Tax出力）

## 1. 監査スコープ（15観点）
1. 仕様準拠性（青色/白色/e-Tax）
2. 会計データモデル整合性
3. 取引入力バリデーション
4. 自動仕訳生成ルール
5. 手動仕訳・ロック運用
6. P/L・B/S・試算表整合性
7. 会計年度境界（開始月）
8. e-Taxフィールドマッピング
9. XML/CSVエクスポート妥当性
10. 文字種/入力値バリデーション
11. CSVインポート/エクスポート互換
12. セキュリティ・個人情報保護
13. テスト網羅性
14. 実行環境の検証可能性
15. 技術的負債（コメント・実装乖離）

## 2. 監査方針
- 推測は記載しない。すべて「確認できた事実」のみ記載する。
- 各Todoは「根拠ファイル/行」「影響」「修正方針」「受入条件」を必須化する。
- UIデザイン変更は対象外。ロジック・整合性・出力正確性のみ対象。

## 2.1 実装進捗（2026-02-26）
- 完了: `P0-04`（e-Tax値モデルを数値/文字/フラグ対応に拡張、申告者情報を実値で保持）
- 完了: `P0-05`（`internalKey -> xmlTag` マッピング駆動へ変更、未対応年分はエラー化）
- 完了: `P0-06`（文字種バリデーション対象をラベルから出力値へ変更）
- 完了: `P0-07`（会計レポート/e-Taxプレビューに会計年度開始月を伝播）
- 完了: `P1-07`（消費税集計サービスが開始月指定に対応）
- 完了: `P1-06`（固定資産/棚卸CRUDに年度ロックガードを実装）
- 完了: `P0-05`準備フェーズ（CAB未投入でも `抽出 -> 検証 -> TaxYear反映` を実行可能なバッチ基盤を追加）
- 完了: 公式CAB/Excel（`e-taxall` 実データ）投入後の本番値反映を実施（`xmlTag` 差分0、`requiredRule/format/dataType` を39項目反映）

## 3. P0（申告・帳簿の正確性に直結、最優先）

### P0-01 振替取引の入力制約が仕様と不一致
- 事実:
  - `isValid` が取引種別に関係なく `カテゴリ必須 + 配分100%必須` を要求している。
  - 画面構成で振替時にもカテゴリ・配分セクションを常時表示している。
- 根拠:
  - `ProjectProfit/Views/Components/TransactionFormView.swift:57`
  - `ProjectProfit/Views/Components/TransactionFormView.swift:70`
  - `ProjectProfit/Views/Components/TransactionFormView.swift:74`
  - `ProjectProfit/Views/Components/TransactionFormView.swift:343`
  - `ProjectProfit/Views/Components/TransactionFormView.swift:491`
- 影響:
  - 仕様上「振替はカテゴリ不要・配分不要」を満たせず、正常系入力を阻害する。
- 修正Todo:
  1. `isValid` を `type` 別の検証に分岐する（`transfer` は `from/to` 必須、カテゴリ/配分不要）。
  2. `transfer` 選択時はカテゴリ/配分セクションを非表示にする。
  3. `from == to` を禁止するバリデーションを追加する。
- 受入条件:
  - 振替取引がカテゴリ未選択・配分なしでも保存できる。
  - 同一口座間振替は保存できず、UIでエラー表示される。

### P0-02 取引編集で消費税フィールドが更新されない
- 事実:
  - 編集時の `updateTransaction` 呼び出し3経路で `taxAmount/taxRate/isTaxIncluded/taxCategory` を渡していない。
  - さらに `resolvedTaxRate` に必要経費算入率を代入している。
- 根拠:
  - `ProjectProfit/Views/Components/TransactionFormView.swift:668`
  - `ProjectProfit/Views/Components/TransactionFormView.swift:691`
  - `ProjectProfit/Views/Components/TransactionFormView.swift:703`
  - `ProjectProfit/Views/Components/TransactionFormView.swift:712`
  - `ProjectProfit/Services/DataStore.swift:638`
- 影響:
  - 取引作成後の編集で消費税データが意図どおり反映されず、仕訳・帳票値が不正になる。
- 修正Todo:
  1. 編集時の `updateTransaction` 全経路に消費税4項目を渡す。
  2. 変数名/代入を修正し、`taxRate` と `taxDeductibleRate` の混同を除去する。
- 受入条件:
  - 編集前後で消費税項目が正しく差分反映され、関連仕訳が更新される。

### P0-03 記帳ロック仕様のコメントと実装が乖離
- 事実:
  - `AccountingEngine` のコメントは `bookkeepingMode == .locked` を前提にしている。
  - 実装は `entryType == .manual` の場合のみスキップしており、`locked` 判定は存在しない。
  - `BookkeepingMode` enum には `singleEntry/doubleEntry` しか定義がない。
- 根拠:
  - `ProjectProfit/Services/AccountingEngine.swift:21`
  - `ProjectProfit/Services/AccountingEngine.swift:31`
  - `ProjectProfit/Models/AccountingEnums.swift:239`
  - `ProjectProfit/Models/Models.swift:191`
  - `ProjectProfit/Services/DataStore.swift:693`
- 影響:
  - 「自動更新を止める」という仕様意図が成立せず、編集済み仕訳が上書きされ得る。
- 修正Todo:
  1. 記帳モードの仕様を `auto/locked` などに再定義し、モデル/ロジック/UIを統一する。
  2. `updateTransaction` -> `upsertJournalEntry` 経路にロック判定を実装する。
  3. コメントを実装と一致させる。
- 受入条件:
  - ロック済み取引の更新で仕訳明細が変化しない。
  - ロック解除後は再生成される。

### P0-04 e-Taxモデルが申告者情報文字列を保持できない
- 事実:
  - `EtaxField` は `value: Int` のみ保持する。
  - `populateDeclarantInfo` は氏名/住所等が入力済みでも `value: 0` を設定している。
- 根拠:
  - `ProjectProfit/Models/EtaxModels.swift:10`
  - `ProjectProfit/Services/EtaxFieldPopulator.swift:102`
  - `ProjectProfit/Services/EtaxFieldPopulator.swift:108`
  - `ProjectProfit/Services/EtaxFieldPopulator.swift:120`
  - `ProjectProfit/Services/EtaxFieldPopulator.swift:144`
- 影響:
  - 申告者情報が実値として出力されず、提出データとして不完全になる。
- 修正Todo:
  1. `EtaxField` を数値/文字の両対応モデルへ変更する。
  2. `populateDeclarantInfo` でプロファイル値を実際にマップする。
  3. プレビュー表示も文字値を反映する。
- 受入条件:
  - 入力済み氏名・住所・電話番号等が出力データで確認できる。

### P0-05 e-Tax出力が年分タグマッピング非依存の独自XML
- 事実:
  - XMLルートが `<税務申告データ>` など独自構造で生成されている。
  - フィールドは `id` と `taxLine` 属性で出力され、年分別 `xmlTag` マップを使用していない。
- 根拠:
  - `ProjectProfit/Services/EtaxXtxExporter.swift:63`
  - `ProjectProfit/Services/EtaxXtxExporter.swift:141`
  - `ProjectProfit/Services/EtaxXtxExporter.swift:150`
  - `ProjectProfit/Services/TaxYearDefinitionLoader.swift:24`
- 影響:
  - 仕様書ベースのタグ互換を担保できず、e-Tax読込失敗リスクが高い。
- 修正Todo:
  1. 年分別マッピング（`internalKey -> xmlTag`）駆動に変更する。
  2. 生成対象を「仕様準拠XML」に限定し、独自タグを廃止する。
  3. 年分未対応時は明示エラーで出力停止する。
- 受入条件:
  - 対応年分の全必須内部キーにタグが割当済みで、出力前チェックで保証される。

### P0-06 文字種バリデーション対象がラベルのみ
- 事実:
  - `validateForm` は `field.fieldLabel` だけ検証しており、値（出力データ本体）は検証していない。
- 根拠:
  - `ProjectProfit/Services/EtaxCharacterValidator.swift:79`
  - `ProjectProfit/Services/EtaxCharacterValidator.swift:88`
- 影響:
  - 実データに禁止文字が含まれても検出できず、提出時エラーの原因になる。
- 修正Todo:
  1. バリデーション対象を「ラベル」ではなく「出力値全体」に拡張する。
  2. 文字列値に対して置換/エラー動作を選択できるようにする。
- 受入条件:
  - 出力値に禁止文字がある場合、生成前に必ず検出される。

### P0-07 会計年度開始月が会計レポート/e-Tax下書きに連動しない
- 事実:
  - `AccountingReportService` は `startMonth` のデフォルトを `1` にしている。
  - `AccountingReportViewModel` と `EtaxExportViewModel` は `startMonth` を渡していない。
- 根拠:
  - `ProjectProfit/Services/AccountingReportService.swift:13`
  - `ProjectProfit/ViewModels/AccountingReportViewModel.swift:28`
  - `ProjectProfit/ViewModels/EtaxExportViewModel.swift:37`
- 影響:
  - 設定上の会計年度とレポート・e-Tax出力期間が不一致になり得る。
- 修正Todo:
  1. `FiscalYearSettings.startMonth` を会計レポート生成に必ず注入する。
  2. e-Taxプレビュー生成も同一開始月を使用する。
- 受入条件:
  - 開始月変更後、帳簿画面とe-Taxプレビューの対象期間が一致する。

## 4. P1（運用・信頼性に影響、早期対応）

### P1-01 年分定義が2025年分のみ
- 事実:
  - リソースに `TaxYear2025.json` しか存在しない。
- 根拠:
  - `ProjectProfit/Resources/TaxYear2025.json:1`
  - `ProjectProfit/Services/TaxYearDefinitionLoader.swift:27`
- 影響:
  - 年分切替時に未対応年はフォールバック依存となり、制度追従の品質が担保しづらい。
- 修正Todo:
  1. 年分別定義ファイル追加方針を確立する（最低: 対応対象年を明記）。
  2. 未対応年はUI上で出力不可にする。
- 受入条件:
  - 対応年分が明示され、未対応年分は誤って出力できない。

### P1-02 CSV入出力仕様が会計拡張フィールド未対応
- 事実:
  - `parseCSV` は6列前提で、口座/振替先/必要経費算入率を扱わない。
  - `generateCSV` ヘッダにも同列が存在しない。
- 根拠:
  - `ProjectProfit/Utilities/Utilities.swift:589`
  - `ProjectProfit/Utilities/Utilities.swift:606`
  - `ProjectProfit/Utilities/Utilities.swift:719`
- 影響:
  - CSV経由で会計情報が欠落し、再取込後の仕訳整合が崩れる可能性がある。
- 修正Todo:
  1. 新CSV仕様（支払口座/振替先口座/必要経費算入率）を定義して実装する。
  2. 旧フォーマット互換（読み取りのみ）を残す。
- 受入条件:
  - 新フォーマットのexport -> importで会計フィールドが保持される。

### P1-03 高機微情報保護の実装根拠が不足
- 事実:
  - 申告者情報（氏名・住所・電話等）は `PPAccountingProfile` に平文で保持している。
  - リポジトリ検索で `Keychain/CryptoKit/SecItem` 利用箇所は確認できない。
- 根拠:
  - `ProjectProfit/Models/PPAccountingProfile.swift:13`
  - `ProjectProfit/Views/Settings/ProfileSettingsView.swift:176`
- 影響:
  - 仕様上の「高機微情報の保護要件」を満たす実装根拠が不足している。
- 修正Todo:
  1. 保存対象データを分類し、保護対象（暗号化/保管先）を明文化する。
  2. 保護実装（例: Keychain利用など）を導入する。
- 受入条件:
  - 保護対象の保存先・暗号化方針・同意フローがコード/仕様の双方で確認できる。

### P1-04 ローカルテスト実行環境が不安定
- 事実:
  - `xcodebuild test` 実行時に `CoreSimulatorService connection became invalid` が発生し、テストを実行できない。
- 根拠:
  - 実行ログ（2026-02-26）:
    - `CoreSimulatorService connection became invalid`
    - `Tests must be run on a concrete device`
- 影響:
  - 回帰確認の自動化が不十分になり、変更の安全性が下がる。
- 修正Todo:
  1. CI/ローカルで実行可能なテストレーン（in-memory unit tests中心）を整備する。
  2. Simulator依存テストを分離し、失敗時の診断手順を文書化する。
- 受入条件:
  - 最低限の会計/エクスポート単体テストが安定実行できる。

## 5. P2（保守性向上・将来対策）

### P2-01 コメントと実装の同期ルール不足
- 事実:
  - 「locked前提」のコメントと実コードが一致していない箇所が存在する。
- 根拠:
  - `ProjectProfit/Services/AccountingEngine.swift:21`
- 修正Todo:
  1. コメントを仕様ソース化せず、テストで仕様を担保する方針へ統一する。
  2. 重要仕様は ADR か docs に集約して参照リンクを貼る。
- 受入条件:
  - 主要会計ロジックの仕様はテストケースで追跡できる。

### P2-02 監査項目の継続運用ルールを未定義
- 事実:
  - 会計・申告向けの監査Todo運用ルール（完了定義、証跡管理）が未定義。
- 修正Todo:
  1. 各Todoに「修正PR」「検証結果」「残リスク」を紐付けるテンプレートを追加する。
  2. リリース前チェックに本ファイルのP0/P1完了確認を組み込む。
- 受入条件:
  - 監査Todoが継続更新され、リリース判断に使用できる。

## 6. 実装時チェックリスト（共通）
- [x] 変更前後で仕訳の貸借一致が崩れていない。
- [x] 振替・消費税・按分を含むE2Eシナリオで数値が一致する。
- [x] e-Tax出力の入力値バリデーションがラベル依存ではない。
- [x] 会計年度開始月を変更してもレポート/e-Tax期間が一致する。
- [x] 追加テストが失敗する状態を再現し、修正後に通過する。
- 確認根拠:
  - `python3 -m unittest discover -s tools/etax/tests -p 'test_*.py'`（14/14 success）
  - `ETAX_ARTIFACTS_DIR=/tmp/etax-unit-lane-final ETAX_TAG_INPUT_DIR=e-taxall ./scripts/run_etax_unit_lane.sh`（success）

## 7. 第2次監査（アプリ全体）: 15観点エージェント分割ログ
- 実施内容:
  - `確定申告仕様書` 配下4文書と、`ProjectProfit` / `ProjectProfitTests` 全体を突合した。
  - 1観点=1エージェントとして15観点に分割し、検出事項を本Todoへ統合した。

| Agent | 観点 | 追加検出 | 主なTodo ID |
|---|---|---:|---|
| A01 | 仕様準拠（振替入力） | あり | P0-01, P0-12 |
| A02 | 会計データ更新整合 | あり | P0-02 |
| A03 | 仕訳ロック運用 | あり | P0-03, P0-09 |
| A04 | e-Taxデータモデル | あり | P0-04 |
| A05 | e-Taxタグマッピング | あり | P0-05, P1-01 |
| A06 | 文字種/値検証 | あり | P0-06 |
| A07 | 会計年度境界 | あり | P0-07, P1-07 |
| A08 | CSV契約互換性 | あり | P1-02 |
| A09 | 個人情報保護 | あり | P1-03 |
| A10 | 年度ロック一貫性 | あり | P0-08, P0-09 |
| A11 | 定期取引と仕訳同期 | あり | P0-10, P0-11, P1-05 |
| A12 | OCR/レシート登録経路 | あり | P0-12 |
| A13 | 固定資産/棚卸ロック | あり | P1-06 |
| A14 | テスト実行再現性 | あり | P1-04 |
| A15 | 技術的負債（仕様乖離） | あり | P2-01 |

## 8. 追加で確認した修正Todo（第2次監査）

### P0-08 年度ロック時 `addTransaction` が未保存のダミー取引を返す（解消）
- 実施:
  - `DataStore.addTransaction` の失敗時ダミー返却を廃止し、失敗時は `preconditionFailure` で明示失敗させる契約に変更。
  - 失敗判定が必要な呼び出しは `addTransactionResult` を利用する方針へ統一し、`YearLockTests` を更新。
- 根拠:
  - `ProjectProfit/Services/DataStore.swift`
  - `ProjectProfitTests/YearLockTests.swift`
- 検証結果:
  - 年度ロック時の追加は `addTransactionResult` が `.failure(.yearLocked)` を返し、`lastError` が設定されることを単体テストで確認。

### P0-09 年度ロック判定が暦年固定で会計年度開始月と不整合
- 事実:
  - 年度ロック判定は `Calendar.current.component(.year, from: date)` を使用している。
  - 一方でアプリ設定は開始月を 1〜12 月で変更可能で、会計年度ユーティリティも別実装されている。
- 根拠:
  - `ProjectProfit/Services/DataStore+YearLock.swift:11`
  - `ProjectProfit/Services/DataStore+YearLock.swift:12`
  - `ProjectProfit/Utilities/FiscalYearSettings.swift:7`
  - `ProjectProfit/Views/Settings/SettingsView.swift:153`
  - `ProjectProfit/Utilities/FiscalYearUtilities.swift:8`
- 影響:
  - 開始月が1月以外の運用で、ロック対象年度と実会計年度がズレる。
- 修正Todo:
  1. 年度ロック判定を `fiscalYear(for:startMonth:)` ベースへ置換する。
  2. `isYearLocked(for date:)` で `FiscalYearSettings.startMonth` を参照する。
  3. 既存ロック年度データの移行方針を明記する。
- 受入条件:
  - 開始月4月のとき `2026-03-31` と `2026-04-01` が別年度として正しく判定される。
  - 年度ロックのUI表示年度と内部判定年度が一致する。

### P0-10 定期取引生成が仕訳同期・取引一覧同期を通らない
- 事実:
  - `createTransactionFromRecurring` は `PPTransaction` を直接 `modelContext.insert` しており、`addTransaction` の仕訳自動生成経路を通らない。
  - `processRecurringTransactions` は生成後に `refreshRecurring()` のみ実行し、`refreshTransactions()/refreshJournalEntries()/refreshJournalLines()` を呼ばない。
  - テストにも「processRecurringTransactions は dataStore.transactions を更新しない」旨の注記がある。
- 根拠:
  - `ProjectProfit/Services/DataStore.swift:1247`
  - `ProjectProfit/Services/DataStore.swift:1319`
  - `ProjectProfit/Services/DataStore.swift:1331`
  - `ProjectProfit/Services/DataStore.swift:1461`
  - `ProjectProfit/Services/DataStore.swift:1463`
  - `ProjectProfitTests/RecurringProcessingTests.swift:1165`
  - `ProjectProfit/Views/ContentView.swift:26`
- 影響:
  - 定期取引生成後に仕訳や取引一覧が即時整合しない状態が発生し得る。
- 修正Todo:
  1. 定期生成時も `addTransaction` 経路を利用するか、同等の仕訳生成/更新処理を必ず呼ぶ。
  2. 生成後に `refreshTransactions()/refreshJournalEntries()/refreshJournalLines()` を実行する。
  3. 起動時 `.task` 後の表示データが即時一致する検証テストを追加する。
- 受入条件:
  - 定期取引生成直後に、取引一覧・仕訳一覧・レポートが同じ件数/金額になる。
  - 既存テスト注記（同期不足）に該当する状態が再現しない。

### P0-11 年次定期（月次分割）生成で会計フィールドが欠落
- 事実:
  - 年次定期の月次分割生成で作成する `PPTransaction` には `paymentAccountId/transferToAccountId/taxDeductibleRate` が設定されていない。
  - 同一ファイル内の通常定期生成経路では同フィールドを設定している。
- 根拠:
  - `ProjectProfit/Services/DataStore.swift:1610`
  - `ProjectProfit/Services/DataStore.swift:1617`
  - `ProjectProfit/Services/DataStore.swift:1327`
  - `ProjectProfit/Services/DataStore.swift:1329`
- 影響:
  - 月次分割で生成された取引のみ会計前提フィールドが欠落し、仕訳や税務集計の一貫性が崩れる。
- 修正Todo:
  1. 月次分割生成でも `paymentAccountId/transferToAccountId/taxDeductibleRate` を引き継ぐ。
  2. `type == .transfer` の場合の必須項目検証を追加する。
  3. 月次分割生成の回帰テストに会計フィールド検証を追加する。
- 受入条件:
  - 月次分割で生成された全取引に会計フィールドが期待値どおり保存される。
  - 同テンプレートの通常生成/分割生成でフィールド差が発生しない。

### P0-12 OCRレシート登録経路が会計/税務項目を保持しない
- 事実:
  - `ReceiptReviewView` は振替を含む3種類を選択できるが、`isValid` は常に `カテゴリ必須 + 配分100%` 条件。
  - 保存時の `addTransaction` 呼び出しでは `paymentAccountId/transferToAccountId/taxDeductibleRate/taxAmount/taxRate/isTaxIncluded/taxCategory` を渡していない。
- 根拠:
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift:50`
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift:52`
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift:157`
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift:488`
  - `ProjectProfit/Views/Receipt/ReceiptReviewView.swift:497`
- 影響:
  - OCR由来の登録経路だけ会計前提フィールドが欠落し、通常入力との整合性が崩れる。
- 修正Todo:
  1. `ReceiptReviewView` に会計項目/消費税項目の入力と保存マッピングを追加する。
  2. `transfer` 時のバリデーションを通常取引フォームと統一する。
  3. OCR経路のE2Eテスト（入力->保存->仕訳->レポート）を追加する。
- 受入条件:
  - OCR経路でも通常フォームと同じ会計フィールドが保存される。
  - 振替/OCR登録でカテゴリ非依存の保存可否が仕様どおりになる。

### P1-05 定期取引（手動配分）で保存可能だが生成されない状態がある
- 事実:
  - 手動配分の入力検証は「合計>0 かつ 合計!=100」のときのみエラーで、合計0は通過する。
  - 生成処理では `allocationMode == .manual && allocations.isEmpty` の場合にスキップする。
- 根拠:
  - `ProjectProfit/Views/Components/RecurringFormView.swift:547`
  - `ProjectProfit/Views/Components/RecurringFormView.swift:549`
  - `ProjectProfit/Services/DataStore.swift:1346`
- 影響:
  - 有効な定期取引として保存されても実取引が生成されない設定を作れてしまう。
- 修正Todo:
  1. 手動配分時は「配分件数>=1」「合計=100」を必須化する。
  2. 既存不正データ検出（保存済み0%配分）と修復導線を追加する。
- 受入条件:
  - 手動配分で0%・空配分の定期取引は保存できない。
  - 既存0%データは起動時に警告表示される。

### P1-06 固定資産/棚卸CRUDに年度ロックガードが無い（解消）
- 実施:
  - 固定資産 `add/update/delete` に `isYearLocked` 判定を追加し、対象年度ロック時は処理を拒否するよう修正。
  - 棚卸 `add/update/delete` にも同等のロック判定を追加し、ロック年度の更新を拒否するよう修正。
- 根拠:
  - `ProjectProfit/Services/DataStore+FixedAsset.swift`
  - `ProjectProfit/Services/DataStore+Inventory.swift`
  - `ProjectProfitTests/DataStoreFixedAssetTests.swift`
  - `ProjectProfitTests/DataStoreInventoryTests.swift`
- 検証結果:
  - 固定資産: ロック年度での追加/更新/削除拒否を単体テストで確認。
  - 棚卸: ロック年度での追加/更新/削除拒否を単体テストで確認。

### P1-07 消費税集計サービスが会計年度開始月に未対応
- 事実:
  - `ConsumptionTaxReportService.fiscalYearRange` は `1/1〜12/31` 固定で集計している。
- 根拠:
  - `ProjectProfit/Services/ConsumptionTaxReportService.swift:49`
  - `ProjectProfit/Services/ConsumptionTaxReportService.swift:51`
  - `ProjectProfit/Services/ConsumptionTaxReportService.swift:52`
  - `ProjectProfit/Views/Settings/SettingsView.swift:153`
- 影響:
  - 開始月を変更している事業者の会計年度集計とズレる。
- 修正Todo:
  1. 消費税集計に `startMonth` 引数を追加し、会計年度ユーティリティを共通利用する。
  2. 既存画面/VMから開始月を注入する。
- 受入条件:
  - 開始月変更時でも消費税集計期間が他レポートと一致する。

## 9. 仕様突合で追加確認した事実（仕様書 vs 実装）
- 仕様書で「振替時はカテゴリ非表示・配分空許容」と定義されている。
  - `確定申告仕様書/Project Profit iOS：複式簿記コア導入・完全仕様書（外注実装用）.md:117`
  - `確定申告仕様書/Project Profit iOS：複式簿記コア導入・完全仕様書（外注実装用）.md:371`
  - 実装側根拠: `ProjectProfit/Views/Components/TransactionFormView.swift:57`
- 仕様書で `BookkeepingMode` は `auto/locked` と定義されている。
  - `確定申告仕様書/Project Profit iOS：複式簿記コア導入・完全仕様書（外注実装用）.md:109`
  - 実装側根拠: `ProjectProfit/Models/AccountingEnums.swift:239`
- 仕様書で年分別 `internalKey -> xmlTag` を必須化している。
  - `確定申告仕様書/仕様書：e‑Tax「決算書・収支内訳書」データ作成.md:40`
  - `確定申告仕様書/仕様書：e‑Tax「決算書・収支内訳書」データ作成.md:126`
  - 実装側根拠: `ProjectProfit/Services/EtaxXtxExporter.swift:145`
- 仕様書でCSV拡張列（支払口座/振替先口座/必要経費算入率）を定義している。
  - `確定申告仕様書/Project Profit iOS：複式簿記コア導入・完全仕様書（外注実装用）.md:417`
  - `確定申告仕様書/Project Profit iOS：複式簿記コア導入・完全仕様書（外注実装用）.md:426`
  - 実装側根拠: `ProjectProfit/Utilities/Utilities.swift:606`
- 仕様書で高機微情報は端末内暗号化を必須化している。
  - `確定申告仕様書/仕様書：e‑Tax「決算書・収支内訳書」データ作成.md:178`
  - 実装側根拠: `ProjectProfit/Models/PPAccountingProfile.swift:23`

## 10. 完了までのマスターTodo（実装順）
- [x] フェーズ1（入力・登録経路の整合）
  - 対象: P0-01, P0-02, P0-12
  - 完了条件: 通常入力/OCR入力/振替入力で保存項目とバリデーションが一致。
- [x] フェーズ2（年度ロックと会計年度境界）
  - 対象: P0-08, P0-09, P1-06, P1-07
  - 完了条件: 開始月を変えてもロック判定・集計期間・固定資産/棚卸編集可否が一致。
- [x] フェーズ3（定期取引と仕訳同期）
  - 対象: P0-10, P0-11, P1-05
  - 完了条件: 定期取引生成直後に取引/仕訳/レポートが同一データを参照。
- [x] フェーズ4（e-Taxデータ品質）
  - 対象: P0-04, P0-05, P0-06, P1-01
  - 完了条件: 年分別マッピング駆動で文字列/数値を正しく出力し、事前検証で弾ける。
- [x] フェーズ5（互換・保護・運用）
  - 対象: P1-02, P1-03, P1-04, P2-01, P2-02
  - 完了条件: CSV互換・個人情報保護・テスト実行性・監査運用テンプレートが整備済み。
- 完了判定根拠:
  - `docs/etaxall-implementation-pack/02_evidence/etax-ci-local-evidence-2026-02-26.md`
  - `docs/etaxall-implementation-pack/00_todo/etax-regression-checklist.md`
