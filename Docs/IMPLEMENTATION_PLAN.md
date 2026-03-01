# 帳簿管理機能 統合実装計画

## 現状分析サマリー

### 既存アプリの会計機能（既に実装済み）
- SwiftData `@Model` ベース: PPAccount(30+科目), PPJournalEntry, PPJournalLine
- AccountingEngine: 取引→仕訳自動生成
- SubLedger: 現金出納帳/売掛帳/買掛帳/経費帳（簡易版）
- CSVExportService / PDFExportService（既存版、納品版とは別）
- LedgerView, SubLedgerView, JournalListView 等のUI
- FixedAsset / Depreciation / Inventory管理
- e-Tax XML出力

### 納品ファイル（変更不可）
| ファイル | 型 | 特徴 |
|---------|---|------|
| LedgerModels.swift | Plain Codable structs | SwiftDataではない、UUID id |
| LedgerExportService.swift | CSV/Import/PDF Config | BOM付きCSV、Excel原本準拠 |
| LedgerExcelExportService.swift | Excel出力 | libxlsxwriter(C言語)依存 |
| master_schema.json | 全台帳JSON定義 | 11台帳×16バリエーション |
| csv_templates/ | 17ファイル | ヘッダー定義テンプレート |

### 統合上の主要課題
1. **データモデル不一致**: 既存SwiftData `@Model` vs 納品Codable struct
2. **勘定科目マスター競合**: 既存PPAccount(30+) vs 納品AccountMaster(51)
3. **ExportService名前衝突**: 既存CSVExportService vs 納品CSVExportService
4. **外部ライブラリ追加**: libxlsxwriter（現在は外部依存ゼロ）
5. **UI統合**: 既存AccountingHomeView配下に11台帳を追加

---

## 実装方針

### 方針1: ブリッジパターンで吸収
納品ファイル3本は変更不可のため、SwiftData永続化レイヤーを新規作成し、
納品Codable struct ↔ SwiftData @Model 間の変換レイヤー（Bridge）で吸収する。

### 方針2: 名前空間で衝突回避
納品の `CSVExportService` は既存と名前衝突するため、
納品ファイルは `Ledger/` サブフォルダに配置し、呼び出し時は明示的に区別する。
（ただし納品ファイル自体は変更不可なので、既存側をリネームするか
呼び出しコードで完全修飾名を使う）

### 方針3: 既存機能は壊さない
既存のAccountingHome, SubLedger, JournalList等は温存。
新しい帳簿機能は別タブまたはAccountingHome内の新セクションとして追加。

---

## 段階A: 調査（完了済み）

上記の現状分析で完了。

### 調査結果まとめ
- UI: SwiftUI 100%（UIKitなし）
- iOS最小: 17.0
- アーキテクチャ: MVVM + Service Layer + SwiftData
- パッケージ管理: なし（純正Appleフレームワークのみ）
- 依存ライブラリ: なし → libxlsxwriter追加が必要
- 永続化: SwiftData（in-memory テスト対応済み）
- エントリーポイント: ProjectProfitApp.swift → ContentView → MainTabView(5タブ)
- 既存テスト: 68+テストファイル

### 競合リスク一覧
| リスク | 深刻度 | 対策 |
|--------|--------|------|
| CSVExportService名前衝突 | HIGH | 既存を `ProjectCSVExportService` にリネーム、または納品側をnamespace化 |
| AccountMaster vs PPAccount | MEDIUM | 納品AccountMasterは読み取り専用マスター、PPAccountとは別系統として共存 |
| LedgerEntry型名衝突 | MEDIUM | DataStore.LedgerEntry（既存）vs 納品のEntry型群 → 完全修飾名で区別 |
| libxlsxwriter追加 | LOW | SwiftPM対応、project.ymlに追加 |

---

## 段階B: 設計

### B-1. ファイル配置設計

```
ProjectProfit/
├── Ledger/                              # ← 新規ディレクトリ
│   ├── Models/
│   │   └── LedgerModels.swift           # 納品ファイル（変更不可）
│   ├── Services/
│   │   ├── LedgerExportService.swift    # 納品ファイル（変更不可）
│   │   └── LedgerExcelExportService.swift # 納品ファイル（変更不可）
│   ├── Bridge/                          # ← 新規：変換レイヤー
│   │   ├── LedgerDataStore.swift        # SwiftData CRUD for ledger entries
│   │   ├── LedgerSwiftDataModels.swift  # @Model wrapper classes
│   │   └── LedgerBridge.swift           # Codable ↔ @Model 変換
│   ├── ViewModels/                      # ← 新規
│   │   ├── LedgerListViewModel.swift    # 台帳一覧VM
│   │   └── LedgerDetailViewModel.swift  # 台帳詳細VM（全11台帳共通ロジック）
│   ├── Views/                           # ← 新規
│   │   ├── LedgerHomeView.swift         # 帳簿トップ（11台帳一覧）
│   │   ├── LedgerDetailView.swift       # 台帳詳細（エントリー一覧+入力）
│   │   ├── LedgerEntryFormView.swift    # エントリー入力フォーム（台帳別）
│   │   ├── LedgerExportView.swift       # エクスポートメニュー
│   │   └── Components/                  # 共通UI部品
│   │       ├── AccountPickerView.swift  # 勘定科目選択
│   │       ├── InvoiceFieldsView.swift  # インボイス入力フィールド
│   │       └── BalanceRowView.swift     # 残高表示行
│   └── Resources/
│       ├── master_schema.json           # 納品ファイル（変更不可）
│       └── csv_templates/               # 納品ファイル17本（変更不可）
│
├── Models/                              # 既存（変更なし）
├── Services/                            # 既存
│   ├── CSVExportService.swift           # 既存（要リネーム検討）
│   └── ...
└── Views/
    └── Accounting/
        └── AccountingHomeView.swift     # 既存（帳簿セクション追加）
```

### B-2. データモデル統合設計

#### SwiftData永続化モデル（新規作成）

```swift
// LedgerSwiftDataModels.swift

/// 台帳インスタンス（1台帳 = 1レコード）
@Model final class SDLedgerBook {
    @Attribute(.unique) var id: UUID
    var ledgerType: String              // LedgerType.rawValue
    var title: String                   // ユーザー定義名
    var metadataJSON: String            // メタデータをJSON文字列で保存
    var includeInvoice: Bool
    var createdAt: Date
    var updatedAt: Date
}

/// 台帳エントリー（各行のデータ）
@Model final class SDLedgerEntry {
    @Attribute(.unique) var id: UUID
    var bookId: UUID                    // FK → SDLedgerBook.id
    var entryJSON: String               // 納品structをJSON文字列で保存
    var sortOrder: Int                  // 表示順
    var createdAt: Date
    var updatedAt: Date
}
```

**設計理由:**
- 納品structは11種類あり各々プロパティが異なるため、個別@Modelを11個作ると煩雑
- JSON文字列として保存し、Bridge層で型安全に変換するのが最もシンプル
- 納品structはCodable準拠済みなのでJSON化は容易
- 検索が必要なフィールド（month, day等）は将来的にインデックス列として追加可能

#### Bridge層の設計

```swift
// LedgerBridge.swift
struct LedgerBridge {
    // SDLedgerEntry → 納品struct
    static func decodeCashBookEntry(from sd: SDLedgerEntry) -> CashBookEntry?
    static func decodeGeneralLedgerEntry(from sd: SDLedgerEntry) -> GeneralLedgerEntry?
    // ... 各台帳タイプ

    // 納品struct → SDLedgerEntry
    static func encode(_ entry: CashBookEntry, bookId: UUID, order: Int) -> SDLedgerEntry
    // ... 各台帳タイプ

    // メタデータ変換
    static func decodeCashBookMetadata(from json: String) -> CashBookMetadata?
    static func encode(_ metadata: CashBookMetadata) -> String
    // ... 各台帳タイプ
}
```

#### マスターデータ
- 納品 `AccountMaster.all`（51科目）は読み取り専用staticプロパティとして利用
- 既存 `PPAccount`（30+科目）とは別系統として共存
- 将来的に統合が必要ならマイグレーションで対応

### B-3. UI統合設計

#### ナビゲーション接続
```
既存: AccountingHomeView
  └── 帳簿管理セクション（新規追加）
      └── LedgerHomeView（11台帳一覧）
          └── LedgerDetailView（各台帳の詳細）
              ├── エントリー一覧（残高計算付き）
              ├── エントリー追加フォーム
              └── エクスポートメニュー
```

#### 共通コンポーネント
1. **AccountPickerView**: 台帳タイプに応じた勘定科目サブセットPicker
   - 全51科目（現金/預金/仕訳/総勘定元帳）
   - 売掛帳用7科目 / 買掛帳用7科目 / 経費帳用4科目
2. **InvoiceFieldsView**: 軽減税率チェック + インボイス区分Picker
3. **BalanceRowView**: 残高/合計のリアルタイム計算表示

### B-4. エクスポート統合設計

#### libxlsxwriter追加
- project.ymlにSwiftPMパッケージ追加
- `packages:` セクションに `https://github.com/jmcnamara/libxlsxwriter` 追加
- `xcodegen generate` で反映

#### エクスポートフロー
```
LedgerExportView
  ├── CSV出力 → 納品CSVExportService.shared.export*()
  │   └── UIActivityViewController
  ├── Excel出力 → LedgerExcelExportService.shared.export*()
  │   └── UIActivityViewController
  └── PDF出力 → UIGraphicsPDFRenderer（新規実装）
      └── UIActivityViewController
```

---

## 段階C: 実装フェーズ

### Phase 1: 基盤整備（データ層）
1. `Ledger/` ディレクトリ構造を作成
2. 納品ファイル3本を `Ledger/` に配置
3. master_schema.json と csv_templates/ を Resources に配置
4. project.yml を更新（ファイル配置 + libxlsxwriter追加）
5. `SDLedgerBook` / `SDLedgerEntry` SwiftDataモデルを作成
6. `ProjectProfitApp.swift` の modelContainer に追加
7. `LedgerBridge` 変換レイヤーを作成
8. **ビルド確認**

### Phase 2: データ層CRUD
1. `LedgerDataStore` を作成（CRUD + 残高計算）
2. 各台帳の残高/合計計算ロジックを実装（7パターン）
3. AccountMasterのサブセットフィルタ
4. **ビルド確認 + ユニットテスト**

### Phase 3: UI実装
1. `LedgerHomeView`（11台帳一覧画面）
2. 共通コンポーネント（AccountPicker, InvoiceFields, BalanceRow）
3. `LedgerDetailView`（エントリー一覧 + 残高表示）
4. `LedgerEntryFormView`（各台帳の入力フォーム）
5. 仕訳帳の複合仕訳UI
6. 白色申告の24列ワイドテーブル
7. 固定資産台帳/交通費精算書のフォーム
8. AccountingHomeViewへの導線追加
9. **ビルド確認**

### Phase 4: エクスポート実装
1. 名前衝突の解消（既存CSVExportServiceのリネーム or namespace対応）
2. `LedgerExportView`（エクスポートメニューUI）
3. CSV出力統合（納品CSVExportService呼び出し）
4. Excel出力統合（納品LedgerExcelExportService呼び出し）
5. PDF出力（UIGraphicsPDFRenderer新規実装）
6. CSVインポート機能
7. UIActivityViewControllerでシェア
8. **ビルド確認**

### Phase 5: テスト
1. 計算ロジック検証（INSTRUCTIONS.md記載の全テストケース）
   - 現金出納帳: 繰越100,000 → 出金168 → 残高99,832
   - 売掛帳: 繰越500,000 → 売上200,000 → 残高700,000 → 入金300,000 → 残高400,000
   - 総勘定元帳(費用): 繰越0 → 借方1,500 → 残高1,500 → 借方3,800 → 残高5,300
   - 総勘定元帳(負債): 繰越0 → 貸方10,000 → 残高10,000 → 借方3,000 → 残高7,000
   - 経費帳: 1,500→1,500 → 3,800→5,300 → 1,100→6,400
2. エクスポート検証（CSV BOM, Excel数式, PDF）
3. 既存機能の回帰テスト
4. **全テストPASS確認**

---

## 実装順序と依存関係

```
Phase 1 (基盤) ──→ Phase 2 (CRUD) ──→ Phase 3 (UI) ──→ Phase 4 (Export) ──→ Phase 5 (Test)
                                         ↑
                              共通UIは先に作成
                              台帳UIは並列可能
```

## 新規ファイル一覧（予定）

| ファイル | 役割 |
|---------|------|
| Ledger/Bridge/LedgerSwiftDataModels.swift | SDLedgerBook, SDLedgerEntry |
| Ledger/Bridge/LedgerBridge.swift | Codable ↔ @Model 変換 |
| Ledger/Bridge/LedgerDataStore.swift | CRUD + 計算 |
| Ledger/ViewModels/LedgerListViewModel.swift | 台帳一覧VM |
| Ledger/ViewModels/LedgerDetailViewModel.swift | 台帳詳細VM |
| Ledger/Views/LedgerHomeView.swift | 帳簿トップ画面 |
| Ledger/Views/LedgerDetailView.swift | 台帳詳細画面 |
| Ledger/Views/LedgerEntryFormView.swift | エントリー入力 |
| Ledger/Views/LedgerExportView.swift | エクスポートメニュー |
| Ledger/Views/Components/AccountPickerView.swift | 勘定科目選択 |
| Ledger/Views/Components/InvoiceFieldsView.swift | インボイス入力 |
| Ledger/Views/Components/BalanceRowView.swift | 残高表示 |
| ProjectProfitTests/LedgerBridgeTests.swift | Bridge層テスト |
| ProjectProfitTests/LedgerCalculationTests.swift | 計算ロジックテスト |
| ProjectProfitTests/LedgerExportTests.swift | エクスポートテスト |

## 既存ファイル変更一覧（予定）

| ファイル | 変更内容 |
|---------|---------|
| project.yml | libxlsxwriter追加, Ledger/ソース追加 |
| ProjectProfitApp.swift | modelContainer に SDLedgerBook, SDLedgerEntry 追加 |
| Views/Accounting/AccountingHomeView.swift | 帳簿管理セクション追加 |
| Services/CSVExportService.swift | 名前衝突回避（リネーム検討） |

---

## リスク軽減策

1. **納品ファイル保護**: Docs/ にオリジナルを残し、Ledger/ にコピー。diffで差分監視
2. **既存機能回帰**: Phase毎にビルド確認、Phase 5で既存テスト全件実行
3. **名前衝突**: Ledger/サブフォルダで論理分離、必要なら既存側をリネーム
4. **libxlsxwriter互換性**: SwiftPM対応済みライブラリ、iOS 17+で問題なし
