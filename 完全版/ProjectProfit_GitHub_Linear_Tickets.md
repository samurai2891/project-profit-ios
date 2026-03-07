# ProjectProfit GitHub Issues / Linear チケット変換版
## 12週間スプリント計画を実行可能なチケットへ分解したバックログ

作成日: 2026-03-01

この文書は、既存の 12 週間スプリント計画を **GitHub Issues / Linear の親子チケット構成** に変換したものです。

### 運用ルール
- **Epic** を親チケットとして作成
- 各 `PP-xxx` を子チケットとして作成
- GitHub では `labels` と `milestone` を使い、Linear では `Project / Cycle / Labels / Parent` に対応させる
- `Sprint 1` 〜 `Sprint 6` は 2 週間サイクルを想定
- `Priority` は GitHub/Linear 共通で **P0 / P1 / P2** を使う

### 推奨フィールド対応
- **Title**: そのままチケットタイトル
- **Description**: `要約 / 主な変更点 / 完了条件` の本文を貼る
- **Labels**: `epic`, `tax`, `books`, `ui`, `migration` など
- **Priority**: P0 / P1 / P2
- **Estimate**: 1〜5 を相対ポイントとして使用
- **Cycle**: Sprint 1〜6
- **Parent / Dependencies**: Epic と先行チケット

### 優先度ガイド
- **P0**: リリース必須。これが欠けると完成形に到達できない
- **P1**: リリースに含めたい。後倒し可だが完成度に大きく効く
- **P2**: 余裕があれば入れる。次フェーズ候補

---

# Epic 一覧

## EPIC-01 基盤凍結・移行準備・カットオーバー管理
- Priority: P0
- Labels: epic, platform, migration
- Goal: 現行機能の比較基準を固定し、段階移行と安全なリリースを可能にする。

## EPIC-02 Canonical Domain・永続化・正本一本化
- Priority: P0
- Labels: epic, domain, persistence
- Goal: 証憑→候補→確定仕訳を唯一の正本にし、二重台帳を解消する。

## EPIC-03 税務状態マシン・税ルールエンジン
- Priority: P0
- Labels: epic, tax, rules
- Goal: 青色/白色・消費税・インボイス特例を年分ごとに安全に判定できるようにする。

## EPIC-04 証憑台帳・オンデバイス Document Intake
- Priority: P0
- Labels: epic, evidence, ocr, on-device-ai
- Goal: 原本保存、OCR、抽出、検索、履歴、重複検知を備えた証憑基盤を構築する。

## EPIC-05 Posting・定期取引・自動配賦・照合
- Priority: P0
- Labels: epic, posting, automation, distribution
- Goal: 候補生成→承認→確定→照合を一貫させ、月次の自動化を最大化する。

## EPIC-06 帳簿Projection・決算整理・消費税集計表
- Priority: P0
- Labels: epic, books, projection, vat
- Goal: すべての帳簿を確定仕訳から再生成し、決算整理と消費税集計を完成させる。

## EPIC-07 青色/白色帳票・FormEngine・e-Tax
- Priority: P0
- Labels: epic, forms, etax, filing
- Goal: 収支内訳書・青色申告決算書・e-Tax XML を年分パックで生成可能にする。

## EPIC-08 UI/UX・マスタ管理・業種汎用化
- Priority: P1
- Labels: epic, ui, masters, workflow
- Goal: 証憑中心 UX と、勘定科目・ジャンル・取引先の拡張性を両立させる。

## EPIC-09 Import/Export・バックアップ・外部明細
- Priority: P1
- Labels: epic, import, export, backup
- Goal: 大量入力・帳簿配布・保全を実務レベルに引き上げる。

## EPIC-10 QA・性能・回帰・リリース
- Priority: P0
- Labels: epic, qa, performance, release
- Goal: 税務・帳簿・移行の壊れを自動検知し、安全に切り替える。

---

# チケット一覧

> 形式: そのまま GitHub Issue / Linear Issue に貼り付けられるよう、1チケットごとにタイトル・要約・依存・完了条件をまとめています。

## PP-001 現行機能インベントリと画面/出力物のベースラインを固定する
- Epic: EPIC-01
- Sprint: Sprint 1
- Priority: P0
- Estimate: 3
- Labels: platform, baseline, audit
- Dependencies: なし

### 要約
現行機能、モデル、サービス、画面、帳票、テストを棚卸しし、比較対象を固定する。

### 主な変更点 / 対象
- project tree
- existing PDFs/CSVs/XML
- current screenshots

### 成果物
- 機能一覧
- 画面一覧
- モデル一覧
- 出力物サンプル
- 既知不具合一覧

### 完了条件
- [ ] 現行出力の golden サンプルが保存されている
- [ ] 以降のリファクタリング比較基準として使える

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
現行機能、モデル、サービス、画面、帳票、テストを棚卸しし、比較対象を固定する。

#### スコープ
- 機能一覧
- 画面一覧
- モデル一覧
- 出力物サンプル
- 既知不具合一覧

#### 依存
- なし

#### Done
- [ ] 現行出力の golden サンプルが保存されている
- [ ] 以降のリファクタリング比較基準として使える
```

---

## PP-002 Golden dataset と帳簿/帳票スナップショットを作成する
- Epic: EPIC-01
- Sprint: Sprint 1
- Priority: P0
- Estimate: 3
- Labels: qa, golden-data, snapshot
- Dependencies: PP-001

### 要約
青色、白色、消費税、棚卸、固定資産、定期取引の代表データセットを整備する。

### 主な変更点 / 対象
- sample data
- tests

### 成果物
- 青色65ケース
- 白色ケース
- 2割特例ケース
- 軽減税率混在ケース
- 定期取引配賦ケース

### 完了条件
- [ ] 各ケースに期待帳簿と期待帳票がある
- [ ] CI で再利用できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
青色、白色、消費税、棚卸、固定資産、定期取引の代表データセットを整備する。

#### スコープ
- 青色65ケース
- 白色ケース
- 2割特例ケース
- 軽減税率混在ケース
- 定期取引配賦ケース

#### 依存
- PP-001

#### Done
- [ ] 各ケースに期待帳簿と期待帳票がある
- [ ] CI で再利用できる
```

---

## PP-003 Feature Flag と parallel-run 比較基盤を導入する
- Epic: EPIC-01
- Sprint: Sprint 1
- Priority: P0
- Estimate: 2
- Labels: platform, feature-flag, parallel-run
- Dependencies: PP-001

### 要約
新旧エンジンを並走させ、差分比較と段階的リリースを可能にする。

### 主な変更点 / 対象
- app bootstrap
- settings

### 成果物
- 新旧 engine 切替フラグ
- migration dry-run フラグ
- debug diff view

### 完了条件
- [ ] 新旧の帳簿出力を同一データで比較できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
新旧エンジンを並走させ、差分比較と段階的リリースを可能にする。

#### スコープ
- 新旧 engine 切替フラグ
- migration dry-run フラグ
- debug diff view

#### 依存
- PP-001

#### Done
- [ ] 新旧の帳簿出力を同一データで比較できる
```

---

## PP-004 Domain モジュール構成と命名規則を確定する
- Epic: EPIC-02
- Sprint: Sprint 1
- Priority: P0
- Estimate: 2
- Labels: domain, architecture
- Dependencies: PP-001

### 要約
Business/Tax/Evidence/Posting/Books/Forms/Automation の責務を定義し、以後の実装先を固定する。

### 主な変更点 / 対象
- ProjectProfit/Domain/*

### 成果物
- ディレクトリ作成
- README
- 命名規則

### 完了条件
- [ ] 新規コードの置き場が明確
- [ ] 旧 Models.swift への追記禁止ルールが決まる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
Business/Tax/Evidence/Posting/Books/Forms/Automation の責務を定義し、以後の実装先を固定する。

#### スコープ
- ディレクトリ作成
- README
- 命名規則

#### 依存
- PP-001

#### Done
- [ ] 新規コードの置き場が明確
- [ ] 旧 Models.swift への追記禁止ルールが決まる
```

---

## PP-005 BusinessProfile と TaxYearProfile を新設する
- Epic: EPIC-02
- Sprint: Sprint 1
- Priority: P0
- Estimate: 3
- Labels: domain, tax-year, profile
- Dependencies: PP-004

### 要約
事業者共通情報と年分固有の税務状態を分離した新 canonical profile を導入する。

### 主な変更点 / 対象
- PPAccountingProfile.swift

### 成果物
- BusinessProfile
- TaxYearProfile
- migration adapter

### 完了条件
- [ ] 青色/白色・青色控除レベル・VAT方式を保持できる
- [ ] 旧 isBlueReturn 依存が縮退開始する

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
事業者共通情報と年分固有の税務状態を分離した新 canonical profile を導入する。

#### スコープ
- BusinessProfile
- TaxYearProfile
- migration adapter

#### 依存
- PP-004

#### Done
- [ ] 青色/白色・青色控除レベル・VAT方式を保持できる
- [ ] 旧 isBlueReturn 依存が縮退開始する
```

---

## PP-006 Counterparty / Genre / IndustryPreset を新設する
- Epic: EPIC-02
- Sprint: Sprint 1
- Priority: P0
- Estimate: 3
- Labels: domain, masters, genre, counterparty
- Dependencies: PP-004

### 要約
取引先マスタ、自由分析用ジャンル、業種プリセットを定義して、拡張性の土台を作る。

### 主な変更点 / 対象
- new domain models

### 成果物
- Counterparty
- GenreMaster
- IndustryPreset

### 完了条件
- [ ] T番号・既定勘定科目・既定税区分・既定ジャンルを保持できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
取引先マスタ、自由分析用ジャンル、業種プリセットを定義して、拡張性の土台を作る。

#### スコープ
- Counterparty
- GenreMaster
- IndustryPreset

#### 依存
- PP-004

#### Done
- [ ] T番号・既定勘定科目・既定税区分・既定ジャンルを保持できる
```

---

## PP-007 ChartOfAccounts v2 と legal mapping モデルを定義する
- Epic: EPIC-02
- Sprint: Sprint 1
- Priority: P0
- Estimate: 3
- Labels: domain, accounts, legal-mapping
- Dependencies: PP-004

### 要約
system account と custom account を分離し、法定帳票マッピングを必須化する。

### 主な変更点 / 対象
- PPAccount.swift
- AccountingConstants.swift

### 成果物
- AccountGroup
- LegalLineMapping
- custom account policy

### 完了条件
- [ ] ユーザー追加勘定科目が帳票へ落とせる設計になる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
system account と custom account を分離し、法定帳票マッピングを必須化する。

#### スコープ
- AccountGroup
- LegalLineMapping
- custom account policy

#### 依存
- PP-004

#### Done
- [ ] ユーザー追加勘定科目が帳票へ落とせる設計になる
```

---

## PP-008 Evidence / Candidate / PostedJournal の canonical モデルを定義する
- Epic: EPIC-02
- Sprint: Sprint 1
- Priority: P0
- Estimate: 5
- Labels: domain, evidence, posting
- Dependencies: PP-004

### 要約
証憑、取引候補、仕訳候補、確定仕訳の新しい正本系列を定義する。

### 主な変更点 / 対象
- PPDocumentRecord.swift
- ReceiptData.swift
- Models.swift
- PPJournalEntry.swift

### 成果物
- EvidenceDocument
- EvidenceVersion
- TransactionCandidate
- PostingCandidate
- PostedJournal

### 完了条件
- [ ] 会計正本が 1 系統に整理される
- [ ] AI候補と確定仕訳が分離される

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
証憑、取引候補、仕訳候補、確定仕訳の新しい正本系列を定義する。

#### スコープ
- EvidenceDocument
- EvidenceVersion
- TransactionCandidate
- PostingCandidate
- PostedJournal

#### 依存
- PP-004

#### Done
- [ ] 会計正本が 1 系統に整理される
- [ ] AI候補と確定仕訳が分離される
```

---

## PP-009 移行マッピング RFC を作成し、旧→新対応表を確定する
- Epic: EPIC-01
- Sprint: Sprint 1
- Priority: P0
- Estimate: 2
- Labels: migration, rfc
- Dependencies: PP-005, PP-006, PP-007, PP-008

### 要約
旧 DataStore / LedgerDataStore / document record を新 canonical model へ移す対応表を文書化する。

### 主な変更点 / 対象
- legacy models
- new domain

### 成果物
- migration matrix
- known risks
- fallback rules

### 完了条件
- [ ] 各旧モデルに新保存先が定義されている

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
旧 DataStore / LedgerDataStore / document record を新 canonical model へ移す対応表を文書化する。

#### スコープ
- migration matrix
- known risks
- fallback rules

#### 依存
- PP-005
- PP-006
- PP-007
- PP-008

#### Done
- [ ] 各旧モデルに新保存先が定義されている
```

---

## PP-010 Repository 層を新設し DataStore 依存を縮退させる
- Epic: EPIC-02
- Sprint: Sprint 2
- Priority: P0
- Estimate: 5
- Labels: persistence, repository, refactor
- Dependencies: PP-008

### 要約
巨大な DataStore を repository/use-case 構成へ移し、ドメインと永続化の境界を引く。

### 主な変更点 / 対象
- DataStore.swift
- DataStore+*.swift

### 成果物
- BusinessProfileRepository
- EvidenceRepository
- PostingRepository
- ProjectRepository

### 完了条件
- [ ] 新規コードが DataStore に直接集約されない

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
巨大な DataStore を repository/use-case 構成へ移し、ドメインと永続化の境界を引く。

#### スコープ
- BusinessProfileRepository
- EvidenceRepository
- PostingRepository
- ProjectRepository

#### 依存
- PP-008

#### Done
- [ ] 新規コードが DataStore に直接集約されない
```

---

## PP-011 Evidence file store と metadata store を分離する
- Epic: EPIC-02
- Sprint: Sprint 2
- Priority: P0
- Estimate: 3
- Labels: evidence, storage, files
- Dependencies: PP-008

### 要約
原本ファイル保存と DB メタデータ保存を分離し、ハッシュ・MIME・file protection を標準化する。

### 主な変更点 / 対象
- ReceiptImageStore.swift
- DataStore+Documents.swift

### 成果物
- file store abstraction
- content hash
- stable file id

### 完了条件
- [ ] 原本ファイルが evidence metadata と一意に結び付く

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
原本ファイル保存と DB メタデータ保存を分離し、ハッシュ・MIME・file protection を標準化する。

#### スコープ
- file store abstraction
- content hash
- stable file id

#### 依存
- PP-008

#### Done
- [ ] 原本ファイルが evidence metadata と一意に結び付く
```

---

## PP-012 Evidence / Journal 検索インデックスを実装する
- Epic: EPIC-04
- Sprint: Sprint 2
- Priority: P0
- Estimate: 3
- Labels: search, compliance, evidence
- Dependencies: PP-011

### 要約
日付・金額・取引先・T番号・プロジェクトで高速検索できるインデックスを作る。

### 主な変更点 / 対象
- new search services

### 成果物
- search index
- query primitives
- reindex job

### 完了条件
- [ ] 電子取引保存を意識した検索導線が動く

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
日付・金額・取引先・T番号・プロジェクトで高速検索できるインデックスを作る。

#### スコープ
- search index
- query primitives
- reindex job

#### 依存
- PP-011

#### Done
- [ ] 電子取引保存を意識した検索導線が動く
```

---

## PP-013 Migration Runner と dry-run レポートを実装する
- Epic: EPIC-01
- Sprint: Sprint 2
- Priority: P0
- Estimate: 5
- Labels: migration, dry-run, report
- Dependencies: PP-009, PP-010, PP-011

### 要約
本移行前に件数差分・孤立データ・変換失敗を可視化する dry-run を作る。

### 主な変更点 / 対象
- new migration package

### 成果物
- runner
- diff report
- error buckets

### 完了条件
- [ ] 実データで dry-run できる
- [ ] 本番移行前に問題を洗える

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
本移行前に件数差分・孤立データ・変換失敗を可視化する dry-run を作る。

#### スコープ
- runner
- diff report
- error buckets

#### 依存
- PP-009
- PP-010
- PP-011

#### Done
- [ ] 実データで dry-run できる
- [ ] 本番移行前に問題を洗える
```

---

## PP-014 Snapshot backup / restore を実装する
- Epic: EPIC-09
- Sprint: Sprint 2
- Priority: P1
- Estimate: 3
- Labels: backup, restore, safety
- Dependencies: PP-010

### 要約
年分単位と全体バックアップをローカルで保存/復元できるようにする。

### 主な変更点 / 対象
- backup module

### 成果物
- snapshot export
- snapshot import
- checksum

### 完了条件
- [ ] 移行前後に退避・復元ができる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
年分単位と全体バックアップをローカルで保存/復元できるようにする。

#### スコープ
- snapshot export
- snapshot import
- checksum

#### 依存
- PP-010

#### Done
- [ ] 移行前後に退避・復元ができる
```

---

## PP-015 TaxYearPack loader と schema を導入する
- Epic: EPIC-07
- Sprint: Sprint 2
- Priority: P0
- Estimate: 4
- Labels: tax-year-pack, forms, etax
- Dependencies: PP-005

### 要約
年分ごとの field map / validation / XML version を読む TaxYearPack 基盤を作る。

### 主な変更点 / 対象
- TaxYearDefinitionLoader.swift
- Resources/TaxYear2025.json

### 成果物
- TaxYearPack schema
- loader
- 2025/2026 skeleton

### 完了条件
- [ ] 単一 JSON 依存から脱却できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
年分ごとの field map / validation / XML version を読む TaxYearPack 基盤を作る。

#### スコープ
- TaxYearPack schema
- loader
- 2025/2026 skeleton

#### 依存
- PP-005

#### Done
- [ ] 単一 JSON 依存から脱却できる
```

---

## PP-016 FilingStyleEngine と BlueDeductionEngine を実装する
- Epic: EPIC-03
- Sprint: Sprint 2
- Priority: P0
- Estimate: 4
- Labels: tax, blue-return, white-return
- Dependencies: PP-005, PP-015

### 要約
青色一般/現金主義/白色、65/55/10 の要件判定ロジックを独立サービス化する。

### 主な変更点 / 対象
- new tax engines

### 成果物
- filing style engine
- blue deduction engine
- validation messages

### 完了条件
- [ ] 青色控除レベルと現金主義の関係を判定できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
青色一般/現金主義/白色、65/55/10 の要件判定ロジックを独立サービス化する。

#### スコープ
- filing style engine
- blue deduction engine
- validation messages

#### 依存
- PP-005
- PP-015

#### Done
- [ ] 青色控除レベルと現金主義の関係を判定できる
```

---

## PP-017 VAT state machine を実装する
- Epic: EPIC-03
- Sprint: Sprint 2
- Priority: P0
- Estimate: 4
- Labels: tax, vat, state-machine
- Dependencies: PP-005

### 要約
課税/免税、一般/簡易/2割特例、インボイス登録状態を年分プロフィールと連動して判定する。

### 主な変更点 / 対象
- new tax engines

### 成果物
- VATStatus
- VATMethod
- eligibility rules

### 完了条件
- [ ] VAT方式を UI トグルではなく状態機械で管理できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
課税/免税、一般/簡易/2割特例、インボイス登録状態を年分プロフィールと連動して判定する。

#### スコープ
- VATStatus
- VATMethod
- eligibility rules

#### 依存
- PP-005

#### Done
- [ ] VAT方式を UI トグルではなく状態機械で管理できる
```

---

## PP-018 TaxCode master と PurchaseCreditMethod enum を実装する
- Epic: EPIC-03
- Sprint: Sprint 2
- Priority: P0
- Estimate: 3
- Labels: tax-code, invoice, purchase-credit
- Dependencies: PP-017

### 要約
税区分を master 化し、少額特例・80%・50%・帳簿のみ特例などの控除根拠を enum 化する。

### 主な変更点 / 対象
- AccountingEnums.swift
- ConsumptionTaxModels.swift

### 成果物
- TaxCode master
- PurchaseCreditMethod

### 完了条件
- [ ] InvoiceType の不十分な表現を置き換えられる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
税区分を master 化し、少額特例・80%・50%・帳簿のみ特例などの控除根拠を enum 化する。

#### スコープ
- TaxCode master
- PurchaseCreditMethod

#### 依存
- PP-017

#### Done
- [ ] InvoiceType の不十分な表現を置き換えられる
```

---

## PP-019 少額特例・80%/50%経過措置・2割特例ルールを実装する
- Epic: EPIC-03
- Sprint: Sprint 3
- Priority: P0
- Estimate: 5
- Labels: tax, special-cases, invoice
- Dependencies: PP-017, PP-018

### 要約
期間、事業者要件、取引単位、控除率を踏まえた特例判定を実装する。

### 主な変更点 / 対象
- new tax rule services

### 成果物
- small amount rule
- transitional 80/50 rule
- two-tenths rule

### 完了条件
- [ ] 代表シナリオで控除可否と率が正しく出る

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
期間、事業者要件、取引単位、控除率を踏まえた特例判定を実装する。

#### スコープ
- small amount rule
- transitional 80/50 rule
- two-tenths rule

#### 依存
- PP-017
- PP-018

#### Done
- [ ] 代表シナリオで控除可否と率が正しく出る
```

---

## PP-020 家事按分・事業専用割合エンジンを実装する
- Epic: EPIC-03
- Sprint: Sprint 3
- Priority: P0
- Estimate: 3
- Labels: tax, apportionment, expense
- Dependencies: PP-007, PP-017

### 要約
通信費・家賃・水道光熱費などの事業按分をルールベースで処理する。

### 主な変更点 / 対象
- new apportionment services

### 成果物
- apportionment rule
- override support

### 完了条件
- [ ] 必要経費算入額と帳票反映が一致する

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
通信費・家賃・水道光熱費などの事業按分をルールベースで処理する。

#### スコープ
- apportionment rule
- override support

#### 依存
- PP-007
- PP-017

#### Done
- [ ] 必要経費算入額と帳票反映が一致する
```

---

## PP-021 源泉徴収・支払調書の基礎モデルを導入する
- Epic: EPIC-03
- Sprint: Sprint 3
- Priority: P1
- Estimate: 3
- Labels: withholding, reports, tax
- Dependencies: PP-006, PP-007

### 要約
報酬料金等の源泉徴収と支払調書に必要な属性を保持できるようにする。

### 主な変更点 / 対象
- new withholding models

### 成果物
- withholding fields
- payee classification

### 完了条件
- [ ] 源泉対象支払の記帳と後続帳票に必要な情報を保持できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
報酬料金等の源泉徴収と支払調書に必要な属性を保持できるようにする。

#### スコープ
- withholding fields
- payee classification

#### 依存
- PP-006
- PP-007

#### Done
- [ ] 源泉対象支払の記帳と後続帳票に必要な情報を保持できる
```

---

## PP-022 DocumentIntakePipeline の雛形を作成する
- Epic: EPIC-04
- Sprint: Sprint 3
- Priority: P0
- Estimate: 4
- Labels: intake, ocr, pipeline
- Dependencies: PP-008, PP-011

### 要約
取り込み→OCR→抽出→分類→候補化までのパイプラインを新サービス構成で再設計する。

### 主な変更点 / 対象
- ReceiptScannerService.swift

### 成果物
- pipeline interfaces
- stage contracts

### 完了条件
- [ ] レシート以外も扱える責務分離ができる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
取り込み→OCR→抽出→分類→候補化までのパイプラインを新サービス構成で再設計する。

#### スコープ
- pipeline interfaces
- stage contracts

#### 依存
- PP-008
- PP-011

#### Done
- [ ] レシート以外も扱える責務分離ができる
```

---

## PP-023 Import チャネル（カメラ/写真/PDF/Share/CSV）を追加する
- Epic: EPIC-04
- Sprint: Sprint 3
- Priority: P0
- Estimate: 4
- Labels: import, files, share-sheet
- Dependencies: PP-022

### 要約
ユーザーが原本を入れる入口を統一し、証憑/明細取り込みを 1 箇所に集約する。

### 主な変更点 / 対象
- new intake UI/services

### 成果物
- camera import
- pdf import
- share sheet import
- csv import stub

### 完了条件
- [ ] 全チャネルから evidence draft が作成される

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
ユーザーが原本を入れる入口を統一し、証憑/明細取り込みを 1 箇所に集約する。

#### スコープ
- camera import
- pdf import
- share sheet import
- csv import stub

#### 依存
- PP-022

#### Done
- [ ] 全チャネルから evidence draft が作成される
```

---

## PP-024 OCR ステージング（layout/entity/line item）を実装する
- Epic: EPIC-04
- Sprint: Sprint 3
- Priority: P0
- Estimate: 5
- Labels: ocr, entities, line-items
- Dependencies: PP-022, PP-023

### 要約
OCR text だけでなく、レイアウトブロック、行アイテム、税額ブロックを段階的に抽出する。

### 主な変更点 / 対象
- new OCR services

### 成果物
- OCRBlock
- EntityExtraction
- LineItemExtraction

### 完了条件
- [ ] 金額・日付・行明細を別々に取得できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
OCR text だけでなく、レイアウトブロック、行アイテム、税額ブロックを段階的に抽出する。

#### スコープ
- OCRBlock
- EntityExtraction
- LineItemExtraction

#### 依存
- PP-022
- PP-023

#### Done
- [ ] 金額・日付・行明細を別々に取得できる
```

---

## PP-025 T番号抽出と取引先照合を実装する
- Epic: EPIC-04
- Sprint: Sprint 3
- Priority: P0
- Estimate: 3
- Labels: invoice, t-number, counterparty
- Dependencies: PP-006, PP-024

### 要約
OCR から T番号を抽出し、取引先マスタや登録状態と照合する。

### 主な変更点 / 対象
- new parser services

### 成果物
- T-number parser
- counterparty matcher

### 完了条件
- [ ] T番号が evidence に保持され、取引先候補へ反映される

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
OCR から T番号を抽出し、取引先マスタや登録状態と照合する。

#### スコープ
- T-number parser
- counterparty matcher

#### 依存
- PP-006
- PP-024

#### Done
- [ ] T番号が evidence に保持され、取引先候補へ反映される
```

---

## PP-026 税率別ブロック抽出と信頼度スコアを実装する
- Epic: EPIC-04
- Sprint: Sprint 3
- Priority: P0
- Estimate: 4
- Labels: vat, confidence, extraction
- Dependencies: PP-024

### 要約
10% / 8% の対象額・税額を抽出し、抽出結果に confidence を付ける。

### 主な変更点 / 対象
- new parser/scoring services

### 成果物
- tax block parser
- confidence scorer

### 完了条件
- [ ] 要確認か自動承認候補かをスコアで判断できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
10% / 8% の対象額・税額を抽出し、抽出結果に confidence を付ける。

#### スコープ
- tax block parser
- confidence scorer

#### 依存
- PP-024

#### Done
- [ ] 要確認か自動承認候補かをスコアで判断できる
```

---

## PP-027 重複検知と evidence versioning を実装する
- Epic: EPIC-04
- Sprint: Sprint 3
- Priority: P0
- Estimate: 4
- Labels: duplicates, versioning, audit
- Dependencies: PP-011, PP-012

### 要約
原本ハッシュと近似条件で重複を検知し、修正履歴と採用履歴を保持する。

### 主な変更点 / 対象
- EvidenceDocument
- EvidenceVersion

### 成果物
- duplicate detector
- version history

### 完了条件
- [ ] 二重計上の予防と訂正履歴の追跡ができる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
原本ハッシュと近似条件で重複を検知し、修正履歴と採用履歴を保持する。

#### スコープ
- duplicate detector
- version history

#### 依存
- PP-011
- PP-012

#### Done
- [ ] 二重計上の予防と訂正履歴の追跡ができる
```

---

## PP-028 オンデバイス AI ガードと fallback 実装を入れる
- Epic: EPIC-04
- Sprint: Sprint 3
- Priority: P0
- Estimate: 3
- Labels: on-device-ai, privacy, fallback
- Dependencies: PP-022

### 要約
外部 API へ本文を送らない設計を強制し、非対応端末では rule-based extraction へフォールバックする。

### 主な変更点 / 対象
- AI invocation layer

### 成果物
- AI guard
- offline fallback

### 完了条件
- [ ] AI なし端末でも主要導線が動く

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
外部 API へ本文を送らない設計を強制し、非対応端末では rule-based extraction へフォールバックする。

#### スコープ
- AI guard
- offline fallback

#### 依存
- PP-022

#### Done
- [ ] AI なし端末でも主要導線が動く
```

---

## PP-029 証憑 Inbox UI を実装する
- Epic: EPIC-08
- Sprint: Sprint 4
- Priority: P1
- Estimate: 4
- Labels: ui, inbox, evidence
- Dependencies: PP-023, PP-027

### 要約
未処理・要確認・確定済み・重複疑いを一覧できる証憑中心 UX を導入する。

### 主な変更点 / 対象
- new inbox views

### 成果物
- inbox list
- filters
- quick actions

### 完了条件
- [ ] 証憑から会計を始める流れが成立する

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
未処理・要確認・確定済み・重複疑いを一覧できる証憑中心 UX を導入する。

#### スコープ
- inbox list
- filters
- quick actions

#### 依存
- PP-023
- PP-027

#### Done
- [ ] 証憑から会計を始める流れが成立する
```

---

## PP-030 TransactionCandidate / PostingCandidate フローを実装する
- Epic: EPIC-05
- Sprint: Sprint 4
- Priority: P0
- Estimate: 4
- Labels: posting, candidate, workflow
- Dependencies: PP-008, PP-024

### 要約
証憑や明細から直接仕訳せず、候補状態を経由して確定するフローを作る。

### 主な変更点 / 対象
- new candidate services

### 成果物
- candidate state machine
- candidate storage

### 完了条件
- [ ] AI 抽出結果が正本仕訳と分離される

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
証憑や明細から直接仕訳せず、候補状態を経由して確定するフローを作る。

#### スコープ
- candidate state machine
- candidate storage

#### 依存
- PP-008
- PP-024

#### Done
- [ ] AI 抽出結果が正本仕訳と分離される
```

---

## PP-031 PostingEngine へ AccountingEngine を分割する
- Epic: EPIC-05
- Sprint: Sprint 4
- Priority: P0
- Estimate: 5
- Labels: posting, refactor, accounting-engine
- Dependencies: PP-030, PP-018

### 要約
仕訳構築、税判断、配賦、確定を独立コンポーネントに分割する。

### 主な変更点 / 対象
- AccountingEngine.swift

### 成果物
- PostingEngine
- TaxDecisionEngine
- JournalPoster

### 完了条件
- [ ] AccountingEngine の一枚岩ロジックが解体される

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
仕訳構築、税判断、配賦、確定を独立コンポーネントに分割する。

#### スコープ
- PostingEngine
- TaxDecisionEngine
- JournalPoster

#### 依存
- PP-030
- PP-018

#### Done
- [ ] AccountingEngine の一枚岩ロジックが解体される
```

---

## PP-032 複数税率・複数行・複数プロジェクト対応の候補生成を実装する
- Epic: EPIC-05
- Sprint: Sprint 4
- Priority: P0
- Estimate: 5
- Labels: multi-line, multi-rate, distribution
- Dependencies: PP-031, PP-026

### 要約
1証憑多行、多税率、多プロジェクト配賦、固定資産+消耗品混在を扱えるようにする。

### 主な変更点 / 対象
- PostingEngine

### 成果物
- line-level candidate generation

### 完了条件
- [ ] 1証憑=1仕訳の前提がなくなる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
1証憑多行、多税率、多プロジェクト配賦、固定資産+消耗品混在を扱えるようにする。

#### スコープ
- line-level candidate generation

#### 依存
- PP-031
- PP-026

#### Done
- [ ] 1証憑=1仕訳の前提がなくなる
```

---

## PP-033 承認ワークフロー・取消仕訳・監査ログを実装する
- Epic: EPIC-05
- Sprint: Sprint 4
- Priority: P0
- Estimate: 4
- Labels: approval, reversal, audit
- Dependencies: PP-030, PP-031

### 要約
suggested/needsReview/approved/posted/reversed の状態と取消仕訳処理を実装する。

### 主な変更点 / 対象
- PostedJournal
- AuditEvent

### 成果物
- approval flow
- reversal flow

### 完了条件
- [ ] posted 後は修正ではなく取消/訂正で扱う

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
suggested/needsReview/approved/posted/reversed の状態と取消仕訳処理を実装する。

#### スコープ
- approval flow
- reversal flow

#### 依存
- PP-030
- PP-031

#### Done
- [ ] posted 後は修正ではなく取消/訂正で扱う
```

---

## PP-034 Recurring engine を再設計する
- Epic: EPIC-05
- Sprint: Sprint 4
- Priority: P0
- Estimate: 4
- Labels: recurring, automation
- Dependencies: PP-009, PP-031

### 要約
定期取引テンプレートを idempotent に再設計し、月次発生と編集履歴を扱えるようにする。

### 主な変更点 / 対象
- PPRecurringTransaction
- Recurring*

### 成果物
- RecurringTemplate
- generation log

### 完了条件
- [ ] 同じ月に重複生成しない

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
定期取引テンプレートを idempotent に再設計し、月次発生と編集履歴を扱えるようにする。

#### スコープ
- RecurringTemplate
- generation log

#### 依存
- PP-009
- PP-031

#### Done
- [ ] 同じ月に重複生成しない
```

---

## PP-035 単月の全プロジェクト一括配賦バッチを実装する
- Epic: EPIC-05
- Sprint: Sprint 4
- Priority: P0
- Estimate: 4
- Labels: distribution, projects, month-close
- Dependencies: PP-034

### 要約
指定月の共通費を、全アクティブプロジェクトへ一括按分する機能を実装する。

### 主な変更点 / 対象
- DistributionRule
- batch service

### 成果物
- monthly batch distribution
- preview diff

### 完了条件
- [ ] preview → approve → apply の流れがある

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
指定月の共通費を、全アクティブプロジェクトへ一括按分する機能を実装する。

#### スコープ
- monthly batch distribution
- preview diff

#### 依存
- PP-034

#### Done
- [ ] preview → approve → apply の流れがある
```

---

## PP-036 DistributionRule engine を実装する
- Epic: EPIC-05
- Sprint: Sprint 4
- Priority: P0
- Estimate: 4
- Labels: distribution, rules, projects
- Dependencies: PP-006, PP-034

### 要約
均等・固定比率・売上比・予算比・残差処理を扱う配賦ルールエンジンを実装する。

### 主な変更点 / 対象
- DistributionRule

### 成果物
- distribution modes
- rounding policies

### 完了条件
- [ ] 定期取引と単月配賦の双方で再利用できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
均等・固定比率・売上比・予算比・残差処理を扱う配賦ルールエンジンを実装する。

#### スコープ
- distribution modes
- rounding policies

#### 依存
- PP-006
- PP-034

#### Done
- [ ] 定期取引と単月配賦の双方で再利用できる
```

---

## PP-037 User Rule Engine とローカル学習メモリを実装する
- Epic: EPIC-05
- Sprint: Sprint 4
- Priority: P1
- Estimate: 4
- Labels: rules, local-learning, automation
- Dependencies: PP-030, PP-028

### 要約
ユーザー修正からローカルルールを作り、次回候補へ反映できるようにする。

### 主な変更点 / 対象
- ClassificationLearningService.swift

### 成果物
- rule editor
- local suggestion memory

### 完了条件
- [ ] 修正を繰り返すほど候補精度が改善する

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
ユーザー修正からローカルルールを作り、次回候補へ反映できるようにする。

#### スコープ
- rule editor
- local suggestion memory

#### 依存
- PP-030
- PP-028

#### Done
- [ ] 修正を繰り返すほど候補精度が改善する
```

---

## PP-038 銀行/カード照合の基礎を実装する
- Epic: EPIC-09
- Sprint: Sprint 4
- Priority: P1
- Estimate: 3
- Labels: reconciliation, bank, card
- Dependencies: PP-030

### 要約
明細と候補/仕訳のマッチング基礎を入れ、将来の bank/card import と接続する。

### 主な変更点 / 対象
- new reconciliation module

### 成果物
- match states
- match primitives

### 完了条件
- [ ] 未照合・候補一致・確定一致を扱える

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
明細と候補/仕訳のマッチング基礎を入れ、将来の bank/card import と接続する。

#### スコープ
- match states
- match primitives

#### 依存
- PP-030

#### Done
- [ ] 未照合・候補一致・確定一致を扱える
```

---

## PP-039 BookProjectionEngine を実装する
- Epic: EPIC-06
- Sprint: Sprint 5
- Priority: P0
- Estimate: 5
- Labels: books, projection, ledger
- Dependencies: PP-033

### 要約
確定仕訳からすべての帳簿を deterministic に生成する projection engine を実装する。

### 主な変更点 / 対象
- new books module

### 成果物
- projection engine
- rebuild command

### 完了条件
- [ ] 帳簿が正本ではなく派生物になる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
確定仕訳からすべての帳簿を deterministic に生成する projection engine を実装する。

#### スコープ
- projection engine
- rebuild command

#### 依存
- PP-033

#### Done
- [ ] 帳簿が正本ではなく派生物になる
```

---

## PP-040 BookSpecRegistry と帳簿フォーマット定義を実装する
- Epic: EPIC-06
- Sprint: Sprint 5
- Priority: P0
- Estimate: 3
- Labels: books, format, registry
- Dependencies: PP-039

### 要約
帳簿ごとの列、表示順、集計ルール、PDF/CSV/Excel フォーマット定義を集約する。

### 主な変更点 / 対象
- new book spec registry

### 成果物
- book specs for core ledgers

### 完了条件
- [ ] フォーマット仕様がコード断片に散らばらない

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
帳簿ごとの列、表示順、集計ルール、PDF/CSV/Excel フォーマット定義を集約する。

#### スコープ
- book specs for core ledgers

#### 依存
- PP-039

#### Done
- [ ] フォーマット仕様がコード断片に散らばらない
```

---

## PP-041 主要帳簿（仕訳帳/総勘定元帳/現金/預金/売掛/買掛/経費）を実装する
- Epic: EPIC-06
- Sprint: Sprint 5
- Priority: P0
- Estimate: 5
- Labels: books, core-ledgers
- Dependencies: PP-039, PP-040

### 要約
法定・実務の主要帳簿を canonical posted journal から生成する。

### 主な変更点 / 対象
- book projections

### 成果物
- journal book
- general ledger
- cash book
- bank book
- A/R
- A/P
- expense book

### 完了条件
- [ ] 帳簿単位の golden test を作成できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
法定・実務の主要帳簿を canonical posted journal から生成する。

#### スコープ
- journal book
- general ledger
- cash book
- bank book
- A/R
- A/P
- expense book

#### 依存
- PP-039
- PP-040

#### Done
- [ ] 帳簿単位の golden test を作成できる
```

---

## PP-042 固定資産台帳と減価償却 projection を完成させる
- Epic: EPIC-06
- Sprint: Sprint 5
- Priority: P0
- Estimate: 4
- Labels: fixed-assets, depreciation, books
- Dependencies: PP-041

### 要約
取得・償却・特別償却・事業専用割合を台帳と帳票へ繋げる。

### 主な変更点 / 対象
- PPFixedAsset.swift
- DepreciationEngine.swift

### 成果物
- fixed asset book
- depreciation schedule

### 完了条件
- [ ] 決算書の減価償却明細に必要な値が揃う

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
取得・償却・特別償却・事業専用割合を台帳と帳票へ繋げる。

#### スコープ
- fixed asset book
- depreciation schedule

#### 依存
- PP-041

#### Done
- [ ] 決算書の減価償却明細に必要な値が揃う
```

---

## PP-043 棚卸台帳と売上原価 projection を完成させる
- Epic: EPIC-06
- Sprint: Sprint 5
- Priority: P0
- Estimate: 4
- Labels: inventory, cogs, books
- Dependencies: PP-041

### 要約
期首/仕入/期末棚卸から売上原価を算定し、台帳と決算書へ反映する。

### 主な変更点 / 対象
- PPInventoryRecord.swift
- InventoryService.swift

### 成果物
- inventory ledger
- COGS calculation

### 完了条件
- [ ] 期末棚卸が P/L/収支内訳書へ繋がる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
期首/仕入/期末棚卸から売上原価を算定し、台帳と決算書へ反映する。

#### スコープ
- inventory ledger
- COGS calculation

#### 依存
- PP-041

#### Done
- [ ] 期末棚卸が P/L/収支内訳書へ繋がる
```

---

## PP-044 プロジェクト別補助元帳を実装する
- Epic: EPIC-06
- Sprint: Sprint 5
- Priority: P0
- Estimate: 3
- Labels: projects, books, management-accounting
- Dependencies: PP-041, PP-036

### 要約
プロジェクトごとの収入・支出・配賦を帳簿として追えるようにする。

### 主な変更点 / 対象
- project subledger projection

### 成果物
- project subsidiary ledger

### 完了条件
- [ ] プロジェクト損益の根拠が帳簿で見える

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
プロジェクトごとの収入・支出・配賦を帳簿として追えるようにする。

#### スコープ
- project subsidiary ledger

#### 依存
- PP-041
- PP-036

#### Done
- [ ] プロジェクト損益の根拠が帳簿で見える
```

---

## PP-045 ConsumptionTaxWorksheet を実装する
- Epic: EPIC-06
- Sprint: Sprint 5
- Priority: P0
- Estimate: 5
- Labels: vat, worksheet, invoice
- Dependencies: PP-019, PP-041

### 要約
標準税率/軽減税率、国税 7.8/6.24、控除税額小計、差引税額まで持つ消費税集計表エンジンを作る。

### 主な変更点 / 対象
- ConsumptionTaxModels.swift
- ConsumptionTaxReportService.swift

### 成果物
- worksheet model
- worksheet service
- UI-ready rows

### 完了条件
- [ ] ユーザー添付の集計表に近い列構成で集計できる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
標準税率/軽減税率、国税 7.8/6.24、控除税額小計、差引税額まで持つ消費税集計表エンジンを作る。

#### スコープ
- worksheet model
- worksheet service
- UI-ready rows

#### 依存
- PP-019
- PP-041

#### Done
- [ ] ユーザー添付の集計表に近い列構成で集計できる
```

---

## PP-046 BookValidationService と月締め/年締めサービスを実装する
- Epic: EPIC-06
- Sprint: Sprint 5
- Priority: P0
- Estimate: 4
- Labels: validation, close, lock
- Dependencies: PP-041, PP-045

### 要約
帳簿整合チェック、月締め、年締め、ロック、解除ログを実装する。

### 主な変更点 / 対象
- new validation/close services

### 成果物
- book validation
- month close
- year close

### 完了条件
- [ ] 締め前チェックリストとロックが機能する

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
帳簿整合チェック、月締め、年締め、ロック、解除ログを実装する。

#### スコープ
- book validation
- month close
- year close

#### 依存
- PP-041
- PP-045

#### Done
- [ ] 締め前チェックリストとロックが機能する
```

---

## PP-047 FormEngine と TaxYearPack field map を実装する
- Epic: EPIC-07
- Sprint: Sprint 6
- Priority: P0
- Estimate: 5
- Labels: forms, field-map, tax-year-pack
- Dependencies: PP-015, PP-041

### 要約
法定帳票 line registry、field mapping、validation を年分パックで扱う基盤を実装する。

### 主な変更点 / 対象
- EtaxFieldPopulator.swift
- TaxLineDefinitions.swift

### 成果物
- FormEngine
- FormLineRegistry
- field mappers

### 完了条件
- [ ] 帳票ロジックが 1 箇所へ集約される

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
法定帳票 line registry、field mapping、validation を年分パックで扱う基盤を実装する。

#### スコープ
- FormEngine
- FormLineRegistry
- field mappers

#### 依存
- PP-015
- PP-041

#### Done
- [ ] 帳票ロジックが 1 箇所へ集約される
```

---

## PP-048 収支内訳書ビルダーを完全化する
- Epic: EPIC-07
- Sprint: Sprint 6
- Priority: P0
- Estimate: 4
- Labels: forms, white-return
- Dependencies: PP-047, PP-041, PP-042, PP-043

### 要約
収支内訳書 1-2 ページの主要欄・売上先/仕入先明細・減価償却・地代家賃等を埋められるようにする。

### 主な変更点 / 対象
- ShushiNaiyakushoBuilder.swift

### 成果物
- white return builder
- page mapping

### 完了条件
- [ ] 一般用 1-2 ページの主要行と明細が生成される

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
収支内訳書 1-2 ページの主要欄・売上先/仕入先明細・減価償却・地代家賃等を埋められるようにする。

#### スコープ
- white return builder
- page mapping

#### 依存
- PP-047
- PP-041
- PP-042
- PP-043

#### Done
- [ ] 一般用 1-2 ページの主要行と明細が生成される
```

---

## PP-049 青色申告決算書（一般用）ビルダーを完全化する
- Epic: EPIC-07
- Sprint: Sprint 6
- Priority: P0
- Estimate: 5
- Labels: forms, blue-return
- Dependencies: PP-047, PP-041, PP-042, PP-043

### 要約
一般用 1-4 ページ（損益計算書、月別売上、減価償却、貸借対照表）を生成できるようにする。

### 主な変更点 / 対象
- new blue return builder

### 成果物
- blue return builder
- page mapping

### 完了条件
- [ ] 一般用 1-4 ページの主要欄が埋まる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
一般用 1-4 ページ（損益計算書、月別売上、減価償却、貸借対照表）を生成できるようにする。

#### スコープ
- blue return builder
- page mapping

#### 依存
- PP-047
- PP-041
- PP-042
- PP-043

#### Done
- [ ] 一般用 1-4 ページの主要欄が埋まる
```

---

## PP-050 青色申告決算書（現金主義用）ビルダーを追加する
- Epic: EPIC-07
- Sprint: Sprint 6
- Priority: P1
- Estimate: 3
- Labels: forms, cash-basis
- Dependencies: PP-047, PP-049

### 要約
青色現金主義の専用フォームと validation を実装する。

### 主な変更点 / 対象
- cash-basis form builder

### 成果物
- cash-basis form builder

### 完了条件
- [ ] filingStyle=blueCashBasis のとき専用帳票が出る

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
青色現金主義の専用フォームと validation を実装する。

#### スコープ
- cash-basis form builder

#### 依存
- PP-047
- PP-049

#### Done
- [ ] filingStyle=blueCashBasis のとき専用帳票が出る
```

---

## PP-051 ETaxExportService と preflight validator を実装する
- Epic: EPIC-07
- Sprint: Sprint 6
- Priority: P0
- Estimate: 4
- Labels: etax, xml, validation
- Dependencies: PP-047, PP-048, PP-049

### 要約
提出用 XML の生成、必須項目チェック、禁則文字チェック、TaxYearPack 整合チェックを実装する。

### 主な変更点 / 対象
- EtaxXtxExporter.swift

### 成果物
- ETaxExportService
- preflight report

### 完了条件
- [ ] PDF と XML の役割が明確に分離される

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
提出用 XML の生成、必須項目チェック、禁則文字チェック、TaxYearPack 整合チェックを実装する。

#### スコープ
- ETaxExportService
- preflight report

#### 依存
- PP-047
- PP-048
- PP-049

#### Done
- [ ] PDF と XML の役割が明確に分離される
```

---

## PP-052 ExportCoordinator（PDF/CSV/Excel/XML）を実装する
- Epic: EPIC-09
- Sprint: Sprint 6
- Priority: P1
- Estimate: 3
- Labels: export, pdf, csv, excel
- Dependencies: PP-040, PP-047, PP-051

### 要約
帳簿と帳票の export を一元化し、フォーマット差分を出力層に閉じ込める。

### 主な変更点 / 対象
- PDFExportService.swift
- CSVExportService.swift
- LedgerExportService.swift

### 成果物
- ExportCoordinator
- export naming rules

### 完了条件
- [ ] 集計ロジックの重複が無くなる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
帳簿と帳票の export を一元化し、フォーマット差分を出力層に閉じ込める。

#### スコープ
- ExportCoordinator
- export naming rules

#### 依存
- PP-040
- PP-047
- PP-051

#### Done
- [ ] 集計ロジックの重複が無くなる
```

---

## PP-053 ホーム/設定/マスタ UI を再設計する
- Epic: EPIC-08
- Sprint: Sprint 6
- Priority: P1
- Estimate: 4
- Labels: ui, settings, masters
- Dependencies: PP-005, PP-006, PP-007, PP-029

### 要約
事業者情報、年分設定、勘定科目、取引先、ジャンル、定期取引、配賦ルールの管理 UI をまとめる。

### 主な変更点 / 対象
- Dashboard/Home/Settings views

### 成果物
- settings workspace
- master screens

### 完了条件
- [ ] マスタ変更が UI から完結する

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
事業者情報、年分設定、勘定科目、取引先、ジャンル、定期取引、配賦ルールの管理 UI をまとめる。

#### スコープ
- settings workspace
- master screens

#### 依存
- PP-005
- PP-006
- PP-007
- PP-029

#### Done
- [ ] マスタ変更が UI から完結する
```

---

## PP-054 候補レビュー / 帳簿 / 申告ワークスペース UI を再設計する
- Epic: EPIC-08
- Sprint: Sprint 6
- Priority: P1
- Estimate: 4
- Labels: ui, workflow, filing
- Dependencies: PP-030, PP-041, PP-048, PP-049

### 要約
証憑→候補→確定→帳簿→申告のワークフローを画面で繋げる。

### 主な変更点 / 対象
- candidate review / books / filing views

### 成果物
- candidate review UI
- books hub
- filing hub

### 完了条件
- [ ] 初心者でも次に何をすべきか分かる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
証憑→候補→確定→帳簿→申告のワークフローを画面で繋げる。

#### スコープ
- candidate review UI
- books hub
- filing hub

#### 依存
- PP-030
- PP-041
- PP-048
- PP-049

#### Done
- [ ] 初心者でも次に何をすべきか分かる
```

---

## PP-055 E2E 回帰・性能測定・移行リハーサルを実施する
- Epic: EPIC-10
- Sprint: Sprint 6
- Priority: P0
- Estimate: 5
- Labels: qa, performance, migration, e2e
- Dependencies: PP-046, PP-051, PP-052

### 要約
全主要シナリオで E2E テストを行い、移行リハーサルと性能計測を完了させる。

### 主な変更点 / 対象
- tests
- ci
- migration runner

### 成果物
- regression report
- performance report
- dress rehearsal result

### 完了条件
- [ ] 主要シナリオがすべて通り、性能閾値を満たす

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
全主要シナリオで E2E テストを行い、移行リハーサルと性能計測を完了させる。

#### スコープ
- regression report
- performance report
- dress rehearsal result

#### 依存
- PP-046
- PP-051
- PP-052

#### Done
- [ ] 主要シナリオがすべて通り、性能閾値を満たす
```

---

## PP-056 カットオーバーと旧 ledger 正本の撤去を実施する
- Epic: EPIC-01
- Sprint: Sprint 6
- Priority: P0
- Estimate: 3
- Labels: cutover, cleanup, release
- Dependencies: PP-055

### 要約
新 canonical path を既定にし、旧 ledger 正本コードを read-only または削除に移行する。

### 主な変更点 / 対象
- feature flags
- legacy ledger code

### 成果物
- cutover checklist
- legacy decommission plan

### 完了条件
- [ ] 新正本が既定となり、旧正本への新規書込が止まる

### GitHub / Linear へ入れるときの本文テンプレート
```markdown
#### 目的
新 canonical path を既定にし、旧 ledger 正本コードを read-only または削除に移行する。

#### スコープ
- cutover checklist
- legacy decommission plan

#### 依存
- PP-055

#### Done
- [ ] 新正本が既定となり、旧正本への新規書込が止まる
```

---

# 推奨 Milestone / Cycle 構成

## Sprint 1
- Tickets: 9
- IDs: PP-001, PP-002, PP-003, PP-004, PP-005, PP-006, PP-007, PP-008, PP-009

## Sprint 2
- Tickets: 9
- IDs: PP-010, PP-011, PP-012, PP-013, PP-014, PP-015, PP-016, PP-017, PP-018

## Sprint 3
- Tickets: 10
- IDs: PP-019, PP-020, PP-021, PP-022, PP-023, PP-024, PP-025, PP-026, PP-027, PP-028

## Sprint 4
- Tickets: 10
- IDs: PP-029, PP-030, PP-031, PP-032, PP-033, PP-034, PP-035, PP-036, PP-037, PP-038

## Sprint 5
- Tickets: 8
- IDs: PP-039, PP-040, PP-041, PP-042, PP-043, PP-044, PP-045, PP-046

## Sprint 6
- Tickets: 10
- IDs: PP-047, PP-048, PP-049, PP-050, PP-051, PP-052, PP-053, PP-054, PP-055, PP-056

---

# 推奨ラベルセット

## Priority
- p0
- p1
- p2

## Area
- platform
- domain
- tax
- evidence
- posting
- books
- forms
- ui
- import
- export
- qa

## Cross-cutting
- migration
- compliance
- on-device-ai
- performance
- etax
- distribution
- recurring

## Type
- epic
- feature
- refactor
- bug
- tech-debt
- qa-task

---

# Linear 用インポート補足

- `Parent` には Epic ID を設定
- `Cycle` には Sprint 1〜6 を設定
- `Estimate` は 1〜5 をそのまま利用
- `Description` には各チケットの「本文テンプレート」を貼り付け
- `Labels` はカンマ区切りで投入

---

# GitHub 用運用補足

- Epic は `epic` ラベル + Issue 本文に子チケット一覧を貼る
- 子チケットは `- [ ] PP-xxx` のチェックリストで親に紐付ける
- Milestone は Sprint 1〜6 で作る
- Projects (beta) を使う場合は `Status / Priority / Epic / Sprint / Estimate` フィールドを作る

---

# 備考

- 本バックログは、**個人事業主向け・プロジェクト別管理・オンデバイス AI 限定** という前提を壊さないように切っている
- 青色申告決算書と収支内訳書は多ページ構成で、月別売上・給料賃金・減価償却・貸借対照表・売上先/仕入先明細を含むため、フォーム実装は別 Epic に切り出している
- e-Tax XML は PDF の代替ではないので、FormEngine と ETaxExportService は別チケットに分離している