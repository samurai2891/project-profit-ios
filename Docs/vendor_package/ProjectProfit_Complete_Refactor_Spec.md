
# ProjectProfit 完全リファクタリング指示書  
## 個人事業主向け・プロジェクト別管理を維持したまま、会計・税務・帳簿・証憑・申告までを一体化するための最終設計書

作成日: 2026-03-01  
対象: `project-profit-ios` 現行コードベースの全面再設計  
前提: **コンセプトは維持する**  
- 個人事業主向け
- プロジェクトごとに管理できる
- 会計がノーストレス
- AI は **オンデバイス限定**
- UI は必要なら変えてよい
- 汎用性を高め、幅広い業種に対応する
- 帳簿は **法定帳簿としても、管理会計としても破綻しない完成形** にする

> 現況注記（2026-03-07）
> この文書は目標アーキテクチャ仕様書として維持する。現行 repo では canonical profile、税務状態/preflight、evidence intake、approval queue、検索 index、migration dry-run、backup / restore、golden / canonical E2E、release CI は実装済みまたは部分実装まで進んでいる。
> 一方で、`AccountingEngine` の runtime caller 残存、`Recurring` 自動実行、`FormEngine` 不在、`TaxYearPacks/*/filing` と `consumption_tax` 未整備、`ExportCoordinator` 本線未集約は未達である。
> 現在の実装棚卸しには `release_ticket_list.md` を優先する。

---

# 0. この指示書の結論

このアプリは、現状でも

- プロジェクト配賦
- 定期取引
- OCR 取込
- 自動仕訳
- 青色/白色の帳票生成
- e-Tax XML 出力の土台
- 固定資産・棚卸
- テスト群

をすでに持っており、**「良い方向を向いている」** のは間違いありません。

しかし、現状のままでは **完成した会計システム** にはなりません。  
理由は単純で、現在の設計が **「取引入力中心の家計簿寄り会計アプリ」** と **「税務申告システム」** の中間にあり、次の重要要素が未完成だからです。

1. **税務状態が薄い**  
   青色 65/55/10、現金主義、白色、課税/免税、一般/簡易/2割特例、インボイス登録有無、電子帳簿要件が、内部モデルに十分載っていない。

2. **証憑が弱い**  
   OCR で文字が読めても、証憑台帳・電子取引保存・検索・訂正削除履歴・帳簿との相互関連が十分ではない。

3. **消費税が浅い**  
   いまの消費税ロジックでは、標準/軽減の分離、税率別税額、少額特例、80%/50% 経過措置、2割特例、適格/非適格の証憑根拠を扱いきれない。

4. **帳簿の正本が二重化している**  
   `DataStore` 側の会計世界と `LedgerDataStore` 側の帳簿世界が分かれていて、将来の整合性事故の原因になる。

5. **帳票が公式様式の細部に届いていない**  
   収支内訳書と青色申告決算書は、表面の合計額だけではなく、月別、明細、内訳、貸借対照表、減価償却、売上先・仕入先明細まで揃って初めて「完成」と言える。

したがって、**直すべき本質は UI ではなく、ドメインモデルと正本設計** です。

このリファクタリングの最終目標は次です。

> **証憑を起点に、プロジェクト配賦・会計・消費税・青色/白色申告・帳簿保存・e-Tax 出力までを一貫管理できる、個人事業主向け完全会計システムにする。**

---

# 1. 非交渉原則（絶対に守る設計原則）

## 1-1. コンセプトは変えない
このアプリの核は **プロジェクト別管理** です。  
これは絶対に残すべきです。  
むしろ、一般的な会計アプリとの差別化要因なので、強化対象です。

ただし、税務申告はプロジェクト単位ではなく **事業者 × 年分** で作る必要があります。  
したがって、

- **プロジェクト = 管理会計・分析軸**
- **申告 = 事業者 × 年分**

という二層構造にするのが正しいです。

## 1-2. AI はオンデバイス限定
AI は今後も完全に **オンデバイス限定** にすること。  
外部 LLM 送信、自動クラウド判定、自動アップロード前提の設計は採用しない。

AI にやらせてよいのは次のみです。

- OCR 補助
- 項目抽出候補
- 勘定科目候補
- プロジェクト候補
- 重複証憑候補
- 異常値候補
- 類似修正候補

AI にやらせてはいけないのは次です。

- 最終税務判定
- 控除可否の確定
- 申告区分の法的確定
- 仕訳の自動確定
- 帳簿保存要件の適合確定

最終判断は **ルールエンジン + ユーザー承認** です。

## 1-3. 正本は 1 系統だけにする
このアプリでは、法定帳簿・申告・プロジェクト分析・PDF/CSV/e-Tax XML が全部必要です。  
しかし、正本が複数あると必ず壊れます。

したがって、今後の正本は次の一連の流れに一本化します。

> **証憑 → 取引候補 → 仕訳候補 → 確定仕訳**

この確定仕訳だけを会計の正本にし、  
総勘定元帳・現金出納帳・収支内訳書・青色申告決算書・消費税集計表・プロジェクト損益・PDF・CSV・XML は **すべて派生** にすること。

## 1-4. 法定様式と管理会計 UI を分ける
「完璧な帳簿」を目指すときにやってはいけないのは、**法定印刷帳票をそのまま内部データ構造にすること** です。

正解は 3 層です。

1. **Canonical Internal Book（内部正本）**  
   一番情報量が多い。証憑 ID、プロジェクト、税区分、T番号、配賦、タグ、履歴を全部持つ。

2. **Legal Print View（法定表示）**  
   国税庁の帳簿・帳票様式に沿って必要な列や表示だけを出す。

3. **Management View（管理会計表示）**  
   プロジェクト、ジャンル、タグ、取引先、期間比較など分析に最適化する。

この 3 層分離が、汎用性と完璧な帳簿の両立に必要です。

---

# 2. 現行コードベースに対する診断（何が悪く、何を残すべきか）

以下は現行コードを見て、**残すべきもの** と **差し替えるべきもの** を整理したものです。

---

## 2-1. 残すべきもの

### A. `PPProject` と配賦思想
`PPTransaction.allocations` により、1 取引を複数プロジェクトへ配賦できる発想は正しいです。  
この思想はコアとして残してください。

### B. `ReceiptScannerService`
オンデバイス OCR + ローカル抽出 + フォールバックの方向性は正しいです。  
ただし、これは「残す」のではなく **Document Intake に昇格** させます。

### C. `PPDocumentRecord`
証憑保存の土台があります。  
ただし、現状のままでは弱いので、全面拡張が必要です。

### D. `AccountingEngine`
仕訳生成の考え方自体は捨てなくてよいですが、現在は単純すぎます。  
後述する新しい `PostingEngine` に役割分解して再実装します。

### E. `TaxYearDefinitionLoader`
「年分ごとに定義を切り替える」という思想は正しいです。  
しかし今は 2025 固定寄りなので、`TaxYearPack` 方式に進化させる必要があります。

### F. テスト資産
テスト数はかなり多く、これは大きな強みです。  
既存テストは残しつつ、ドメイン変更に合わせて **ゴールデンテスト** と **年分回帰テスト** を大量追加します。

---

## 2-2. 差し替えるべきもの

### A. `PPAccountingProfile.swift`
現行の `isBlueReturn: Bool` では制度を表現できません。  
**完全差し替え** 対象です。

### B. `ConsumptionTaxModels.swift`
`outputTaxTotal / inputTaxTotal / taxPayable` の 3 項目では不足です。  
**全面作り直し** が必要です。

### C. `TaxLineDefinitions.swift`
現行の `TaxLine` は科目ラインの粒度が荒く、青色/白色帳票に足りません。  
**法定ラインマッピング層** を別に新設する必要があります。

### D. `LedgerDataStore` 系
現状は会計正本と並行して別帳簿系の世界を持っており危険です。  
**正本から派生する Books レイヤー** に置き換えるべきです。

### E. `InvoiceType`
`〇 / 8割控除 / 少額特例` しかなく、50% 経過措置が欠けています。  
**消費税控除根拠モデル** に差し替えます。

### F. `ShushiNaiyakushoBuilder` / `EtaxFieldPopulator`
部分的には使えますが、いまのままでは帳票の細部に届きません。  
**Form Engine** に再構築します。

### G. `ChartOfAccountsView`
現在はほぼ閲覧用です。  
ユーザー追加勘定科目・マッピング変更が必要なので、**完全な勘定科目管理画面** に差し替えます。

---

## 2-3. 追加が必須なもの

- `Counterparty` 取引先マスタ
- `TaxYearProfile`
- `EvidenceDocument`
- `EvidenceVersion`
- `PostingCandidate`
- `PostingApproval`
- `TaxCode`
- `PurchaseCreditMethod`
- `ConsumptionTaxWorksheet`
- `FormPack`
- `LegalReportLine`
- `GenreTag`
- `DistributionRule`
- `ProjectSharedBucket`
- `AuditEvent`
- `YearLock`
- `BookSpec`
- `SearchIndex`
- `ImportProfile`
- `PreflightValidation`

---

# 3. 最終到達形のプロダクト定義

このアプリの完成形を明確に定義します。

## 3-1. プロダクト定義
このアプリは次の一文で表現できる状態にする。

> **個人事業主が、証憑を取り込むだけで、プロジェクト別の収支と利益を把握しながら、法定帳簿・消費税集計・青色申告決算書・収支内訳書・e-Tax 提出データまで、オンデバイスで安全に作成・保存できる会計システム。**

## 3-2. ユーザーが感じるべき価値
- 領収書や請求書を撮るだけで、ほぼ下書きが完成する
- プロジェクト損益が一目で分かる
- 定期取引や共通経費が自動で配賦される
- 青色/白色/消費税のルールを意識しなくても、間違いにくい
- 税務上必要な帳簿・証憑の保存が漏れない
- 年末に慌てない
- クラウド AI に証憑を送らなくてよい

---

# 4. 完成形アーキテクチャ

---

## 4-1. 推奨レイヤー構成

```text
App / SwiftUI
 ├─ Features
 │   ├─ Inbox（証憑）
 │   ├─ Projects
 │   ├─ Transactions / Approvals
 │   ├─ Books
 │   ├─ Filing
 │   ├─ Tax
 │   └─ Settings
 │
 ├─ Application Layer
 │   ├─ IntakeOrchestrator
 │   ├─ PostingOrchestrator
 │   ├─ ClosingOrchestrator
 │   ├─ FilingOrchestrator
 │   └─ ImportOrchestrator
 │
 ├─ Domain Layer
 │   ├─ BusinessProfile
 │   ├─ TaxYearProfile
 │   ├─ Project
 │   ├─ Counterparty
 │   ├─ EvidenceDocument
 │   ├─ PostingCandidate
 │   ├─ PostedJournal
 │   ├─ Account / TaxCode / LegalReportLine
 │   ├─ FixedAsset / Inventory
 │   ├─ DistributionRule / RecurringTemplate
 │   ├─ ConsumptionTaxWorksheet
 │   ├─ ReturnPackage
 │   └─ AuditEvent / YearLock
 │
 ├─ Domain Services
 │   ├─ OCRExtractionService (on-device)
 │   ├─ ClassificationService
 │   ├─ PostingEngine
 │   ├─ TaxEngine
 │   ├─ BookEngine
 │   ├─ FormEngine
 │   ├─ ValidationEngine
 │   └─ SearchIndexService
 │
 ├─ Infrastructure
 │   ├─ Persistence
 │   ├─ FileStore
 │   ├─ Keychain / SecureStore
 │   ├─ PDF / CSV / XLSX / XML exporters
 │   └─ TaxYearPack Loader
 │
 └─ Tax Packs
     ├─ 2025
     ├─ 2026
     └─ ...
```

---

## 4-2. 正本データの流れ

```text
証憑原本
  ↓
OCR / 抽出 / ルール判定
  ↓
証憑フィールド確定
  ↓
仕訳候補
  ↓（承認）
確定仕訳
  ↓
帳簿・帳票・集計・申告・XML・PDF
```

この順番を崩してはいけません。

---

# 5. データモデルの全面再設計

---

## 5-1. `PPAccountingProfile` を分割して作り直す

### 現状の問題
- `isBlueReturn` が Bool
- VAT/インボイス状態が不足
- 青色 65/55/10/現金主義の分離がない
- 年分別のルールが載っていない

### 新しいモデル構成

## `BusinessProfile`
事業者の恒久情報

- businessId
- ownerName
- ownerNameKana
- businessName
- businessType
- businessAddress
- phone
- myNumber / filing IDs（必要部分は Keychain）
- taxOfficeCode
- openingDate
- invoiceRegistrationNumber
- invoiceIssuerStatus
- defaultCurrency = JPY

## `TaxYearProfile`
年分ごとの税務状態

- businessId
- taxYear
- filingStyle  
  - `blueGeneral`
  - `blueCashBasis`
  - `white`
- blueDeductionLevel  
  - `none`
  - `ten`
  - `fiftyFive`
  - `sixtyFive`
- bookkeepingBasis  
  - `single`
  - `double`
  - `cashBasis`
- vatStatus  
  - `exempt`
  - `taxable`
- vatMethod  
  - `general`
  - `simplified`
  - `twoTenths`
- simplifiedBusinessCategory（簡易課税用）
- invoiceIssuerStatusAtYear
- electronicBookLevel  
  - `none`
  - `standard`
  - `superior`
- etaxSubmissionPlanned
- yearLockState
- taxPackVersion

### 必須仕様
- 青色 65/55/10 判定を UI ではなく **モデル** に持つこと
- 2割特例や経過措置は、年分/取引日ベースで判定可能にすること
- 年分を跨いでも状態がズレないこと

---

## 5-2. `PPTransaction` 中心から、`EvidenceDocument` 中心へ移行する

### 新モデル

## `EvidenceDocument`
証憑正本

- evidenceId
- businessId
- taxYear
- sourceType  
  - camera
  - photoLibrary
  - scannedPDF
  - emailAttachment
  - importedPDF
  - manualNoFile
- legalDocumentType  
  - receipt
  - invoice
  - qualifiedInvoice
  - simplifiedQualifiedInvoice
  - deliveryNote
  - estimate
  - contract
  - statement
  - cashRegisterReceipt
  - other
- storageCategory  
  - paperScan
  - electronicTransaction
- receivedAt
- issueDate
- paymentDate
- originalFilename
- mimeType
- fileHash
- originalFilePath
- ocrText
- extractionVersion
- searchTokens
- linkedCounterpartyId
- linkedProjectIds
- complianceStatus
- retentionPolicyId
- deletedAt
- lockedAt

## `EvidenceVersion`
訂正履歴

- versionId
- evidenceId
- changedAt
- changedBy
- previousStructuredFields
- nextStructuredFields
- reason
- modelSource  
  - ai
  - rule
  - user

## `EvidenceStructuredFields`
抽出済み構造化データ

- counterpartyName
- registrationNumber
- invoiceNumber
- transactionDate
- subtotalStandardRate
- taxStandardRate
- subtotalReducedRate
- taxReducedRate
- totalAmount
- paymentMethod
- lineItems[]
- confidence

## 必須要件
- 原本ファイルと抽出結果を分ける
- 修正履歴を残す
- `日付 / 金額 / 取引先` で検索できる
- 電子取引と紙スキャンを区別する
- 証憑から仕訳・帳票まで追跡できる

---

## 5-3. `PPTransaction` は「会計イベント」へ整理する

完全に消す必要はありませんが、位置づけを変えます。

### 新しい考え方
- `EvidenceDocument` は証憑正本
- `PostingCandidate` は仕訳候補
- `PostedJournal` は会計正本
- `Transaction` は UI 上のまとまり概念または legacy bridge として扱う

### 新モデル

## `PostingCandidate`
- candidateId
- evidenceId
- businessId
- taxYear
- candidateDate
- counterpartyId
- projectAllocations[]
- proposedLines[]
- taxAnalysis
- confidenceScore
- status  
  - draft
  - needsReview
  - approved
  - rejected
- source  
  - OCR
  - recurring
  - import
  - manual
  - carryForward

## `PostingLineCandidate`
- debitAccountId
- creditAccountId
- amount
- taxCodeId
- legalReportLineId
- projectAllocationId
- memo
- evidenceLineReference

---

## 5-4. 会計正本は `PostedJournal` に一本化する

## `PostedJournal`
- journalId
- businessId
- taxYear
- journalDate
- voucherNo
- sourceEvidenceId
- sourceCandidateId
- entryType  
  - normal
  - opening
  - closing
  - depreciation
  - inventoryAdjustment
  - recurring
  - taxAdjustment
- description
- lines[]
- approvedAt
- lockedAt

## `JournalLine`
- lineId
- journalId
- accountId
- debitAmount
- creditAmount
- taxCodeId
- legalReportLineId
- counterpartyId
- projectAllocationId
- genreTagIds[]
- evidenceReferenceId
- sortOrder

### 非交渉ルール
- 1 journal = 複数 line 前提
- 1 evidence = 複数 line 前提
- 1 evidence = 複数プロジェクト前提
- 1 evidence = 8% + 10% 混在前提
- 税抜 / 税込 両対応
- tax-inclusive / exclusive を必ず line 単位で扱えること

---

## 5-5. 取引先マスタを追加する

現状は `counterparty: String?` で弱すぎます。  
これは必須追加です。

## `Counterparty`
- counterpartyId
- displayName
- kana
- legalName
- corporateNumber
- invoiceRegistrationNumber
- invoiceIssuerStatus
- statusEffectiveFrom
- statusEffectiveTo
- countryCode
- address
- phone
- email
- defaultAccountId
- defaultTaxCodeId
- defaultProjectId
- defaultGenreTagIds
- paymentTerms
- notes

## `CounterpartyTaxStatusHistory`
- counterpartyId
- effectiveFrom
- effectiveTo
- invoiceStatus
- creditMethodDefault

### 効果
- T番号の再利用
- 売上先・仕入先明細の帳票生成
- 消費税控除根拠の精度向上
- OCR から取引先候補が引ける
- 継続取引の自動仕訳精度が上がる

---

## 5-6. 勘定科目・カテゴリ・ジャンルを完全に分離する

これは必須です。  
現状は `Category`、`Account`、`TaxLine` が少し混ざっています。  
このままだと汎用性が出ません。

## 3 層に分ける

### 1. `Account`
会計上の勘定科目  
仕訳で使う。ユーザー追加可能。

### 2. `QuickCategory`
入力補助カテゴリ  
「レシートからこのカテゴリにしやすい」という UX 用。  
内部では account/tax/genre にマッピングする。

### 3. `GenreTag`
完全自由な分析タグ  
業種ごとのジャンル、テーマ、案件種別、社内ルール、色分け、検索などに使う。  
階層化可能にする。

### 4. `LegalReportLine`
法定帳票上の固定ライン  
白色/青色/消費税帳票に落とし込むための固定マッピング先。  
これはユーザーが自由に増減してはいけない。

### 必須設計
- **Account は増やせる**
- **Genre は増やせる**
- **QuickCategory は増やせる**
- **LegalReportLine は固定**
- 各 Account は `defaultLegalReportLine` を持てる
- 1 Account を複数 LegalReportLine に期間・条件付きでマッピング可能にする

---

# 6. 勘定科目体系の再設計

---

## 6-1. 現状の問題
現行の `AccountSubtype` は、公式帳票に必要な科目行が不足しています。  
たとえば青色/白色帳票で重要な以下が弱い、または直接表現しにくい状態です。

- 荷造運賃
- 給料賃金
- 専従者給与
- 貸倒金
- 修繕費
- 福利厚生費
- 外注工賃
- 雑収入
- 税理士・弁護士等報酬
- 家事按分対象の複数パターン
- 売掛金・買掛金の補助元帳
- 仮受/仮払消費税の補助属性

## 6-2. 新しい勘定科目仕様

## 資産
- 現金
- 普通預金
- 定期預金
- 売掛金
- 受取手形
- 未収入金
- 前払費用
- 仮払金
- 立替金
- 棚卸資産
- 工具器具備品
- 車両運搬具
- 建物
- 建物附属設備
- 機械装置
- 土地
- 敷金保証金
- 事業主貸 など

## 負債
- 買掛金
- 支払手形
- 未払金
- 未払費用
- 前受金
- 仮受金
- 借入金
- 仮受消費税
- 未払消費税等
- 事業主借 など

## 収益
- 売上高
- 雑収入
- 受取利息
- 受取配当
- 収入補助金
- 返金・値引戻し調整 など

## 費用
- 仕入高
- 荷造運賃
- 水道光熱費
- 旅費交通費
- 通信費
- 広告宣伝費
- 接待交際費
- 損害保険料
- 修繕費
- 消耗品費
- 減価償却費
- 福利厚生費
- 給料賃金
- 専従者給与
- 外注工賃
- 地代家賃
- 利子割引料
- 租税公課
- 新聞図書費
- 会議費
- 研修費
- 支払手数料
- 税理士・弁護士等報酬
- 雑費
- 貸倒金
- 控除対象外消費税
- 家事按分調整
- 期首棚卸 / 期末棚卸調整 など

### 重要原則
- 初期科目は豊富に持つ
- ただし帳票マッピング先は固定
- ユーザーは自由に勘定科目を追加できる
- 追加科目は必ず次を設定する
  - account type
  - 通常借方/貸方
  - default legal line
  - default tax code
  - project allocatable flag
  - household-use-proration allowed flag

---

# 7. 消費税エンジンの全面作り直し

---

## 7-1. 現行の問題
現行 `ConsumptionTaxSummary` は 3 数値しかありません。  
しかし、実際に必要なのは、あなたが添付した消費税集計表のような **税率別・区分別・科目別・控除根拠別** の集計です。

したがって、`ConsumptionTaxReportService` は完全に作り直します。

---

## 7-2. 新しい消費税モデル

## `TaxCode`
- code
- displayName
- taxKind  
  - output
  - input
  - exempt
  - nonTaxable
  - outOfScope
- rate  
  - 10
  - 8
  - 0
- priceBasis  
  - taxIncluded
  - taxExcluded
- invoiceRequirement  
  - qualifiedRequired
  - notRequired
- creditEligibilityRule
- legalReferenceKey
- effectiveFrom
- effectiveTo

## `PurchaseCreditMethod`
仕入税額控除根拠

- qualifiedInvoice
- simplifiedQualifiedInvoice
- smallAmountSpecial
- transitional80
- transitional50
- notCreditEligible
- exemptBusinessPurchase
- mixedUsePartial
- nonTaxablePurchase

## `ConsumptionTaxLine`
- journalLineId
- transactionDate
- taxCodeId
- priceExcludingTax
- taxAmount
- rate
- direction  
  - output
  - input
- purchaseCreditMethod
- counterpartyId
- counterpartyInvoiceStatus
- evidenceId
- accountId
- legalExpenseLine
- projectAllocationId

## `ConsumptionTaxWorksheet`
- taxYear
- standardRateSalesGross
- standardRateSalesNet
- standardRateOutputTax
- reducedRateSalesGross
- reducedRateSalesNet
- reducedRateOutputTax
- expenseBreakdowns[]
- deductibleTaxSubtotalStandard
- deductibleTaxSubtotalReduced
- nonDeductibleTax
- payableTax
- creditMethodBreakdown[]
- notes

---

## 7-3. 必須ルール
このエンジンは次を満たすこと。

### 税率
- 10%
- 8%
- 非課税
- 不課税
- 対象外

### 価格基準
- 税込入力
- 税抜入力
- mixed line

### 証憑根拠
- 適格請求書
- 適格簡易請求書
- 少額特例
- 80% 経過措置
- 50% 経過措置
- 控除不可

### 制度モード
- 免税
- 課税
- 一般課税
- 簡易課税
- 2割特例

### 判定軸
- 取引日
- 相手先登録番号状態
- 証憑種別
- 課税期間
- 取引単位

### 端数処理
- **1 請求書につき、税率ごとに 1 回**
- 行単位端数処理のまま自動確定しない

### 小規模/特例判定
- 少額特例は「一取引単位」で判定できる構造にする
- 経過措置 80 → 50 の境目は **取引時点** ベースで判定可能にする
- 2割特例は `TaxYearProfile` の状態で判定可能にする

---

## 7-4. あなたの添付した消費税集計表を正式仕様にする
このアプリでは、管理用ワークシートとして、最低でも次の表を出せるようにすること。

### `ConsumptionTaxWorksheetPrint`
列:
- 項目
- 課税取引額（標準税率）
- うち国税 7.8% 適用分
- 課税取引額（軽減税率）
- うち国税 6.24% 適用分
- 合計

行:
- 課税売上高（税込）
- 課税標準額
- 消費税額
- 仕入高（税抜）
- 租税公課
- 水道光熱費
- 旅費交通費
- 通信費
- 広告宣伝費
- 接待交際費
- 損害保険料
- 修繕費
- 消耗品費
- 福利厚生費
- 外注工賃
- 地代家賃
- 利子割引料
- 雑費
- 控除税額小計
- 課税売上高（税抜）
- 差引税額

### 重要
- この表は **申告補助用の管理表** として正式採用する
- ただし内部計算の正本は `ConsumptionTaxLine` とする
- 表と内部明細は必ず drill-down できるようにする

---

# 8. 帳簿を完璧にするための標準仕様

ここはこの指示書の中でも最重要です。

**「帳簿を完璧な形式にする」** とは、単に PDF を綺麗にすることではありません。  
以下を同時に満たすことを意味します。

1. 法定帳簿として説明可能
2. 証憑との追跡が可能
3. 消費税と所得税の双方に使える
4. プロジェクト別分析も可能
5. 年次・月次・期間指定で切れる
6. PDF / CSV / 画面表示で破綻しない
7. 項目不足が起きない
8. ユーザー追加科目やジャンルにも対応できる

そのため、帳簿は **内部正本列** と **印刷表示列** を分けます。

---

## 8-1. 帳簿共通フォーマット規約

### 共通内部列（Canonical Columns）
すべての帳簿・台帳が最終的に辿れるべき内部列:

- entryId
- journalId
- lineId
- voucherNo
- evidenceId
- evidenceVersionId
- postingDate
- transactionDate
- fiscalYear
- counterpartyId
- counterpartyName
- counterpartyInvoiceNumber
- accountId
- accountCode
- accountName
- oppositeAccountName
- debitAmount
- creditAmount
- runningBalance
- taxCode
- taxRate
- purchaseCreditMethod
- taxAmount
- legalReportLine
- projectId
- projectCode
- projectName
- genreTags
- memo
- sourceType
- createdAt
- updatedAt
- lockedAt

### 共通印刷規約
- 金額は原則円単位、整数表示
- マイナスは括弧ではなく `▲` または負号のどちらかに統一
- 日付は `YYYY-MM-DD` を内部正規形式にし、印刷時は `M/D` 表示可
- 帳簿名・対象期間・事業者名・年分・ページ番号をヘッダに出す
- 月次帳簿は月初繰越・月次小計・月末残高を表示する
- 年次帳簿は期首残高・期末残高・年間合計を持てる
- 証憑番号を必ず追跡可能にする
- 税区分列は簡易表示（10, 8, 非, 不, 対外など）を持つ
- プロジェクト列は法定印刷時には非表示可、管理表示では表示する

---

## 8-2. 仕訳帳
### 目的
法定帳簿・総勘定元帳の基礎

### 印刷列
- 日付
- 伝票番号
- 摘要
- 借方科目
- 借方金額
- 貸方科目
- 貸方金額
- 税区分
- 証憑番号
- 備考

### 必須機能
- 複数行仕訳
- 仕訳承認状態
- 自動生成/手動入力の区別
- 月別小計
- 年次エクスポート
- ドリルダウンで証憑を開けること

---

## 8-3. 総勘定元帳
### 印刷列
- 日付
- 伝票番号
- 相手勘定
- 摘要
- 借方金額
- 貸方金額
- 残高
- 税区分
- 証憑番号

### 必須機能
- 科目別出力
- 期首残高 / 期末残高
- 補助科目・取引先・プロジェクトの絞り込み
- 月次小計
- 残高異常検知

---

## 8-4. 現金出納帳
### 印刷列
- 日付
- 伝票番号
- 相手勘定
- 摘要
- 入金
- 出金
- 差引残高
- 証憑番号
- プロジェクト

### 必須機能
- 現金勘定に紐づく取引のみ
- 家事消費・事業主貸借の区別
- プロジェクト別フィルタ
- 月次締め・繰越

---

## 8-5. 預金出納帳
### 印刷列
- 日付
- 伝票番号
- 銀行口座
- 相手勘定
- 摘要
- 入金
- 出金
- 残高
- 証憑番号
- プロジェクト

### 必須機能
- 口座別に出力
- 銀行明細取込と突合
- 未照合フラグ
- 振替取引の相互リンク

---

## 8-6. 売上帳
### 印刷列
- 売上日
- 伝票番号
- 売上先
- 登録番号
- 摘要
- 税抜金額（10%）
- 消費税額（10%）
- 税抜金額（8%）
- 消費税額（8%）
- 税込合計
- 入金区分
- プロジェクト
- 証憑番号

### 必須機能
- 売上先マスタとの連携
- 月別集計
- 青色/白色帳票の売上明細へ連携
- 消費税売上集計へ連携

---

## 8-7. 仕入帳
### 印刷列
- 仕入日
- 伝票番号
- 仕入先
- 登録番号
- 摘要
- 税抜金額（10%）
- 消費税額（10%）
- 税抜金額（8%）
- 消費税額（8%）
- 税込合計
- 控除方法
- プロジェクト
- 証憑番号

### 必須機能
- 適格/少額/80/50/控除不可の区別
- 控除根拠別フィルタ
- 消費税集計表への直結

---

## 8-8. 経費帳
### 印刷列
- 支出日
- 伝票番号
- 支払先
- 摘要
- 勘定科目
- 税抜本体
- 消費税額
- 税区分
- 控除方法
- 家事按分率
- 事業按分後金額
- プロジェクト
- ジャンル
- 証憑番号

### 必須機能
- 収支内訳書・青色申告決算書へのマッピング
- 雑費から正式科目への昇格提案
- 共通経費配賦前/配賦後表示

---

## 8-9. 売掛金元帳
### 印刷列
- 日付
- 伝票番号
- 得意先
- 摘要
- 売上
- 入金
- 値引返品
- 残高
- プロジェクト
- 証憑番号

### 必須機能
- 得意先別
- 請求書/入金突合
- 未回収一覧
- 期末残高を B/S に反映

---

## 8-10. 買掛金元帳
### 印刷列
- 日付
- 伝票番号
- 仕入先
- 摘要
- 仕入
- 支払
- 値引戻し
- 残高
- 控除方法
- 証憑番号

### 必須機能
- 仕入先別
- 未払一覧
- 期末残高を B/S に反映

---

## 8-11. 固定資産台帳
### 印刷列
- 資産名
- 取得日
- 取得価額
- 償却方法
- 耐用年数
- 償却率
- 事業専用割合
- 本年償却額
- 累計償却額
- 未償却残高
- プロジェクト
- 証憑番号

### 必須機能
- 青色/白色帳票の減価償却欄へ連携
- 償却方法差異
- 期中取得/売却/除却
- 少額減価償却資産等の区分

---

## 8-12. 棚卸資産台帳
### 印刷列
- 品目
- 数量
- 単価
- 評価額
- 期首数量
- 期首金額
- 期末数量
- 期末金額
- 倉庫/場所
- プロジェクト

### 必須機能
- 期首/期末棚卸
- 仕入高と売上原価の連動
- 青色/白色帳票の棚卸欄へ反映

---

## 8-13. 証憑台帳
### 印刷列 / 一覧列
- 受領日
- 取引日
- 種別
- 支払先/売上先
- 登録番号
- 金額
- 電子取引/紙スキャン
- ファイル名
- ハッシュ
- 関連仕訳
- 関連プロジェクト
- 保存期限
- 保存状態
- 最終修正日

### 必須機能
- `日付 / 金額 / 取引先` 検索
- 画像/PDF プレビュー
- 改ざん防止ログ
- 修正履歴
- 年度ロック後の編集制御
- 電子取引保存要件の可視化

---

## 8-14. プロジェクト元帳
### 目的
このアプリ独自の強み。必須帳簿。

### 印刷列
- 日付
- 伝票番号
- プロジェクト
- 区分  
  - 売上
  - 仕入
  - 経費
  - 配賦
  - 調整
- 摘要
- 勘定科目
- 収入
- 支出
- 利益寄与額
- 証憑番号
- 相手先
- ジャンル

### 必須機能
- プロジェクト別 P/L
- 共通費配賦内訳
- 期間比較
- 完了案件アーカイブ
- 単月一括全プロジェクト配賦
- プロジェクトタグ/ジャンル別分析

---

## 8-15. 定期取引台帳
### 印刷列
- テンプレート名
- 開始日
- 終了日
- 発生規則
- 金額
- 勘定科目
- 税区分
- 配賦ルール
- 対象プロジェクト範囲
- 次回実行日
- 最終生成日
- 有効/停止
- 証憑添付ルール

### 必須機能
- 該当月の自動生成
- 遡及生成
- 月次一括レビュー
- equal all projects / weighted / active-days / manual
- 単月のみ全プロジェクト配賦
- ジャンル自動付与

---

# 9. プロジェクト管理コンセプトを壊さずに完成度を上げる設計

---

## 9-1. 正しい位置づけ
プロジェクトはこのアプリの主役です。  
ただし税務申告の主軸ではありません。  
したがって、次のルールを採用します。

### ルール
- すべての証憑・仕訳は **0..n 個のプロジェクト** に紐づけ可能
- プロジェクト未所属の共通経費を許可する
- 共通経費は `shared` バケットに入り、後で配賦可能
- 申告作成時は、全プロジェクトを合算した年分全体で作成
- ただし、帳票の明細元データには project allocation を保持する

---

## 9-2. 配賦ルールの正式モデル化

## `DistributionRule`
- ruleId
- name
- scope  
  - allProjects
  - allActiveProjectsInMonth
  - selectedProjects
  - projectsByTag
  - projectsByClient
- basis  
  - equal
  - fixedWeight
  - activeDays
  - revenueRatio
  - expenseRatio
  - customFormula
- weights[]
- roundingPolicy  
  - lastProjectAdjust
  - largestWeightAdjust
- effectiveFrom
- effectiveTo
- applyTo  
  - recurring
  - manualBulk
  - monthlyClose
  - sharedCostAllocation

### これで実現すること
- 定期取引の該当月自動分配
- 単月の全プロジェクトへの自動分配
- 完了済み案件を除外した配賦
- アクティブ案件だけ配賦
- 重みづけ配賦
- 売上比/原価比/日数按分

---

## 9-3. 共通経費処理
個人事業主で多いのは、通信費、水道光熱費、サブスク、事務所家賃などの共通経費です。  
これらは最初から案件に直接つかないことが多いです。

### 新仕様
- 最初は `shared` へ投入
- 月末に一括配賦提案
- ルールに応じて自動配賦
- 配賦前/後の両表示が可能
- 申告上は合計額のみ使い、プロジェクトは管理会計で使う

---

# 10. 定期取引・自動分配機能の完成仕様

これはあなたが特に重視している部分なので、現行機能を拡張して完成仕様にします。

---

## 10-1. `RecurringTemplate` へ昇格する
現行 `PPRecurringTransaction` を拡張して次を持たせる。

## `RecurringTemplate`
- templateId
- name
- enabled
- startDate
- endDate
- cadence  
  - monthly
  - biMonthly
  - quarterly
  - yearly
  - customCronLike
- postingDayRule  
  - fixedDay
  - monthEnd
  - businessDayBefore
  - firstBusinessDay
- amountRule  
  - fixed
  - lastMonthSame
  - inflationAdjusted
  - variableFromSource
- baseAccountId
- oppositeAccountId
- taxCodeId
- evidenceRequirement  
  - none
  - optional
  - mandatoryBeforeApproval
- defaultCounterpartyId
- defaultGenreTagIds
- distributionRuleId
- autoApprovePolicy
- nextRunDate
- catchUpMode

---

## 10-2. 必須機能
- 該当月の自動生成
- 遡及生成
- 未生成月の一括補完
- 配賦ルール連動
- 単月のみ全プロジェクト自動分配
- ジャンル自動付与
- 証憑必須/任意の設定
- 発生後レビューキュー
- 支払日/利用期間の区別
- 解約・停止時の途中終了

---

## 10-3. 自動承認の範囲
定期取引は自動承認できるものと、できないものを分ける。

### 自動承認してよいもの
- 毎月同額、相手先固定、税区分固定、証憑不要または毎回同形式
- 通信費定額
- ソフトウェアサブスク
- 既知の減価償却月次仕訳

### レビュー必須
- 金額が閾値以上ズレた
- プロジェクト数が変わった
- T番号状態が変わった
- 証憑未添付
- 課税方式切替時
- 経過措置境界月

---

# 11. ユーザー追加勘定科目・ジャンル・入力補助カテゴリの完成仕様

---

## 11-1. ユーザー追加勘定科目
現状ここが弱いので、必須で強化します。

### 勘定科目作成画面に必要な項目
- 科目名
- 科目コード
- 科目種別（資産/負債/収益/費用/資本）
- 通常残高（借方/貸方）
- 補助科目可否
- プロジェクト配賦可否
- 家事按分可否
- 初期税区分
- 初期法定帳票ライン
- 表示順
- アーカイブ可否

### 重要制約
- 法定帳票ライン未設定のまま確定仕訳不可
- 削除ではなくアーカイブ方式
- 過去仕訳がある科目は名称変更可、物理削除不可

---

## 11-2. ジャンル（GenreTag）
業種汎用性のために、自由タグは必須です。

### `GenreTag`
- genreId
- name
- parentGenreId
- color
- icon
- sortOrder
- archived
- suggestedAccounts[]
- suggestedProjects[]
- suggestedCounterparties[]

### 用途
- 「案件種別」
- 「広告媒体」
- 「商品ジャンル」
- 「部門」
- 「サービス種別」
- 「経費テーマ」
- 「季節イベント」
- 「EC/店舗/業務委託」など

### 重要
- Genre は帳票ラインとは無関係
- 完全自由に増やせる
- 検索・配賦・分析に使う

---

## 11-3. 入力補助カテゴリ（QuickCategory）
ユーザー体験のための、最短入力用分類。

### 例
- コンビニ
- 電車
- カフェ打合せ
- ソフトウェア
- 外注
- 仕入
- 送料
- EC 売上
- 家賃
- 光熱費

### QuickCategory が保持するもの
- defaultAccount
- defaultTaxCode
- defaultGenreTags
- householdProrationDefault
- projectDefaultRule
- OCR keyword patterns
- counterparty patterns

---

# 12. OCR / 証憑取込を Document Intake に昇格させる

---

## 12-1. 名前を変える
`ReceiptScannerService` という名称では将来狭すぎます。  
**`DocumentIntakeService`** に改名・再設計します。

### 対応対象
- レシート
- 請求書
- 適格請求書
- 適格簡易請求書
- 納品書
- 見積書
- 契約書
- 通帳/利用明細 PDF
- メール添付 PDF
- Web 領収書 PDF
- 手入力（ファイルなし）

---

## 12-2. オンデバイス AI の責務
- OCR
- 文書種別分類
- 取引先抽出
- T番号抽出
- 日付抽出
- 金額抽出
- 税率別小計候補
- 明細行抽出
- 既存取引先とのマッチング候補
- 勘定科目候補
- プロジェクト候補
- 重複候補

### 最終判定はルールエンジン
AI が出した候補は、次の deterministic rule に通す。

- `TaxYearProfile`
- Counterparty status history
- TaxCode rules
- Price basis
- Rounding rules
- Distribution rules
- Filing rules

---

## 12-3. UI フロー
### 新トップフロー
1. **Inbox**
2. 未処理証憑一覧
3. 候補確認
4. 不足項目補完
5. 仕訳候補確認
6. 承認
7. 帳簿へ反映

### Inbox 内の状態
- 未処理
- 要確認
- 自動確定候補
- 証憑不足
- 重複候補
- 年度ロック対象
- 申告反映済み

---

## 12-4. 重複証憑検知
### 判定要素
- ハッシュ
- 取引先名類似
- 日付近似
- 金額一致
- 伝票番号一致
- OCR text 類似

### 出力
- duplicated
- possible duplicate
- unique

---

# 13. 自動仕訳エンジンを候補エンジンへ作り直す

---

## 13-1. 現行の問題
- `isTaxIncluded` の扱いが弱い
- 1 証憑 1 金額寄り
- 多税率・多行・多配賦に弱い
- 税務根拠を line に持っていない

## 13-2. 新しい構成

### `PostingEngine`
責務:
- `EvidenceStructuredFields` を `PostingCandidate` に変換
- 勘定科目候補
- 税区分候補
- 配賦候補
- ジャンル候補

### `TaxDecisionEngine`
責務:
- 仕入税額控除方法
- 2割特例/経過措置判定
- 課税/非課税/対象外判定
- tax-inclusive/exclusive 正規化

### `PostingApprovalService`
責務:
- 候補の承認
- 警告表示
- 監査ログ
- 確定仕訳生成

---

## 13-3. 非交渉仕様
- taxIncluded / taxExcluded を必ず別扱い
- 1 証憑内複数税率
- 1 証憑内複数勘定科目
- 1 証憑内複数プロジェクト
- 家事按分
- 分割仕訳
- 期中・期末調整仕訳
- 証憑なし手動仕訳も許可するが、要理由入力

---

# 14. 青色申告決算書・収支内訳書・e-Tax を Form Engine 化する

---

## 14-1. 基本思想
現在の帳票生成は「合計額を埋める」寄りです。  
完成形では、**公式様式の全ページ構造** を内部モデルと結び付けます。

---

## 14-2. `FormPack` を年分ごとに持つ

## `FormPack`
- taxYear
- version
- formDefinitions[]
- fieldDefinitions[]
- validationRules[]
- xmlMappings[]
- printLayouts[]
- deprecationRules[]
- references[]

### 例
- `FormPack/2025/blue_general.json`
- `FormPack/2025/white_shushi.json`
- `FormPack/2025/common.json`
- `FormPack/2025/consumption_tax_worksheet.json`
- `FormPack/2026/...`

### 非交渉ルール
- 1 年 1 JSON ではなく、**帳票ごとに分割**
- フィールド定義・バリデーション・表示条件・ XML mapping を分ける
- 年分パックがないときは「提出用」出力をブロック

---

## 14-3. 青色申告決算書の完成仕様
添付の PDF を基準に、少なくとも次を **完全に** サポートする。

### 1ページ
- 売上
- 期首/期末棚卸
- 差引金額
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
- 減価償却費
- 福利厚生費
- 給料賃金
- 外注工賃
- 利子割引料
- 地代家賃
- 貸倒金
- 雑費
- 繰入・戻入・専従者給与・青色特別控除計算導線

### 2ページ
- 月別売上・仕入
- 給料賃金の内訳
- 専従者給与の内訳
- 青色申告特別控除額の計算
- 貸倒引当金繰入額の計算

### 3ページ
- 減価償却費の計算
- 利子割引料の内訳
- 税理士・弁護士等の報酬の内訳
- 地代家賃の内訳
- 本年中における特殊事情

### 4ページ
- 貸借対照表
- 期首/期末
- 現金
- 当座/普通預金
- 売掛金
- 受取手形
- 棚卸資産
- 前払金
- 貸付金
- 建物/附属設備/機械/車両/工具器具備品/土地
- 買掛金
- 借入金
- 未払金
- 前受金
- 預り金
- 事業主借
- 元入金
- 青色申告特別控除前の所得金額
- 事業主貸
- 合計整合

### 完成条件
- PDF 表示
- XML 出力
- プレビューと提出データの一致
- エラー箇所ハイライト
- 明細からの drill-down

---

## 14-4. 収支内訳書の完成仕様
添付の PDF を基準に、少なくとも次を完全にサポートする。

### 1ページ
- 売上（収入）金額
- 家事消費
- その他の収入
- 期首/期末商品（製品）棚卸高
- 仕入金額
- 差引金額
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
- 空欄科目追加
- 雑費
- 専従者控除
- 所得金額

### 2ページ
- 売上先（収入先）金額の明細
- 仕入先金額の明細
- 減価償却費の計算
- 地代家賃の内訳
- 利子割引料の内訳
- 特殊事情

### 完成条件
- 空欄経費行をユーザー追加できる
- 売上先/仕入先を明細行まで埋められる
- 住所や名称が Counterparty から自動反映する
- 太枠必須項目の未入力をブロックする

---

## 14-5. e-Tax 出力の原則
- PDF は提出用データではなく、**閲覧/印刷/控え用**
- 提出用は **年分に対応した XML**
- XML field coverage が足りない場合、提出ボタンを無効化し「プレビューのみ」と表示
- 年分パックが古い場合は、提出不可にする

### 追加するべき機能
- preflight validation
- XML schema version check
- required field coverage rate
- preview vs filing parity test
- 添付不要/必要の明示
- 提出履歴保存

---

# 15. 白色申告を「青色の簡易版」にしない

これはとても重要です。

白色は単に機能を減らしたモードではなく、**別 UX** として設計する必要があります。

## 必須白色 UX
- 白色スタートウィザード
- はじめての人向け簡易記帳
- 収支内訳書の必須項目だけ先に集める
- 売上先/仕入先明細の誘導
- 空欄経費追加
- 専従者控除のガイド
- 難しい用語を青色より少なくする
- 「白色から青色へ移行」導線

---

# 16. 帳簿保存・電子取引保存の完成仕様

---

## 16-1. 現状の問題
現行 `PPDocumentRecord` は土台として良いですが、保存期間や電子取引/紙区分、検索要件、訂正削除履歴が不足しています。

## 16-2. `RetentionPolicy`
## `RetentionPolicy`
- policyId
- documentType
- storageCategory
- requiredYears
- basisDateRule
- deletionAllowedAfter
- requiresSearchIndex
- requiresRevisionHistory
- requiresMutualLinking
- legalReferenceKey

### 重要
保存期間や起算日は文書種別・年度・制度で変わる可能性があるため、**TaxPack / CompliancePack で管理** する。

---

## 16-3. 必須要件
- 電子取引か紙スキャンか明示
- 原本保存
- 修正履歴
- 訂正削除ログ
- 帳簿との相互関連
- `日付 / 金額 / 取引先` 検索
- 年度ロック後の編集制限
- エクスポート可能な証憑台帳
- ハッシュ検証
- 複数ファイル束ね（請求書 + 明細 + 納品書）

---

# 17. UI 再設計指示（UI は多少変えてよい前提）

---

## 17-1. 現在の主な問題
- 機能が散っていて正本が見えにくい
- 取引入力と帳簿と申告の導線が分離しきれていない
- OCR がレシート取り込みに見えて、証憑台帳の中心感がない
- 勘定科目や税設定が弱い

---

## 17-2. 新しいトップナビゲーション
おすすめは次です。

1. **Inbox**  
   証憑、OCR、未処理、要確認

2. **Projects**  
   案件一覧、利益、配賦、ジャンル分析

3. **Approvals**  
   仕訳候補、定期取引、共通費配賦、異常検知

4. **Books**  
   仕訳帳、総勘定元帳、現金出納帳、預金出納帳、売上帳、経費帳、プロジェクト元帳、証憑台帳

5. **Tax & Filing**  
   消費税集計、収支内訳書、青色申告決算書、e-Tax preflight

6. **Settings**  
   事業者情報、年分設定、勘定科目、税区分、取引先、ジャンル、インポート設定

---

## 17-3. Inbox を主役にする理由
個人事業主のストレスは「入力」ではなく「証憑整理」と「判断」にあります。  
だから Home/Dashboard よりも、まずは Inbox 主導にした方が実用的です。

### Inbox 画面に必要なカード
- 今日の未処理件数
- 要確認証憑
- 重複候補
- 定期取引レビュー
- 月末締め待ち
- 申告不足項目
- 消費税注意
- 電子取引保存注意

---

# 18. インポート機能の追加

OCR だけではノーストレスになりません。  
必須で次を追加します。

## 18-1. 銀行/カード/CSV インポート
### 追加機能
- 銀行 CSV マッピング
- カード明細 CSV マッピング
- EC 売上 CSV マッピング
- モール手数料分解
- 振替/二重計上検知
- 証憑自動紐付け候補

## 18-2. インポートプロフィール
## `ImportProfile`
- providerName
- filePattern
- columnMappings
- dateFormat
- amountRule
- signRule
- counterpartyNormalization
- defaultTaxRule
- duplicateKeyPolicy

---

# 19. `LedgerDataStore` を派生ビュー層へ再配置する

---

## 19-1. 問題
現状は `DataStore` と `LedgerDataStore` が並立し、帳簿系テンプレートが duplicate しています。

### 具体的な重複
- cash_book / cash_book_invoice
- expense_book / expense_book_invoice
- general_ledger / general_ledger_invoice
- white_tax_bookkeeping / white_tax_bookkeeping_invoice

これは長期的に壊れます。

---

## 19-2. 新方式
`LedgerDataStore` は廃止するか、少なくとも **派生出力のキャッシュ層** に落とします。

### 新構成
- 正本: `PostedJournal`
- 派生: `BookEngine.build(bookSpec, filters)`
- キャッシュ: `BookSnapshot`

## `BookSpec`
- bookType
- printColumns
- includeProjectColumns
- includeTaxColumns
- legalStyle
- subtotalPolicy
- groupingPolicy
- exportFormats

これで invoice 版 / non-invoice 版のテンプレート重複を消せます。

---

# 20. 実装置換マップ（現行ファイル単位）

この章はそのまま開発チームの作業指示に使えるようにします。

---

## 20-1. 差し替え対象

| 現行ファイル | 方針 | 新設 / 置換先 |
|---|---|---|
| `Models/PPAccountingProfile.swift` | 完全差し替え | `Domain/BusinessProfile.swift`, `Domain/TaxYearProfile.swift` |
| `Models/ConsumptionTaxModels.swift` | 完全差し替え | `Domain/Tax/ConsumptionTaxWorksheet.swift`, `TaxCode.swift`, `PurchaseCreditMethod.swift` |
| `Models/TaxLineDefinitions.swift` | 大幅再設計 | `Domain/Reporting/LegalReportLine.swift` |
| `Models/PPDocumentRecord.swift` | 全面拡張 | `Domain/Evidence/EvidenceDocument.swift`, `EvidenceVersion.swift`, `RetentionPolicy.swift` |
| `Services/AccountingEngine.swift` | 分割・再実装 | `PostingEngine.swift`, `TaxDecisionEngine.swift`, `PostingApprovalService.swift` |
| `Services/ConsumptionTaxReportService.swift` | 完全再実装 | `Tax/ConsumptionTaxEngine.swift`, `Tax/ConsumptionTaxWorksheetBuilder.swift` |
| `Services/ShushiNaiyakushoBuilder.swift` | FormEngine に統合 | `Forms/FormEngine.swift`, `Forms/WhiteReturnBuilder.swift` |
| `Services/EtaxFieldPopulator.swift` | FormPack 化 | `Forms/FormFieldMapper.swift` |
| `Services/TaxYearDefinitionLoader.swift` | Pack Loader 化 | `TaxPacks/TaxYearPackLoader.swift` |
| `Ledger/Services/LedgerDataStore.swift` | 派生ビュー層へ縮退 | `Books/BookEngine.swift` |
| `Ledger/Models/LedgerModels.swift` | 正本から派生する表示モデルへ | `Books/BookRows/*.swift` |
| `Views/Accounting/ChartOfAccountsView.swift` | 編集可能な管理画面へ | `Features/Settings/Accounts/AccountManagerView.swift` |
| `Services/ReceiptScannerService.swift` | 改名・拡張 | `Features/Inbox/DocumentIntakeService.swift` |

---

## 20-2. 新規追加対象

- `Domain/Counterparty/Counterparty.swift`
- `Domain/Counterparty/CounterpartyStatusHistory.swift`
- `Domain/Evidence/*`
- `Domain/Posting/*`
- `Domain/Reporting/LegalReportLine.swift`
- `Domain/Tax/*`
- `Domain/Distribution/DistributionRule.swift`
- `Domain/Recurring/RecurringTemplate.swift`
- `Domain/Genres/GenreTag.swift`
- `Domain/Locking/YearLock.swift`
- `Domain/Audit/AuditEvent.swift`
- `Books/BookEngine.swift`
- `Books/BookSpec.swift`
- `Forms/FormPackLoader.swift`
- `Forms/BlueReturnBuilder.swift`
- `Forms/WhiteReturnBuilder.swift`
- `Forms/ConsumptionTaxWorksheetBuilder.swift`
- `Validation/PreflightValidator.swift`
- `Search/EvidenceSearchIndex.swift`

---

## 20-3. 削除または非推奨化対象

- `InvoiceType`（現行 enum）
- invoice / non-invoice 二重 CSV テンプレート
- `receiptImagePath` を transaction に持つ設計
- 正本とは別に ledger entry を保持する仕組み
- `isBlueReturn: Bool`
- 読み取り専用の勘定科目 UI

---

# 21. 永続化・監査・ロックの完成仕様

---

## 21-1. 永続化方針
完全会計システムにするなら、永続化は「見た目が簡単」より「監査性・移行性・検索性」を優先するべきです。

### 推奨
- Repository 層を明示
- migration version を厳密に持つ
- 証憑検索と帳簿集計のための index を用意
- 履歴テーブルを持つ

SwiftData を継続利用してもよいですが、以下が満たせない場合は SQLite/GRDB 等の採用を検討してください。

- 複雑な migration
- 複数 index
- 集計クエリの安定性
- versioned audit trail
- book snapshot cache

---

## 21-2. 監査イベント
## `AuditEvent`
- eventId
- eventType
- aggregateType
- aggregateId
- beforeStateHash
- afterStateHash
- actor
- createdAt
- reason
- relatedEvidenceId
- relatedJournalId

### 対象
- 証憑修正
- 仕訳承認
- 仕訳取消
- 年度ロック
- 勘定科目変更
- 税区分変更
- 配賦ルール変更
- 年分設定変更

---

## 21-3. 年度ロック
## `YearLock`
- taxYear
- stage  
  - softClose
  - taxClose
  - filed
  - finalLock
- lockedAt
- lockReason
- allowsAdjustingEntries
- adjustedByEntriesOnly

### ルール
- filed 後は原則編集不可
- 証憑削除は不可
- 追加入力は adjusting entries で対応
- 変更履歴は完全保持

---

# 22. 業種汎用性を持たせる方法

ユーザーが求めているのは「幅広い業種対応」です。  
ここでやってはいけないのは、全業種を 1 つの固定科目表に無理やり押し込むことです。

正解は **Preset Pack + Core Engine** です。

---

## 22-1. 汎用コアは固定
- 証憑
- 仕訳
- 勘定科目
- 税区分
- プロジェクト
- 配賦
- 帳簿
- 申告
- 保存要件

これは全業種共通。

## 22-2. 業種 Preset Pack を追加
### 例
- IT / 開発 / 受託制作
- デザイン / クリエイター
- コンサル / 士業
- 物販 / EC
- 小売 / 店舗
- 軽飲食 / フード
- イベント / 教育 / 講師
- 不動産
- 農業（将来別様式対応）

### Preset Pack が持つもの
- 初期勘定科目セット
- よく使うジャンル
- OCR キーワード
- よく使う定期取引
- 帳簿表示順
- 推奨配賦ルール
- 推奨ダッシュボード

### 重要
- Preset はあくまで初期値
- Core domain は変えない
- 不動産 / 農業など別様式が必要な分野は `FormPack` 追加で吸収する

---

# 23. テスト戦略（必須追加）

現状でもテストは多いですが、完成形にするにはテストの質を変える必要があります。

---

## 23-1. 追加必須ユニットテスト
- 青色 65 / 55 / 10 判定
- 青色現金主義
- 白色専用フロー
- 一般課税
- 簡易課税
- 2割特例
- 80% 経過措置
- 50% 経過措置
- 少額特例
- taxIncluded / taxExcluded
- 1 証憑内 8% + 10%
- 1 証憑内複数勘定科目
- 1 証憑複数プロジェクト配賦
- 家事按分
- 年度ロック
- 証憑修正履歴
- T番号抽出と Counterparty 照合
- 重複証憑判定
- 定期取引単月全プロジェクト配賦
- ユーザー追加勘定科目
- ユーザー追加ジャンル
- white 空欄経費追加
- blue/white 帳票未入力エラー
- e-Tax preflight

---

## 23-2. ゴールデンテスト
### 追加必須
- 青色申告決算書 PDF スナップショット
- 青色申告決算書 XML ゴールデン
- 収支内訳書 PDF スナップショット
- 消費税集計表ゴールデン
- 仕訳帳 / 総勘定元帳 / 現金出納帳 / プロジェクト元帳の CSV ゴールデン

---

## 23-3. 年分回帰テスト
- 2025
- 2026
- 2027

### 確認対象
- 80 → 50 切替
- 2割特例期間終端
- XML mapping 差異
- 帳票項目の増減
- バリデーション差異

---

## 23-4. 実シナリオテスト
- フリーランスエンジニア
- デザイナー
- 小規模物販
- 講師業
- 店舗併用
- 家事按分あり
- 複数プロジェクト同時進行
- 売上先・仕入先多数
- 定期取引 30 件/月
- 証憑未整理からの年末締め

---

# 24. 受け入れ基準（Definition of Done）

このリファクタリングが完了したと言える条件を明確にします。

## 24-1. 会計正本
- 仕訳正本が 1 系統である
- すべての帳簿が正本から派生する
- 借貸一致エラーがゼロ
- すべての証憑から仕訳へ辿れる

## 24-2. 帳簿
- 仕訳帳、総勘定元帳、現金出納帳、預金出納帳、売上帳、仕入帳、経費帳、証憑台帳、固定資産台帳、棚卸資産台帳、プロジェクト元帳が出せる
- PDF / CSV / 画面表示の値が一致する
- 月次小計・期首/期末残高が整合する

## 24-3. 税務
- 青色 65/55/10 / 現金主義 / 白色を切り替えられる
- 消費税モード（免税/一般/簡易/2割）を切り替えられる
- 80/50/少額特例/控除不可を line 単位で判定できる
- 消費税集計表が出る
- 青色申告決算書 4 ページ構造を埋められる
- 収支内訳書 2 ページ構造を埋められる
- e-Tax preflight が通る

## 24-4. UX
- 証憑 Inbox 主導
- 定期取引自動生成
- 単月全プロジェクト配賦
- ユーザー追加勘定科目
- ユーザー追加ジャンル
- OCR から候補が出る
- 要確認だけレビューすればよい

## 24-5. 保存要件
- 電子取引/紙スキャン区別
- 訂正削除履歴
- 検索
- 相互関連
- 年度ロック

## 24-6. AI
- すべてオンデバイス
- オフライン主要機能動作
- AI は候補生成のみ
- 税務最終判定はルールエンジン

---

# 25. 実装フェーズ案

---

## Phase 1: 正本統合
- `BusinessProfile` / `TaxYearProfile`
- `Counterparty`
- `EvidenceDocument`
- `PostedJournal`
- Repository 層
- `LedgerDataStore` 依存削減

## Phase 2: Tax Engine
- `TaxCode`
- `PurchaseCreditMethod`
- `ConsumptionTaxEngine`
- 80/50/2割/少額特例
- 消費税集計表

## Phase 3: Form Engine
- `FormPack`
- 青色申告決算書
- 収支内訳書
- XML preflight

## Phase 4: Inbox / OCR / Approvals
- `DocumentIntakeService`
- 重複検知
- 承認キュー
- 取引先連携

## Phase 5: Books 完成
- canonical books
- print books
- project books
- audit books

## Phase 6: UX 強化
- 定期取引完全化
- 単月全プロジェクト配賦
- 勘定科目/ジャンル管理
- 業種プリセット
- インポート

---

# 26. 最後に: このアプリを「完全な会計システム」にするための本当のポイント

最後に、最重要ポイントだけをまとめます。

## 26-1. いちばん大切なこと
このアプリは、**会計入力アプリ** として作るのではなく、  
**証憑・税務状態・プロジェクト配賦を中心にした会計システム** として作るべきです。

## 26-2. 壊してはいけない強み
- プロジェクト別管理
- オンデバイス AI
- OCR からの半自動化
- 個人事業主に寄せた UX

## 26-3. いちばん直すべき弱点
- 税務状態が薄い
- 消費税が浅い
- 帳簿正本が二重
- 証憑保存が弱い
- 法定帳票ラインが足りない
- 勘定科目とカテゴリと帳票ラインが混ざっている

## 26-4. 最終的に目指すべき体験
ユーザーはこう感じるべきです。

- 「プロジェクト別の利益が自然に見える」
- 「レシートや請求書を入れるだけで、だいたい終わる」
- 「確認すべき箇所だけ直せばよい」
- 「青色/白色/消費税で詰まらない」
- 「帳簿も保存も不安がない」
- 「AI を使っても証憑は端末外に出ない」

この体験に到達できたとき、初めてこのアプリは **本当に完成した個人事業主向け会計システム** になります。

---

# 27. 参考資料・制度確認元（実装時の一次参照）

※ 実装時は必ず最新の公式情報で年分更新を確認すること。  
※ URL は 2026-03-01 時点確認。

## 国税庁
- 青色申告特別控除  
  https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/2072.htm

- 白色申告者の記帳・帳簿等保存制度  
  https://www.nta.go.jp/taxes/shiraberu/taxanswer/shotoku/2080.htm

- 適格請求書等の記載事項  
  https://www.nta.go.jp/taxes/shiraberu/taxanswer/shohi/6625.htm

- 適格請求書等保存方式（インボイス制度・保存・経過措置等）  
  https://www.nta.go.jp/taxes/shiraberu/taxanswer/shohi/6498.htm

- 優良な電子帳簿の要件  
  https://www.nta.go.jp/publication/pamph/sonota/0024011-027.pdf

- 電子帳簿保存法一問一答（電子取引保存、検索、訂正削除履歴等）  
  https://www.nta.go.jp/law/joho-zeikaishaku/sonota/jirei/05.htm

- 令和7年分 青色申告決算書（一般用）の書き方  
  https://www.nta.go.jp/taxes/shiraberu/shinkoku/tebiki/2025/pdf/037.pdf

- 令和7年分 収支内訳書（一般用）の書き方  
  https://www.nta.go.jp/taxes/shiraberu/shinkoku/tebiki/2025/pdf/034.pdf

- 帳簿の記帳のしかた（事業所得者用）  
  https://www.nta.go.jp/publication/pamph/koho/kurashi/html/01_2.htm

- 帳簿の様式例（事業所得者用）  
  https://www.nta.go.jp/taxes/shiraberu/shinkoku/tebiki/2025/pdf/047.pdf

- インボイス Q&A（端数処理、少額特例、経過措置、2割特例を含む）  
  https://www.nta.go.jp/taxes/shiraberu/zeimokubetsu/shohi/keigenzeiritsu/qa_invoice.htm

## e-Tax
- e-Tax 仕様書一覧  
  https://www.e-tax.nta.go.jp/shiyo/shiyo3.htm

- 所得税の確定申告書等作成時の提出データ仕様  
  https://www.e-tax.nta.go.jp/shiyo/shiyo2.htm

- イメージデータで提出できない添付書類の取扱い確認ページ  
  https://www.e-tax.nta.go.jp/tetsuzuki/shinkoku/shinkoku01.htm

---

# 28. 添付資料レビューの反映範囲

本指示書では、あなたが添付した次の実物様式も前提にしています。

- **収支内訳書 PDF**  
  1ページ目: 本体  
  2ページ目: 売上先/仕入先/減価償却/地代家賃/利子割引料の内訳  
  3-4ページ目: 控用

- **青色申告決算書 PDF**  
  1ページ目: 損益計算書  
  2ページ目: 月別売上・仕入、給与賃金、専従者給与、青色申告特別控除額計算  
  3ページ目: 減価償却、利子割引料、税理士等報酬、地代家賃、特殊事情  
  4ページ目: 貸借対照表  
  5-8ページ目: 控用

- **消費税集計表画像**  
  標準税率/軽減税率/国税相当分/控除税額小計/差引税額を管理できる形を、正式ワークシート仕様として採用

---

# 29. 実装チーム向け最終指示（短く要点だけ）

1. **正本を 1 つにしろ**  
   `PostedJournal` を唯一の会計正本にすること。

2. **プロジェクトは残せ**  
   ただし申告軸は `Business x TaxYear` にしろ。

3. **証憑を主役にしろ**  
   `ReceiptScanner` ではなく `Document Intake + Evidence Ledger` に進化させること。

4. **消費税を作り直せ**  
   3 値集計をやめ、`TaxCode + PurchaseCreditMethod + Worksheet` にすること。

5. **勘定科目・カテゴリ・ジャンル・法定ラインを分けろ**  
   この分離が汎用性の核心である。

6. **帳票は FormPack 方式にしろ**  
   年分変更に耐える設計にすること。

7. **AI は候補まで**  
   最終税務判断は deterministic rules にしろ。

8. **帳簿は内部正本と印刷表示を分けろ**  
   これで完璧な形式と汎用性を両立できる。

---

以上


# 30. 補遺: コード実査で確認した具体的欠陥一覧

この章は、現行コードを実際に確認して「なぜ全面リファクタリングが必要なのか」を、実装レベルで明示するための補遺です。

---

## 30-1. `PPAccountingProfile.swift`
### 現在確認できる問題
- `isBlueReturn: Bool` しかなく、青色 65/55/10 / 現金主義 / 白色を分離できない
- VAT 状態やインボイス登録状態を十分に持てない
- 年分ごとの税務状態が Profile に十分乗っていない

### そのまま残すと起きること
- UI 上の設定が増えるほど if 分岐が爆発する
- 帳票生成時に「どの制度状態だったか」がブレる
- 年跨ぎマイグレーションで事故る

### 指示
- `BusinessProfile` と `TaxYearProfile` に完全分離
- 現行モデルは migration bridge としてのみ残す

---

## 30-2. `Models/TaxLineDefinitions.swift`
### 現在確認できる問題
現行の `TaxLine` は費目ラインが少なすぎる。  
白色・青色の公式帳票行に対して、次のようなラインが直接表現しにくい、または不足している。

- 給料賃金
- 専従者給与
- 荷造運賃
- 貸倒金
- 福利厚生費
- 雑収入
- 税理士・弁護士等報酬の扱い
- 収支内訳書の空欄追加科目

### 指示
- `TaxLine` を帳票ラインの正本にしない
- `LegalReportLine` を別に作る
- `Account -> LegalReportLine` マッピング方式に変える

---

## 30-3. `ConsumptionTaxModels.swift`
### 現在確認できる問題
`ConsumptionTaxSummary` が
- `outputTaxTotal`
- `inputTaxTotal`
- `taxPayable`

の 3 項目しか持っていない。

### そのまま残すと起きること
- 標準税率/軽減税率の分解ができない
- 税込/税抜売上を両方持てない
- 科目別控除税額小計が作れない
- 80%/50%/少額特例/控除不可の管理ができない
- あなたの消費税集計表を生成できない

### 指示
- `ConsumptionTaxLine` と `ConsumptionTaxWorksheet` に全面置換
- 集計の正本は journal line ベースにする

---

## 30-4. `Ledger/Models/LedgerModels.swift`
### 現在確認できる問題
`InvoiceType` が次の 3 値しかない。

- `〇`
- `8割控除`
- `少額特例`

### 欠陥
- `50%控除` が存在しない
- `控除不可` が明示的にない
- `適格簡易請求書` を識別できない
- 根拠の説明責任が弱い

### 指示
- `InvoiceType` は廃止
- `PurchaseCreditMethod` に差し替える

---

## 30-5. `Services/AccountingEngine.swift`
### 現在確認できる問題
`buildIncomeLines` / `buildExpenseLines` は、`taxAmount > 0` の場合に `amount - taxAmount` を本体金額とみなすロジックを持つが、`isTaxIncluded == false` を十分に反映していない。

### 欠陥
- 税抜入力なのに `amount - taxAmount` される危険がある
- 税込/税抜混在入力の安全性が低い
- 1 証憑 1 金額中心で、複数税率・複数 line に弱い

### 指示
- `PostingEngine` で line 単位に正規化
- `TaxDecisionEngine` で税込/税抜を確定
- `AccountingEngine` は legacy bridge として縮退させる

---

## 30-6. `Models/PPDocumentRecord.swift`
### 現在確認できる問題
- 書類保存モデルはあるが、電子取引/紙スキャンの厳密区別がない
- OCR 構造化データを持っていない
- 訂正削除履歴が弱い
- `invoice` の保存ポリシーが粗い
- 保管期限計算が `issueDate + years` の単純計算寄り

### 欠陥
- インボイス保存・電子取引保存の精度が不足
- 帳簿との相互関連要件に弱い
- 検索可能性が不足

### 指示
- `EvidenceDocument`, `EvidenceVersion`, `RetentionPolicy` に分離
- `日付 / 金額 / 取引先` 検索インデックスを必須化

---

## 30-7. `Resources/TaxYear2025.json`
### 現在確認できる問題
現行の 2025 年定義は、青色・白色・共通を合わせてもフィールド数が非常に少なく、公式様式の細部を十分に表現できていない。

### 欠陥
- 青色 4 ページ全体の細部に足りない
- 収支内訳書 2 ページの明細に足りない
- 年ごとの差分管理がしにくい

### 指示
- `TaxYear2025.json` を単独巨大 JSON のまま育てない
- `FormPack` 分割方式へ移行

---

## 30-8. `ShushiNaiyakushoBuilder.swift`
### 現在確認できる問題
- 合計値中心
- 売上先/仕入先明細、住所、内訳、空欄科目対応が弱い
- 白色専用 UX を前提にしていない

### 指示
- `WhiteReturnBuilder` と `WhiteReturnPreflight` に役割分離
- Counterparty 明細を自動反映できるようにする

---

## 30-9. `Views/Accounting/ChartOfAccountsView.swift`
### 現在確認できる問題
- ほぼ閲覧用
- ユーザー追加/編集/アーカイブ導線が弱い

### 指示
- 完全な勘定科目管理画面に差し替え
- `AccountManagerView`
- `AccountMappingEditorView`
- `QuickCategoryManagerView`
- `GenreManagerView` を追加

---

## 30-10. `Views/ContentView.swift`
### 現在確認できる問題
`DataStore` と `LedgerDataStore` の 2 つがアプリ全体のトップで並行注入されている。

### 欠陥
- 正本が二重であることをアーキテクチャ上固定化している
- 表示レイヤーから split-brain を助長している

### 指示
- `LedgerDataStore` のグローバル注入をやめる
- `BooksViewModel` が `BookEngine` へ問い合わせる方式に変える

---

## 30-11. `PPTransaction.counterparty`
### 現在確認できる問題
`String?` で保持されている。

### 欠陥
- T番号を持てない
- 住所を持てない
- 状態履歴を持てない
- 売上先/仕入先明細へ流用しにくい
- OCR の候補マッチング精度が上がらない

### 指示
- `counterpartyId` に置き換える
- migration 時に文字列から候補 master を自動生成

---

## 30-12. `PPRecurringTransaction`
### 現在確認できる問題
配賦モードはあるが、テンプレートの表現力が限定的で、
- 単月のみ全プロジェクト自動分配
- active projects only
- weight-based 配賦
- ジャンル自動付与
- 証憑必須ルール

などが弱い。

### 指示
- `RecurringTemplate + DistributionRule` に格上げ

---

# 31. 入力モードと内部複式の分離

これは完成システム化のために非常に重要です。

## 31-1. 方針
ユーザーに見せる入力モードは複数あってよい。

- 白色向け簡易入力
- 青色向け標準入力
- OCR からの承認入力
- 定期取引自動生成
- 仕訳帳直接入力

しかし、**内部正本は可能な限り複式仕訳に正規化** してください。

### 理由
- 総勘定元帳が安定する
- B/S が作りやすい
- 課税/非課税整理がしやすい
- 年末調整仕訳や期首/期末振替が扱いやすい
- 帳簿の相互関連性が高まる

## 31-2. つまりどうするか
- White/Simple モードの UI は残してよい
- ただし内部では `PostingCandidate -> PostedJournal` に落とす
- 「簡易入力」と「内部正本」は別物として扱う

---

# 32. 月次締め・年次締めワークフロー仕様

ノーストレスな会計アプリにするには、入力画面だけではなく **締めフロー** を作る必要があります。

---

## 32-1. 月次締め
### 月次締めチェックリスト
- 未処理証憑がないか
- 重複候補が残っていないか
- 定期取引が未生成でないか
- 銀行/カード明細の未照合がないか
- 共通経費配賦が未実行でないか
- 固定資産登録漏れがないか
- 棚卸が必要な業種で未入力がないか
- 消費税上の要確認取引が残っていないか

### 月次締めの成果物
- 月次 P/L
- 月次プロジェクト別損益
- 現金/預金残高確認
- 月次消費税ワークシート
- 未処理一覧

---

## 32-2. 年次締め
### 年次締めチェックリスト
- 期首/期末棚卸
- 減価償却
- 未払/前払/未収/前受の確認
- 家事按分の最終調整
- 専従者給与/専従者控除の確認
- 青色申告特別控除の要件確認
- 白色/青色の様式選択確認
- 消費税方式最終確認
- e-Tax preflight
- 年度ロック前レビュー

### 年次締めの成果物
- 仕訳帳
- 総勘定元帳
- 青色申告決算書 or 収支内訳書
- 消費税集計表
- B/S
- 固定資産台帳
- 証憑台帳
- XML / PDF / CSV パッケージ

---

# 33. 帳簿フォーマット詳細規約（印刷・CSV・PDF・画面）

この章は「完璧な形式」の具体化です。

---

## 33-1. 画面表示規約
- 金額は右寄せ
- 日付は左寄せ
- 主要キー（証憑番号、伝票番号、プロジェクトコード）は等幅に近い見せ方
- 税区分と控除根拠はバッジ表示
- 重要異常は赤、要確認は黄、自動確定候補は青
- 列表示のプリセットを用意
  - Legal
  - Management
  - Tax
  - Project

---

## 33-2. PDF 規約
- A4 縦/横を帳簿に応じて固定
- ヘッダに必ず出すもの
  - 帳簿名
  - 事業者名
  - 年分
  - 期間
  - ページ番号
  - 出力日時
- フッタに必ず出すもの
  - システム名
  - 出力モード（Legal / Management）
- 各ページに繰越/前頁計/次頁繰越を表示可能にする
- 月次小計は薄いグレー帯
- 年次合計は太線
- 数字は桁区切り
- 借方/貸方/残高列は固定幅
- PDF と画面で金額相違を出さない

---

## 33-3. CSV 規約
- UTF-8 with BOM を標準
- Excel 互換用に CRLF も選択可能
- 列名は日本語ヘッダ + 英語内部キーの両方に対応できる設計
- カンマ、改行、ダブルクォートを厳密エスケープ
- 日付は ISO 8601 で出力可能
- 金額は整数円を原則
- 取り込み再現性のため `id` 列をオプション出力可能にする

---

## 33-4. XLSX 規約
- 印刷範囲設定
- ウィンドウ枠固定
- ヘッダ行固定
- 小計行のスタイル固定
- 0 円は空白/0 切替可能
- シート名は 31 文字制限に対応
- 日本語科目名の崩れを防ぐ列幅初期値

---

# 34. 家事按分の完成仕様

個人事業主アプリとして、家事按分は重要度が高いです。

---

## 34-1. 現在の良い点
現行モデルに `taxDeductibleRate` があるため、思想の土台はあります。

## 34-2. 完成仕様
### `ProrationRule`
- ruleId
- name
- appliesToAccounts[]
- percentage
- basis  
  - fixed
  - area
  - time
  - usage
  - custom
- effectiveFrom
- effectiveTo
- defaultProjectHandling  
  - sharedOnly
  - allocateAfterProration
- notes

### 運用
- 取引入力時に既定按分を自動適用
- 年末に一括見直し
- 証憑ごとに override 可
- 帳票上は事業用部分のみ反映
- 証憑台帳には元金額と按分後金額を両保持

### テスト必須
- 家賃
- 電気
- 通信費
- 車両費
- 混在ケース
- 年途中変更

---

# 35. 補足結論

このアプリを完璧にするために必要なのは、機能を足し続けることではありません。  
**正本設計、税務状態、証憑台帳、帳簿派生、フォーム年分管理** の 5 本柱を先に固め、その上に OCR、配賦、自動化、UI を載せることです。

とくに重要なのは、次の 6 つです。

1. `PostedJournal` を唯一の会計正本にする  
2. `EvidenceDocument` を証憑正本にする  
3. `TaxYearProfile` で制度状態を完全に持つ  
4. `Account / QuickCategory / GenreTag / LegalReportLine` を分離する  
5. `ConsumptionTaxEngine` を別エンジンとして独立させる  
6. `FormPack` で年分更新に耐えるようにする  

この 6 つが揃えば、UI は後からでも磨けます。  
逆に、この 6 つが揃わない限り、いくら画面を綺麗にしても「完成した会計システム」にはなりません。

---
