# Project Profit iOS：複式簿記コア導入・完全仕様書（外注実装用）

- 対象リポジトリ：`project-profit-ios-main/ProjectProfit`（SwiftData / DataStore中心 / PPTransaction中心）
- iOS Deployment Target：iOS 17.0（現行 `project.yml`）
- 追加スコープ：複式簿記（青色：55/65、白色にも有用）に必要な帳簿・集計・チェック・帳票プレビュー準備、e-Tax `.xtx`生成I/F
- 送信スコープ：**送信（e-Taxログイン/署名/送信操作）自体は行わない**（ユーザーが公式導線で送信）

---

## 0. 背景・要件整理（税務の最小要件の位置づけ）

### 0.1 青色申告（55/65万円控除）に最低限必要なこと
- **55万円控除**：正規の簿記（一般に複式簿記）で記帳し、**貸借対照表・損益計算書**等を期限内申告書に添付、など。  
  - 参考：国税庁 Tax Answer No.2072  
  - https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/2072.htm
- **65万円控除**：55万円要件に加え、**e-Taxで期限内提出**または**電子帳簿保存**（仕訳帳・総勘定元帳など）等が必要。  
  - 同上
- 重要注記：**現金主義の特例を選択している場合、55万円控除は受けられない旨の注記**あり。  
  - 同上

本アプリは「会計ソフトとしての帳簿整備＋提出データ生成」に寄せ、送信はユーザーがe-Tax公式で実行する。

### 0.2 e-Tax連携（.xtx）位置づけ
- 民間会計ソフト等で作った申告等データを送信するには、**拡張子 `.xtx` のファイルが必要**と明記。  
  - https://www.e-tax.nta.go.jp/toiawase/faq/sousin/03.htm
- e-Taxソフト（WEB版）で、民間会計ソフト等の `.xtx` を**読み込んで送信可能**。  
  - https://www.e-tax.nta.go.jp/toiawase/qa/e-taxweb/49.htm
- 仕様は国税庁が「ソフトウェア開発業者向け」に公開しており、**ドラフト版は変更の可能性**あり。  
  - https://www.e-tax.nta.go.jp/shiyo/index.htm
- e-Tax側には**利用可能文字制限**があり、禁止文字が混入するとエラーになる可能性があるため、生成前にチェックが必要。  
  - https://www.e-tax.nta.go.jp/tetsuzuki/tetsuzuki7.htm

---

## 1. 目的（ゴール）と非ゴール

### 1.1 ゴール
1) 既存の「プロジェクト別管理会計（PPTransaction）」を維持しつつ、**複式簿記の会計コア（仕訳・元帳・試算表・P/L・B/S）**をアプリ内に実装  
2) 既存取引（PPTransaction）を自動で仕訳に変換し、**帳簿が揃う**状態にする  
3) 青色/白色の申告に必要な集計・分類・チェック・帳票プレビューを提供  
4) e-Taxの**提出データ（.xtx）生成のためのエクスポータI/F**を実装（本体生成ロジックはe-Tax仕様書に準拠）

### 1.2 非ゴール（本フェーズではやらない）
- e-Taxへのログイン、電子署名、送信、送信結果取得（受信通知）などの自動化  
- 税務判断（勘定科目の妥当性、必要経費性の最終判定、法令改正の保証）  
- 電子帳簿保存法の「承認・要件を満たす運用」の保証（機能として出せる範囲の支援は行う）

---

## 2. 現行構成（前提：コード読解結果の要点）
- SwiftDataモデル：`Models/Models.swift`
  - `PPProject`, `PPTransaction`, `PPCategory`, `PPRecurringTransaction`
- 中核ストア：`Services/DataStore.swift`
  - `loadData()`でSwiftData fetch → 配列保持
  - 取引CRUD（add/update/delete）
  - プロジェクト配分の再計算（プロラタ/均等割 等）
  - CSV Import/Export（`Utilities.swift`）
- UI
  - 取引入力：`Views/Components/TransactionFormView.swift`（収益/経費のみ、カテゴリ+配分、支払口座の概念なし）
  - タブ：Dashboard / Projects / Transactions / Report / Settings（`ContentView.swift`）

---

## 3. 追加する会計ドメイン（全体設計）

### 3.1 会計の“真実”をどこに置くか（重要）
本仕様では、次の二層構造を採用する：

- **入力（現行維持）**：`PPTransaction`（管理会計・プロジェクト配分・レシート・OCR結果）
- **財務会計（新規）**：`PPJournalEntry` / `PPJournalLine` / `PPAccount`（複式簿記）

両者の同期は `AccountingEngine` で行う。  
基本方針：  
- 通常は **PPTransaction → 自動生成仕訳（2行 or 3行）**  
- “会計モードで編集”した仕訳は **ロック**して以降は自動上書きしない（後述）

---

## 4. データモデル仕様（SwiftData @Model / 追加・変更）

### 4.1 既存enum変更：TransactionTypeに「振替」を追加
`Models/Models.swift`

```swift
enum TransactionType: String, Codable {
    case income
    case expense
    case transfer   // NEW：口座間振替
}
```

- `label` 追加：transfer = "振替"
- 既存集計ロジックが「income以外はexpense扱い」になっている箇所を全て修正（後述）

### 4.2 PPTransaction（既存モデル）に追加する属性
`Models/Models.swift` の `PPTransaction` に以下を追加：

| フィールド | 型 | 必須 | デフォルト | 説明 |
|---|---:|:---:|---|---|
| `paymentAccountId` | `String` | ✅ | `"acct-cash"` | 入出金口座（経費：支払元 / 収益：入金先） |
| `transferToAccountId` | `String?` | 条件 | `nil` | `type == .transfer` の場合の振替先口座 |
| `taxDeductibleRate` | `Int` | ✅ | `100` | 必要経費算入率（0-100）。家事按分等に対応 |
| `bookkeepingMode` | `BookkeepingMode` | ✅ | `.auto` | 仕訳生成の扱い（自動/ロック/手動） |
| `journalEntryId` | `UUID?` | ✅ | `nil` | 自動生成した仕訳の参照（紐付け） |

追加enum：

```swift
enum BookkeepingMode: String, Codable {
    case auto    // 自動生成（Transaction更新時に仕訳も更新）
    case locked  // 仕訳をユーザーが編集したので自動更新しない
}
```

制約：
- `taxDeductibleRate` は 0...100 にクランプ
- `type == .transfer` のとき  
  - `categoryId` は “空” を許容（UIでカテゴリ非表示）  
  - `allocations` は空でも許容（プロジェクト配分は無し）

### 4.3 PPCategory（既存）に「勘定科目紐付け」を追加
`Models/Models.swift` の `PPCategory` に以下を追加：

| フィールド | 型 | 必須 | デフォルト | 説明 |
|---|---:|:---:|---|---|
| `linkedAccountId` | `String?` | ✅ | `nil` | このカテゴリを会計上どの勘定科目に計上するか |

方針：
- 既存カテゴリは維持（UI/管理会計で使う）
- 会計上は `linkedAccountId` を参照して仕訳作成
- 未設定カテゴリがある場合は、会計画面で「未紐付け」を提示し、ユーザーに設定させる

---

## 5. 新規SwiftDataモデル定義（Accounting Models）

新規ファイル：`ProjectProfit/Models/AccountingModels.swift`（または `Models/Accounting/*.swift`）

### 5.1 勘定科目：PPAccount
```swift
@Model
final class PPAccount {
    @Attribute(.unique) var id: String   // 例: "acct-cash", "acct-sales"
    var name: String                     // 表示名
    var type: AccountType                // 資産/負債/純資産/収益/費用
    var subtype: AccountSubtype          // 現金/普通預金/売掛金/...（UI用途）
    var normalBalance: NormalBalance     // 借方/貸方（計算用）
    var isSystem: Bool                   // システム勘定（削除不可）
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
}
```

enum：
```swift
enum AccountType: String, Codable { case asset, liability, equity, revenue, expense }
enum NormalBalance: String, Codable { case debit, credit }
enum AccountSubtype: String, Codable {
    case cash, bank, accountsReceivable, accountsPayable, creditCard
    case ownerCapital, ownerDrawings
    case sales, otherIncome
    case hosting, tools, ads, contractor, communication, supplies, transport, food, entertainment, otherExpense
    case suspense // 仮勘定（未紐付け時の退避）
}
```

必須要件：
- `id` は**固定ID**を採用（移行・テンプレ・マッピングのため）
- `isSystem == true` の科目は削除不可・名称編集制限あり（例：現金、事業主貸/借 など）

### 5.2 仕訳：PPJournalEntry / PPJournalLine
```swift
@Model
final class PPJournalEntry {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sourceKey: String // "tx:<uuid>" or "manual:<uuid>"
    var date: Date
    var memo: String
    var entryType: JournalEntryType
    var isPosted: Bool           // trueのみ帳簿に反映
    var createdAt: Date
    var updatedAt: Date
}

enum JournalEntryType: String, Codable {
    case transaction   // PPTransaction由来
    case opening       // 期首残高
    case adjusting     // 決算整理
    case closing       // 決算振替
    case manual        // 手入力
}
```

`PPJournalLine`：
```swift
@Model
final class PPJournalLine {
    @Attribute(.unique) var id: UUID
    var entryId: UUID           // SwiftData relationshipでも可（推奨はrelationship）
    var accountId: String
    var debit: Int
    var credit: Int
    var memo: String
    var createdAt: Date
    var updatedAt: Date
}
```

**推奨（SwiftData Relationship版）**  
- `PPJournalEntry` に `@Relationship(deleteRule: .cascade) var lines: [PPJournalLine]`  
- `PPJournalLine` に `var entry: PPJournalEntry?`（inverse）

制約（保存前に必ず検証）：
- 1行につき `debit > 0 XOR credit > 0`（両方>0禁止、両方0禁止）
- 1仕訳合計で `sum(debit) == sum(credit)`  
- 金額は `>= 0`、円単位（Int）
- `isPosted == false` の仕訳は帳票/集計に含めない（ドラフト扱い）

### 5.3 会計設定：PPAccountingProfile（1件のみ）
```swift
@Model
final class PPAccountingProfile {
    @Attribute(.unique) var id: String // "profile-default"
    var bookkeepingEnabled: Bool       // 会計機能ON/OFF（既存ユーザー段階導入）
    var defaultPaymentAccountId: String // "acct-cash"
    var fiscalStartMonth: Int          // 既存UserDefaultsと同期
    var createdAt: Date
    var updatedAt: Date
}
```

同期方針：
- 既存の `FiscalYearSettings.startMonth`（UserDefaults）を **単一ソース**にしない  
  → 互換性のため、**起動時に profile.fiscalStartMonth → UserDefaults を同期**し、設定変更時も両方更新

---

## 6. マイグレーション仕様（SwiftData + データ補完）

### 6.1 SwiftDataスキーマ移行方針
- 今回の変更は「新規モデル追加」「既存モデルに optional/デフォルト付き属性追加」が中心であり、ModelContainerはスキーマ変化に対して自動マイグレーションを行い、複雑なケースでは `SchemaMigrationPlan` を指定できる。  
  - Apple公式：ModelContainer  
  - https://developer.apple.com/documentation/swiftdata/modelcontainer
- 本実装では、**SwiftDataの自動マイグレーション + 起動後のデータ補完（バックフィル）**を採用する  
  （VersionedSchema本格導入は将来の大規模変更時に検討）

### 6.2 起動時データ補完（必須）：AccountingBootstrapService
新規：`ProjectProfit/Services/Accounting/AccountingBootstrapService.swift`

#### 6.2.1 実行タイミング
- `DataStore.loadData()` の最後に必ず実行（カテゴリseedの後）
- 1回のみ実行したい処理は `PPAccountingProfile` の存在で判定

#### 6.2.2 補完手順（厳密）
1) `PPAccountingProfile` がなければ作成  
   - `id = "profile-default"`
   - `bookkeepingEnabled = true`（初期はONでよいが、UIでOFFも可能）
   - `defaultPaymentAccountId = "acct-cash"`
   - `fiscalStartMonth = FiscalYearSettings.startMonth`

2) **デフォルト勘定科目の作成（id固定）**  
   作成する最小セット（isSystem=true）：

   - 資産：  
     - `acct-cash`（現金 / subtype.cash / normalBalance.debit）  
     - `acct-bank`（普通預金 / subtype.bank / debit）  
     - `acct-ar`（売掛金 / subtype.accountsReceivable / debit）  
   - 負債：  
     - `acct-ap`（買掛金 / subtype.accountsPayable / credit）  
     - `acct-cc`（クレジットカード / subtype.creditCard / credit）  
   - 純資産：  
     - `acct-owner-capital`（元入金 / subtype.ownerCapital / credit）  
     - `acct-owner-drawings`（事業主貸 / subtype.ownerDrawings / debit）  
   - 収益：  
     - `acct-sales`（売上高 / subtype.sales / credit）  
     - `acct-other-income`（雑収入 / subtype.otherIncome / credit）  
   - 費用：  
     - `acct-hosting`, `acct-tools`, ... （DEFAULT_CATEGORIESに対応する費用科目 / debit）  
   - 仮勘定：  
     - `acct-suspense`（仮勘定 / subtype.suspense / debit）  
       ※カテゴリ未紐付けの場合の退避先

3) `PPCategory.linkedAccountId` の初期紐付け  
   - DEFAULT_CATEGORIES の id と名前から、対応する `acct-*` を設定  
   - ユーザー追加カテゴリは `nil` のまま（会計画面で設定させる）

4) 既存 `PPTransaction` に不足フィールドを補完  
   - `paymentAccountId` 未設定 → profile.defaultPaymentAccountId（通常 `acct-cash`）  
   - `taxDeductibleRate` 未設定 → 100  
   - `bookkeepingMode` 未設定 → `.auto`

5) **既存取引 → 仕訳生成（バックフィル）**
   - 全 `PPTransaction` を走査し、`AccountingEngine.upsertJournalForTransaction()` を呼ぶ  
   - 生成した `PPJournalEntry.id` を `PPTransaction.journalEntryId` に保存

6) **整合性検査（必須）**
   - 全仕訳で貸借一致チェック  
   - 不一致があれば `PPJournalEntry.isPosted = false` とし、会計ホームで「要修正」として出す（原因表示）

---

## 7. 既存取引→仕訳変換仕様（AccountingEngine）

新規：`ProjectProfit/Services/Accounting/AccountingEngine.swift`

### 7.1 Public API（DataStoreから呼ぶ）
```swift
@MainActor
final class AccountingEngine {
    init(modelContext: ModelContext)

    func upsertJournal(for transaction: PPTransaction) throws -> PPJournalEntry
    func deleteJournal(for transactionId: UUID) throws
    func rebuildAllJournals(transactions: [PPTransaction]) throws

    func validate(entry: PPJournalEntry) -> [AccountingIssue]
}
```

`AccountingIssue` 例：
- `.unbalanced(debitTotal:Int, creditTotal:Int)`
- `.missingAccount(accountId:String)`
- `.invalidLine(debit:Int, credit:Int)`
- `.illegalCharacter(field:String, char:String)`（e-Tax向けにも再利用）

### 7.2 sourceKey設計（重複生成防止）
- `PPJournalEntry.sourceKey = "tx:\(transaction.id.uuidString)"` を固定  
- upsert時は sourceKeyで既存Entryをfetchし更新、なければ新規作成

### 7.3 変換ルール（TransactionType別）

#### 7.3.1 収益（income）
- 金額：`A = transaction.amount`
- 入金口座：`payment = transaction.paymentAccountId`
- 収益科目：  
  - `category.linkedAccountId` があればそれ  
  - なければ `acct-sales`（収益カテゴリの場合）  
  - それも無理なら `acct-suspense`

仕訳：
- 借方：`payment` に `A`
- 貸方：`revenue` に `A`

#### 7.3.2 経費（expense）
- 金額：`A`
- 支払口座：`payment`
- 費用科目：`expenseAccount = category.linkedAccountId ?? acct-other-expense ?? acct-suspense`
- 必要経費算入率：`r = taxDeductibleRate (0..100)`

算入額：
- `B = floor(A * r / 100)`
- `C = A - B`

仕訳（r==100なら2行、r<100なら3行）：
- 借方：`expenseAccount` に `B`
- 借方：`acct-owner-drawings` に `C`（家事按分・私的分）
- 貸方：`payment` に `A`

#### 7.3.3 振替（transfer）
- 金額：`A`
- 振替元：`from = transaction.paymentAccountId`
- 振替先：`to = transaction.transferToAccountId`（必須）

仕訳：
- 借方：`to` に `A`
- 貸方：`from` に `A`

UI/入力制約：
- transfer時はカテゴリ選択を無効化（または「なし固定」）
- allocationsは空でもOK

### 7.4 ロック（bookkeepingMode = locked）挙動
- `PPTransaction.bookkeepingMode == .locked` の場合：
  - `upsertJournal(for:)` は「金額/日付/メモ等」を**更新しない**（完全不干渉）
  - 代わりに `AccountingIssue.lockedTransactionMismatch` を出して会計画面で警告
- 解除操作（UI）：  
  - 「仕訳を自動生成に戻す」ボタン → `bookkeepingMode = .auto` に戻して再生成

---

## 8. DataStore改修仕様（CRUD同期・ロード）

### 8.1 loadData()拡張（会計モデルのFetch追加）
`Services/DataStore.swift`

追加：
- accounts / journalEntries / journalLines をfetch（必要に応じて）
- `AccountingBootstrapService.runIfNeeded()` を呼び出し
- bootstrap後に accounts/journals を refresh

DataStoreに保持する配列追加：
```swift
var accounts: [PPAccount] = []
var journalEntries: [PPJournalEntry] = []
```

### 8.2 取引CRUDでの仕訳同期
`addTransaction` / `updateTransaction` / `deleteTransaction` の最後に：

- add/update：
  - `let entry = try accountingEngine.upsertJournal(for: transaction)`
  - `transaction.journalEntryId = entry.id`
- delete：
  - `try accountingEngine.deleteJournal(for: id)`
  - transaction削除の前に実行

### 8.3 配分再計算系の既存ロジックへの影響
配分（allocations）変更は、仕訳金額や貸借に直接影響しない（本仕様では仕訳にプロジェクト配分を持たせないため）。  
ただし、以下フィールドが変わる場合は仕訳再生成が必要：
- `type`, `amount`, `date`, `categoryId`, `memo`, `paymentAccountId`, `transferToAccountId`, `taxDeductibleRate`

### 8.4 CSV Import/Export拡張
`Utilities.generateCSV`, `parseCSV`, `DataStore.importTransactions`

#### 8.4.1 CSVヘッダ（新）
既存：`日付, 種類, 金額, カテゴリ, プロジェクト, メモ`

追加：
- `支払口座`（paymentAccountName or id）
- `振替先口座`（transfer時）
- `必要経費算入率`

例：
`"日付","種類","金額","カテゴリ","支払口座","振替先口座","必要経費算入率","プロジェクト","メモ"`

#### 8.4.2 Import仕様
- 支払口座名 → `PPAccount.name` でマッチ、なければ `acct-cash`
- 振替は `種類=="振替"` を認識し `transferToAccountId` を設定
- 算入率が空なら100

---

## 9. 会計レポート生成仕様（試算表・元帳・P/L・B/S）

新規：`ProjectProfit/Services/Accounting/AccountingReportService.swift`

### 9.1 基本：仕訳の抽出条件
- `PPJournalEntry.isPosted == true`
- 対象期間：`startDate <= entry.date <= endDate`
- 勘定科目存在チェック：accountIdが不正な行はレポートから除外し、Issuesへ

### 9.2 試算表（Trial Balance）
出力：勘定科目ごとに
- 期首残高（借/貸）
- 当期増減（借/貸）
- 期末残高（借/貸）

計算：
- 期首残高：`opening` エントリ（当期startDate当日）からの残高、または前期末までの累積残高  
  - 実装簡易性のため、**opening仕訳方式を必須**とする
- 当期増減：期間内の journalLines を accountId で集計
- 期末残高：期首 + 当期増減

**貸借一致チェック（試算表レベル）**
- 全科目の当期借方合計 == 当期貸方合計
- 不一致なら「帳簿エラー」としてトップに警告

### 9.3 総勘定元帳（General Ledger）
- 口座（勘定科目）を選択 → 仕訳行を日付順に一覧
- 各行：日付 / 相手科目（可能なら推定）/ 摘要 / 借方 / 貸方 / 残高
- “相手科目”推定：同一仕訳の中で、自行と反対側の最大金額の科目を表示（複数なら「複数」）

### 9.4 損益計算書（P/L）
- 収益（AccountType.revenue）：`credit - debit` の合計
- 費用（AccountType.expense）：`debit - credit` の合計
- 当期純利益：収益合計 - 費用合計
- 表示：科目別内訳 + 合計

### 9.5 貸借対照表（B/S）
- 資産：`debit - credit`
- 負債・純資産：`credit - debit`
- 期末で資産合計 == 負債+純資産合計 をチェック
- 不一致時：原因候補（未投稿仕訳、仮勘定残高、未設定opening）を提示

---

## 10. UI追加仕様（画面・導線・文言）

### 10.1 タブ追加（MainTabView）
`Views/ContentView.swift` の `TabView` に新規タブ：

- タブ名：**「帳簿」**
- systemImage：`"book.closed.fill"`（例）
- 構成：`NavigationStack { AccountingHomeView() }`

### 10.2 AccountingHomeView（会計ホーム）
新規：`Views/Accounting/AccountingHomeView.swift`

表示要素：
- 期間選択（年度：現行 FiscalYearSettings startMonth を利用）
- ステータスカード：
  - 未紐付けカテゴリ数
  - 未設定口座（存在しないaccountId参照）数
  - 貸借不一致仕訳数
  - 仮勘定残高（acct-suspense）
- クイック導線：
  - 勘定科目（Chart of Accounts）
  - 仕訳帳
  - 元帳
  - 試算表
  - P/L
  - B/S
  - e-Tax出力（準備）

### 10.3 勘定科目管理（ChartOfAccountsView）
新規：`Views/Accounting/ChartOfAccountsView.swift`

機能：
- 科目一覧（type別セクション）
- 追加（ユーザー科目のみ）
- 編集（name, subtype, sortOrder, isActive）
- 削除（isSystem==falseのみ / 使用中なら削除不可）

### 10.4 カテゴリ→科目紐付け画面（CategoryAccountMappingView）
新規：`Views/Accounting/CategoryAccountMappingView.swift`

機能：
- 収益カテゴリ一覧（linkedAccountId未設定を上に）
- 経費カテゴリ一覧（同上）
- 各カテゴリ行：カテゴリ名 + 紐付け科目Picker
- “未紐付けが残っている場合はe-Tax出力不可” とする（ただし帳簿表示は仮勘定で可能）

### 10.5 仕訳帳（JournalListView / JournalDetailView）
新規：`Views/Accounting/JournalListView.swift`, `JournalDetailView.swift`

一覧：
- 日付 / 摘要 / 借方合計 / 貸方合計 / entryType / posted
- フィルタ：期間、entryType、posted

詳細：
- 仕訳行（借方/貸方、科目、金額、摘要）
- エラー表示（貸借不一致、科目不明）
- postedトグル（会計に反映/しない）

編集：
- `entryType != .transaction` の場合は自由編集可（決算整理・手入力）
- `entryType == .transaction` の場合：
  - 「会計モードで編集」ボタン → 編集後、元の `PPTransaction.bookkeepingMode = .locked` にする  
  - Transaction画面には「仕訳がロックされています」バナー表示

### 10.6 元帳（LedgerView）
新規：`Views/Accounting/LedgerView.swift`

- 科目選択 → 明細一覧
- 残高推移、期間フィルタ

### 10.7 試算表 / P/L / B/S 画面
新規：
- `TrialBalanceView.swift`
- `ProfitLossView.swift`
- `BalanceSheetView.swift`

共通：
- 期間選択（会計年度）
- CSV/PDF書き出し（最初はCSV必須、PDFは任意）

---

## 11. 取引入力UI改修（TransactionFormView）

`Views/Components/TransactionFormView.swift`

### 11.1 種類セクション改修
現状：経費/収益の2択  
→ 3択：経費 / 収益 / 振替

- 振替選択時：
  - カテゴリセクション非表示
  - 配分セクション非表示（または固定で空）
  - 口座セクションで「振替元」「振替先」を必須入力

### 11.2 口座セクション（新規）
追加セクション：`accountSection`

- income/expense：
  - 「入出金口座（現金/普通預金/クレカ…）」Picker  
  - 初期値：`acct-cash`
- transfer：
  - 「振替元口座」Picker（paymentAccountId）
  - 「振替先口座」Picker（transferToAccountId）

Picker候補：
- `PPAccount` のうち subtypeが cash/bank/creditCard/ar/ap 等の “実務口座” を優先表示
- isActiveのみ

### 11.3 必要経費算入率（新規）
- 経費のみ表示
- UI：0/50/80/100 のクイック + スライダー（0..100）
- 初期100
- 補足：家事按分等の用途説明（税務判断はユーザー責任）

### 11.4 保存バリデーション
- income/expense：
  - amount>0
  - category必須
  - allocations必須 & 合計100（現行維持）
  - paymentAccountId必須
- transfer：
  - amount>0
  - from/to必須（同一口座禁止）
  - allocations不要
  - category不要

---

## 12. e-Tax `.xtx` エクスポータ：I/F完全仕様

### 12.1 事実前提（仕様準拠の根拠）
- `.xtx` は申告等データとして利用され、e-Taxソフト等で読み込み・送信に使われる。  
  - https://www.e-tax.nta.go.jp/toiawase/faq/sousin/03.htm
- 国税庁は開発者向けに e-Tax仕様書を公開し、ドラフト版は変更され得る旨を明記している。  
  - https://www.e-tax.nta.go.jp/shiyo/index.htm
- 文字制限があり、禁止文字混入時にエラーになり得るため、生成前チェックが必要。  
  - https://www.e-tax.nta.go.jp/tetsuzuki/tetsuzuki7.htm

### 12.2 データモデル（エクスポータ入力）  
新規：`ProjectProfit/Services/Etax/EtaxModels.swift`

```swift
struct EtaxExportRequest {
    let taxYear: Int                 // 例：2025年分
    let filer: EtaxFilerProfile      // 納税者情報（最低限）
    let bookkeeping: EtaxBookkeepingPackage // 青色/白色用の帳票データ
    let options: EtaxExportOptions
}

struct EtaxFilerProfile {
    var name: String
    var nameKana: String?
    var address: String?
    var phone: String?
    // マイナンバー等は原則入力させない（セキュリティ/運用上）
}

enum EtaxReturnType { case blue, white }

struct EtaxBookkeepingPackage {
    let type: EtaxReturnType
    let profitLoss: ProfitLossSnapshot
    let balanceSheet: BalanceSheetSnapshot? // 青色の一般用を想定
    let notes: [String: String]             // 任意（摘要など）
}

struct EtaxExportOptions {
    var validateAllowedCharacters: Bool = true
    var replaceIllegalCharacters: Bool = true
    var illegalCharacterReplacement: String = " " // 空白
    var includePreviewPdf: Bool = false // まずはfalse固定でもOK
}
```

`ProfitLossSnapshot / BalanceSheetSnapshot` は会計レポートサービスの結果をそのまま使える形で定義する（科目→金額の辞書 + 合計）。

### 12.3 エクスポータI/F（プロトコル）
新規：`ProjectProfit/Services/Etax/EtaxXtxExporter.swift`

```swift
protocol EtaxXtxExporting {
    func export(request: EtaxExportRequest) throws -> EtaxExportResult
}

struct EtaxExportResult {
    let fileName: String         // 例: "ProjectProfit_2025_xtx.xtx"
    let data: Data               // xtxファイル本体
    let warnings: [EtaxWarning]  // 文字置換/未設定項目 等
}

enum EtaxWarning: Equatable {
    case illegalCharacterReplaced(field: String, original: String, replacedWith: String)
    case missingOptionalField(field: String)
    case mappedToSuspense(accountId: String)
}

enum EtaxExportError: Error {
    case missingRequiredField(String)
    case invalidState(String)         // 貸借不一致など
    case etaxSpecNotAvailable(String) // 年分仕様が見つからない
    case buildFailed(String)
}
```

### 12.4 実装要件（必須）
1) **年分別のe-Tax仕様に基づき、XML構造・フィールドを生成できる構成**にする  
   - 仕様書は国税庁が公開、更新がある  
   - https://www.e-tax.nta.go.jp/shiyo/index.htm  
   - 方針：`EtaxFieldMap_<taxYear>.json` 等のマッピングファイルをアプリ同梱し差し替え可能にする

2) **利用可能文字チェック**  
   - 公式の利用可能文字一覧に準拠し、禁止文字を検知・置換/エラー  
   - https://www.e-tax.nta.go.jp/tetsuzuki/tetsuzuki7.htm

3) **生成前の会計整合性チェック**（ブロッカー）
- 試算表が貸借一致していること
- 仮勘定（acct-suspense）残高が0であること（またはユーザーに承認させる）
- 未紐付けカテゴリが0であること（青色は必須）

### 12.5 UI（e-Tax出力画面：EtaxExportView）
新規：`Views/Etax/EtaxExportView.swift`

- 年分選択
- 青色/白色選択
- チェックリスト（OK/NG）
  - 貸借一致
  - 未紐付け
  - 仮勘定残
  - 禁止文字
- 「.xtxを生成」→ ShareSheet で書き出し  
- “送信はe-Tax公式で行う” 文言表示（免責）

### 12.6 受入テスト（.xtx）
- 生成した `.xtx` が e-Taxソフト（WEB版）で読み込めること  
  - https://www.e-tax.nta.go.jp/toiawase/qa/e-taxweb/49.htm

---

## 13. 非機能要件

### 13.1 パフォーマンス
- 取引 10万件でも試算表生成が実用（目安：2秒以内）  
  - 方針：journalLines を一括fetchし辞書集計、画面表示のたびに全件スキャンしない

### 13.2 端末内完結（プライバシー）
- 会計データ、納税者情報（氏名等）は端末内保存（SwiftData）  
- `.xtx` 生成はオンデバイスのみ  
- 共有はユーザー操作（ShareSheet）

---

## 14. テスト仕様（ProjectProfitTestsに追加・更新）

### 14.1 既存テスト更新
- `TransactionType` のallCases数/ rawValue 前提のテストを更新  
- `getOverallSummary` 等が transfer を誤って費用扱いしないよう修正

### 14.2 新規テスト（必須）
新規：`ProjectProfitTests/AccountingEngineTests.swift`

1) income→2行仕訳（借：口座、貸：収益）  
2) expense（r=100）→2行仕訳  
3) expense（r=80）→3行仕訳（事業主貸が残る）  
4) transfer→2行仕訳（資産間振替）  
5) カテゴリ未紐付け→仮勘定を使用しwarningが出る  
6) bookkeepingMode=locked→upsertが仕訳を上書きしない  
7) 貸借一致検証  

新規：`ProjectProfitTests/TrialBalanceTests.swift`
- 試算表貸借一致
- B/S一致（資産=負債+純資産）

---

## 15. 受入条件（外注納品のDefinition of Done）

1) 既存アプリがクラッシュせず起動し、既存データが残る  
2) 会計ホームにて、勘定科目/仕訳帳/元帳/試算表/P-L/B-S が閲覧できる  
3) 既存の PPTransaction を自動で仕訳化し、試算表が貸借一致する（少なくとも仮勘定で破綻しない）  
4) 取引入力で「入出金口座」「振替」「必要経費算入率」が扱える  
5) `.xtx` エクスポータI/F が実装され、禁止文字チェックを行い、ShareSheetでファイル出力できる  
6) 単体テストが追加され、Xcode test が通る

---

## 16. 既知の不確実性と、仕様としての吸収方法（重要）
- `.xtx` の内部構造・フィールドは国税庁の開発者向け仕様書に準拠し、更新があり得る。  
  - https://www.e-tax.nta.go.jp/shiyo/index.htm  
  → 本仕様では、**I/Fと年分別マッピングファイル方式**を必須化し、変更吸収を可能にする  
- e-Taxの禁止文字は運用上トラブルになりやすい  
  - https://www.e-tax.nta.go.jp/tetsuzuki/tetsuzuki7.htm  
  → 事前検査と置換/エラー分岐を必須化  
- 65万円控除は e-Tax提出または電子帳簿保存が絡む  
  - https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/2072.htm  
  → 本仕様は帳簿整備・データ生成まで。送信はユーザーが公式で実施

---

## 最終セルフチェック（仕様の穴になりやすい点）
- 「transfer追加」により、既存集計（income以外=expense）を全箇所修正が必要（Dashboard/Report/Category集計など）。漏れると数字が壊れる。  
- `.xtx` は“生成できる”と“e-Taxに取り込める”が別。I/F＋仕様書準拠＋読み込み受入テストをセットで要求している。  
- 青色65万円要件は国税庁の記載に沿い、保証をせず、ユーザーの運用・提出責任に寄せている。

