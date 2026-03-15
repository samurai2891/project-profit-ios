import XCTest
import SwiftData
@testable import ProjectProfit

/// 総勘定元帳（General Ledger）の enrichment テスト
/// LedgerEntry に取引先(counterparty)・消費税区分(taxCategory)が正しく反映されることを検証する。
@MainActor
final class GeneralLedgerEnrichmentTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Counterparty Enrichment

    /// 収入取引に設定した取引先が、現金勘定の元帳エントリに反映されること
    func testLedgerEntry_CounterpartyFromTransaction() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 50000,
            date: date(2025, 6, 15),
            categoryId: "cat-sales",
            memo: "売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterparty: "上野商店"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertFalse(entries.isEmpty, "現金勘定にエントリが存在すること")
        for entry in entries {
            XCTAssertEqual(entry.counterparty, "上野商店", "取引先が元帳エントリに反映されること")
        }
    }

    // MARK: - TaxCategory Enrichment

    /// 経費取引の軽減税率が元帳エントリに反映されること
    func testLedgerEntry_TaxCategoryFromTransaction() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 10000,
            date: date(2025, 7, 1),
            categoryId: "cat-supplies",
            memo: "消耗品",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 800,
            taxCategory: .reducedRate
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertFalse(entries.isEmpty, "現金勘定にエントリが存在すること")
        for entry in entries {
            XCTAssertEqual(entry.taxCategory, .reducedRate, "軽減税率が元帳エントリに反映されること")
        }
    }

    /// 標準税率の取引が元帳エントリに正しく反映されること
    func testLedgerEntry_StandardRateTaxCategory() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 100000,
            date: date(2025, 8, 10),
            categoryId: "cat-sales",
            memo: "コンサルティング",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 10000,
            taxCategory: .standardRate,
            counterparty: "株式会社ABC"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertFalse(entries.isEmpty)
        for entry in entries {
            XCTAssertEqual(entry.taxCategory, .standardRate, "標準税率が元帳エントリに反映されること")
        }
    }

    // MARK: - Manual Journal Entry (No Enrichment)

    /// 手動仕訳にはソーストランザクションがないため counterparty は nil であること
    func testLedgerEntry_ManualJournal_NilCounterparty() {
        _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 9, 1),
            memo: "決算整理仕訳",
            lines: [
                (accountId: "acct-cash", debit: 10000, credit: 0, memo: "現金入金"),
                (accountId: "acct-sales", debit: 0, credit: 10000, memo: "売上計上"),
            ]
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertFalse(entries.isEmpty, "手動仕訳のエントリが存在すること")
        for entry in entries {
            XCTAssertNil(entry.counterparty, "手動仕訳では取引先が nil であること")
        }
    }

    /// 手動仕訳にはソーストランザクションがないため taxCategory は nil であること
    func testLedgerEntry_ManualJournal_NilTaxCategory() {
        _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 9, 2),
            memo: "減価償却仕訳",
            lines: [
                (accountId: "acct-cash", debit: 0, credit: 5000, memo: ""),
                (accountId: "acct-owner-contributions", debit: 5000, credit: 0, memo: ""),
            ]
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertFalse(entries.isEmpty, "手動仕訳のエントリが存在すること")
        for entry in entries {
            XCTAssertNil(entry.taxCategory, "手動仕訳では消費税区分が nil であること")
        }
    }

    // MARK: - Running Balance

    /// 借方正常勘定（現金）の残高推移: 入金 +50000、出金 -20000 → 50000, 30000
    func testLedgerEntry_RunningBalance_DebitNormal() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 50000,
            date: date(2025, 6, 1),
            categoryId: "cat-sales",
            memo: "入金",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 20000,
            date: date(2025, 6, 2),
            categoryId: "cat-supplies",
            memo: "出金",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertEqual(entries.count, 2, "現金勘定に2件のエントリがあること")

        XCTAssertEqual(entries[0].debit, 50000, "最初のエントリは借方50000")
        XCTAssertEqual(entries[0].runningBalance, 50000, "最初の残高は50000")

        XCTAssertEqual(entries[1].credit, 20000, "2番目のエントリは貸方20000")
        XCTAssertEqual(entries[1].runningBalance, 30000, "2番目の残高は30000")
    }

    /// 貸方正常勘定（売上高）の残高推移: 売上計上 +100000 → 残高 100000
    func testLedgerEntry_RunningBalance_CreditNormal() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 100000,
            date: date(2025, 7, 1),
            categoryId: "cat-sales",
            memo: "大口売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-sales")
        XCTAssertFalse(entries.isEmpty, "売上高勘定にエントリが存在すること")

        if let first = entries.first {
            XCTAssertEqual(first.credit, 100000, "売上高の貸方が100000であること")
            XCTAssertEqual(first.runningBalance, 100000, "貸方正常勘定の残高が100000であること")
        }
    }

    // MARK: - Chronological Order

    /// 異なる日付の3取引が日付昇順でソートされること
    func testLedgerEntry_MultipleTransactions_ChronologicalOrder() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        // 意図的に日付を逆順で登録
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 30000,
            date: date(2025, 6, 15),
            categoryId: "cat-sales",
            memo: "2番目",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterparty: "B社"
        )

        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 10000,
            date: date(2025, 6, 1),
            categoryId: "cat-sales",
            memo: "1番目",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterparty: "A社"
        )

        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5000,
            date: date(2025, 6, 30),
            categoryId: "cat-supplies",
            memo: "3番目",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterparty: "C社"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertEqual(entries.count, 3, "3件のエントリがあること")

        // 日付昇順ソートを検証
        XCTAssertEqual(entries[0].date, date(2025, 6, 1), "1番目は6/1")
        XCTAssertEqual(entries[1].date, date(2025, 6, 15), "2番目は6/15")
        XCTAssertEqual(entries[2].date, date(2025, 6, 30), "3番目は6/30")

        // 取引先も日付順に対応
        XCTAssertEqual(entries[0].counterparty, "A社")
        XCTAssertEqual(entries[1].counterparty, "B社")
        XCTAssertEqual(entries[2].counterparty, "C社")
    }

    // MARK: - Empty Account

    /// 取引のない勘定の元帳エントリは空配列を返すこと
    func testLedgerEntry_EmptyAccount() {
        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertTrue(entries.isEmpty, "取引のない勘定は空配列を返すこと")
    }

    // MARK: - Counterparty & TaxCategory Available for Display

    /// 取引先とメモが同時に元帳エントリに存在し、表示用データとして利用可能であること
    func testLedgerEntry_DescriptionIncludesCounterparty() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 80000,
            date: date(2025, 10, 1),
            categoryId: "cat-sales",
            memo: "ウェブ制作費",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 8000,
            taxCategory: .standardRate,
            counterparty: "渋谷デザイン株式会社"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertFalse(entries.isEmpty)

        if let entry = entries.first {
            // counterparty と memo の両方が存在し、ビュー層で "[counterparty] memo ※" 形式に整形可能
            XCTAssertEqual(entry.counterparty, "渋谷デザイン株式会社", "取引先が取得可能であること")
            XCTAssertEqual(entry.memo, "ウェブ制作費", "メモが取得可能であること")
            XCTAssertNotNil(entry.counterparty, "取引先が nil でないこと")
        }
    }

    /// 軽減税率の元帳エントリで ※ マーク表示用の taxCategory データが利用可能であること
    func testLedgerEntry_ReducedRateTaxMark() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5400,
            date: date(2025, 11, 1),
            categoryId: "cat-supplies",
            memo: "食料品仕入",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 400,
            taxCategory: .reducedRate,
            counterparty: "スーパー山田"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertFalse(entries.isEmpty)

        if let entry = entries.first {
            XCTAssertEqual(entry.taxCategory, .reducedRate, "軽減税率が設定されていること")
            // ビュー層で taxCategory == .reducedRate の場合に ※ マークを表示する想定
            XCTAssertTrue(entry.taxCategory == .reducedRate, "※マーク表示判定用の軽減税率フラグ")
        }
    }

    // MARK: - Backward Compatibility

    /// taxAmount が nil の取引では taxCategory も nil であること（後方互換性）
    func testLedgerEntry_NilTaxAmount_NoTaxCategory() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 3000,
            date: date(2025, 5, 1),
            categoryId: "cat-supplies",
            memo: "古い取引",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
            // taxAmount, taxCategory ともに省略（nil）
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertFalse(entries.isEmpty, "エントリが存在すること")

        for entry in entries {
            XCTAssertNil(entry.taxCategory, "taxAmount nil の場合は taxCategory も nil であること")
        }
    }

    // MARK: - Combined Enrichment

    /// counterparty と taxCategory の両方が同時に正しく反映されること
    func testLedgerEntry_BothCounterpartyAndTaxCategory() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 200000,
            date: date(2025, 12, 1),
            categoryId: "cat-sales",
            memo: "年末売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 20000,
            taxCategory: .standardRate,
            counterparty: "東京商事株式会社"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertEqual(entries.count, 1)

        let entry = entries[0]
        XCTAssertEqual(entry.counterparty, "東京商事株式会社", "取引先が反映されること")
        XCTAssertEqual(entry.taxCategory, .standardRate, "標準税率が反映されること")
        XCTAssertEqual(entry.debit, 200000, "借方金額が正しいこと")
        XCTAssertEqual(entry.runningBalance, 200000, "残高が正しいこと")
    }

    /// 非課税取引の taxCategory が正しく反映されること
    func testLedgerEntry_ExemptTaxCategory() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 50000,
            date: date(2025, 4, 1),
            categoryId: "cat-sales",
            memo: "非課税取引",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxCategory: .exempt,
            counterparty: "公益法人"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertFalse(entries.isEmpty)

        if let entry = entries.first {
            XCTAssertEqual(entry.taxCategory, .exempt, "非課税区分が反映されること")
            XCTAssertEqual(entry.counterparty, "公益法人")
        }
    }

    // MARK: - Mixed Sources (Auto + Manual)

    /// 自動仕訳と手動仕訳が混在する場合、自動仕訳のみ enrichment されること
    func testLedgerEntry_MixedAutoAndManual_OnlyAutoEnriched() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        // 自動仕訳（取引から生成）
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 40000,
            date: date(2025, 3, 1),
            categoryId: "cat-sales",
            memo: "自動売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 4000,
            taxCategory: .standardRate,
            counterparty: "自動取引先"
        )

        // 手動仕訳
        _ = mutations(dataStore).addManualJournalEntry(
            date: date(2025, 3, 15),
            memo: "手動調整",
            lines: [
                (accountId: "acct-cash", debit: 5000, credit: 0, memo: ""),
                (accountId: "acct-owner-contributions", debit: 0, credit: 5000, memo: ""),
            ]
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertEqual(entries.count, 2, "自動と手動の2件のエントリ")

        // 日付昇順で 3/1 が先
        let autoEntry = entries[0]
        let manualEntry = entries[1]

        XCTAssertEqual(autoEntry.counterparty, "自動取引先", "自動仕訳は取引先あり")
        XCTAssertEqual(autoEntry.taxCategory, .standardRate, "自動仕訳は税区分あり")

        XCTAssertNil(manualEntry.counterparty, "手動仕訳は取引先 nil")
        XCTAssertNil(manualEntry.taxCategory, "手動仕訳は税区分 nil")
    }

    // MARK: - EntryType Verification

    /// 自動仕訳の entryType が .auto であること
    func testLedgerEntry_AutoEntryType() {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 15000,
            date: date(2025, 5, 15),
            categoryId: "cat-tools",
            memo: "ツール購入",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(entries[0].entryType, .auto, "取引由来の仕訳は entryType が .auto であること")
    }
}
