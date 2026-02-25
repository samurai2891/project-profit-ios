# 15 Agent Team 並列実装計画（5タスク × 3Agent）

> **選定基準**: ファイル競合を最小化し、完全並列実行可能な5タスクを選定
> **Agent構成**: 各タスク = Planner(計画) → Implementer(実装) → Reviewer(レビュー)

---

## 選定した5タスク

| # | ID | 概要 | 変更ファイル | 競合リスク |
|---|-----|------|-------------|-----------|
| 1 | **M15** | ProjectFormView 日付整合性バリデーション | ProjectFormView.swift | なし |
| 2 | **M10** | カテゴリ名一意性チェック | CategoryManageView.swift, DataStore.swift(addCategory/updateCategory) | 低 |
| 3 | **M4** | categoryId 空文字禁止 | RecurringFormView.swift, TransactionFormView.swift, DataStore.swift(CRUD) | 低 |
| 4 | **M8** | CSV エクスポート全データオプション | TransactionsViewModel.swift | なし |
| 5 | **M6** | monthOfYear 範囲制約(1-12) | Models.swift, DataStore.swift(updateRecurring) | 低 |

### 選定理由

- 5タスクとも**独立したコードパス**を変更（同一メソッドへの同時変更なし）
- M5(ratio), M11(重複プロジェクト)は TransactionFormView/RecurringFormView の M4 と同一セクションを変更するため次バッチへ
- M12(endDate過去日)は RecurringFormView の M4 と近接するため次バッチへ

---

## Task 1: M15 — ProjectFormView 日付整合性バリデーション

### 問題
`save()` に日付チェックなし。`startDate > completedAt` でpro-rataの `calculateActiveDaysInMonth` が0を返し全配分額が0になる。

### 変更ファイル
- `ProjectProfit/Views/Components/ProjectFormView.swift` — save() にバリデーション追加

### 実装方針
```swift
// save() 内、guard !trimmedName.isEmpty の直後に追加
if hasStartDate && status == .completed && hasCompletedAt {
    if startDate > completedAt {
        // エラーメッセージ表示（@State var errorMessage: String? を追加）
        errorMessage = "開始日は完了日より前にしてください"
        return
    }
}
if hasStartDate && hasPlannedEndDate {
    if startDate > plannedEndDate {
        errorMessage = "開始日は終了予定日より前にしてください"
        return
    }
}
```

### テスト
- ProjectFormView の日付バリデーションは UI テストまたは DataStore 側 `addProject`/`updateProject` にガード追加してユニットテスト

---

## Task 2: M10 — カテゴリ名一意性チェック

### 問題
同名カテゴリ作成可能。CSV インポートで `categories.first(where:)` が意図しないカテゴリにヒット。

### 変更ファイル
- `ProjectProfit/Views/Components/CategoryManageView.swift` — saveNewCategory(), saveEdit()
- `ProjectProfit/Services/DataStore.swift` — addCategory(), updateCategory()

### 実装方針
```swift
// CategoryManageView.swift saveNewCategory() 内
guard !trimmedName.isEmpty else { ... }
// 一意性チェック追加
let existingInType = dataStore.categories.filter { $0.type == type }
if existingInType.contains(where: { $0.name == trimmedName }) {
    errorMessage = "同じ名前のカテゴリが既に存在します"
    return
}

// saveEdit() でも同様（自分自身は除外）
if existingInType.contains(where: { $0.id != category.id && $0.name == trimmedName }) {
    errorMessage = "同じ名前のカテゴリが既に存在します"
    return
}
```

### テスト
- DataStoreCRUDTests に重複カテゴリ名テスト追加

---

## Task 3: M4 — categoryId 空文字禁止

### 問題
`selectedCategoryId ?? ""` で空文字が保存される。`getCategory(id: "")` が nil を返し「不明」表示。

### 変更ファイル
- `ProjectProfit/Views/Components/RecurringFormView.swift` — save()（L729）
- `ProjectProfit/Views/Components/TransactionFormView.swift` — save()
- `ProjectProfit/Services/DataStore.swift` — addTransaction, addRecurring, updateTransaction, updateRecurring（オプション: ガード追加）

### 実装方針
```swift
// RecurringFormView.swift save() 内 L729
guard let categoryId = selectedCategoryId, !categoryId.isEmpty else {
    validationMessage = "カテゴリを選択してください"
    showValidationError = true
    return
}

// TransactionFormView.swift も同様のバリデーション追加
// DataStore 側はフォールバックカテゴリ（cat-other-expense/cat-other-income）への自動マッピングを追加
```

### テスト
- DataStoreCRUDTests に空文字 categoryId 拒否テスト追加

---

## Task 4: M8 — CSV エクスポート全データオプション

### 問題
`generateCSVText()` が `filteredTransactions` のみ出力。バックアップ目的で全データエクスポート不可。

### 変更ファイル
- `ProjectProfit/ViewModels/TransactionsViewModel.swift` — generateCSVText() に引数追加

### 実装方針
```swift
// TransactionsViewModel.swift
func generateCSVText(exportAll: Bool = false) -> String {
    let target = exportAll ? dataStore.transactions : filteredTransactions
    return generateCSV(
        transactions: target,
        getCategory: { self.dataStore.getCategory(id: $0) },
        getProject: { self.dataStore.getProject(id: $0) }
    )
}
```

UI 側（TransactionsView の CSV エクスポートボタン）で選択肢を提供:
- 「フィルタ中のデータ」/ 「全データ」の選択 ActionSheet または confirmationDialog

### テスト
- TransactionsViewModel のテストで exportAll=true/false の出力件数を検証

---

## Task 5: M6 — monthOfYear 範囲制約(1-12)

### 問題
`monthOfYear: Int?` に 1-12 の制約なし。月=13 で `Calendar.date()` が nil または翌年にロールオーバー。

### 変更ファイル
- `ProjectProfit/Models/Models.swift` — PPRecurringTransaction init（L299）
- `ProjectProfit/Services/DataStore.swift` — updateRecurring() の monthOfYear 代入（L723-724）

### 実装方針
```swift
// Models.swift PPRecurringTransaction init L299
self.monthOfYear = frequency == .yearly ? monthOfYear.flatMap { (1...12).contains($0) ? $0 : nil } : nil

// DataStore.swift updateRecurring()
if let monthOfYear {
    guard (1...12).contains(monthOfYear) else { return }
    recurring.monthOfYear = monthOfYear
}
```

### テスト
- ModelsTests に monthOfYear 範囲外テスト追加
- DataStoreCRUDTests に updateRecurring 不正 monthOfYear テスト追加

---

## 実行順序

```
Phase A（全5タスク並列、各 worktree 分離）:
  Task 1 (M15): Planner → Implementer → Reviewer
  Task 2 (M10): Planner → Implementer → Reviewer
  Task 3 (M4):  Planner → Implementer → Reviewer
  Task 4 (M8):  Planner → Implementer → Reviewer
  Task 5 (M6):  Planner → Implementer → Reviewer

Phase B（マージ）:
  1. 各 worktree の変更を main にマージ（競合があれば手動解決）
  2. xcodebuild build で全体ビルド確認
  3. xcodebuild test で全テスト実行

Phase C（次バッチ候補）:
  M5 (ratio範囲), M11 (重複プロジェクト), M12 (endDate過去日), M3 (dayOfMonth注記)
```

---

## 選定外の理由

| ID | 除外理由 |
|----|---------|
| M1 | M2（SwiftDataマイグレーション）完了が前提 |
| M2 | 大規模・高リスク。単独フェーズで実施すべき |
| M3 | 意図的設計。注記改善のみで優先度低 |
| M5 | TransactionFormView/RecurringFormView の M4 と同一セクション変更。次バッチ |
| M7 | RecurringFormView の M4 と近接。次バッチ |
| M9 | M8 完了後に拡張する方が自然 |
| M11 | TransactionFormView/RecurringFormView の M4 と同一セクション変更。次バッチ |
| M12 | RecurringFormView の M4 と近接。次バッチ |
| T1-T7 | Phase 4（確定申告機能）の一部。Phase 1-3 完了が前提 |
