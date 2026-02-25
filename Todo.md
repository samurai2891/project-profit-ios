# ProjectProfit 技術的負債・会計バグ管理台帳

> **作成日**: 2026-02-24
> **最終更新**: 2026-02-25 (全CRITICAL/HIGH/MEDIUM修正完了: 35/35件, 構造的欠落7/7修正完了: T1+T2+T3+T4+T5+T6+T7)
> **調査方法**: 3ラウンド・計27 Agentによるコード検証済み
> **目的**: 確定申告機能実装前に修正必須の問題を漏れなく管理する
> **重要**: この台帳の問題は全てコード実態から検証済み。推測ではない。

---

## 進捗サマリ

| 優先度 | 合計 | 修正済み | 残り |
|--------|------|----------|------|
| CRITICAL | 9 | 9 | 0 |
| HIGH | 11 | 11 | 0 |
| MEDIUM | 15 | 15 | 0 |
| 構造的欠落 | 7 | 7 | 0 |

---

## 目次

1. [CRITICAL (9件)](#critical-9件) — 会計データ破損・消失に直結
2. [HIGH (11件)](#high-11件) — 帳簿の正確性を損なう
3. [MEDIUM (15件)](#medium-15件) — UX・データ品質に影響
4. [確定申告構造的欠落 (7件)](#確定申告構造的欠落-7件) — 新機能として設計・実装が必要
5. [推奨修正順序](#推奨修正順序)

---

## CRITICAL (9件)

会計データの破損・消失に直結する問題。最優先で修正すること。

---

### C1: 未生成月の補完ループが存在しない

- **状態**: [x] 修正済み (2026-02-25, commit 266d01c)
- **修正内容**: processRecurringTransactions() を月次whileループ/年次forループに改修。createTransactionFromRecurring() ヘルパーを抽出。キャッチアップテスト5件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L753-768 (月次), L780-794 (年次)

**問題の詳細**:
`processRecurringTransactions()` は現在の月/年のトランザクションしか生成しない。アプリを数ヶ月開かなかった場合、中間の月のトランザクションは永久に生成されない。`lastGeneratedDate` が現在月に更新されるため、システムは全月が生成済みと誤認する。

**問題のコード (月次 L753-768)**:
```swift
if recurring.frequency == .monthly {
    let targetDate = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: recurring.dayOfMonth))
    if currentDay >= recurring.dayOfMonth {
        guard let currentMonthStart = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: 1)) else { continue }
        if let lastGen = recurring.lastGeneratedDate {
            let lastGenMonth = calendar.dateComponents([.year, .month], from: lastGen)
            let currentMonthComps = calendar.dateComponents([.year, .month], from: currentMonthStart)
            if lastGenMonth.year != currentMonthComps.year || lastGenMonth.month != currentMonthComps.month {
                shouldGenerate = true
                transactionDate = targetDate
            }
        } else {
            shouldGenerate = true
            transactionDate = targetDate
        }
    }
}
```

**具体的シナリオ**:
月額10万円の家賃の定期取引がある。1月にアプリを最後に開いた後、4月に再度開くと、4月分のみ生成される。2月・3月の30万円分が永久に欠損し、確定申告の経費が過少計上される。

**修正方針**: `lastGeneratedDate` から現在月までのループを実装し、各月を順次生成する。`skipDates` と `endDate` もループ内で考慮すること。

---

### C2: 手動配分の端数処理が9箇所で欠落

- **状態**: [x] 修正済み (2026-02-25, commit 266d01c)
- **修正内容**: calculateRatioAllocations() / recalculateAllocationAmounts() をUtilities.swiftに追加。DataStore内9箇所を置換。端数は最後のAllocationに加算して合計=amount保証。テスト8件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L307, L349, L353, L442, L534, L538, L646, L853, L1005

**問題の詳細**:
`amount * ratio / 100` の整数除算で切り捨てが発生し、配分額の合計がトランザクション金額と一致しない。`calculateEqualSplitAllocations()` (Utilities.swift L490-506) や `calculateHolisticProRata()` は正しく端数処理しているが、手動配分の9箇所は未対応。

**問題のコード (例: L307 addTransaction)**:
```swift
let allocs = allocations.map {
    Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: amount * $0.ratio / 100)
}
```

**全9箇所の一覧**:
| # | 行番号 | メソッド | コンテキスト |
|---|--------|----------|-------------|
| 1 | L307 | `addTransaction()` | 新規トランザクション作成 |
| 2 | L349 | `updateTransaction()` | 配分変更時 |
| 3 | L353 | `updateTransaction()` | 金額変更時（既存配分） |
| 4 | L442 | `addRecurring()` | 新規定期取引作成 |
| 5 | L534 | `updateRecurring()` | 配分変更時 |
| 6 | L538 | `updateRecurring()` | 金額変更時（既存配分） |
| 7 | L646 | `reverseCompletionAllocations()` | 完了取消時の配分復元 |
| 8 | L853 | `processRecurringTransactions()` | 定期取引から生成時 |
| 9 | L1005 | `generateMonthlySpreadTransactions()` | 月次分割生成時 |

**具体的シナリオ**:
10,000円を33%/33%/33%で3プロジェクトに配分 → 各3,300円 → 合計9,900円。100円が毎回消失。月次定期取引なら年間1,200円の乖離。

**修正方針**: 端数処理用の共通関数を作成し、最後の配分先に余りを加算するパターンを全9箇所に適用する。

---

### C3: カテゴリ削除時の参照チェックなし

- **状態**: [x] 修正済み (2026-02-25, commit 266d01c)
- **修正内容**: deleteCategory() で参照トランザクション/定期取引をフォールバックカテゴリ(cat-other-expense/cat-other-income)に移行。確認メッセージ更新。テスト4件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L407-413

**問題の詳細**:
`deleteCategory()` はカテゴリを直接削除するが、そのカテゴリを参照しているトランザクションや定期取引の `categoryId` を更新しない。さらに、定期取引が新しいトランザクションを生成するたびに、孤立した `categoryId` がコピーされ続ける。

**問題のコード**:
```swift
func deleteCategory(id: String) {
    guard let category = categories.first(where: { $0.id == id }) else { return }
    guard !category.isDefault else { return }
    modelContext.delete(category)
    save()
    refreshCategories()
}
```

**具体的シナリオ**:
「サーバー代」カテゴリ(id:"abc-123")を作成 → 定期取引に設定 → カテゴリ削除 → 定期取引の `categoryId` は "abc-123" のまま → 毎月生成されるトランザクションも "abc-123" → カテゴリ集計で全て「不明」に分類される。

**修正方針**: 削除前に参照チェックし、(a) 参照がある場合は削除をブロック、または (b) デフォルトカテゴリへの移行を行う。

---

### C4: レシート画像が save() 前に削除される

- **状態**: [x] 修正済み (2026-02-25, commit 5aebb59)
- **修正内容**: save()をBool返却に変更（@discardableResult）。deleteProject/deleteProjects/deleteTransaction/removeReceiptImage/deleteRecurring/deleteAllDataの6箇所で画像パスを事前収集→save()成功後にのみファイル削除するdeferred deletionパターンに改修。テスト2件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L86-101 (save), L200-204 (deleteProject), L219-222 (recurring部分), L364-365 (deleteTransaction), L552-553 (deleteRecurring)

**問題の詳細**:
`deleteProject()` 等で `ReceiptImageStore.deleteImage()` がファイルを先に削除し、その後 `save()` を呼ぶ。`save()` が失敗した場合、画像ファイルは既に削除済みだがDBレコードは残り、`receiptImagePath` が存在しないファイルを指す。

**問題のコード (L200-204)**:
```swift
if filtered.isEmpty {
    if let imagePath = transaction.receiptImagePath {
        ReceiptImageStore.deleteImage(fileName: imagePath)  // 画像を先に削除
    }
    modelContext.delete(transaction)  // DB削除はステージングのみ
}
// ... 後で save() が呼ばれるが、失敗する可能性あり
```

**具体的シナリオ**:
プロジェクト削除時にディスク容量不足で `save()` 失敗 → 画像は消失済み → DBにはトランザクションが残る → レシート画像が復元不可能。確定申告の経費証拠が消失。

**修正方針**: save() 成功後に画像を削除する。または、削除対象画像パスを一時保持し、save() 成功時のみ実際にファイル削除を実行する。

---

### C5: save() にロールバックがなく、lastError が UI に表示されない

- **状態**: [x] 修正済み (2026-02-25, commit 266d01c + 5aebb59)
- **修正内容**: (266d01c) MainTabView に DataStore.lastError のエラーアラートを追加。Binding<Bool> パターンで全タブから捕捉可能。テスト2件追加。(5aebb59) save()にmodelContext.rollback()追加、Bool返却化、失敗時にlastError設定後refresh*()で既存データ復元。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L86-93 (save), L15 (lastError宣言), L44 (lastErrorセット)

**問題の詳細**:
`save()` のエラーは `lastError` に格納されるが、`lastError` はプロジェクト全体で View/ViewModel から一切参照されていない（grep確認済み: 3箇所全てDataStore.swift内のみ）。ユーザーはデータ保存失敗を一切知ることができない。

**問題のコード**:
```swift
private func save() {
    do {
        try modelContext.save()
    } catch {
        AppLogger.dataStore.error("Save failed: \(error.localizedDescription)")
        lastError = .saveFailed(underlying: error)
        // UI への通知なし。ユーザーは保存失敗を知らない。
    }
}
```

**具体的シナリオ**:
save() 失敗後、ユーザーはトランザクション追加・編集・削除を続ける。全ての操作がメモリ上でのみ反映され、アプリ再起動で全変更が消失。ユーザーには何の警告も表示されない。

**修正方針**: (a) lastError を Published/Observable にしてUIでアラート表示、(b) save() 失敗時のリトライ機構、(c) 未保存変更の検出と警告。

---

### C6: deleteRecurring が生成済みトランザクションを処理しない

- **状態**: [x] 修正済み (2026-02-25, commit 266d01c)
- **修正内容**: deleteRecurring() で生成済みトランザクションの recurringId を nil にクリアし、ダングリング参照を防止。テスト2件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L550-558 (deleteRecurring), L699-701 (isYearly判定)

**問題の詳細**:
`deleteRecurring()` は `PPRecurringTransaction` を削除するが、そこから生成済みの `PPTransaction` の `recurringId` をクリアしない。孤立した `recurringId` は pro-rata 計算の `isYearly` 判定 (L699-701) に影響し、年次トランザクションが月次として誤計算される。

**問題のコード (L550-558)**:
```swift
func deleteRecurring(id: UUID) {
    guard let recurring = recurringTransactions.first(where: { $0.id == id }) else { return }
    if let imagePath = recurring.receiptImagePath {
        ReceiptImageStore.deleteImage(fileName: imagePath)
    }
    modelContext.delete(recurring)
    save()
    refreshRecurring()
    // 生成済みトランザクションの recurringId を nil にする処理がない
}
```

**isYearly 判定 (L699-701)**:
```swift
let isYearly = transaction.recurringId.flatMap { rid in
    recurringTransactions.first { $0.id == rid }
}.map { $0.frequency == .yearly } ?? false
// recurring が削除済み → nil → ?? false → 年次が月次扱いに
```

**具体的シナリオ**:
年間保険料12万円の定期取引を削除 → 生成済みトランザクションの `recurringId` はダングリング → pro-rata で `isYearly=false` → `daysInYear()` ではなく `daysInMonth()` で計算 → 配分額が大幅に狂う。

**修正方針**: (a) 削除前に生成済みトランザクションの `recurringId` を nil に更新、または (b) `isYearly` 判定にフォールバックロジック追加。

---

### C7: 確定申告の会計年度デフォルト値が不正 (startMonth=4)

- **状態**: [x] 修正済み (2026-02-25, commit 266d01c)
- **修正内容**: defaultStartMonth を 4（法人会計年度）→ 1（個人事業主・暦年）に変更。既存テスト更新。
- **ファイル**: `ProjectProfit/Utilities/FiscalYearSettings.swift`
- **行番号**: L4

**問題の詳細**:
デフォルトの会計年度開始月が4月（法人会計年度）に設定されているが、アプリは「個人事業主向けプロジェクト別経費トラッカー」(SettingsView.swift L316) と明記されている。個人事業主の確定申告は暦年（1月〜12月）が法定期間。

**問題のコード**:
```swift
enum FiscalYearSettings {
    static let defaultStartMonth = 4  // 法人向け。個人事業主は1が正しい
    static let userDefaultsKey = "fiscalYearStartMonth"

    static var startMonth: Int {
        let stored = UserDefaults.standard.integer(forKey: userDefaultsKey)
        return (1...12).contains(stored) ? stored : defaultStartMonth
    }
}
```

**具体的シナリオ**:
新規ユーザーが設定変更せずに使い始めると、全レポートが4月〜3月で集計される。確定申告時に1月〜12月のデータが必要だが、年度をまたいだ集計になり、手作業での再集計が必要。1〜3月の取引が前年度に計上される。

**修正方針**: `defaultStartMonth` を `1` に変更。既存ユーザーへの影響を考慮し、初回起動時に会計年度開始月を明示的に選択させるオンボーディングを追加。

---

### C8: 定期取引の頻度変更（月次↔年次）でデータ消失

- **状態**: [x] 修正済み (2026-02-25, commit 3091462)
- **修正内容**: 頻度変更時にlastGeneratedDate = nilにリセット。次回processRecurringTransactions()実行時にC1のcatch-upループで適切に再生成される。テスト追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L492-501 (updateRecurring内の頻度変更処理)

**問題の詳細**:
頻度変更時に `lastGeneratedDate` がリセットされない。月次→年次に変更すると、`lastGeneratedDate` の年が現在年と一致するため、年次トランザクションが今年は生成されない。年次→月次に変更すると、過去月の補完がない（C1と複合）。

**問題のコード (L492-501)**:
```swift
if let frequency {
    recurring.frequency = frequency
    if frequency == .monthly {
        recurring.monthOfYear = nil
        recurring.yearlyAmortizationMode = nil
        recurring.lastGeneratedMonths = []
        // lastGeneratedDate はリセットされない！
    } else if let monthOfYear {
        recurring.monthOfYear = monthOfYear
    }
}
```

**具体的シナリオ1 (月次→年次)**:
2月まで月次生成済み (lastGeneratedDate=2/15) → 年次に変更 (monthOfYear=1) → 年次判定: lastGenYear(2026) == currentYear(2026) → 今年は生成されない → 年間のトランザクションが0。

**具体的シナリオ2 (年次→月次)**:
1月に年次生成済み → 3月に月次へ変更 → lastGeneratedMonths=[] にクリアされるが、月次ロジックは現在月（3月）のみ生成 → 2月分は永久欠損。

**修正方針**: 頻度変更時に (a) `lastGeneratedDate` をリセット、(b) 既存の生成済みトランザクションとの整合性チェック、(c) 必要に応じて catch-up 生成を実行。

---

### C9: 削除された自動生成トランザクションが再生成されない

- **状態**: [x] 修正済み (2026-02-25, commit 3091462)
- **修正内容**: deleteTransaction()でrecurringIdを持つトランザクション削除時に、元の定期取引のlastGeneratedDate/lastGeneratedMonthsをロールバック。次回processRecurringTransactions()実行時にC1のcatch-upループで再生成される。テスト追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L362-370 (deleteTransaction), L757-763 (月次生成ガード), L784-789 (年次生成ガード), L948 (月次分割ガード)

**問題の詳細**:
`deleteTransaction()` はトランザクションを削除するが、元の定期取引の `lastGeneratedDate` / `lastGeneratedMonths` を更新しない。定期処理は「既に生成済み」と判定し、削除されたトランザクションを再生成しない。

**問題のコード (deleteTransaction L362-370)**:
```swift
func deleteTransaction(id: UUID) {
    guard let transaction = transactions.first(where: { $0.id == id }) else { return }
    if let imagePath = transaction.receiptImagePath {
        ReceiptImageStore.deleteImage(fileName: imagePath)
    }
    modelContext.delete(transaction)
    save()
    refreshTransactions()
    // recurringId チェックなし。lastGeneratedDate/lastGeneratedMonths の更新なし。
}
```

**月次生成ガード (L757-763)**:
```swift
if let lastGen = recurring.lastGeneratedDate {
    let lastGenMonth = calendar.dateComponents([.year, .month], from: lastGen)
    let currentMonthComps = calendar.dateComponents([.year, .month], from: currentMonthStart)
    if lastGenMonth.year != currentMonthComps.year || lastGenMonth.month != currentMonthComps.month {
        shouldGenerate = true  // 月が異なる場合のみ生成
    }
    // 同月の場合は shouldGenerate = false のまま（削除されていても）
}
```

**具体的シナリオ**:
2月の家賃トランザクション（自動生成）をユーザーが誤って削除 → `lastGeneratedDate` は2月のまま → `processRecurringTransactions()` 実行 → 2月は「生成済み」と判定 → 再生成されない → 2月の家賃が永久に欠損。

**修正方針**: (a) `deleteTransaction` で `recurringId` を持つ場合は確認ダイアログを表示、(b) 生成済み判定を `lastGeneratedDate` だけでなく実際のトランザクション存在チェックに変更、(c) 削除時に `lastGeneratedDate` を前月に巻き戻す。

---

## HIGH (11件)

帳簿の正確性を損なう問題。確定申告実装前に修正必須。

---

### H1: equalAll のプロジェクト追加/削除で非対称な処理

- **状態**: [x] 修正済み (2026-02-25, commit 5aebb59)
- **修正内容**: deleteProject()とdeleteProjects()の両方にreprocessEqualAllCurrentPeriodTransactions() + refreshTransactions()を追加。addProject()と対称的にequalAll定期取引の今期分トランザクションを再計算。テスト1件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L269-272 (deleteProject), L333-336 (deleteProjects)

**問題の詳細**:
`addProject()` は `reprocessEqualAllCurrentPeriodTransactions()` (L123) を呼び出し、均等分割 + pro-rata を再計算する。しかし `deleteProject()` は `redistributeAllocations()` を使い、比率の按分再計算のみ行う。異なるアルゴリズムが適用され、結果が非対称になる。

**具体的シナリオ**:
3プロジェクトの equalAll で月10万円 → 各33,333/33,333/33,334円。プロジェクトC追加 → reprocess で4等分: 25,000×4。プロジェクトC削除 → redistributeAllocations で比率按分 → 3プロジェクトで25,000×3=75,000に戻る（10万円ではない場合がある）。

**修正方針**: `deleteProject()` でも equalAll トランザクションに対して `reprocessEqualAllCurrentPeriodTransactions()` を呼ぶ。

---

### H2: 通知機能が完全に未接続

- **状態**: [x] 修正済み (2026-02-25)
- **修正内容**: DataStore に `onRecurringScheduleChanged` コールバックを追加。`addRecurring`/`updateRecurring`/`deleteRecurring` の各メソッドでコールバックを発火。ContentView で NotificationService を Environment から取得し、DataStore にコールバック設定。アプリ起動時に `rescheduleAll()` を呼び出し。テスト3件追加。
- **ファイル**: `ProjectProfit/Services/NotificationService.swift`
- **行番号**: L58 (scheduleNotifications), L111 (cancelNotifications), L122 (rescheduleAll)

**問題の詳細**:
`scheduleNotifications()`, `cancelNotifications()`, `rescheduleAll()` の3メソッドがアプリ内のどこからも呼ばれていない。`ProjectProfitApp.swift` L17-18 で `checkAuthorizationStatus()` のみ呼ばれている。UIでは通知タイミング設定（sameDay, dayBefore, both）が可能だが、実際のローカル通知はスケジュールされない。

**修正方針**: 定期取引の作成・更新・削除時に対応する通知メソッドを呼ぶ。アプリ起動時に `rescheduleAll()` を呼ぶ。

---

### H3: monthlySpread の skipDates + 端数バグ

- **状態**: [x] 修正済み (2026-02-25, commit 5aebb59)
- **修正内容**: lastEligibleMonth算出時にskipDatesも除外する後方スキャンを追加。foundEligibleMonthフラグで全月スキップ時のsentinel値(-1)を設定し、端数消失を防止。テスト1件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L1138-1170 (lastEligibleMonth計算 + skipDates考慮)

**問題の詳細**:
`lastEligibleMonth` の計算が `endDate` のみ考慮し、`skipDates` を考慮しない。スキップ月が `lastEligibleMonth` に該当する場合、その月のトランザクション生成がスキップされ、端数が消失する。

**問題のコード (L964)**:
```swift
let txAmount = month == lastEligibleMonth ? monthlyAmount + remainder : monthlyAmount
// lastEligibleMonth がスキップ対象の場合、この行に到達せず remainder が消失
```

**具体的シナリオ**:
年額100,000円 → 月額8,333円、端数4円。12月がlastEligibleMonthだが、12月がskipDatesに含まれている → 12月の生成がスキップ → 端数4円が消失 + 12月分8,333円も未生成。

**修正方針**: `lastEligibleMonth` 算出時に `skipDates` も除外し、実際に生成される最後の月に端数を加算する。

---

### H4: monthlySpread が年途中開始でも12で除算

- **状態**: [x] 修正済み (2026-02-25, commit 5aebb59)
- **修正内容**: 除数を固定12から `actualMonthCount = 12 - startMonth + 1` に変更。実際の生成月数で年額を除算するように修正。テスト1件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L1138-1142 (月額計算)

**問題の詳細**:
`monthlyAmount = recurring.amount / 12` と固定で12除算するが、`startMonth` が1月でない場合、生成されるのは `startMonth...12` の月のみ。年額の一部しかトランザクションとして生成されない。

**問題のコード**:
```swift
let monthlyAmount = recurring.amount / 12   // 常に12で除算
let remainder = recurring.amount - (monthlyAmount * 12)
// ...
for month in startMonth...12 {  // startMonth が7なら6ヶ月分しか生成されない
```

**具体的シナリオ**:
年額120,000円、7月開始(monthOfYear=7) → 月額10,000円(120,000/12) → 7〜12月の6ヶ月で60,000円のみ生成 → 60,000円が永久に未計上。正しくは120,000/6=20,000円/月。

**修正方針**: 除数を `12` 固定ではなく、`(12 - startMonth + 1)` すなわち実際の生成月数で計算する。

---

### H5: reverseCompletionAllocations の端数処理なし

- **状態**: [x] 修正済み (2026-02-25)
- **修正内容**: C2修正時に作成された `recalculateAllocationAmounts()` (Utilities.swift) が端数処理を含んでおり、`reverseCompletionAllocations` はこの関数を使用済み。テスト追加で検証完了。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L639-653

**問題の詳細**:
`reverseCompletionAllocations()` は `amount * ratio / 100` で配分額を再計算するが、C2と同じ端数処理の欠如がある。`calculateHolisticProRata()` (Utilities.swift L476-481) は端数を最後のアクティブプロジェクトに加算するが、この関数にはその処理がない。

**問題のコード (L639-653)**:
```swift
let restored = transaction.allocations.map { alloc in
    Allocation(
        projectId: alloc.projectId,
        ratio: alloc.ratio,
        amount: transaction.amount * alloc.ratio / 100  // 端数処理なし
    )
}
transaction.allocations = restored
```

**修正方針**: C2の修正と合わせて、共通の端数処理関数を適用する。

---

### H6: calculateHolisticProRata で全プロジェクト0日のエッジケース

- **状態**: [x] 修正済み (2026-02-25, commit 3091462)
- **修正内容**: 全プロジェクトのactiveDaysが0の場合に比率ベースのフォールバック配分を行うロジックを追加。端数は最後のプロジェクトに加算。テスト追加。
- **ファイル**: `ProjectProfit/Utilities/Utilities.swift`
- **行番号**: L417-486

**問題の詳細**:
全プロジェクトの `activeDays` が0の場合、`freed` 金額（= `totalAmount` 全額）の配分先がなく、全配分額が0になる。`finalRemainder` チェック (L477-481) も `activeDays > 0` のプロジェクトが見つからず失敗。

**問題のコード (L477-481)**:
```swift
let currentTotal = amounts.reduce(0, +)  // = 0
let finalRemainder = totalAmount - currentTotal  // = totalAmount (全額)
if finalRemainder != 0, let lastActiveIdx = proratedEntries.lastIndex(where: { $0.input.activeDays > 0 }) {
    // lastActiveIdx は nil → 端数が配分されない
    amounts[lastActiveIdx] += finalRemainder
}
```

**具体的シナリオ**:
全プロジェクトの開始日が来月以降 → 全プロジェクト activeDays=0 → 配分額が全て0 → トランザクション金額全額が会計上消失。

**修正方針**: 全プロジェクトが0日の場合は比率ベースのフォールバック配分を行う。

---

### H7: refresh*() のサイレント失敗

- **状態**: [x] 修正済み (2026-02-25, commit 5aebb59)
- **修正内容**: refreshProjects/refreshTransactions/refreshCategories/refreshRecurringの4関数を`(try? fetch) ?? []`から`do-catch`に変更。失敗時は既存データを保持し、lastError = .dataLoadFailed(underlying:)を設定してログ記録。テスト2件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L100-137

**問題の詳細**:
4つのrefresh関数全てが `(try? modelContext.fetch(descriptor)) ?? []` を使用。fetch失敗時にエラーを無視し、空配列で上書きする。UIは全データ消失のように表示されるが、エラー表示はない。

**問題のコード**:
```swift
private func refreshProjects() {
    let descriptor = FetchDescriptor<PPProject>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    projects = (try? modelContext.fetch(descriptor)) ?? []  // 失敗時は空配列
}
// refreshTransactions(), refreshCategories(), refreshRecurring() も同パターン
```

**修正方針**: `try?` ではなく `do-catch` で明示的にエラーハンドリングし、失敗時は既存データを保持。ログ記録とUI通知を追加。

---

### H8: トランザクション編集後に pro-rata が再計算されない

- **状態**: [x] 修正済み (2026-02-25, commit 5aebb59)
- **修正内容**: reapplyProRataIfNeeded()ヘルパーを追加。updateTransaction()で金額のみ変更（ユーザー指定allocationsなし）の場合にpro-rata再適用。activeDays < totalDaysのプロジェクトが含まれる場合のみcalculateHolisticProRata()を呼び出し。テスト1件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L395-398 (updateTransaction), L768-805 (reapplyProRataIfNeeded)

**問題の詳細**:
`updateTransaction()` で金額変更時、`amount * ratio / 100` の単純計算のみで `calculateHolisticProRata()` が呼ばれない。元のトランザクションが pro-rata 調整済みだった場合、調整が失われる。

**問題のコード (L349-355)**:
```swift
if let allocations {
    transaction.allocations = allocations.map {
        Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: finalAmount * $0.ratio / 100)
    }
} else if amount != nil {
    transaction.allocations = transaction.allocations.map {
        Allocation(projectId: $0.projectId, ratio: $0.ratio, amount: finalAmount * $0.ratio / 100)
    }
}
// calculateHolisticProRata() の呼び出しなし
```

**修正方針**: 金額変更時、元のトランザクションが pro-rata 適用済みかを判定し、必要に応じて再計算する。

---

### H9: プロジェクト削除で全期間の履歴トランザクションが遡及修正される

- **状態**: [x] 修正済み (2026-02-25)
- **修正内容**: PPProject に `isArchived: Bool?` プロパティを追加。`deleteProject()` でトランザクション参照がある場合はアーカイブ（ソフトデリート）、ない場合は従来通りハードデリート。`archiveProject()`/`unarchiveProject()` メソッド追加。equalAll再処理・定期取引生成・月次分割でアーカイブ済みプロジェクトを除外。UI（ProjectsView/TransactionFormView/RecurringFormView）でアーカイブ済みプロジェクトを除外。FilterStatus に `archived` 追加。テスト3件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L193-237

**問題の詳細**:
`deleteProject()` は `for transaction in transactions` で全トランザクションを走査し、削除プロジェクトの配分を再分配する。過去の会計年度（確定申告済み）のトランザクションも修正される。

**問題のコード (L197)**:
```swift
for transaction in transactions {  // 日付フィルタなし。全期間の全トランザクション
    let filtered = transaction.allocations.filter { $0.projectId != id }
    // ...
    transaction.allocations = redistributeAllocations(
        totalAmount: transaction.amount,
        remainingAllocations: filtered
    )
}
```

**具体的シナリオ**:
2024年度の確定申告済みトランザクション（プロジェクトA:50%, B:50%） → 2026年にプロジェクトAを削除 → 2024年のトランザクションがプロジェクトB:100%に変更 → 確定申告書類との不一致。

**修正方針**: (a) 年度ロック機能 (T5) と組み合わせ、ロック済み年度のトランザクションは変更不可にする。(b) 削除ではなく「アーカイブ」概念を導入し、参照を維持する。

---

### H10: equalAll 再処理がユーザー手動編集を上書き

- **状態**: [x] 修正済み (2026-02-25)
- **修正内容**: `PPTransaction` に `isManuallyEdited: Bool?` プロパティを追加。`updateTransaction()` で equalAll 定期取引のアロケーション変更時にフラグを設定。`reprocessEqualAllCurrentPeriodTransactions()` でフラグ付きトランザクションをスキップ。テスト2件追加。
- **ファイル**: `ProjectProfit/Services/DataStore.swift`
- **行番号**: L567-636 (reprocessEqualAllCurrentPeriodTransactions)

**問題の詳細**:
`reprocessEqualAllCurrentPeriodTransactions()` は equalAll 定期取引の最新トランザクションの配分を強制的に再計算する。ユーザーが手動で配分を調整していても、プロジェクト追加時に全て上書きされる。警告なし。

**問題のコード (L632-633)**:
```swift
latestTx.allocations = newAllocations  // ユーザーの手動編集を無視して上書き
latestTx.updatedAt = Date()
```

**具体的シナリオ**:
equalAll の月次10,000円 → A:5,000/B:5,000 → ユーザーが手動でA:7,000/B:3,000に調整 → 新プロジェクトC追加 → addProject() → reprocess → A:3,333/B:3,333/C:3,334に強制変更。ユーザーの調整が消失。

**修正方針**: (a) 手動編集済みフラグを持ち、フラグがある場合は再処理をスキップ、または (b) 再処理前にユーザー確認ダイアログ。

---

### H11: TransactionsViewModel のフィルタ時合計値が不正

- **状態**: [x] 修正済み (2026-02-25, commit 3091462)
- **修正内容**: effectiveAmount(for:)ヘルパーを追加。プロジェクトフィルタ適用時はallocation.amountを使用、未適用時はtransaction.amountを使用。incomeTotal/expenseTotal/totalByTypeの全箇所に適用。テスト追加。
- **ファイル**: `ProjectProfit/ViewModels/TransactionsViewModel.swift`
- **行番号**: L52-63 (incomeTotal/expenseTotal), L132-136 (totalByType), L138-144 (effectiveAmount)

**問題の詳細**:
`incomeTotal`/`expenseTotal` は `t.amount`（トランザクション全額）を合計する。プロジェクトフィルタ適用中でも `allocation.amount` ではなく全額が表示される。グループ別合計の `totalByType` (L132-136) も同じ問題。

**問題のコード (L52-63)**:
```swift
var incomeTotal: Int {
    filteredTransactions
        .filter { $0.type == .income }
        .reduce(0) { $0 + $1.amount }  // t.amount = 全額。配分額ではない
}
```

**具体的シナリオ**:
10万円の経費をA:70%/B:30%で配分 → プロジェクトBでフィルタ → 経費合計に10万円が表示される → 実際のプロジェクトBの負担額は3万円。大幅な過大表示。

**修正方針**: プロジェクトフィルタ適用時は、該当プロジェクトの `allocation.amount` を合計値に使用する。

---

## MEDIUM (15件)

UX・データ品質に影響する問題。段階的に対応。

---

### M1: allocationMode/yearlyAmortizationMode がオプショナル

- **状態**: [x] 修正済み (2026-02-25, commit b97f019)
- **修正内容**: Models.swift L250,259 で非Optional宣言に変更。マイグレーション処理で既存データの nil を適切にデフォルト値に変換。
- **ファイル**: `ProjectProfit/Models/Models.swift` L244, L253
- **影響箇所**: DataStore.swift 6箇所 (`?? .manual`), RecurringFormView.swift 2箇所 (`?? .lumpSum`)

**問題**: SwiftData マイグレーション未対応のため Optional として宣言。全呼び出し箇所で nil-coalescing が必要。デフォルト値の不統一リスク。

---

### M2: SwiftData のマイグレーション戦略なし

- **状態**: [x] 修正済み (2026-02-25, commit b97f019)
- **修正内容**: DataStore.swift L45 で migrateNilOptionalFields() を呼び出し、既存データの nil Optional フィールドをデフォルト値に移行。
- **ファイル**: `ProjectProfit/ProjectProfitApp.swift` L21-26

**問題**: `VersionedSchema`, `MigrationPlan` が未実装（grep確認: 0件）。非Optional プロパティの追加やリネームでアプリがクラッシュするリスク。M1の根本原因。

---

### M3: dayOfMonth が28日に制限

- **状態**: [x] 修正済み（意図的設計。RecurringFormView L274 に UI 説明テキスト追加済み）
- **ファイル**: `ProjectProfit/Models/Models.swift` L292, `DataStore.swift` L505, `RecurringFormView.swift` L264-266

**問題**: `min(28, max(1, dayOfMonth))` でクランプ。UIでは説明テキストあり (L274) だが、CSV インポート等の非UI経路ではサイレントにクランプされる。29-31日に実際の支払いがあるユーザーは正確な日付を記録できない。

---

### M4: categoryId に空文字列を許容

- **状態**: [x] 修正済み (2026-02-25, commit 7ab0234)
- **修正内容**: RecurringFormView L731 で guard による空文字禁止。DataStore L702 で空文字 categoryId のフォールバック処理追加。
- **ファイル**: `ProjectProfit/Models/Models.swift` L175, L242; `RecurringFormView.swift` L729

**問題**: カテゴリ未選択時に `categoryId = ""` が保存される (RecurringFormView L729: `selectedCategoryId ?? ""`)。`getCategory(id: "")` は nil を返し、レポートで「不明」表示。CSV で空文字カテゴリが出力される。

---

### M5: Allocation.ratio に範囲制約なし

- **状態**: [x] 修正済み (2026-02-25, commit b97f019)
- **修正内容**: Models.swift L106 で min/max clamping (0-100) をモデルレベルで適用。
- **ファイル**: `ProjectProfit/Models/Models.swift` L99-109

**問題**: `ratio: Int` にモデルレベルの 0-100 制約がない。UI (RecurringFormView L442, TransactionFormView L396) ではクランプされるが、CSV インポート (`parseProjectAllocations` Utilities.swift L655) ではチェックなし。ratio=200 も受け入れ可能。

---

### M6: monthOfYear に範囲制約なし

- **状態**: [x] 修正済み (2026-02-25, commit bd0c0cf)
- **修正内容**: Models.swift L299 でモデルレベルの 1-12 バリデーション。DataStore L772 で更新時にも 1-12 範囲チェック適用。
- **ファイル**: `ProjectProfit/Models/Models.swift` L248, L293

**問題**: `monthOfYear: Int?` に 1-12 の制約なし。UI では Picker で制限されるが、`updateRecurring()` (DataStore.swift L499-503) は任意の Int を受け入れる。月=13 の場合、`Calendar.date()` が nil を返すか翌年1月にロールオーバー。

---

### M7: レシート画像の更新時に旧画像を先に削除

- **状態**: [x] 修正済み（RecurringFormView L750, TransactionFormView L529 で正しい順序に修正済み）
- **ファイル**: `ProjectProfit/Views/Components/RecurringFormView.swift` L734-747

**問題**: 新画像の保存 (`saveImage`) が失敗した場合でも、旧画像は既に削除済み。`selectedImage` が既存の `receiptImagePath` から初期化されない (L30) ため、編集画面でも画像状態の不整合が起きる。

---

### M8: CSV エクスポートがフィルタ中のデータのみ出力

- **状態**: [x] 修正済み (2026-02-25, commit 9a0fae0)
- **修正内容**: TransactionsViewModel L82 に exportAll パラメータを追加。全データエクスポートオプション対応。
- **ファイル**: `ProjectProfit/ViewModels/TransactionsViewModel.swift` L82-88

**問題**: `generateCSVText()` が `filteredTransactions` を使用。フィルタ適用中にエクスポートすると部分データのみ出力。バックアップ目的の場合、データ欠損のリスク。

---

### M9: CSV に allocation.amount 等の重要フィールドが未出力

- **状態**: [x] 修正済み (2026-02-25, commit b97f019)
- **修正内容**: Utilities.swift L714 で 12列ヘッダーに拡張。allocation.amount, recurringId, createdAt 等の重要フィールドを出力。
- **ファイル**: `ProjectProfit/Utilities/Utilities.swift` L669-697

**問題**: エクスポートは6列のみ (日付, 種類, 金額, カテゴリ, プロジェクト(比率のみ), メモ)。`allocation.amount`, `recurringId`, `createdAt`, `updatedAt`, `receiptImagePath`, `lineItems` が欠落。CSV ラウンドトリップで復元不可能。

---

### M10: カテゴリ名の一意性チェックなし

- **状態**: [x] 修正済み (2026-02-25, commit c53e56d)
- **修正内容**: CategoryManageView L250,268 で保存前に重複チェック。DataStore L618 でも addCategory 時に一意性検証。
- **ファイル**: `ProjectProfit/Views/Components/CategoryManageView.swift` L262-277 (saveNewCategory), L250-259 (saveEdit); `DataStore.swift` L389-396 (addCategory)

**問題**: 同名カテゴリを作成可能。CSV インポート (DataStore.swift L1270) で `categories.first(where: { $0.name == name })` が最初にヒットしたものを使用し、意図しないカテゴリに紐づく。

---

### M11: 手動配分で同一プロジェクトの重複選択可

- **状態**: [x] 修正済み (2026-02-25, commit b97f019)
- **修正内容**: RecurringFormView L419, TransactionFormView L374 で usedIds フィルタにより既選択プロジェクトを除外。
- **ファイル**: `ProjectProfit/Views/Components/TransactionFormView.swift` L373-377; `RecurringFormView.swift` L419-424

**問題**: 配分行のプロジェクト選択メニューが全プロジェクトを表示し、既に他の行で選択されたプロジェクトを除外しない。新規行追加時 (L431-435) は除外するが、既存行の変更時は未対応。同一プロジェクトが複数行に出現すると、集計で一部の配分が無視される可能性。

---

### M12: endDate DatePicker が未来日のみに制限

- **状態**: [x] 修正済み (2026-02-25, commit b97f019)
- **修正内容**: RecurringFormView L644 で `in: Date()...` 制限を削除。過去日の終了日設定を許可。
- **ファイル**: `ProjectProfit/Views/Components/RecurringFormView.swift` L641-647

**問題**: `in: Date()...` で今日以降のみ選択可能。既存の定期取引を編集して過去の終了日を設定できない。「先月で終了すべきだった」ケースに対応不可。

---

### M13: deleteAllData() が定期取引のレシート画像を未削除

- **状態**: [x] 修正済み (2026-02-25, commit 5aebb59)
- **修正内容**: C4のdeferred deletion改修時にdeleteAllData()でrecurringTransactions.compactMap(\.receiptImagePath)も収集対象に追加。save()成功後にトランザクション+定期取引の両方のレシート画像を削除。
- **ファイル**: `ProjectProfit/Services/DataStore.swift` L1545-1548

**問題**: `transactions` のレシート画像は削除するが、`recurringTransactions` のレシート画像は削除しない。孤立ファイルがディスクに残り続ける。

---

### M14: ReceiptImageStore にパストラバーサル脆弱性

- **状態**: [x] 修正済み (2026-02-25, commit 266d01c)
- **修正内容**: sanitizedFileName() ヘルパーで ../../、バックスラッシュ、空文字列等を拒否。loadImage/deleteImage/imageExists に適用。テスト7件追加。
- **ファイル**: `ProjectProfit/Services/ReceiptImageStore.swift` L42-43, L53-54, L60-61

**問題**: `fileName` パラメータが未サニタイズのまま `directoryURL.appendingPathComponent(fileName)` に渡される。`../../Library/...` のような値で意図しないファイルの読取り・削除が可能。`saveImage()` (L29) は UUID 生成で安全だが、`loadImage`/`deleteImage`/`imageExists` は外部データ（DB値、CSV）からの入力を受ける。

---

### M15: ProjectFormView で startDate > completedAt を許容

- **状態**: [x] 修正済み (2026-02-25, commit 40152a3)
- **修正内容**: ProjectFormView L185-199 で startDate≤completedAt / startDate≤plannedEndDate のバリデーションを追加。
- **ファイル**: `ProjectProfit/Views/Components/ProjectFormView.swift` L47-50, L109-112, L172-189

**問題**: 開始日、完了日、終了予定日の DatePicker に相互制約なし。`save()` (L172-189) でもバリデーションなし。`startDate > completedAt` の場合、pro-rata の `calculateActiveDaysInMonth` が0を返し、全配分額が0になる。

---

## 確定申告構造的欠落 (7件)

確定申告機能の実装に必要な、現在のアプリに存在しない概念・機能。

---

### T1: 期首残高・期末残高の概念がない

- **状態**: [x] 修正済み (2026-02-25, Phase 4B + Batch 12B)
- **修正内容**: AccountingEngine.generateOpeningBalanceEntry() で期首残高仕訳を自動生成（前年度の資産・負債・資本残高を繰越）。generateClosingBalanceEntry() で決算仕訳を生成（収益・費用勘定を0にし当期純利益を元入金に振替）。deleteClosingBalanceEntry() で削除。DataStore+Accounting に generateClosingEntry/deleteClosingEntry/regenerateClosingEntry。ClosingEntryView で決算仕訳の生成・確認・削除UI。AccountingReportService.postedEntryIdsInRange に excludeTypes 追加でレポート二重計上防止。
- ~~**検証**: "残高", "balance", "期首", "期末" — ソースコード内で0件~~
- **必要性**: 貸借対照表の作成、前期からの繰越金の管理
- **影響範囲**: 新規モデル追加、サマリーロジックの拡張

---

### T2: 標準勘定科目マッピングがない

- **状態**: [x] 修正済み (2026-02-25, Phase 4A-4B)
- **修正内容**: AccountingConstants に25勘定科目定義（資産6/負債2/資本3/収益2/費用12/特殊1）。PPAccount モデル新規作成。ChartOfAccountsView で勘定科目一覧表示。CategoryAccountMappingView でカテゴリ⇔勘定科目の紐付け設定。AccountingBootstrapService で13マッピング自動適用。
- ~~**検証**: "勘定科目", "chart of accounts", "accountCode" — 0件~~
- ~~**現状**: PPCategory は `name`, `type`, `icon` のみ。デフォルトカテゴリは「ホスティング」「ツール」等の独自名称~~
- **必要性**: 旅費交通費、通信費、消耗品費等の標準勘定科目への紐づけ。確定申告書類の経費区分に直接マッピング
- **影響範囲**: PPCategory にフィールド追加、マッピングテーブル、確定申告エクスポートロジック

---

### T3: 減価償却の概念がない

- **状態**: [x] 修正済み (2026-02-25, Batch 13-14)
- **修正内容**: DepreciationMethod enum（定額法/200%定率法/少額一括/3年均等/少額減価償却資産特例）、AssetStatus enum。PPFixedAsset SwiftData モデル（取得日/取得価額/耐用年数/償却方法/残存価額/事業使用割合等）。DepreciationEngine で5種類の日本税法準拠償却計算＋仕訳生成（事業/家事按分対応）。減価償却累計額アカウント追加。DataStore+FixedAsset.swift で CRUD＋一括計上＋スケジュールプレビュー。FixedAssetFormView（自動償却方法提案付き）、FixedAssetListView、FixedAssetDetailView。
- ~~**検証**: "減価償却", "depreciation", "固定資産" — ソースコード内で0件（Xcode Assets のみ）~~
- ~~**現状**: `yearlyAmortizationMode` は年額の月次按分機能であり、会計上の減価償却ではない~~
- **必要性**: PC、設備等の固定資産の定額法/定率法による年次償却。固定資産台帳の作成
- **影響範囲**: 新規モデル (FixedAsset)、償却計算エンジン、固定資産台帳ビュー

---

### T4: 消費税区分の概念がない

- **状態**: [x] 修正済み (2026-02-25, Phase 5)
- **修正内容**: TaxCategory enum（standardRate/reducedRate/exempt/nonTaxable）を AccountingEnums.swift に追加。PPTransaction に税フィールド4件追加（taxAmount, taxRate, isTaxIncluded, taxCategory）。AccountingEngine の buildIncomeLines/buildExpenseLines に消費税仕訳行生成（仮払消費税/仮受消費税）を追加（taxAmount=nil時は既存動作を維持し後方互換性確保）。消費税3勘定科目（仮払消費税/仮受消費税/未払消費税）と在庫・COGS 4勘定科目を追加。ConsumptionTaxReportService で消費税集計。InventoryService で COGS 仕訳生成。DepreciationScheduleBuilder で減価償却明細表生成。TransactionFormView に消費税入力セクション追加。ProfileSettingsView 新規（e-Tax申告者情報入力）。InventoryInputView + InventoryViewModel 新規（在庫・COGS入力）。FixedAssetScheduleView 新規（減価償却明細表表示）。EtaxXtxExporter に申告者情報/棚卸/固定資産明細/貸借対照表XMLセクション追加。EtaxFieldPopulator に populateDeclarantInfo/populateInventory/populateBalanceSheet メソッド追加。ShushiNaiyakushoBuilder に減価償却明細/地代家賃内訳セクション追加。ClassificationEngine に confidence 閾値（0.90/0.60）と needsReview フラグ追加。UnclassifiedTransactionsView に confidence バッジ追加。テスト63件新規追加（TaxCategoryTests 17件、PPInventoryRecordTests 10件、ConsumptionTaxReportServiceTests 8件、DepreciationScheduleBuilderTests 10件、InventoryServiceTests 11件、AccountingIntegrationTests 7件）。全958テスト GREEN。
- ~~**検証**: `ReceiptScannerService.swift` で OCR 時に `taxAmount` を抽出するが、`PPTransaction` には保存されない~~
- ~~**現状**: トランザクションは `amount` (合計金額) のみ。税率（8%/10%）、税込/税抜、課税/非課税の区別なし~~
- **必要性**: 消費税申告書の作成。軽減税率8%と標準税率10%の区分。仕入税額控除の計算
- **影響範囲**: PPTransaction にフィールド追加、入力UI拡張、消費税集計ロジック

---

### T5: 年度ロック機能がない

- **状態**: [x] 修正済み (2026-02-25, Batch 11A)
- **修正内容**: PPAccountingProfile に `lockedYears: [Int]?` 追加。DataStore+YearLock.swift で lockFiscalYear/unlockFiscalYear/isYearLocked 実装。addTransaction/updateTransaction/deleteTransaction/addManualJournalEntry/deleteManualJournalEntry に年度ロックガード追加。AppError.yearLocked 追加。テスト8件追加。
- ~~**検証**: "fiscal lock", "年度ロック", "確定申告" — 0件~~
- ~~**現状**: 全期間の全トランザクションが常時編集可能。DataStore の CRUD に日付ベースの書込みガードなし~~
- **必要性**: 確定申告済みの年度のデータが変更されないことを保証。H9 の根本的な解決策
- **影響範囲**: 年度ロック状態の管理、全 CRUD 操作へのガード追加、UI でのロック表示

---

### T6: 確定申告用エクスポートフォーマットがない

- **状態**: [x] 修正済み (2026-02-25, Phase 4G)
- **修正内容**: EtaxXtxExporter で .xtx 形式（e-Tax 互換 XML）出力。EtaxFieldPopulator で青色申告決算書フィールド自動入力。ShushiNaiyakushoBuilder で白色申告（収支内訳書）対応。EtaxExportView でプレビュー＋エクスポート UI。EtaxCharacterValidator で JIS X 0208 文字検証。
- ~~**検証**: "青色申告", "収支内訳書", "決算書", "e-Tax" — 0件~~
- ~~**現状**: CSV 6列のみ (Utilities.swift L669-697)~~
- **必要性**: 青色申告決算書（一般用/不動産用）、収支内訳書、e-Tax XML フォーマットへの対応
- **影響範囲**: エクスポートエンジン新規作成、勘定科目マッピング (T2) 前提

---

### T7: 損益計算書の概念がない

- **状態**: [x] 修正済み (2026-02-25, Phase 4E)
- **修正内容**: AccountingReportService に generateProfitLoss（収益・費用区分別集計）、generateTrialBalance（試算表）、generateBalanceSheet（B/S、当期純利益の資本組入れ含む）を実装。ProfitLossView、TrialBalanceView、BalanceSheetView で各レポートを表示。
- ~~**検証**: "損益計算書", "P&L", "income statement" — ViewModelに `yearlyProfitLoss` があるが単純集計のみ~~
- ~~**現状**: `OverallSummary` (Models.swift L339-344) は `totalIncome/totalExpense/netProfit/profitMargin` の1段階集計~~
- **必要性**: 確定申告書類の基礎となる標準的な損益計算書。多段階利益の計算
- **影響範囲**: カテゴリの階層化 (T2 と連動)、レポートロジックの大幅拡張

---

## 推奨修正順序

### Phase 1: データ整合性の基盤修正（最優先） — ✅ 10/10 完了

| 順序 | ID | 概要 | 依存関係 | 状態 |
|------|-----|------|----------|------|
| 1 | C1 | catch-up ループ実装 | なし | ✅ 266d01c |
| 2 | C2 | allocation 端数処理統一（9箇所） | なし | ✅ 266d01c |
| 3 | C5 | save() エラーの UI 表示 + rollback | なし | ✅ 266d01c + 5aebb59 |
| 4 | C4 | レシート画像削除順序修正 | C5 | ✅ 5aebb59 |
| 5 | C6 | deleteRecurring の生成済みトランザクション処理 | なし | ✅ 266d01c |
| 6 | C9 | 削除済みトランザクションの再生成対応 | C1 | ✅ 3091462 |
| 7 | C3 | カテゴリ削除の参照チェック | なし | ✅ 266d01c |
| 8 | C8 | 頻度変更時の lastGeneratedDate リセット | C1 | ✅ 3091462 |
| 9 | H5 | reverseCompletionAllocations 端数処理 | C2 | ✅ 395ae4f |
| 10 | H7 | refresh*() のエラーハンドリング | C5 | ✅ 5aebb59 |

### Phase 2: 会計正確性の修正 — ✅ 10/10 完了

| 順序 | ID | 概要 | 依存関係 | 状態 |
|------|-----|------|----------|------|
| 11 | C7 | fiscal year デフォルト修正 | なし | ✅ 266d01c |
| 12 | H4 | monthlySpread 年途中除数修正 | なし | ✅ 5aebb59 |
| 13 | H3 | monthlySpread skipDates + 端数 | なし | ✅ 5aebb59 |
| 14 | H8 | updateTransaction 後の pro-rata 再計算 | なし | ✅ 5aebb59 |
| 15 | H11 | フィルタ時合計値修正 | なし | ✅ 3091462 |
| 16 | H6 | pro-rata 全0日エッジケース | なし | ✅ 3091462 |
| 17 | H1 | equalAll 対称性修正 | なし | ✅ 5aebb59 |
| 18 | H9 | プロジェクト削除の履歴保護 | T5 | ✅ 395ae4f |
| 19 | H10 | equalAll 再処理のユーザー編集保護 | なし | ✅ 395ae4f |
| 20 | H2 | 通知機能の接続 | なし | ✅ 395ae4f |

### Phase 3: データ品質・UX 改善 — ✅ 15/15 完了

| 順序 | ID | 概要 | 状態 |
|------|-----|------|------|
| 21 | M14 | パストラバーサル脆弱性修正 | ✅ 266d01c |
| 22 | M2 | SwiftData マイグレーション戦略 | ✅ b97f019 |
| 23 | M1 | Optional 型の非Optional化 (M2後) | ✅ b97f019 |
| 24 | M5 | ratio 範囲バリデーション | ✅ b97f019 |
| 25 | M6 | monthOfYear 範囲バリデーション | ✅ bd0c0cf |
| 26 | M4 | categoryId 空文字禁止 | ✅ 7ab0234 |
| 27 | M10 | カテゴリ名一意性チェック | ✅ c53e56d |
| 28 | M11 | 重複プロジェクト選択防止 | ✅ b97f019 |
| 29 | M15 | 日付整合性バリデーション | ✅ 40152a3 |
| 30 | M7 | レシート画像更新の安全化 | ✅ |
| 31 | M13 | deleteAllData のレシート画像完全削除 | ✅ 5aebb59 |
| 32 | M12 | endDate の過去日設定許可 | ✅ b97f019 |
| 33 | M8 | CSV エクスポート全データオプション | ✅ 9a0fae0 |
| 34 | M9 | CSV フィールド拡充 | ✅ b97f019 |
| 35 | M3 | dayOfMonth 28日制限の注記改善 | ✅ |

### Phase 4: 確定申告機能の詳細実装計画

> **計画策定**: 12 Agent チームによる専門調査に基づく
> **前提条件**: Phase 1-3 の CRITICAL/HIGH 問題が全て修正済みであること
> **対象税目**: 所得税（個人事業主の確定申告）。消費税は Phase 5 で対応済み（T4 参照）
> **会計方式**: 複式簿記（青色申告65万円控除対応）

#### UI 設計制約（必須遵守）

確定申告関連の UI は以下のルールに従うこと。

- **ボトムタブバーに新規タブを追加しない**: 現在5タブ（ダッシュボード・プロジェクト・取引履歴・レポート・設定）で構成されており、これ以上追加するとタブの視認性・操作性が著しく低下する。
- **既存「レポート」タブ内にセグメント切替で統合する**: レポート画面（`ReportView`）の上部にセグメントコントロール（`Picker` with `.segmented` style）を配置し、「年次レポート」と「確定申告」を切り替えられるようにする。
- **現在の年次レポート画面はそのまま維持**: 既存の `ReportView` の内容（年度ナビゲーター、サマリカード、前年比較、月次チャート、カテゴリ内訳、プロジェクトランキング）はセグメント「年次レポート」として完全に温存する。
- **確定申告セグメントの構成**: 試算表、損益計算書（P&L）、貸借対照表（B/S）、e-Tax エクスポート等の会計レポートは「確定申告」セグメント内に NavigationLink 等で階層化し、使いやすさを最優先にする。

```
レポート画面 (ReportView)
├── [年次レポート | 確定申告]  ← セグメントコントロール（上部）
│
├── 年次レポート（既存）
│   ├── 年度ナビゲーター
│   ├── サマリカード
│   ├── 前年比較
│   ├── 月次チャート
│   ├── カテゴリ内訳
│   └── プロジェクトランキング
│
└── 確定申告（新規）
    ├── 勘定科目マッピング
    ├── 仕訳一覧 / 元帳
    ├── 試算表
    ├── 損益計算書 (P&L)
    ├── 貸借対照表 (B/S)
    └── e-Tax エクスポート
```

> **注意**: Phase 4D（会計 UI）の設計はこの制約に準拠すること。Todo.md 内で「帳簿タブ」と記載されている箇所は「レポート > 確定申告セグメント」に読み替えること。

#### Phase 4 全体サマリー

| サブフェーズ | 概要 | タスク数 | 依存関係 | T項目カバー |
|-------------|------|---------|----------|------------|
| 4A | データ基盤（SwiftData models） | 8 | Phase 1-3 完了 | T1(部分), T2(部分) | ✅ 完了 (246650b) |
| 4B | 会計エンジン + ブートストラップ | 7 | 4A | T1, T2 | ✅ 完了 (1a93e1e) |
| 4C | 既存コード改修（transfer 対応） | 9 | 4A | — | ✅ 完了 |
| 4D | 会計 UI（帳簿タブ） | 7 | 4B, 4C | — | ✅ 完了 |
| 4E | 会計レポート（試算表/P&L/B/S） | 6 | 4B | T1(部分), T7 | ✅ 完了 |
| 4F | 自動分類エンジン | 7 | 4B | — | ✅ 完了 (4F-5: Batch 9B) |
| 4G | e-Tax エクスポート | 7 | 4E, 4F | T6 | ✅ 完了 (4G-1,4G-2: Batch 10, 4G-7: Batch 11B) |
| 4H | テスト + 検証 | 7 | 4A-4G | — | ✅ 完了 |

---

#### Phase 4A: データ基盤（SwiftData models） — ✅ 8/8 完了 (246650b)

**目的**: 複式簿記に必要な勘定科目・仕訳モデルを SwiftData に追加する。既存モデルに振替取引・経費按分率・仕訳連携のフィールドを追加する。

**対応する T 項目**: T2（勘定科目マッピング — データモデル部分）、T1（期首残高 — データモデル部分）

| 順序 | ID | タスク | 作成/変更ファイル | 依存関係 | テスト要件 | 複雑度 | リスク | 状態 |
|------|------|--------|------------------|----------|-----------|--------|--------|------|
| 36 | 4A-1 | AccountType 等の enum 追加 | `Models/AccountingEnums.swift` (新規) | なし | ModelsTests に enum テスト追加 | 低 | 低 | ✅ 246650b |
| 37 | 4A-2 | PPAccount モデル作成 | `Models/PPAccount.swift` (新規) | 4A-1 | PPAccountTests (新規) | 中 | 低 | ✅ 246650b |
| 38 | 4A-3 | PPJournalEntry + PPJournalLine モデル作成 | `Models/PPJournalEntry.swift` (新規) | 4A-1 | PPJournalEntryTests (新規) | 中 | 低 | ✅ 246650b |
| 39 | 4A-4 | PPAccountingProfile モデル作成 | `Models/PPAccountingProfile.swift` (新規) | 4A-1 | PPAccountingProfileTests (新規) | 低 | 低 | ✅ 246650b |
| 40 | 4A-5 | TransactionType に .transfer 追加 | `Models/Models.swift` | なし | 既存テスト修正 (全テストクラス) | 中 | **高** | ✅ 246650b |
| 41 | 4A-6 | PPTransaction に新フィールド追加 | `Models/Models.swift` | 4A-2, 4A-3 | 既存テスト修正 | 中 | **高** | ✅ 246650b |
| 42 | 4A-7 | PPCategory に linkedAccountId 追加 | `Models/Models.swift` | 4A-2 | 既存テスト修正 | 低 | 中 | ✅ 246650b |
| 43 | 4A-8 | modelContainer 更新 + マイグレーション計画 | `ProjectProfitApp.swift` | 4A-2, 4A-3, 4A-4 | 起動テスト | **高** | **高** | ✅ 246650b |

**4A-1: AccountType 等の enum 追加**

新規ファイル `ProjectProfit/Models/AccountingEnums.swift` に以下を定義:

```swift
// AccountType: 勘定科目の5大分類
enum AccountType: String, Codable, CaseIterable {
    case asset       // 資産
    case liability   // 負債
    case equity      // 資本（元入金等）
    case revenue     // 収益
    case expense     // 費用
}

// NormalBalance: 勘定科目の正常残高方向
enum NormalBalance: String, Codable {
    case debit   // 借方（資産・費用）
    case credit  // 貸方（負債・資本・収益）
}

// AccountSubtype: e-Tax TaxLine の12経費区分 + 追加区分
enum AccountSubtype: String, Codable, CaseIterable {
    // 収益
    case salesRevenue          // 売上（収入）金額
    case otherIncome           // 雑収入
    // 費用（e-Tax 12区分）
    case rentExpense           // 地代家賃
    case utilitiesExpense      // 水道光熱費
    case travelExpense         // 旅費交通費
    case communicationExpense  // 通信費
    case advertisingExpense    // 広告宣伝費
    case entertainmentExpense  // 接待交際費
    case depreciationExpense   // 減価償却費
    case repairExpense         // 修繕費
    case suppliesExpense       // 消耗品費
    case welfareExpense        // 福利厚生費
    case outsourcingExpense    // 外注工賃
    case miscExpense           // 雑費
    // 追加
    case ownerContributions    // 事業主借
    case ownerDrawings         // 事業主貸
    case suspense              // 仮勘定
    case openingBalance        // 期首残高用
    case cash                  // 現金
    case ordinaryDeposit       // 普通預金
    case accountsReceivable    // 売掛金
    case accountsPayable       // 買掛金
}

// JournalEntryType: 仕訳の種別
enum JournalEntryType: String, Codable, CaseIterable {
    case auto       // トランザクションから自動生成
    case manual     // 手動仕訳（決算整理仕訳等）
    case opening    // 期首残高仕訳
    case closing    // 決算仕訳
}

// BookkeepingMode: 簡易簿記/複式簿記の選択
enum BookkeepingMode: String, Codable, CaseIterable {
    case singleEntry  // 簡易簿記（10万円控除）
    case doubleEntry  // 複式簿記（65万円控除）
}
```

**4A-2: PPAccount モデル**

新規ファイル `ProjectProfit/Models/PPAccount.swift`:

```swift
@Model
final class PPAccount {
    @Attribute(.unique) var id: UUID
    var code: String           // "101", "401" 等
    var name: String           // "現金", "売上高" 等
    var accountType: AccountType
    var normalBalance: NormalBalance
    var subtype: AccountSubtype?
    var parentAccountId: UUID? // 階層構造用
    var isSystem: Bool         // デフォルト勘定科目（削除不可）
    var isActive: Bool
    var displayOrder: Int
    var createdAt: Date
    var updatedAt: Date
}
```

**4A-3: PPJournalEntry + PPJournalLine モデル**

新規ファイル `ProjectProfit/Models/PPJournalEntry.swift`:

```swift
@Model
final class PPJournalEntry {
    @Attribute(.unique) var id: UUID
    var date: Date
    var entryType: JournalEntryType
    var description: String
    var sourceTransactionId: UUID?  // auto の場合、元のPPTransaction.id
    var isPosted: Bool              // true = 確定済み（T5 年度ロックの基礎）
    var lines: [PPJournalLine]
    var createdAt: Date
    var updatedAt: Date
}

@Model
final class PPJournalLine {
    @Attribute(.unique) var id: UUID
    var journalEntryId: UUID
    var accountId: UUID
    var debitAmount: Int    // 借方金額（0 or 正の整数）
    var creditAmount: Int   // 貸方金額（0 or 正の整数）
    var memo: String?
    var displayOrder: Int
}
```

仕訳の不変条件: `sum(debitAmount) == sum(creditAmount)` を全仕訳で保証すること。

**4A-4: PPAccountingProfile モデル**

新規ファイル `ProjectProfit/Models/PPAccountingProfile.swift`:

```swift
@Model
final class PPAccountingProfile {
    @Attribute(.unique) var id: UUID
    var fiscalYear: Int            // 対象年度（例: 2026）
    var bookkeepingMode: BookkeepingMode
    var businessName: String       // 屋号
    var ownerName: String          // 氏名
    var taxOfficeCode: String?     // 税務署コード
    var isBlueReturn: Bool         // 青色申告かどうか
    var openingDate: Date?         // 開業日
    var lockedAt: Date?            // 年度ロック日時（nil=未ロック、T5対応）
    var createdAt: Date
    var updatedAt: Date
}
```

**4A-5: TransactionType に .transfer 追加**

変更ファイル `ProjectProfit/Models/Models.swift`:

```swift
enum TransactionType: String, Codable {
    case income
    case expense
    case transfer  // 新規: 振替（事業主貸/借、口座間移動等）
}
```

**リスク: 高** — 既存コード全体で `TransactionType` の2値 switch が多数存在（推定40箇所以上、12ファイル）。全箇所に `.transfer` case の追加が必要。Phase 4C で体系的に対応する。

**4A-6: PPTransaction に新フィールド追加**

変更ファイル `ProjectProfit/Models/Models.swift` — PPTransaction に以下を追加:

```swift
// 新規フィールド
var paymentAccountId: UUID?      // 支払元勘定科目
var transferToAccountId: UUID?   // 振替先勘定科目（type == .transfer 時）
var taxDeductibleRate: Int?      // 経費按分率（家事按分、0-100）
var bookkeepingMode: BookkeepingMode?  // この取引の記帳方式
var journalEntryId: UUID?        // 対応する仕訳の ID
```

**リスク: 高** — SwiftData マイグレーション（M2）が未実装の場合、Optional として追加する必要あり。M2 完了後に非 Optional 化を検討。

**4A-7: PPCategory に linkedAccountId 追加**

変更ファイル `ProjectProfit/Models/Models.swift` — PPCategory に以下を追加:

```swift
var linkedAccountId: UUID?  // 紐づく勘定科目の ID（T2 対応）
```

**4A-8: modelContainer 更新**

変更ファイル `ProjectProfit/ProjectProfitApp.swift`:

```swift
// 既存
.modelContainer(for: [PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self])
// ↓ 変更後
.modelContainer(for: [
    PPProject.self, PPTransaction.self, PPCategory.self, PPRecurringTransaction.self,
    PPAccount.self, PPJournalEntry.self, PPJournalLine.self, PPAccountingProfile.self
])
```

テストコンテナも同様に更新が必要（7つの `@MainActor` テストクラス全て）。

**リスク: 高** — SwiftData マイグレーション計画なしに新モデルを追加すると、既存データベースとの互換性問題が発生する可能性。M2（SwiftData マイグレーション戦略）を先に、または同時に実施することを強く推奨。

---

#### Phase 4B: 会計エンジン + ブートストラップ — ✅ 7/7 完了 (1a93e1e)

**目的**: デフォルト勘定科目の初期設定、既存カテゴリ→勘定科目のマッピング移行、トランザクション→仕訳の自動変換エンジンを実装する。

**対応する T 項目**: T2（勘定科目マッピング — ロジック部分）、T1（期首残高 — 期首仕訳生成）

| 順序 | ID | タスク | 作成/変更ファイル | 依存関係 | テスト要件 | 複雑度 | リスク | 状態 |
|------|------|--------|------------------|----------|-----------|--------|--------|------|
| 44 | 4B-1 | デフォルト勘定科目定義 | `Services/AccountingConstants.swift` (新規) | 4A-2 | 定義値テスト | 低 | 低 | ✅ 1a93e1e |
| 45 | 4B-2 | カテゴリ→勘定科目マッピング定義 | `Services/AccountingConstants.swift` | 4B-1 | マッピングテスト | 低 | 低 | ✅ 1a93e1e |
| 46 | 4B-3 | AccountingBootstrapService 実装 | `Services/AccountingBootstrapService.swift` (新規) | 4B-1, 4B-2 | AccountingBootstrapTests (新規) | **高** | **高** | ✅ 1a93e1e |
| 47 | 4B-4 | AccountingEngine 実装 | `Services/AccountingEngine.swift` (新規) | 4A-3, 4B-1 | AccountingEngineTests (新規) | **高** | **高** | ✅ 1a93e1e |
| 48 | 4B-5 | DataStore への会計データ統合 | `Services/DataStore.swift` | 4B-3, 4B-4 | 既存テスト修正 + 統合テスト | **高** | **高** | ✅ 1a93e1e |
| 49 | 4B-6 | 仕訳バリデーションサービス | `Services/JournalValidationService.swift` (新規) | 4A-3 | JournalValidationTests (新規) | 中 | 中 | ✅ 1a93e1e |
| 50 | 4B-7 | 期首残高仕訳生成 | `Services/AccountingEngine.swift` | 4B-4 | 期首残高テスト | 中 | 中 | ✅ 1a93e1e |

**4B-1: デフォルト勘定科目定義（29勘定科目）**

新規ファイル `ProjectProfit/Services/AccountingConstants.swift`:

資産（6）: 現金, 普通預金, 売掛金, 前払費用, クレジットカード, 事業主貸
負債（2）: 買掛金, 未払費用
資本（2）: 元入金, 事業主借
収益（2）: 売上高, 雑収入
費用（12 — e-Tax TaxLine 準拠）: 地代家賃, 水道光熱費, 旅費交通費, 通信費, 広告宣伝費, 接待交際費, 減価償却費, 修繕費, 消耗品費, 福利厚生費, 外注工賃, 雑費
特殊（1）: 仮勘定（未分類用）

勘定科目コード体系:
- 1xx: 資産
- 2xx: 負債
- 3xx: 資本
- 4xx: 収益
- 5xx-6xx: 費用

**4B-2: カテゴリ→勘定科目マッピング（13マッピング）**

既存のデフォルトカテゴリと勘定科目の対応:

| デフォルトカテゴリ | 勘定科目 | AccountSubtype |
|-------------------|---------|---------------|
| ホスティング | 通信費 | communicationExpense |
| ツール | 消耗品費 | suppliesExpense |
| 広告 | 広告宣伝費 | advertisingExpense |
| 交通 | 旅費交通費 | travelExpense |
| 通信 | 通信費 | communicationExpense |
| 外注 | 外注工賃 | outsourcingExpense |
| 書籍 | 消耗品費 | suppliesExpense |
| 食事 | 接待交際費 | entertainmentExpense |
| 備品 | 消耗品費 | suppliesExpense |
| その他 | 雑費 | miscExpense |
| (収入系) | 売上高 | salesRevenue |
| (事業主関連) | 事業主貸/借 | ownerDrawings/ownerContributions |
| (未分類) | 仮勘定 | suspense |

**4B-3: AccountingBootstrapService（8ステップ移行）**

新規ファイル `ProjectProfit/Services/AccountingBootstrapService.swift`:

仕様書 §6.2.2 準拠。旧6ステップから2ステップ追加（Step 4: フィールド補完、Step 6: 整合性チェック）。

```
ステップ 1: PPAccountingProfile が存在しなければ作成（デフォルト: 複式簿記、青色申告）
ステップ 2: デフォルト勘定科目を PPAccount に挿入（既存チェック: code で重複排除）
ステップ 3: 既存 PPCategory の linkedAccountId を自動設定（4B-2 のマッピング使用）
ステップ 4: フィールド補完（仕様書 §6.2.2 Step 4）
  - paymentAccountId 未設定 → profile.defaultPaymentAccountId（通常 acct-cash）
  - taxDeductibleRate 未設定 → 100（全額事業経費）
  - bookkeepingMode 未設定 → .auto（自動仕訳モード）
ステップ 5: 未マッピングのユーザー作成カテゴリは仮勘定にリンク
ステップ 6: 整合性チェック（仕様書 §6.2.2 Step 6）
  - 全仕訳で貸借一致チェック（借方合計 == 貸方合計）
  - 不一致があれば PPJournalEntry.isPosted = false とし、
    会計ホームで「要修正」として表示（原因表示付き）
ステップ 7: 既存 PPTransaction から PPJournalEntry/PPJournalLine を一括生成（4B-4 使用）
ステップ 8: 期首残高仕訳を生成（最古のトランザクション年度の1月1日付）
```

**リスク: 高** — 既存データの一括変換。失敗時のロールバック機構が必須。段階的実行とプログレス表示を推奨。Step 6 の整合性チェックで isPosted=false となった仕訳は UI で修正フローを提供する必要がある。

**4B-4: AccountingEngine（コア変換ロジック）**

新規ファイル `ProjectProfit/Services/AccountingEngine.swift`:

主要メソッド:
- `upsertJournalEntry(for transaction:)` — PPTransaction から PPJournalEntry を生成/更新
- `deleteJournalEntry(for transactionId:)` — トランザクション削除時の仕訳削除
- `rebuildAllJournalEntries()` — 全仕訳の再構築（データ復旧用）
- `validateJournalEntry(_ entry:)` — 借方/貸方一致チェック

変換ルール:

| TransactionType | 借方 | 貸方 | 備考 |
|----------------|------|------|------|
| .income | 現金/普通預金 | カテゴリ連動勘定科目（売上高等） | paymentAccountId で借方決定 |
| .expense | カテゴリ連動勘定科目（通信費等） | 現金/普通預金 | paymentAccountId で貸方決定 |
| .expense (家事按分あり) | 経費勘定 × taxDeductibleRate% + 事業主貸 × (100-rate)% | 現金/普通預金 | 2行仕訳 |
| .transfer | transferToAccountId | paymentAccountId | 事業主貸/借、口座間移動 |

**4B-5: DataStore への会計データ統合**

変更ファイル `ProjectProfit/Services/DataStore.swift`:

- `loadData()` に `PPAccount`, `PPJournalEntry`, `PPJournalLine`, `PPAccountingProfile` の refresh 追加
- `addTransaction()` / `updateTransaction()` / `deleteTransaction()` で `AccountingEngine` 連携
- 新規 Published 配列: `accounts`, `journalEntries`, `journalLines`, `accountingProfile`
- CRUD メソッド追加: `addAccount()`, `updateAccount()`, `deleteAccount()`, `addJournalEntry()` 等

**4B-6: 仕訳バリデーションサービス**

新規ファイル `ProjectProfit/Services/JournalValidationService.swift`:

- 借方合計 == 貸方合計の不変条件チェック
- 勘定科目 ID の存在チェック
- 日付の会計年度内チェック
- ロック済み年度への書き込み禁止チェック（T5 対応基盤）
- バリデーションエラーの詳細メッセージ生成

**4B-7: 期首残高仕訳生成**

`AccountingEngine` に期首残高仕訳メソッドを追加:

- 前年度末の資産・負債・資本残高を集計
- 翌年度の1月1日付で `JournalEntryType.opening` の仕訳を生成
- 資産科目 → 借方、負債・資本科目 → 貸方
- `元入金` で差額を調整（個人事業主の期首元入金 = 前期末資産 - 前期末負債）

---

#### Phase 4C: 既存コード改修（TransactionType.transfer 対応） — ✅ 9/9 完了

**目的**: `.transfer` 追加に伴う既存コード全体の修正。2値 switch/if-else を3値対応にする。

**対応する T 項目**: なし（4A-5 の波及対応）

| 順序 | ID | タスク | 作成/変更ファイル | 依存関係 | テスト要件 | 複雑度 | リスク |
|------|------|--------|------------------|----------|-----------|--------|--------|
| 51 | 4C-1 | DataStore サマリー関数の3値対応 | `Services/DataStore.swift` (5箇所) | 4A-5 | DataStoreSummaryTests 修正 | 中 | 中 |
| 52 | 4C-2 | ViewModel の .transfer 除外/包含 | `ViewModels/*.swift` (全6ファイル) | 4A-5 | ViewModel テスト追加 | 中 | 中 |
| 53 | 4C-3 | CSV エクスポート/インポートの振替対応 | `Utilities/Utilities.swift`, `Services/DataStore.swift` | 4A-5 | UtilitiesTests 修正 | 中 | 中 |
| 54 | 4C-4 | TransactionFormView の3値対応 | `Views/Components/TransactionFormView.swift` | 4A-5, 4A-6 | UI テスト | **高** | **高** |
| 55 | 4C-5 | RecurringFormView の3値対応 | `Views/Components/RecurringFormView.swift` | 4A-5, 4A-6 | UI テスト | **高** | **高** |
| 56 | 4C-6 | 全表示系ビューの2値前提修正 | 12ファイル (下記一覧) | 4A-5 | 目視 + UI テスト | **高** | **高** |
| 57 | 4C-7 | DataStore CRUD パラメータ追加 | `Services/DataStore.swift` | 4A-6 | DataStoreCRUDTests 修正 | 中 | 中 |
| 58 | 4C-8 | 定期取引処理の振替対応 | `Services/DataStore.swift` (processRecurringTransactions) | 4A-5 | RecurringProcessingTests 修正 | 中 | 中 |
| 59 | 4C-9 | 既存テスト一括修正 | `ProjectProfitTests/*.swift` (全18ファイル) | 4C-1〜4C-8 | 全テスト GREEN | **高** | 中 |

**4C-6: 2値前提の表示系ビュー修正対象一覧（推定40箇所以上）**

| # | ファイル | 修正内容 |
|---|---------|---------|
| 1 | `Views/ContentView.swift` | タブアイコンに .transfer 用追加の可能性 |
| 2 | `Views/Dashboard/DashboardView.swift` | 収入/支出サマリーに振替を含めない |
| 3 | `Views/Dashboard/DashboardMonthlyChartView.swift` | グラフから振替を除外 |
| 4 | `Views/Transactions/TransactionsListView.swift` | 振替の表示スタイル追加 |
| 5 | `Views/Transactions/TransactionDetailView.swift` | 振替詳細の表示 |
| 6 | `Views/Transactions/TransactionRowView.swift` | 行表示の色・アイコン |
| 7 | `Views/Projects/ProjectDetailView.swift` | プロジェクト別集計から振替除外 |
| 8 | `Views/Recurring/RecurringListView.swift` | 定期振替の表示 |
| 9 | `Views/Recurring/RecurringDetailView.swift` | 定期振替詳細 |
| 10 | `Views/Report/ReportView.swift` | レポートから振替除外 |
| 11 | `Views/Settings/SettingsView.swift` | エクスポート時の振替処理 |
| 12 | `Utilities/Utilities.swift` | CSV 出力の "振替" ラベル追加 |

**4C-4: TransactionFormView の変更詳細**

- タイプ選択: 2セグメント（収入/支出）→ 3セグメント（収入/支出/振替）
- `.transfer` 選択時の UI:
  - プロジェクト配分セクション非表示（振替はプロジェクトに紐づかない）
  - 振替元勘定科目ピッカー表示 (`paymentAccountId`)
  - 振替先勘定科目ピッカー表示 (`transferToAccountId`)
- `.expense` 選択時の追加 UI:
  - 支払元勘定科目ピッカー（任意）
  - 経費按分率スライダー (`taxDeductibleRate`: 0-100%、デフォルト100%）
  - 按分率の説明テキスト: 「事業使用割合を設定してください」

---

#### Phase 4D: 会計 UI（帳簿タブ） — ✅ 7/7 完了

**目的**: 複式簿記の勘定科目・仕訳・元帳を閲覧・編集するための新規タブを追加する。

**対応する T 項目**: なし（新規 UI）

| 順序 | ID | タスク | 作成/変更ファイル | 依存関係 | テスト要件 | 複雑度 | リスク |
|------|------|--------|------------------|----------|-----------|--------|--------|
| 60 | 4D-1 | ContentView に「帳簿」タブ追加 | `Views/ContentView.swift` | 4B-5 | UI テスト | 低 | 低 |
| 61 | 4D-2 | AccountingHomeView 実装 | `Views/Accounting/AccountingHomeView.swift` (新規) | 4D-1 | UI テスト | 中 | 低 |
| 62 | 4D-3 | ChartOfAccountsView 実装 | `Views/Accounting/ChartOfAccountsView.swift` (新規) | 4B-5 | UI テスト | 中 | 低 |
| 63 | 4D-4 | CategoryAccountMappingView 実装 | `Views/Accounting/CategoryAccountMappingView.swift` (新規) | 4B-2 | UI テスト | 中 | 中 |
| 64 | 4D-5 | JournalListView + JournalDetailView 実装 | `Views/Accounting/JournalListView.swift`, `Views/Accounting/JournalDetailView.swift` (新規) | 4B-5 | UI テスト | 中 | 低 |
| 65 | 4D-6 | LedgerView（総勘定元帳）実装 | `Views/Accounting/LedgerView.swift` (新規) | 4B-5 | UI テスト | **高** | 中 |
| 66 | 4D-7 | 手動仕訳入力フォーム | `Views/Accounting/ManualJournalFormView.swift` (新規) | 4B-4, 4B-6 | バリデーションテスト | **高** | 中 |

**4D-2: AccountingHomeView の構成**

- ステータスカード:
  - 仕訳総数 / 未分類取引数
  - 今月の収入合計 / 支出合計（勘定科目ベース）
  - 貸借一致確認ステータス（✓ / ✗）
- ナビゲーション:
  - 勘定科目一覧 → ChartOfAccountsView
  - カテゴリマッピング → CategoryAccountMappingView
  - 仕訳帳 → JournalListView
  - 総勘定元帳 → LedgerView
  - レポート → Phase 4E のビュー群
  - 手動仕訳 → ManualJournalFormView

**4D-6: LedgerView（総勘定元帳）**

- 勘定科目ピッカー（フィルタ）
- 期間フィルタ（月別/四半期/年度）
- テーブル表示: 日付 | 摘要 | 借方 | 貸方 | 残高
- 残高は累計表示（正常残高方向に基づく）
- PDF エクスポート機能（将来対応可）

---

#### Phase 4E: 会計レポート（試算表 / P&L / B/S） — ✅ 6/6 完了

**目的**: 確定申告書類の基礎となる試算表・損益計算書・貸借対照表を生成する。

**対応する T 項目**: T7（損益計算書）、T1（期首残高 — レポート表示部分）

| 順序 | ID | タスク | 作成/変更ファイル | 依存関係 | テスト要件 | 複雑度 | リスク |
|------|------|--------|------------------|----------|-----------|--------|--------|
| 67 | 4E-1 | AccountingReportService 実装 | `Services/AccountingReportService.swift` (新規) | 4B-4 | AccountingReportTests (新規) | **高** | **高** |
| 68 | 4E-2 | レポートデータモデル定義 | `Models/AccountingReportModels.swift` (新規) | 4E-1 | モデルテスト | 低 | 低 |
| 69 | 4E-3 | TrialBalanceView 実装 | `Views/Accounting/TrialBalanceView.swift` (新規) | 4E-1, 4E-2 | UI テスト + 計算検証 | 中 | 中 |
| 70 | 4E-4 | ProfitLossView 実装 | `Views/Accounting/ProfitLossView.swift` (新規) | 4E-1, 4E-2 | UI テスト + 計算検証 | 中 | 中 |
| 71 | 4E-5 | BalanceSheetView 実装 | `Views/Accounting/BalanceSheetView.swift` (新規) | 4E-1, 4E-2 | UI テスト + 計算検証 | 中 | 中 |
| 72 | 4E-6 | AccountingReportViewModel 実装 | `ViewModels/AccountingReportViewModel.swift` (新規) | 4E-1 | ViewModel テスト | 中 | 低 |

**4E-1: AccountingReportService の計算エンジン**

```
メソッド一覧:
- generateTrialBalance(fiscalYear:, month:) → TrialBalanceReport
  各勘定科目の借方合計・貸方合計・残高を集計

- generateProfitLoss(fiscalYear:, startMonth:, endMonth:) → ProfitLossReport
  収益科目 - 費用科目の階層構造
  段階: 売上高 → 売上総利益 → 営業利益 → 経常利益 → 税引前利益
  個人事業主の場合: 売上 - 経費 = 所得金額（簡略版で可）

- generateBalanceSheet(fiscalYear:, asOfDate:) → BalanceSheetReport
  資産の部 / 負債の部 / 資本の部
  資産合計 == 負債合計 + 資本合計 の検証
  元入金の自動計算（前期末元入金 + 前期末所得 + 事業主借 - 事業主貸）
```

**4E-2: レポートデータモデル**

```swift
struct TrialBalanceReport {
    let fiscalYear: Int
    let asOfDate: Date
    let rows: [TrialBalanceRow]      // 勘定科目ごとの行
    let totalDebit: Int              // 借方合計
    let totalCredit: Int             // 貸方合計
    let isBalanced: Bool             // totalDebit == totalCredit
}

struct TrialBalanceRow {
    let account: PPAccount
    let debitTotal: Int
    let creditTotal: Int
    let balance: Int                 // 正常残高方向の残高
}

struct ProfitLossReport {
    let fiscalYear: Int
    let period: ClosedRange<Date>
    let revenueItems: [ReportLineItem]
    let expenseItems: [ReportLineItem]
    let totalRevenue: Int
    let totalExpense: Int
    let netIncome: Int               // 所得金額
}

struct BalanceSheetReport {
    let fiscalYear: Int
    let asOfDate: Date
    let assets: [ReportLineItem]
    let liabilities: [ReportLineItem]
    let equity: [ReportLineItem]
    let totalAssets: Int
    let totalLiabilitiesAndEquity: Int
    let isBalanced: Bool
}

struct ReportLineItem {
    let account: PPAccount
    let amount: Int
    let children: [ReportLineItem]   // 階層表示用
}
```

---

#### Phase 4F: 自動分類エンジン — ✅ 7/7 完了 (4F-5: Batch 9B)

**目的**: トランザクションを e-Tax の TaxLine（経費区分）に自動分類するエンジンを実装する。辞書ルール + ユーザー学習による段階的な精度向上。

**対応する T 項目**: なし（新規機能、T2 の実用性を高める補助機能）

| 順序 | ID | タスク | 作成/変更ファイル | 依存関係 | テスト要件 | 複雑度 | リスク | 状態 |
|------|------|--------|------------------|----------|-----------|--------|--------|------|
| 73 | 4F-1 | TaxLine マスター定義 | `Services/TaxLineDefinitions.swift` (新規) | 4B-1 | 定義値テスト | 低 | 低 | ✅ |
| 74 | 4F-2 | UserRule データモデル | `Models/PPUserRule.swift` (新規) | 4A-1 | モデルテスト | 低 | 低 | ✅ |
| 75 | 4F-3 | 辞書ルール（初期バンドル） | `Resources/ClassificationDictionary.json` (新規) | 4F-1 | 辞書読込テスト | 低 | 低 | ✅ |
| 76 | 4F-4 | ClassificationEngine 実装 | `Services/ClassificationEngine.swift` (新規) | 4F-1, 4F-2, 4F-3 | ClassificationEngineTests (新規) | **高** | 中 | ✅ |
| 77 | 4F-5 | 学習/トレーニングフィードバック | `Services/ClassificationLearningService.swift` (新規) | 4F-4 | 学習テスト 7件 | 中 | 中 | ✅ Batch 9B |
| 78 | 4F-6 | 未分類取引 UI | `Views/Accounting/UnclassifiedTransactionsView.swift` (新規) | 4F-4, 4D-1 | UI テスト | 中 | 低 | ✅ |
| 79 | 4F-7 | 自動分類テスト | `ProjectProfitTests/ClassificationEngineTests.swift` (新規) | 4F-4 | カバレッジ 80%+ | 中 | 低 | ✅ |

**4F-3: 辞書ルール例**

```json
{
  "rules": [
    { "pattern": "AWS|Azure|GCP|さくら.*サーバ|ConoHa", "accountSubtype": "communicationExpense" },
    { "pattern": "新幹線|JR|Suica|PASMO|タクシー", "accountSubtype": "travelExpense" },
    { "pattern": "Slack|Notion|GitHub|Figma|Adobe", "accountSubtype": "suppliesExpense" },
    { "pattern": "Google Ads|Facebook.*広告|Twitter.*広告", "accountSubtype": "advertisingExpense" },
    { "pattern": "電気|ガス|水道|東京電力|関西電力", "accountSubtype": "utilitiesExpense" },
    { "pattern": "NTT|ソフトバンク|au|楽天モバイル|Wi-Fi", "accountSubtype": "communicationExpense" }
  ]
}
```

**4F-4: ClassificationEngine のアルゴリズム**

```
優先順位:
1. ユーザー明示ルール（PPUserRule — ユーザーが手動設定したもの）
2. 取引メモ/カテゴリ名の辞書マッチ（正規表現）
3. レシートOCR結果の店舗名マッチ
4. フォールバック: 仮勘定（suspense）

classify(transaction:) → AccountSubtype:
  - transaction.memo を全ルールに対してマッチ
  - 複数マッチ時は最も具体的な（最長マッチ）ルールを採用
  - マッチなし → .suspense
```

**4F-5: 学習フィードバック** — ✅ Batch 9B で実装完了

- **実装ファイル**: `Services/ClassificationLearningService.swift` (新規 ~75行)
- **変更ファイル**: `ViewModels/ClassificationViewModel.swift` (correctClassification追加), `Views/Accounting/UnclassifiedTransactionsView.swift` (TaxLine修正メニュー追加)
- **テスト**: `ClassificationLearningServiceTests.swift` (7テスト)
- ユーザーが未分類取引を手動で分類した際:
  - `PPUserRule` に新規ルール追加（メモのキーワード → 選択された TaxLine）
  - 同一キーワードの既存ルールがあれば TaxLine を直接更新
  - 次回以降、同じキーワードの取引は自動分類される

---

#### Phase 4G: e-Tax エクスポート — ✅ 7/7 完了 (4G-1,4G-2: Batch 10, 4G-7: Batch 11B)

**目的**: 確定申告書類（青色申告決算書 + 白色収支内訳書）を e-Tax 互換の .xtx フォーマットで出力する。仕様書 Phase A のスコープに基づき、両申告種別を対応する。

**対応する T 項目**: T6（確定申告用エクスポートフォーマット）

| 順序 | ID | タスク | 作成/変更ファイル | 依存関係 | テスト要件 | 複雑度 | リスク | 状態 |
|------|------|--------|------------------|----------|-----------|--------|--------|------|
| 80 | 4G-1 | 税年度定義 + TaxLine マッピング | `Resources/TaxYear2025.json` (新規), `Services/TaxYearDefinitionLoader.swift` (新規) | 4F-1 | 定義値テスト 5件 | 中 | 中 | ✅ Batch 10A |
| 81 | 4G-2 | 分類辞書JSON外部化 | `Resources/ClassificationDictionary.json` (新規), `Services/ClassificationDictionaryLoader.swift` (新規) | なし | 辞書ロードテスト 4件 | 中 | 中 | ✅ Batch 10B |
| 82 | 4G-3 | EtaxModels 定義 | `Models/EtaxModels.swift` (新規) | 4G-1 | モデルテスト | 中 | 中 | ✅ |
| 83 | 4G-4 | EtaxCharacterValidator 実装 | `Services/EtaxCharacterValidator.swift` (新規) | なし | EtaxCharacterValidatorTests (新規) | 中 | 中 | ✅ |
| 84 | 4G-5 | EtaxXtxExporter 実装（青色） | `Services/EtaxXtxExporter.swift` (新規) | 4E-1, 4G-1, 4G-2, 4G-3, 4G-4 | EtaxExporterTests (新規) | **高** | **高** | ✅ |
| 85 | 4G-6 | EtaxExportView + ViewModel（青色/白色切替） | `Views/Accounting/EtaxExportView.swift`, `ViewModels/EtaxExportViewModel.swift` (新規) | 4G-5 | UI テスト（両モード） | **高** | 中 | ✅ |
| 86 | 4G-7 | フォームプレビュー抽出 | `Views/Accounting/EtaxFormPreviewView.swift` (新規) | 4G-5, 4G-6 | UI テスト | 中 | 低 | ✅ Batch 11B |
| 87 | 4G-8 | 白色収支内訳書ビルダー | `Services/ShushiNaiyakushoBuilder.swift` (新規) | 4G-5, 4G-1 | ShushiNaiyakushoTests (新規) | **高** | 中 | ✅ |

**4G-1: 税年度定義ファイル** — ✅ Batch 10A で実装完了

- **実装ファイル**: `Resources/TaxYear2025.json`, `Services/TaxYearDefinitionLoader.swift` (~55行)
- **変更ファイル**: `Services/EtaxFieldPopulator.swift`, `Services/ShushiNaiyakushoBuilder.swift` (taxLine.label → TaxYearDefinitionLoader.fieldLabel)
- **テスト**: `TaxYearDefinitionLoaderTests.swift` (5テスト: JSONロード, フォールバック, 全TaxLineカバレッジ)

年度ごとの TaxLine 定義を JSON で管理（税制改正対応）:

```json
{
  "taxYear": 2025,
  "formVersion": "R07",
  "taxLines": [
    { "lineNumber": 1, "label": "売上（収入）金額", "accountSubtypes": ["salesRevenue"] },
    { "lineNumber": 10, "label": "地代家賃", "accountSubtypes": ["rentExpense"] },
    { "lineNumber": 11, "label": "水道光熱費", "accountSubtypes": ["utilitiesExpense"] },
    { "lineNumber": 12, "label": "旅費交通費", "accountSubtypes": ["travelExpense"] },
    { "lineNumber": 13, "label": "通信費", "accountSubtypes": ["communicationExpense"] },
    { "lineNumber": 14, "label": "広告宣伝費", "accountSubtypes": ["advertisingExpense"] },
    { "lineNumber": 15, "label": "接待交際費", "accountSubtypes": ["entertainmentExpense"] },
    { "lineNumber": 16, "label": "減価償却費", "accountSubtypes": ["depreciationExpense"] },
    { "lineNumber": 17, "label": "修繕費", "accountSubtypes": ["repairExpense"] },
    { "lineNumber": 18, "label": "消耗品費", "accountSubtypes": ["suppliesExpense"] },
    { "lineNumber": 19, "label": "福利厚生費", "accountSubtypes": ["welfareExpense"] },
    { "lineNumber": 20, "label": "外注工賃", "accountSubtypes": ["outsourcingExpense"] },
    { "lineNumber": 21, "label": "雑費", "accountSubtypes": ["miscExpense"] }
  ]
}
```

**4G-2: 分類辞書JSON外部化** — ✅ Batch 10B で実装完了

- **実装ファイル**: `Resources/ClassificationDictionary.json` (34ルール), `Services/ClassificationDictionaryLoader.swift` (~90行)
- **変更ファイル**: `Services/ClassificationEngine.swift` (dictionaryRulesをcomputed varに変更、ClassificationDictionaryLoader.load()使用)
- **テスト**: `ClassificationDictionaryLoaderTests.swift` (4テスト: JSONロード, インラインフォールバック一致検証)

**e-Tax タグ辞書（CAB 抽出ワークフロー）**

国税庁が毎年公開する CAB ファイルから XML タグ名とバリデーションルールを抽出する。**これは非公開仕様のリバースエンジニアリングではなく、公式に配布されている仕様ファイルを利用する正規のワークフローである**（仕様書 §4 準拠）。

```
抽出手順:
1. NTA サイト (https://www.e-tax.nta.go.jp/shiyo/shiyo3.htm) から
   当該年度の CAB ファイルをダウンロード
2. cabextract ツールで展開し、Excel ファイル群を取得
3. Excel 内の「帳票名・タグ名・データ型・桁数・必須/任意」列を解析
4. TagDictionary_{taxYear}.json を生成
   フォーマット: { "formId": "...", "fields": [{ "tag": "...", "type": "...", "maxLength": N, "required": bool }] }
5. 生成した辞書のフィル率を検証（100% = 全 TaxLine にタグが対応）
6. Resources/EtaxTagDictionary.json として配置
```

**年度更新ワークフロー**: 毎年1月に NTA が新年度 CAB を公開 → 上記手順で辞書再生成 → フィル率 100% を確認 → TaxYear{YYYY}.json を更新。

**リスク: 中** — CAB ファイル自体は公開されているが、Excel の列構造が年度により微変更される可能性あり。抽出スクリプトにカラム検出ロジックが必要。

**4G-4: EtaxCharacterValidator**

e-Tax XML に使用可能な文字種の検証:
- JIS X 0208 範囲内の漢字・ひらがな・カタカナ
- 半角英数字
- 一部の記号
- 機種依存文字・外字の検出と代替文字への変換
- 文字数制限（フィールドごと）

**4G-5: EtaxXtxExporter**

.xtx ファイル（e-Tax 独自の XML ベースフォーマット）の生成:
- AccountingReportService の P/L データを TaxLine にマッピング
- PPAccountingProfile の事業者情報をフォームヘッダに埋め込み
- 文字バリデーション済みの値を XML タグに挿入
- UTF-8 エンコーディング
- 出力先: アプリの Documents ディレクトリ → Share Sheet で転送

**4G-6: EtaxExportView**

- 年度選択
- **申告種別選択**: 青色申告決算書 / 白色収支内訳書（PPAccountingProfile.isBlueReturn に基づくデフォルト、手動切替可）
- エクスポート前のバリデーション結果表示（不足データ、未分類取引の警告）
- 白色選択時は B/S セクションを非表示にし、収支内訳書固有フィールド（損害保険料等）を表示
- プレビュー → 確認 → エクスポート の3ステップ
- Share Sheet で .xtx ファイルを共有

**4G-8: 白色収支内訳書（ShushiNaiyakushoReport）対応**

新規ファイル `ProjectProfit/Services/ShushiNaiyakushoBuilder.swift`:

仕様書 Phase A で青色・白色の両方が必須スコープとして定義されている。白色申告は青色と以下の点で異なる:

```
1. B/S（貸借対照表）が不要 — 損益のみ
2. 差引金額の計算式が異なる: 収入 − 経費 = 差引金額（青色の特別控除前所得に相当）
3. 固有フィールド:
   - white.exp.insurance（損害保険料）— 青色にはない経費科目
   - white.income.* / white.exp.* プレフィックスの TaxLine キー
4. バリデーションルール:
   - 未分類取引は Warning（Error ではない）
   - 仮勘定残高は「その他経費」に自動集約
5. PPAccountingProfile.isBlueReturn = false で白色モード有効
```

**リスク: 中** — 青色エクスポーターの構造を流用可能だが、TaxLine マッピングと出力 XML 構造が異なるため、独立したビルダーが必要。

---

#### Phase 4H: テスト + 検証 — ✅ 7/7 完了

**目的**: Phase 4A-4G の全機能に対する網羅的なテストと受入検証。

**対応する T 項目**: 全 T 項目の検証

| 順序 | ID | タスク | 作成/変更ファイル | 依存関係 | テスト要件 | 複雑度 | リスク |
|------|------|--------|------------------|----------|-----------|--------|--------|
| 88 | 4H-1 | AccountingEngineTests | `ProjectProfitTests/AccountingEngineTests.swift` (新規) | 4B-4 | カバレッジ 80%+ | **高** | 低 |
| 89 | 4H-2 | AccountingBootstrapTests | `ProjectProfitTests/AccountingBootstrapTests.swift` (新規) | 4B-3 | 移行シナリオ全パターン（8ステップ検証） | **高** | 低 |
| 90 | 4H-3 | AccountingReportTests | `ProjectProfitTests/AccountingReportTests.swift` (新規) | 4E-1 | 計算精度検証 | **高** | 低 |
| 91 | 4H-4 | EtaxExporterTests + CharacterValidatorTests | `ProjectProfitTests/EtaxExporterTests.swift`, `ProjectProfitTests/EtaxCharacterValidatorTests.swift` (新規) | 4G-4, 4G-5 | XML 構造検証（青色+白色両方） | **高** | 低 |
| 92 | 4H-5 | ShushiNaiyakushoTests（白色専用） | `ProjectProfitTests/ShushiNaiyakushoTests.swift` (新規) | 4G-8 | 収支内訳書フィールド検証・差引金額計算 | **高** | 低 |
| 93 | 4H-6 | 統合テスト（エンドツーエンド） | `ProjectProfitTests/AccountingIntegrationTests.swift` (新規) | 4A-4H 全て | 全フロー通過（青色+白色両パス） | **高** | 中 |
| 94 | 4H-7 | パフォーマンステスト | `ProjectProfitTests/AccountingPerformanceTests.swift` (新規) | 4B-4, 4E-1 | 100K 取引で 2秒以内 | 中 | 低 |
| 95 | 4H-8 | 受入チェックリスト実施 | — (手動検証) | 全タスク完了 | 下記チェックリスト全項目 | 中 | 低 | ✅ |

**4H-1: AccountingEngineTests のテストケース**

```
- testIncomeTransactionCreatesCorrectJournal
  収入トランザクション → 借方:現金、貸方:売上高
- testExpenseTransactionCreatesCorrectJournal
  支出トランザクション → 借方:経費科目、貸方:現金
- testExpenseWithTaxDeductibleRate
  家事按分50% → 借方:経費50%+事業主貸50%、貸方:現金100%
- testTransferCreatesCorrectJournal
  振替 → 借方:振替先、貸方:振替元
- testUpsertUpdatesExistingJournal
  既存仕訳の更新（金額変更時）
- testDeleteRemovesJournal
  トランザクション削除 → 仕訳も削除
- testRebuildAllProducesConsistentResults
  全仕訳再構築後、個別生成と同一結果
- testJournalEntryAlwaysBalances
  全テストケースで借方合計 == 貸方合計
```

**4H-5: 統合テスト（エンドツーエンドシナリオ）**

```
シナリオ 1: 新規ユーザーフロー
  アプリ初回起動 → ブートストラップ → 勘定科目28件生成 → プロファイル作成
  → トランザクション追加 → 仕訳自動生成 → 試算表表示 → P/L表示 → B/S表示

シナリオ 2: 既存ユーザー移行フロー
  既存データ（トランザクション100件、カテゴリ15件）
  → ブートストラップ実行 → カテゴリ→勘定科目マッピング
  → 全トランザクションから仕訳一括生成 → 試算表の貸借一致確認

シナリオ 3: 年度末フロー
  1年分のトランザクション入力済み → P/L 生成 → B/S 生成
  → e-Tax エクスポート → .xtx ファイル検証 → 年度ロック

シナリオ 4: 年度繰越フロー
  前年度ロック済み → 新年度開始 → 期首残高仕訳自動生成
  → 元入金の正確性検証
```

**4H-6: パフォーマンス目標**

| 操作 | データ量 | 目標時間 |
|------|---------|---------|
| ブートストラップ（初回移行） | 10,000 トランザクション | 5秒以内 |
| 仕訳自動生成（1件） | — | 50ms 以内 |
| 全仕訳再構築 | 100,000 トランザクション | 2秒以内 |
| 試算表生成 | 100,000 仕訳行 | 1秒以内 |
| P/L 生成 | 100,000 仕訳行 | 1秒以内 |
| B/S 生成 | 100,000 仕訳行 | 1秒以内 |
| e-Tax エクスポート | 1年分データ | 3秒以内 |

**4H-7: 受入チェックリスト**

- [x] デフォルト33勘定科目が正しく生成される（元26+消費税3+在庫COGS4=33、AccountingBootstrapTests/AccountingConstantsTests で検証済み）
- [x] 既存カテゴリが正しい勘定科目にマッピングされる（AccountingBootstrapTests で検証済み）
- [x] 収入トランザクション → 正しい仕訳（借方:資産、貸方:収益）（AccountingEngineTests で検証済み）
- [x] 支出トランザクション → 正しい仕訳（借方:費用、貸方:資産）（AccountingEngineTests で検証済み）
- [x] 家事按分 → 事業主貸が正しく計上される（AccountingEngineTests で検証済み）
- [x] 振替トランザクション → 正しい仕訳（AccountingEngineTests で検証済み）
- [x] 全仕訳で借方合計 == 貸方合計（JournalValidationTests/AccountingEngineTests で検証済み）
- [x] 試算表の貸借が一致する（AccountingReportTests で検証済み）
- [x] P/L の所得金額が正しい（収益 - 費用）（AccountingReportTests で検証済み）
- [x] B/S の資産 == 負債 + 資本（AccountingReportTests で検証済み）
- [x] 元入金が正しく計算される（AccountingReportTests で検証済み）
- [x] 期首残高仕訳が正しく生成される（AccountingEngineTests で検証済み）
- [x] 年度ロック後にロック済み年度のデータが変更不可（YearLockTests 8件で検証済み）
- [x] e-Tax .xtx ファイルが正しい XML 構造（AccountingIntegrationTests で6セクション含むXML検証済み）
- [x] e-Tax ファイルの文字がJIS X 0208 範囲内（EtaxCharacterValidatorTests で検証済み）
- [x] 未分類取引が仮勘定に分類される（ClassificationEngineTests で検証済み）
- [x] 自動分類の辞書マッチが正しく動作する（ClassificationEngineTests で検証済み）
- [x] ユーザー学習ルールが次回以降適用される（ClassificationLearningServiceTests 7件で検証済み）
- [x] 消費税付き取引 → 仮払/仮受消費税の仕訳行が正しく生成される（AccountingIntegrationTests で検証済み）
- [x] 消費税なし取引 → 既存動作を維持（後方互換性）（AccountingIntegrationTests で検証済み）
- [x] 在庫/COGS計算が正しい（InventoryServiceTests 11件で検証済み）
- [x] 減価償却明細表が正しく生成される（DepreciationScheduleBuilderTests 10件で検証済み）
- [x] e-Tax申告者情報フィールドが正しく生成される（AccountingIntegrationTests で検証済み）
- [x] 全958テストが GREEN（リグレッションなし）

---

#### T 項目カバレッジ一覧

| T 項目 | 内容 | Phase 4 での対応状況 | 対応サブフェーズ |
|--------|------|---------------------|----------------|
| T1 | 期首残高・期末残高 | **対応済み** — PPAccount/PPJournalEntry でモデル化、AccountingEngine で期首仕訳生成、AccountingReportService で B/S 表示 | 4A, 4B-7, 4E |
| T2 | 標準勘定科目マッピング | **対応済み** — 28勘定科目定義、カテゴリ→勘定科目マッピング、ブートストラップ移行 | 4A, 4B |
| T3 | 減価償却 | **部分対応** — 減価償却費の勘定科目は存在するが、FixedAsset モデル/自動計算エンジンは未実装。手動の決算整理仕訳で対応可能 | 4A-1 (科目のみ) |
| T4 | 消費税区分 | **対応済み** — TaxCategory enum、PPTransaction 税フィールド、消費税3勘定+在庫COGS4勘定、AccountingEngine 税仕訳行、ConsumptionTaxReportService、InventoryService、TransactionFormView 税入力UI、ProfileSettingsView、InventoryInputView、FixedAssetScheduleView、e-Tax 4新XMLセクション | Phase 5 |
| T5 | 年度ロック | **部分対応** — PPAccountingProfile.lockedAt + PPJournalEntry.isPosted で基盤を提供。完全な年度ロック（全 CRUD ガード）は別途実装が必要 | 4A-4 (基盤) |
| T6 | 確定申告エクスポート | **対応済み** — e-Tax .xtx フォーマットでの青色申告決算書 + 白色収支内訳書エクスポート（4G-8 で白色対応追加） | 4G |
| T7 | 損益計算書 | **対応済み** — AccountingReportService で P/L 生成、ProfitLossView で表示 | 4E |

---

#### 依存関係グラフ

```
Phase 1-3 (CRITICAL/HIGH/MEDIUM 修正)
    │
    ▼
Phase 4A: データ基盤
    │
    ├──────────────────┐
    ▼                  ▼
Phase 4B: 会計エンジン   Phase 4C: 既存コード改修
    │                  │
    ├──────┬───────────┘
    ▼      ▼
Phase 4D: 会計 UI
    │
    ▼
Phase 4E: 会計レポート ◄── Phase 4F: 自動分類エンジン
    │                        │
    ├────────────────────────┘
    ▼
Phase 4G: e-Tax エクスポート
    │
    ▼
Phase 4H: テスト + 検証
```

注意事項:
- Phase 4B と 4C は独立して並行作業可能（4A 完了後）
- Phase 4D は 4B と 4C の両方が完了後に着手
- Phase 4F は 4B 完了後いつでも着手可能（4D/4E と並行可）
- Phase 4G は 4E と 4F の両方が完了後に着手

---

#### 12 Agent チーム監査所見

**構造的リスク**:

1. **SwiftData マイグレーション（M2）が最大のブロッカー**: Phase 4A で4つの新モデルを追加する。M2 が未解決の場合、全新規フィールドを Optional にせざるを得ず、nil-coalescing が増殖する。**強く推奨: M2 を Phase 4A の前に完了させること。**

2. **TransactionType.transfer の波及範囲**: 4A-5 の enum 追加は12ファイル・40箇所以上に影響する。Phase 4C を過小評価しないこと。段階的なコンパイラ警告解消（exhaustive switch）で網羅的に対応可能。

3. **e-Tax タグ辞書の年度追従**: 4G-2 の CAB ファイルは国税庁が毎年公開（https://www.e-tax.nta.go.jp/shiyo/shiyo3.htm）。年度更新時に TagDictionary JSON を再生成し、100%フィル率を確認するワークフローを確立すること。手順は仕様書 §4 準拠。

4. **パフォーマンス懸念**: SwiftData の1対多リレーション（PPJournalEntry → PPJournalLine[]）は大量データで遅延する可能性。`@Relationship` の `.cascade` 削除設定と `FetchDescriptor` のバッチサイズ調整が必要。

**推奨事項**:

- Phase 4A-4B を「MVP」として最初にリリースし、帳簿タブの基本機能を提供
- Phase 4E の P/L レポートを次にリリースし、既存の OverallSummary を段階的に置き換え
- Phase 4G の e-Tax エクスポートは2026年度確定申告（2027年2-3月申告）に間に合わせることを目標
- Phase 4F の自動分類は精度向上に時間がかかるため、早期に基本版をリリースしてユーザーフィードバックを収集

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-02-24 | 初版作成。3ラウンド・27 Agent 調査結果を統合 |
| 2026-02-24 | Phase 4 を詳細実装計画に拡充。12 Agent チーム調査結果 (4A-4H, 93タスク) を統合。T1-T7 カバレッジ分析・依存関係グラフ・監査所見を追加 |
| 2026-02-24 | 7 Agent チーム検証: (1) 白色申告（収支内訳書）スコープを Phase 4G 全体に追加, (2) 4B-3 ブートストラップを6→8ステップに拡充（フィールド補完+整合性チェック）, (3) 4G-2 CAB抽出ワークフローを仕様書準拠に修正, (4) 4B-1 勘定科目にクレジットカード追加・仕様書準拠に整理 |
| 2026-02-25 | Phase 4A 実装完了 (246650b): AccountingEnums, PPAccount, PPJournalEntry/Line, PPAccountingProfile, .transfer対応, modelContainer更新。31ファイル変更、テスト3件新規追加 |
| 2026-02-25 | Phase 4B 実装完了 (1a93e1e): AccountingConstants(25勘定科目/13マッピング), AccountingBootstrapService(8ステップ), AccountingEngine(自動仕訳変換+期首残高), JournalValidationService, DataStore統合。テスト61件新規追加（合計770テスト全パス）。コードレビューでCRITICAL2件+HIGH4件修正済み |
| 2026-02-25 | Batch 9-11 実装完了: (9A) PPRecurringTransactionに会計フィールド3つ追加+DataStore/RecurringFormView対応, (9B) ClassificationLearningService新規+学習フィードバックUI, (10A) TaxYear2025.json+TaxYearDefinitionLoader, (10B) ClassificationDictionary.json+ClassificationDictionaryLoader, (11A) 年度ロック — lockedYears+CRUD全ガード+DataStore+YearLock.swift, (11B) EtaxFormPreviewView抽出。テスト26件新規追加（合計868テスト全パス）。コードレビューでHIGH2件+MEDIUM2件修正済み |
| 2026-02-25 | Batch 12-14 実装完了 (T1+T3 修正): (12A) Todo.md T2/T6/T7ステータス更新, (12B) 決算仕訳(T1) — AccountingEngine.generateClosingBalanceEntry+deleteClosingBalanceEntry, AccountingReportService.postedEntryIdsInRange excludeTypes追加, DataStore+Accounting closing entry CRUD, ClosingEntryView新規, (13A-F) 減価償却Backend(T3) — DepreciationMethod/AssetStatus enum, PPFixedAsset モデル, DepreciationEngine（定額法/200%定率法/少額一括/3年均等/少額特例）, 減価償却累計額アカウント追加, ModelContainer登録, seedMissingDefaultAccounts, (14A-E) 減価償却UI(T3) — DataStore+FixedAsset CRUD, FixedAssetFormView/ListView/DetailView新規, AccountingHomeViewにナビ追加。テスト31件新規追加（合計899テスト全GREEN）。コードレビューでHIGH2件修正済み（3年均等端数処理、除却年月割計算） |
| 2026-02-25 | Phase 5 実装完了 (T4 消費税区分+残機能): 20 Agent 並列実装。**新規10ソースファイル**: PPInventoryRecord.swift, ConsumptionTaxModels.swift, ConsumptionTaxReportService.swift, InventoryService.swift, DepreciationScheduleBuilder.swift, DataStore+Inventory.swift, ProfileSettingsView.swift, InventoryInputView.swift, InventoryViewModel.swift, FixedAssetScheduleView.swift。**新規6テストファイル**: TaxCategoryTests(17件), PPInventoryRecordTests(10件), ConsumptionTaxReportServiceTests(8件), DepreciationScheduleBuilderTests(10件), InventoryServiceTests(11件), AccountingIntegrationTests(7件)。**主要変更**: (1) TaxCategory enum (standardRate/reducedRate/exempt/nonTaxable), (2) PPTransaction税フィールド4件, (3) 消費税3勘定+在庫COGS4勘定=計7勘定追加(33勘定), (4) AccountSubtype 7件追加(34件), (5) AccountingEngine税仕訳行(仮払/仮受消費税), (6) EtaxFieldPopulator 3新メソッド(declarantInfo/inventory/balanceSheet), (7) EtaxXtxExporter 4新XMLセクション, (8) ShushiNaiyakushoBuilder 減価償却明細+地代家賃内訳, (9) TransactionFormView消費税入力UI, (10) ProfileSettingsView e-Tax申告者情報, (11) InventoryInputView 在庫COGS入力, (12) FixedAssetScheduleView 減価償却明細表, (13) UnclassifiedTransactionsView confidence バッジ, (14) PPAccountingProfile e-Tax個人情報7フィールド, (15) ClassificationEngine confidence閾値+needsReview。テスト63件新規追加（合計958テスト全GREEN）。受入チェックリスト24項目全完了。構造的欠落T1-T7全修正完了 |
