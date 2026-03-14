# ProjectProfit 全面リファクタリング — Week 1-2 実装計画

> 根拠資料: README_最初に読む.md, ProjectProfit_Complete_Refactor_Spec.md,
> ProjectProfit_Implementation_Task_List.md, ProjectProfit_Outsource_Architecture_Detail_Spec.md,
> ProjectProfit_12_Week_Sprint_Plan.md, ProjectProfit_AgentTeam_Orchestration.md,
> ProjectProfit_GitHub_Linear_Tickets.md, GOLDEN_RULES.md, 既存コードベース

---

## 前提: 資料が定義する Week 1-2 のスコープ

### 12週スプリント計画より (Sprint 1 = W1-2)
> 「W1-2: 基盤凍結・新ドメイン・正本一本化設計」

### GitHub/Linear チケットより (Sprint 1 割当)
PP-001〜PP-009 の9チケット（全て P0）

### Implementation Task List より (最初の20タスク不変順序の前半)
P0-001, P0-002, P0-004, P1-001, P1-002, P1-003, P1-007

### Agent Team Orchestration より
- W1: Plan Agent → Implement (Architect, Domain, Test) → Review Agent
- W2: Plan Agent → Implement (Architect, Domain, Infra) → Review Agent

---

## Week 1: 基盤凍結 + ドメインモデル設計

### Task 1-1: リファクタリング専用ブランチと baseline tag を切る
**チケット:** PP-001 + PP-002 / タスク: P0-001, P0-002
**根拠:** Implementation Task List「最初の20タスク不変順序」の1-2番目

**作業内容:**
1. `refactor/canonical-redesign` ブランチを作成
2. 現行の全テストが green であることを確認
3. `baseline-v1.0` tag を打つ
4. Golden データセット作成:
   - 1年分の代表的な取引データを `ProjectProfitTests/Golden/` に fixture 化
   - 現行の帳簿出力（仕訳帳、元帳、試算表）を期待値として保存
   - 現行の帳票出力（青色決算書、e-Tax XML）を期待値として保存

**完了条件:**
- [ ] baseline tag が存在する
- [ ] 既存テスト全 green
- [ ] Golden fixture データが JSON で保存済み

**対象ファイル:**
- 新規: `ProjectProfitTests/Golden/` ディレクトリ
- 新規: `ProjectProfitTests/Golden/fixtures/` (取引データ fixture)
- 新規: `ProjectProfitTests/Golden/expected/` (期待値出力)

---

### Task 1-2: Feature Flag 基盤を整備する
**チケット:** PP-001 / タスク: P0-005
**根拠:** GitHub Tickets「新旧コード(canonical vs legacy ledger)を切り替え可能にする」

**作業内容:**
1. `FeatureFlags` enum を作成
   - `useCanonicalPosting: Bool` (新正本系統)
   - `useLegacyLedger: Bool` (旧 LedgerDataStore)
2. DataStore initialization で分岐を入れる
3. 段階的に新旧を切り替えられる構造にする

**完了条件:**
- [ ] canonical path と legacy path を機能フラグで切り替えできる

**対象ファイル:**
- 新規: `ProjectProfit/App/FeatureFlags.swift`
- 修正: `ProjectProfit/ProjectProfitApp.swift` (条件付き初期化)

---

### Task 1-3: 出力比較ツールを作る
**チケット:** — / タスク: P0-004
**根拠:** Implementation Task List「帳簿/帳票/XML の diff 比較を自動化」

**作業内容:**
1. `tools/` に比較スクリプトを作成
   - CSV diff (帳簿出力の比較)
   - PDF テキスト/メタデータ diff
   - XML 正規化 diff (e-Tax 出力の比較)

**完了条件:**
- [ ] CSV diff, PDF text diff, XML canonicalization diff が可視化できる

**対象ファイル:**
- 新規: `tools/diff_csv.sh`
- 新規: `tools/diff_xml.sh`

---

### Task 1-4: 新ディレクトリ構造の skeleton を作成する
**根拠:** Architecture Detail Spec の「Directory Structure」セクション全体

**作業内容:**
Architecture Spec が定義する 4 層構造の雛形を作成:

```
ProjectProfit/
├── App/Bootstrap/           ← DI, routing
├── Core/Domain/             ← 純粋ドメイン (SwiftUI/SwiftData 禁止)
│   ├── BusinessProfile/
│   ├── TaxYear/
│   ├── Projects/
│   ├── Distribution/
│   ├── Accounts/
│   ├── Categories/
│   ├── Counterparties/
│   ├── Evidence/
│   ├── Transactions/
│   ├── Posting/
│   ├── Tax/
│   ├── FixedAssets/
│   ├── Inventory/
│   ├── Recurring/
│   ├── Reporting/
│   ├── Filing/
│   └── Audit/
├── Application/UseCases/    ← ユースケース実装
├── Application/Ports/       ← インフラ境界 protocol
├── Application/Mappers/     ← 層間変換
├── Infrastructure/          ← SwiftData, OCR, Export
│   ├── Persistence/SwiftData/Entities/
│   ├── Persistence/SwiftData/Repositories/
│   ├── Persistence/SwiftData/Migrations/
│   ├── OCR/
│   ├── FileStorage/
│   ├── Export/
│   ├── TaxYearPack/
│   └── Search/
├── Features/                ← UI (SwiftUI Screen + ViewModel)
├── Resources/TaxYearPacks/  ← 年分別税制パック
└── Tests/
```

**依存ルール** (Architecture Spec より):
- Core → 依存なし (Foundation のみ)
- Application → Core, Shared
- Infrastructure → Core, Application, Shared
- Features → Application, Shared
- **禁止:** Core → SwiftUI/SwiftData, Features → Infrastructure 直接

**完了条件:**
- [ ] 上記ディレクトリが存在する
- [ ] 各ディレクトリに空の placeholder ファイルがある
- [ ] build が通る

**対象ファイル:**
- 新規: 上記ディレクトリ構造全体

---

### Task 1-5: BusinessProfile と TaxYearProfile を定義する
**チケット:** PP-003 (部分), PP-004, PP-005 / タスク: P1-001
**根拠:** Complete Refactor Spec「BusinessProfile」「TaxYearProfile」モデル定義

**作業内容:**

1. **BusinessProfile** (Core/Domain/BusinessProfile/):
   - `businessId: UUID`
   - `ownerName: String`, `ownerNameKana: String`
   - `businessName: String`
   - `businessAddress: String`, `phone: String`
   - `taxOfficeCode: String?`
   - `openingDate: Date?`
   - `invoiceRegistrationNumber: String?`
   - `invoiceIssuerStatus: InvoiceIssuerStatus`
   - `defaultCurrency: String` (固定: "JPY")

2. **TaxYearProfile** (Core/Domain/TaxYear/):
   - `businessId: UUID`, `taxYear: Int`
   - `filingStyle: FilingStyle` (.blueGeneral, .blueCashBasis, .white)
     **← 現行の `isBlueReturn: Bool` を置換**
   - `blueDeductionLevel: BlueDeductionLevel` (.none, .ten, .fiftyFive, .sixtyFive)
   - `bookkeepingBasis: BookkeepingBasis` (.single, .double, .cashBasis)
   - `vatStatus: VatStatus` (.exempt, .taxable)
   - `vatMethod: VatMethod` (.general, .simplified, .twoTenths)
   - `invoiceIssuerStatusAtYear: InvoiceIssuerStatus`
   - `electronicBookLevel: ElectronicBookLevel` (.none, .standard, .superior)
   - `yearLockState: YearLockState`
   - `taxPackVersion: String`

3. **関連 enum** (Core/Domain/TaxYear/ に配置):
   - `FilingStyle`, `BlueDeductionLevel`, `BookkeepingBasis`
   - `VatStatus`, `VatMethod`, `InvoiceIssuerStatus`
   - `ElectronicBookLevel`, `YearLockState`

4. **Repository protocol** (Core/Domain/ に配置):
   - `BusinessProfileRepository`
   - `TaxYearProfileRepository`

**移行元 (既存コード):**
- `PPAccountingProfile.swift`:
  - `isBlueReturn: Bool` → `FilingStyle` enum
  - `bookkeepingMode: BookkeepingMode` → `BookkeepingBasis` (拡張)
  - `businessName`, `ownerName` 等 → `BusinessProfile` へ移動
  - `fiscalYear`, `lockedYears` → `TaxYearProfile` + `YearLockState` へ移動

**Golden Rules 準拠チェック:**
- [ ] 金額型に Decimal 使用 (Double 禁止)
- [ ] TaxCode は enum/struct (String ベタ書き禁止)
- [ ] `isBlueReturn: Bool` の参照が残っていない

**完了条件:**
- [ ] `isBlueReturn: Bool` の参照が新コードにない
- [ ] 青色/白色/現金主義の分岐が型安全
- [ ] Repository protocol が定義済み

**対象ファイル:**
- 新規: `Core/Domain/BusinessProfile/BusinessProfile.swift`
- 新規: `Core/Domain/BusinessProfile/BusinessProfileRepository.swift`
- 新規: `Core/Domain/TaxYear/TaxYearProfile.swift`
- 新規: `Core/Domain/TaxYear/TaxYearProfileRepository.swift`
- 新規: `Core/Domain/TaxYear/FilingStyle.swift`
- 新規: `Core/Domain/TaxYear/BlueDeductionLevel.swift`
- 新規: `Core/Domain/TaxYear/BookkeepingBasis.swift`
- 新規: `Core/Domain/TaxYear/VatStatus.swift`
- 新規: `Core/Domain/TaxYear/VatMethod.swift`
- 新規: `Core/Domain/TaxYear/InvoiceIssuerStatus.swift`
- 新規: `Core/Domain/TaxYear/ElectronicBookLevel.swift`
- 新規: `Core/Domain/TaxYear/YearLockState.swift`

---

### Task 1-6: TaxYearPack を新設する
**チケット:** PP-004 / タスク: P1-002
**根拠:** Complete Refactor Spec「TaxYearPack」, Architecture Spec「Resources/TaxYearPacks/」

**作業内容:**
1. `TaxYearPack` struct (Core/Domain/TaxYear/):
   - 年分ごとの税率、帳票フィールド、e-Tax 仕様、特例ルールを pack 化
   - `if文連鎖で年度差分` を排除 (Golden Rules 禁止事項)

2. `TaxYearPackLoader` (Infrastructure/TaxYearPack/):
   - JSON から TaxYearPack をロード
   - 年度切り替え対応

3. リソースファイル (Resources/TaxYearPacks/):
   ```
   2025/
   ├── profile.json
   ├── account_mappings.json
   ├── filing/
   │   ├── blue_general_fields.json
   │   ├── blue_cash_basis_fields.json
   │   ├── white_fields.json
   │   └── common_validations.json
   └── consumption_tax/
       ├── rates.json
       ├── invoice_treatments.json
       └── special_rules.json
   ```

**移行元 (既存コード):**
- `TaxYearDefinitionLoader.swift` + `Resources/TaxYear2025.json`
  → 単一 JSON を年分別 pack 構造に分割

**完了条件:**
- [ ] `TaxYear2025.json` 単一依存が解消
- [ ] 年分更新がパック差し替えで完了する構造

**対象ファイル:**
- 新規: `Core/Domain/TaxYear/TaxYearPack.swift`
- 新規: `Infrastructure/TaxYearPack/TaxYearPackProvider.swift`
- 新規: `Resources/TaxYearPacks/2025/profile.json`
- 新規: `Resources/TaxYearPacks/2025/filing/*.json`
- 新規: `Resources/TaxYearPacks/2025/consumption_tax/*.json`

---

### Task 1-7: Tax Status Machine を実装する
**チケット:** PP-005
**根拠:** GitHub Tickets「青色/白色・消費税・インボイス状態を年分ごとに管理」

**作業内容:**
1. `TaxStatus` enum (associated values 付き)
2. State machine: 状態遷移ルールの定義
   - 免税 → 課税一般 / 簡易課税 / 2割特例
   - 青色 ↔ 白色 (年分単位)
   - インボイス登録/未登録
3. `TaxRuleEvaluator`: 年分 + 状態から適用ルールを決定

**完了条件:**
- [ ] 個人事業主の全税制度状態遷移が定義される

**対象ファイル:**
- 新規: `Core/Domain/Tax/TaxStatusMachine.swift`
- 新規: `Core/Domain/Tax/TaxRuleEvaluator.swift`

---

## Week 2: 正本ドメイン + Repository + 永続化基盤

### Task 2-1: Canonical Domain Model (Evidence, Candidate, PostedJournal) を定義する
**チケット:** PP-003 / タスク: P2-002, P2-008
**根拠:** Complete Refactor Spec 正本系統, Golden Rules「Evidence → Candidate → PostedJournal」

**作業内容:**

1. **EvidenceDocument** (Core/Domain/Evidence/):
   - `evidenceId: UUID`
   - `businessId: UUID`, `taxYear: Int`
   - `sourceType: EvidenceSourceType` (.camera, .photoLibrary, .scannedPDF, .emailAttachment, .importedPDF, .manualNoFile)
   - `legalDocumentType: LegalDocumentType` (.receipt, .invoice, .qualifiedInvoice, .simplifiedQualifiedInvoice, .deliveryNote, .estimate, .contract, .statement, .cashRegisterReceipt, .other)
   - `storageCategory: StorageCategory` (.paperScan, .electronicTransaction)
   - `receivedAt: Date`, `issueDate: Date?`, `paymentDate: Date?`
   - `originalFilename: String`, `mimeType: String`, `fileHash: String`
   - `originalFilePath: String`
   - `ocrText: String?`, `extractionVersion: String?`
   - `searchTokens: [String]`
   - `linkedCounterpartyId: UUID?`, `linkedProjectIds: [UUID]`
   - `complianceStatus: ComplianceStatus`
   - `retentionPolicyId: UUID?`
   - `deletedAt: Date?`, `lockedAt: Date?`

2. **EvidenceVersion** (Core/Domain/Evidence/):
   - `versionId: UUID`, `evidenceId: UUID`
   - `changedAt: Date`, `changedBy: String`
   - `previousStructuredFields: EvidenceStructuredFields?`
   - `nextStructuredFields: EvidenceStructuredFields`
   - `reason: String`, `modelSource: ModelSource` (.ai, .rule, .user)

3. **EvidenceStructuredFields** (Core/Domain/Evidence/):
   - `counterpartyName: String?`, `registrationNumber: String?`
   - `invoiceNumber: String?`, `transactionDate: Date?`
   - `subtotalStandardRate: Decimal?`, `taxStandardRate: Decimal?`
   - `subtotalReducedRate: Decimal?`, `taxReducedRate: Decimal?`
   - `totalAmount: Decimal?`, `paymentMethod: String?`
   - `lineItems: [EvidenceLineItem]`, `confidence: Double?`

4. **PostingCandidate** (Core/Domain/Posting/):
   - `candidateId: UUID`, `evidenceId: UUID?`
   - `businessId: UUID`, `taxYear: Int`
   - `candidateDate: Date`, `counterpartyId: UUID?`
   - `projectAllocations: [ProjectAllocation]`
   - `proposedLines: [PostingLineCandidate]`
   - `taxAnalysis: TaxAnalysis?`
   - `confidenceScore: Double`
   - `status: CandidateStatus` (.draft, .needsReview, .approved, .rejected)
   - `source: CandidateSource` (.ocr, .recurring, .import, .manual, .carryForward)

5. **PostedJournal / JournalLine** (Core/Domain/Posting/):
   - `journalId: UUID`, `businessId: UUID`, `taxYear: Int`
   - `journalDate: Date`, `voucherNo: String`
   - `sourceEvidenceId: UUID?`, `sourceCandidateId: UUID?`
   - `entryType: JournalEntryType` (.normal, .opening, .closing, .depreciation, .inventoryAdjustment, .recurring, .taxAdjustment)
   - `description: String`
   - `lines: [JournalLine]`
   - `approvedAt: Date?`, `lockedAt: Date?`
   - **JournalLine**: accountId, debitAmount (Decimal), creditAmount (Decimal), taxCodeId, projectAllocationId, genreTagIds, evidenceReferenceId

**Golden Rules 準拠チェック:**
- [ ] 金額は全て Decimal 型
- [ ] 正本は Evidence → Candidate → PostedJournal の1系統のみ
- [ ] 帳簿は PostedJournal からの派生生成
- [ ] OCR → 即確定仕訳にしない (Candidate 経由必須)
- [ ] 1 証憑 = N 仕訳を許容

**完了条件:**
- [ ] 3 entity の親子関係と不変条件が明確に定義される

**対象ファイル:**
- 新規: `Core/Domain/Evidence/EvidenceDocument.swift`
- 新規: `Core/Domain/Evidence/EvidenceVersion.swift`
- 新規: `Core/Domain/Evidence/EvidenceStructuredFields.swift`
- 新規: `Core/Domain/Evidence/EvidenceLineItem.swift`
- 新規: `Core/Domain/Evidence/EvidenceSourceType.swift`
- 新規: `Core/Domain/Evidence/EvidenceLegalType.swift`
- 新規: `Core/Domain/Evidence/EvidenceStatus.swift`
- 新規: `Core/Domain/Evidence/EvidenceSearchCriteria.swift`
- 新規: `Core/Domain/Posting/PostingCandidate.swift`
- 新規: `Core/Domain/Posting/PostingCandidateLine.swift`
- 新規: `Core/Domain/Posting/PostingSource.swift`
- 新規: `Core/Domain/Posting/JournalEntry.swift`
- 新規: `Core/Domain/Posting/JournalLine.swift`
- 新規: `Core/Domain/Posting/VoucherNumber.swift`

---

### Task 2-2: Accounting Master (勘定科目、取引先、ジャンル) を正規化する
**チケット:** PP-006 / タスク: P1-003, P1-004, P1-006, P1-007
**根拠:** Complete Refactor Spec の Account / Counterparty / GenreTag / QuickCategory 分離

**作業内容:**

1. **Account** (Core/Domain/Accounts/):
   - `accountId: UUID`, `code: String`, `name: String`
   - `accountType: AccountType` (.asset, .liability, .revenue, .expense)
   - `normalBalance: NormalBalance` (.debit, .credit)
   - `defaultLegalReportLine: LegalReportLineId?`
   - `defaultTaxCode: TaxCodeId?`
   - `projectAllocatable: Bool`
   - `householdProrationAllowed: Bool`
   - `archived: Bool`

2. **Counterparty** (Core/Domain/Counterparties/):
   - `counterpartyId: UUID`, `displayName: String`, `kana: String?`
   - `registrationNumber: String?` (T番号)
   - `invoiceIssuerStatus: InvoiceIssuerStatus`
   - `statusEffectiveFrom: Date?`, `statusEffectiveTo: Date?`
   - `defaultAccountId: UUID?`, `defaultTaxCodeId: String?`

3. **GenreTag** (Core/Domain/Tags/):
   - `genreId: UUID`, `name: String`, `parentGenreId: UUID?`
   - `color: String?`, `icon: String?`, `sortOrder: Int`

4. **責務分離** (Complete Refactor Spec の明確な要求):
   - **Account** ≠ **QuickCategory** ≠ **GenreTag** ≠ **LegalReportLine**
   - 現行: `PPCategory` が会計分類と UI 分類を兼務 → 分離

**移行元 (既存コード):**
- `PPCategory.swift`: UI 分類に限定し、会計 mapping は Account が担当
- `PPAccount.swift`: `defaultLegalReportLine`, `defaultTaxCode` を追加
- `PPTransaction.counterparty: String` → `Counterparty` マスタへ昇格

**完了条件:**
- [ ] 勘定科目が enum で定義され、TaxCode とマッピングできる
- [ ] 取引先がマスタとして独立
- [ ] "Category ≠ Account" の明確な分離

**対象ファイル:**
- 新規: `Core/Domain/Accounts/Account.swift`
- 新規: `Core/Domain/Accounts/AccountCode.swift`
- 新規: `Core/Domain/Accounts/AccountType.swift`
- 新規: `Core/Domain/Accounts/ChartOfAccountsRepository.swift`
- 新規: `Core/Domain/Counterparties/Counterparty.swift`
- 新規: `Core/Domain/Counterparties/RegistrationNumber.swift`
- 新規: `Core/Domain/Counterparties/CounterpartyRepository.swift`
- 新規: `Core/Domain/Tags/GenreTag.swift`
- 新規: `Core/Domain/Tags/GenreDimension.swift`
- 新規: `Core/Domain/Categories/Category.swift` (UI 分類限定)

---

### Task 2-3: Allocation Model と pro-rata 計算基盤を実装する
**チケット:** PP-007 / タスク: P1-005
**根拠:** Complete Refactor Spec「DistributionRule」「ProjectAllocation」

**作業内容:**

1. **ProjectAllocation** (Core/Domain/Distribution/):
   - `allocationId: UUID`, `projectId: UUID`
   - `ratio: Decimal`, `amount: Decimal`
   - `basis: AllocationBasis`

2. **DistributionRule** (Core/Domain/Distribution/):
   - `ruleId: UUID`, `name: String`
   - `scope: DistributionScope` (.allProjects, .allActiveProjectsInMonth, .selectedProjects, .projectsByTag)
   - `basis: DistributionBasis` (.equal, .fixedWeight, .activeDays, .revenueRatio, .expenseRatio, .customFormula)
   - `roundingPolicy: RoundingPolicy` (.lastProjectAdjust, .largestWeightAdjust)

3. **AllocationCalculator**: 配賦計算ロジック

**移行元 (既存コード):**
- `Models.swift` の `Allocation` struct → `ProjectAllocation` に昇格
- `AllocationMode` (.equalAll, .manual) → `DistributionRule` に汎化
- 既存の pro-rata 計算ロジック (DataStore) → 独立した `AllocationCalculator` に抽出

**完了条件:**
- [ ] allocation と pro-rata 計算が独立した責務として分離
- [ ] 各配賦の "なぜこの金額か" が追跡可能

**対象ファイル:**
- 新規: `Core/Domain/Distribution/ProjectAllocation.swift`
- 新規: `Core/Domain/Distribution/DistributionRule.swift`
- 新規: `Core/Domain/Distribution/DistributionScope.swift`
- 新規: `Core/Domain/Distribution/DistributionBasis.swift`
- 新規: `Core/Domain/Distribution/AllocationCalculator.swift`
- 新規: `Core/Domain/Distribution/DistributionTemplateRepository.swift`

---

### Task 2-4: AuditEvent ドメインモデルを定義する
**チケット:** PP-011 / タスク: P3-007
**根拠:** Complete Refactor Spec「AuditEvent」, Golden Rules「全操作に AuditEvent を記録」

**作業内容:**
1. **AuditEvent** (Core/Domain/Audit/):
   - `eventId: UUID`
   - `eventType: AuditEventType`
   - `aggregateType: String`, `aggregateId: UUID`
   - `beforeStateHash: String?`, `afterStateHash: String?`
   - `actor: String`, `createdAt: Date`
   - `reason: String?`
   - `relatedEvidenceId: UUID?`, `relatedJournalId: UUID?`

2. **AuditRepository** protocol

**完了条件:**
- [ ] 全操作が audit log に記録される構造

**対象ファイル:**
- 新規: `Core/Domain/Audit/AuditEvent.swift`
- 新規: `Core/Domain/Audit/AuditEventType.swift`
- 新規: `Core/Domain/Audit/AuditRepository.swift`

---

### Task 2-5: Repository protocol + SwiftData Entity + Repository 実装を作成する
**チケット:** PP-008, PP-009 / タスク: Infrastructure 基盤
**根拠:** Architecture Spec「Repository Pattern」「SwiftData Schema」

**作業内容:**

1. **Repository Protocol** (Core/Domain/ 各サブディレクトリ):
   - `EvidenceRepository`
   - `JournalEntryRepository`
   - `BusinessProfileRepository` (Task 1-5 で定義済み)
   - `TaxYearProfileRepository` (Task 1-5 で定義済み)

2. **SwiftData Entity** (Infrastructure/Persistence/SwiftData/Entities/):
   - `BusinessProfileEntity` (@Model)
   - `TaxYearProfileEntity` (@Model)
   - `EvidenceRecordEntity` (@Model)
   - `JournalEntryEntity` (@Model, `JournalLineEntity`)
   - `PostingCandidateEntity` (@Model)
   - `CounterpartyEntity` (@Model)
   - `AuditEventEntity` (@Model)

3. **Repository 実装** (Infrastructure/Persistence/SwiftData/Repositories/):
   - `SwiftDataEvidenceRepository`
   - `SwiftDataJournalEntryRepository`
   - `SwiftDataBusinessProfileRepository`
   - `SwiftDataTaxYearProfileRepository`
   - `SwiftDataAuditRepository`

4. **ModelContainer 設定** (Infrastructure/Persistence/SwiftData/Store/):
   - `ModelContainerFactory`: 新旧モデル共存の container 設定
   - 既存の `PPProject`, `PPTransaction` 等は維持
   - 新 Entity を追加して並行稼働

**Architecture Spec の制約:**
- Entity は Infrastructure 層に閉じ込める
- Repository は Domain entity を返す (Entity を返さない)
- Mapper で Entity ↔ Domain 変換

**完了条件:**
- [ ] Evidence CRUD が repository interface 経由で完結する
- [ ] PostedJournal と JournalEntry の整合性が保たれる
- [ ] SwiftData Entity が Infrastructure 内に閉じている

**対象ファイル:**
- 新規: `Core/Domain/Evidence/EvidenceRepository.swift`
- 新規: `Core/Domain/Posting/JournalEntryRepository.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Entities/BusinessProfileEntity.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Entities/TaxYearProfileEntity.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Entities/EvidenceRecordEntity.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Entities/JournalEntryEntity.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Entities/JournalLineEntity.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Entities/PostingCandidateEntity.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Entities/CounterpartyEntity.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Entities/AuditEventEntity.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Repositories/SwiftDataEvidenceRepository.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Repositories/SwiftDataJournalEntryRepository.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Repositories/SwiftDataBusinessProfileRepository.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Repositories/SwiftDataTaxYearProfileRepository.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Repositories/SwiftDataAuditRepository.swift`
- 新規: `Infrastructure/Persistence/SwiftData/Store/ModelContainerFactory.swift`
- 新規: `Application/Mappers/EvidenceEntityMapper.swift`
- 新規: `Application/Mappers/JournalEntityMapper.swift`

---

### Task 2-6: ドメイン単体テストの作成
**根拠:** Implementation Task List P13-001, AgentTeam Orchestration W1-2 Test Agent

**作業内容:**
1. `TaxYearProfile` テスト:
   - Blue 65/55/10, Cash-basis, White の生成
   - `FilingStyle` → `BlueDeductionLevel` の組み合わせバリデーション
   - `VatStatus` × `VatMethod` の有効組み合わせ

2. `BusinessProfile` テスト:
   - 必須フィールドバリデーション
   - InvoiceIssuerStatus の状態遷移

3. `AllocationCalculator` テスト:
   - 等分配賦 (equal split)
   - 重み付き配賦 (weighted)
   - 端数調整 (rounding policy)

4. `PostedJournal` テスト:
   - 借貸一致バリデーション
   - 複合仕訳の整合性

**完了条件:**
- [ ] 税務コアの主要分岐がユニットテスト済み
- [ ] テストカバレッジ 80%+ (新規ドメインコード)

**対象ファイル:**
- 新規: `Tests/Unit/Core/TaxYearProfileTests.swift`
- 新規: `Tests/Unit/Core/BusinessProfileTests.swift`
- 新規: `Tests/Unit/Core/AllocationCalculatorTests.swift`
- 新規: `Tests/Unit/Core/PostedJournalTests.swift`
- 新規: `Tests/Unit/Core/TaxStatusMachineTests.swift`

---

## project.yml の更新

Week 2 完了時に `xcodegen generate` を実行し、新ディレクトリ構造を Xcode プロジェクトに反映。

---

## Week 1-2 完了時の成果物一覧

### コード成果物
| カテゴリ | ファイル数 | 配置先 |
|---------|----------|-------|
| Domain Models | ~30 | Core/Domain/ |
| Repository Protocols | ~8 | Core/Domain/*/Repository.swift |
| SwiftData Entities | ~8 | Infrastructure/Persistence/SwiftData/Entities/ |
| SwiftData Repositories | ~5 | Infrastructure/Persistence/SwiftData/Repositories/ |
| Mappers | ~3 | Application/Mappers/ |
| TaxYearPack | ~8 (JSON) | Resources/TaxYearPacks/ |
| Feature Flags | 1 | App/ |
| Tools | 2 | tools/ |
| Tests | ~6 | Tests/Unit/Core/ |
| Golden Fixtures | ~3 | ProjectProfitTests/Golden/ |

### CHECKPOINT_W2_HANDOFF.md に記載すべき内容
(AgentTeam Orchestration に従い)
- 到達点: 新ドメインモデル定義完了、Repository 基盤完了
- P0 完了チケット: PP-001, PP-002, PP-003 (部分), PP-004, PP-005, PP-006, PP-007, PP-008, PP-009
- 残課題: Candidate → PostedJournal の昇格フロー (PP-010, Sprint 2)
- W3 前提条件: 新 Entity が build 通ること、旧コードとの並行稼働

---

## リスク (資料に記載されている事実)

1. **既存コードとの並行稼働**: Feature Flag で新旧切り替え可能にする (PP-001)
2. **SwiftData migration**: 新 Entity 追加時の schema migration が必要
3. **Golden Rules 違反**: `Double` での金額計算、`String` ベタ書きの tax code が既存コードに存在 → 新コードでは Decimal / enum を徹底
4. **依存方向違反**: 現行の `DataStore` は UI から直接アクセス → 新コードでは Repository Protocol 経由

---

## 既存コード → 新コード マッピング表 (Architecture Spec より)

| 既存 | アクション | 新ターゲット |
|------|----------|------------|
| `DataStore.swift` (2275行) | **分解** | Repository + Query + UseCase |
| `Models.swift` | **完全分割** | Domain / Persistence / DTO |
| `PPAccountingProfile` | **置換** | BusinessProfile, TaxYearProfile |
| `PPDocumentRecord` | **置換** | EvidenceRecord, EvidenceFile, Audit |
| `ConsumptionTaxModels` | **再設計** | Tax, TaxCategory, ConsumptionTaxSummary |
| `AccountingEngine` | **置換** | PostingRuleEngine, CreatePostingCandidatesUseCase |
| `LedgerDataStore` | **廃止** | 派生帳簿 Query/Export |
| `ViewModels/*` | **移動** | Feature/Presentation/ViewModels |
| `Views/*` | **移動** | Feature/Presentation/Screens |
| `TaxYear2025.json` | **分割** | TaxYearPacks/2025/* |
