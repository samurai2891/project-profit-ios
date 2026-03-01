import XCTest
import SwiftData
@testable import ProjectProfit

/// 青色申告（Blue Tax Return）年間シナリオテスト
/// ITフリーランサーの2025年1月〜12月の完全な事業活動をシミュレートし、
/// 全帳簿（現金出納帳・売掛帳・経費帳・月別総括集計表・総勘定元帳・固定資産台帳）が
/// 正しいデータを生成することを検証する。
@MainActor
final class AnnualBlueReturnScenarioTests: XCTestCase {
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

    // MARK: - Shared Setup

    /// 2025年度の全データをセットアップし、検証に必要な情報を返す
    private struct AnnualSetupResult {
        let webProject: PPProject
        let appProject: PPProject
        let macBookAsset: PPFixedAsset
    }

    private func setupFullYear() -> AnnualSetupResult {
        // -- Projects --
        let webProject = dataStore.addProject(name: "ウェブ制作", description: "Webサイト制作")
        let appProject = dataStore.addProject(name: "アプリ開発", description: "iOSアプリ開発")

        // -- Income Transactions --
        // Jan: Cash sale 300k (cat-sales, ウェブ制作, counterparty "A社")
        _ = dataStore.addTransaction(
            type: .income, amount: 300_000, date: date(2025, 1, 15),
            categoryId: "cat-sales", memo: "1月売上",
            allocations: [(projectId: webProject.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterparty: "A社"
        )

        // Feb: Credit sale 200k (cat-sales, アプリ開発, paymentAccountId "acct-ar", counterparty "B社")
        _ = dataStore.addTransaction(
            type: .income, amount: 200_000, date: date(2025, 2, 15),
            categoryId: "cat-sales", memo: "2月売上",
            allocations: [(projectId: appProject.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "B社"
        )

        // Mar: Cash sale 150k (cat-sales, ウェブ制作, counterparty "A社")
        _ = dataStore.addTransaction(
            type: .income, amount: 150_000, date: date(2025, 3, 15),
            categoryId: "cat-sales", memo: "3月売上",
            allocations: [(projectId: webProject.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterparty: "A社"
        )

        // Apr: Credit sale 250k (cat-sales, アプリ開発, paymentAccountId "acct-ar", counterparty "B社")
        _ = dataStore.addTransaction(
            type: .income, amount: 250_000, date: date(2025, 4, 15),
            categoryId: "cat-sales", memo: "4月売上",
            allocations: [(projectId: appProject.id, ratio: 100)],
            paymentAccountId: "acct-ar",
            counterparty: "B社"
        )

        // May: AR collection 200k (manual entry: Dr cash 200k / Cr ar 200k)
        _ = dataStore.addManualJournalEntry(
            date: date(2025, 5, 10),
            memo: "B社売掛金回収",
            lines: [
                (accountId: "acct-cash", debit: 200_000, credit: 0, memo: "入金"),
                (accountId: "acct-ar", debit: 0, credit: 200_000, memo: "売掛回収"),
            ]
        )

        // Jun: Cash sale 180k (cat-sales, ウェブ制作, counterparty "A社")
        _ = dataStore.addTransaction(
            type: .income, amount: 180_000, date: date(2025, 6, 15),
            categoryId: "cat-sales", memo: "6月売上",
            allocations: [(projectId: webProject.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterparty: "A社"
        )

        // -- Monthly Rent: Jan-Dec 80k/month (manual journal: Dr rent 80k / Cr cash 80k) --
        for month in 1...12 {
            _ = dataStore.addManualJournalEntry(
                date: date(2025, month, 25),
                memo: "\(month)月家賃",
                lines: [
                    (accountId: "acct-rent", debit: 80_000, credit: 0, memo: "地代家賃"),
                    (accountId: "acct-cash", debit: 0, credit: 80_000, memo: "現金支払"),
                ]
            )
        }

        // -- Q1 Travel: 15k each month Jan-Mar (manual: Dr travel / Cr cash) --
        for month in 1...3 {
            _ = dataStore.addManualJournalEntry(
                date: date(2025, month, 20),
                memo: "\(month)月交通費",
                lines: [
                    (accountId: "acct-travel", debit: 15_000, credit: 0, memo: "旅費交通費"),
                    (accountId: "acct-cash", debit: 0, credit: 15_000, memo: "現金支払"),
                ]
            )
        }

        // -- Supplies: Mar 10k, Jun 5k, Sep 8k (manual: Dr supplies / Cr cash) --
        _ = dataStore.addManualJournalEntry(
            date: date(2025, 3, 10),
            memo: "3月消耗品",
            lines: [
                (accountId: "acct-supplies", debit: 10_000, credit: 0, memo: "消耗品費"),
                (accountId: "acct-cash", debit: 0, credit: 10_000, memo: "現金支払"),
            ]
        )
        _ = dataStore.addManualJournalEntry(
            date: date(2025, 6, 10),
            memo: "6月消耗品",
            lines: [
                (accountId: "acct-supplies", debit: 5_000, credit: 0, memo: "消耗品費"),
                (accountId: "acct-cash", debit: 0, credit: 5_000, memo: "現金支払"),
            ]
        )
        _ = dataStore.addManualJournalEntry(
            date: date(2025, 9, 10),
            memo: "9月消耗品",
            lines: [
                (accountId: "acct-supplies", debit: 8_000, credit: 0, memo: "消耗品費"),
                (accountId: "acct-cash", debit: 0, credit: 8_000, memo: "現金支払"),
            ]
        )

        // -- Fixed Asset: MacBook 300k (Jan 2025, 4 years, businessUsePercent 80) --
        guard let macBook = dataStore.addFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: date(2025, 1, 5),
            acquisitionCost: 300_000,
            usefulLifeYears: 4,
            businessUsePercent: 80
        ) else {
            fatalError("固定資産追加に失敗")
        }

        // Post depreciation for 2025
        _ = dataStore.postDepreciation(assetId: macBook.id, fiscalYear: 2025)

        return AnnualSetupResult(
            webProject: webProject,
            appProject: appProject,
            macBookAsset: macBook
        )
    }

    // MARK: - Test 1: Full Year Scenario

    func testAnnualBlueReturn_FullYearScenario() {
        let setup = setupFullYear()

        let yearStart = date(2025, 1, 1)
        let yearEnd = date(2025, 12, 31)

        // 1. 現金出納帳: Cash book entries exist and running balance is correct
        let cashEntries = dataStore.getSubLedgerEntries(
            type: .cashBook, startDate: yearStart, endDate: yearEnd
        )
        XCTAssertFalse(cashEntries.isEmpty, "現金出納帳にエントリが存在すること")

        // Cash inflows: 300k(Jan) + 150k(Mar) + 200k(May AR collection) + 180k(Jun) = 830k
        // Cash outflows: 80k*12(rent) + 15k*3(travel) + 10k+5k+8k(supplies) = 960k + 45k + 23k = 1,028k
        let cashDebitTotal = cashEntries.reduce(0) { $0 + $1.debit }
        let cashCreditTotal = cashEntries.reduce(0) { $0 + $1.credit }
        XCTAssertEqual(cashDebitTotal, 830_000, "現金入金合計")
        XCTAssertEqual(cashCreditTotal, 1_028_000, "現金出金合計")

        let lastCashEntry = cashEntries.last
        XCTAssertNotNil(lastCashEntry, "現金出納帳の最終エントリ")
        // Final running balance = 830k - 1,028k = -198k (deficit is expected in test scenario)
        let expectedCashBalance = 830_000 - 1_028_000
        XCTAssertEqual(lastCashEntry?.runningBalance, expectedCashBalance, "現金残高が正しいこと")

        // 2. 売掛帳: AR book shows B社 credit-sale entries; collection is an unfiltered global balance check.
        // NOTE: The May AR collection (Dr cash / Cr AR 200k) is posted as a manual journal entry
        // which has no sourceTransactionId and therefore no counterparty. The counterpartyFilter
        // for "B社" will exclude it. So the filtered view only shows the two credit sales (debit
        // entries), and the global AR balance (getAccountBalance) reflects the full net position.
        let arEntriesB = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook, startDate: yearStart, endDate: yearEnd,
            counterpartyFilter: "B社"
        )
        XCTAssertFalse(arEntriesB.isEmpty, "売掛帳にB社エントリが存在すること")

        // Filtered entries: only the two credit sales (Feb 200k + Apr 250k = 450k debit, 0 credit)
        let arDebitTotal = arEntriesB.reduce(0) { $0 + $1.debit }
        let arCreditTotal = arEntriesB.reduce(0) { $0 + $1.credit }
        XCTAssertEqual(arDebitTotal, 450_000, "B社掛売上合計: 200k + 250k")
        XCTAssertEqual(arCreditTotal, 0, "B社フィルタ済み回収: 手動仕訳は取引先なしのため除外")

        // Global AR balance (all counterparties): 450k sales - 200k collection = 250k
        let globalARBalance = dataStore.getAccountBalance(accountId: "acct-ar")
        XCTAssertEqual(globalARBalance.balance, 250_000, "売掛金残高（全体）= 掛売上 - 回収")

        // 3. 経費帳: Expense book has rent (12 entries), travel (3 entries), supplies (3 entries)
        let expenseEntries = dataStore.getSubLedgerEntries(
            type: .expenseBook, startDate: yearStart, endDate: yearEnd
        )
        let rentEntries = expenseEntries.filter { $0.accountId == "acct-rent" }
        let travelEntries = expenseEntries.filter { $0.accountId == "acct-travel" }
        let suppliesEntries = expenseEntries.filter { $0.accountId == "acct-supplies" }

        XCTAssertEqual(rentEntries.count, 12, "家賃は12件")
        XCTAssertEqual(travelEntries.count, 3, "交通費は3件")
        XCTAssertEqual(suppliesEntries.count, 3, "消耗品費は3件")

        // Depreciation expense should also appear in expense book
        let depreciationEntries = expenseEntries.filter { $0.accountId == "acct-depreciation" }
        XCTAssertEqual(depreciationEntries.count, 1, "減価償却費は1件")

        // 4. 月別総括集計表: All 12 months populated correctly
        let summary = dataStore.getMonthlySummary(year: 2025)

        let salesTotalRow = summary.first { $0.id == "sales-total" }
        XCTAssertNotNil(salesTotalRow, "sales-total 行が存在すること")
        // Total sales = 300k + 200k + 150k + 250k + 180k = 1,080k
        XCTAssertEqual(salesTotalRow?.total, 1_080_000, "年間売上合計")

        let purchasesTotalRow = summary.first { $0.id == "purchases-total" }
        XCTAssertNotNil(purchasesTotalRow, "purchases-total 行が存在すること")
        XCTAssertEqual(purchasesTotalRow?.total, 0, "仕入金額合計は0")

        let expenseTotalRow = summary.first { $0.id == "expense-total" }
        XCTAssertNotNil(expenseTotalRow, "expense-total 行が存在すること")
        // Total expenses = rent(960k) + travel(45k) + supplies(23k) + depreciation
        // Depreciation: MacBook 300k, 4 years, salvage 1
        // depreciableBasis = 299,999, annualAmount = 299,999/4 = 74,999
        // First year (Jan acquisition) = 74,999 * 12/12 = 74,999
        // businessAmount = 74,999 * 80 / 100 = 59,999
        let expectedExpenseTotal = 960_000 + 45_000 + 23_000 + 59_999
        XCTAssertEqual(expenseTotalRow?.total, expectedExpenseTotal, "年間経費合計")

        // 5. 総勘定元帳: Cash account balance = total deposits - total withdrawals
        let cashBalance = dataStore.getAccountBalance(accountId: "acct-cash")
        XCTAssertEqual(cashBalance.balance, expectedCashBalance, "現金勘定残高")

        // 6. 固定資産台帳: MacBook depreciation posted and schedule correct
        let schedule = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets, fiscalYear: 2025
        )
        XCTAssertEqual(schedule.count, 1, "固定資産台帳は1件")
        let macRow = schedule.first { $0.id == setup.macBookAsset.id }
        XCTAssertNotNil(macRow, "MacBookの減価償却明細が存在すること")
        XCTAssertEqual(macRow?.acquisitionCost, 300_000, "取得価額")
        XCTAssertEqual(macRow?.currentYearAmount, 74_999, "当期償却額")
        XCTAssertEqual(macRow?.businessUsePercent, 80, "事業使用割合")
    }

    // MARK: - Test 2: Cash Book Balance

    func testAnnualBlueReturn_CashBookBalance() {
        _ = setupFullYear()

        let yearStart = date(2025, 1, 1)
        let yearEnd = date(2025, 12, 31)

        let cashEntries = dataStore.getSubLedgerEntries(
            type: .cashBook, startDate: yearStart, endDate: yearEnd
        )

        // Manual calculation:
        // Deposits (debit to cash):
        //   Jan sale: 300,000
        //   Mar sale: 150,000
        //   May AR collection: 200,000
        //   Jun sale: 180,000
        //   Total deposits: 830,000
        //
        // Withdrawals (credit from cash):
        //   Rent: 80,000 x 12 = 960,000
        //   Travel: 15,000 x 3 = 45,000
        //   Supplies: 10,000 + 5,000 + 8,000 = 23,000
        //   Total withdrawals: 1,028,000
        //
        // Final balance: 830,000 - 1,028,000 = -198,000
        let manualDeposits = 300_000 + 150_000 + 200_000 + 180_000
        let manualWithdrawals = (80_000 * 12) + (15_000 * 3) + 10_000 + 5_000 + 8_000

        let actualDeposits = cashEntries.reduce(0) { $0 + $1.debit }
        let actualWithdrawals = cashEntries.reduce(0) { $0 + $1.credit }

        XCTAssertEqual(actualDeposits, manualDeposits, "現金入金合計が手計算と一致")
        XCTAssertEqual(actualWithdrawals, manualWithdrawals, "現金出金合計が手計算と一致")

        let expectedFinalBalance = manualDeposits - manualWithdrawals
        XCTAssertEqual(cashEntries.last?.runningBalance, expectedFinalBalance,
                       "現金出納帳の最終残高が手計算と一致: \(expectedFinalBalance)")

        // Cross-check with general ledger
        let glBalance = dataStore.getAccountBalance(accountId: "acct-cash")
        XCTAssertEqual(glBalance.balance, expectedFinalBalance,
                       "総勘定元帳の現金残高が現金出納帳と一致")
    }

    // MARK: - Test 3: AR Book Counterparty Balance

    func testAnnualBlueReturn_ARBookCounterpartyBalance() {
        _ = setupFullYear()

        let yearStart = date(2025, 1, 1)
        let yearEnd = date(2025, 12, 31)

        // B社: Total credit sales = 200k(Feb) + 250k(Apr) = 450k
        //       Total collection   = 200k(May) — posted as a MANUAL journal entry
        //       Expected net balance = 250k
        //
        // NOTE: The May AR collection (Dr cash 200k / Cr AR 200k) is created via
        // addManualJournalEntry, which has no sourceTransactionId and therefore no
        // counterparty. The counterpartyFilter "B社" excludes it because
        // transaction?.counterparty is nil for manual entries.
        // Therefore the "B社"-filtered view only contains the two credit-sale debits.
        // The true net 250k balance is verified via getAccountBalance (global, unfiltered).
        let arEntriesB = dataStore.getSubLedgerEntries(
            type: .accountsReceivableBook, startDate: yearStart, endDate: yearEnd,
            counterpartyFilter: "B社"
        )
        XCTAssertFalse(arEntriesB.isEmpty, "B社の売掛帳エントリが存在すること")

        let bDebit = arEntriesB.reduce(0) { $0 + $1.debit }
        let bCredit = arEntriesB.reduce(0) { $0 + $1.credit }

        // Filtered entries contain only the two attributed credit sales; collection is excluded.
        XCTAssertEqual(bDebit, 450_000, "B社掛売上合計（フィルタ済み）: 200k + 250k")
        XCTAssertEqual(bCredit, 0, "B社フィルタ済み貸方: 手動仕訳の回収は取引先なしのため除外")

        // The filtered running balance after the last attributed entry equals the debit-only total.
        let lastAREntry = arEntriesB.last
        XCTAssertNotNil(lastAREntry)
        XCTAssertEqual(lastAREntry?.runningBalance, 450_000,
                       "B社フィルタ済み売掛帳の最終残高（手動回収除外）")

        // Verify GLOBAL AR balance via the general ledger (all counterparties):
        // 450k sales (Dr) - 200k collection (Cr) = 250k net balance.
        let glARBalance = dataStore.getAccountBalance(accountId: "acct-ar")
        XCTAssertEqual(glARBalance.balance, 250_000,
                       "総勘定元帳の売掛金残高（全体）= 250,000円")
    }

    // MARK: - Test 4: Monthly Summary Sales Totals

    func testAnnualBlueReturn_MonthlySummary_SalesTotals() {
        _ = setupFullYear()

        let summary = dataStore.getMonthlySummary(year: 2025)
        let salesTotalRow = summary.first { $0.id == "sales-total" }
        XCTAssertNotNil(salesTotalRow, "sales-total 行が存在すること")

        let amounts = salesTotalRow!.amounts
        XCTAssertEqual(amounts.count, 12, "12ヶ月分のデータ")

        // Expected per-month sales:
        // Jan: 300k, Feb: 200k, Mar: 150k, Apr: 250k, May: 0, Jun: 180k
        // Jul-Dec: 0
        XCTAssertEqual(amounts[0], 300_000, "1月売上")
        XCTAssertEqual(amounts[1], 200_000, "2月売上")
        XCTAssertEqual(amounts[2], 150_000, "3月売上")
        XCTAssertEqual(amounts[3], 250_000, "4月売上")
        XCTAssertEqual(amounts[4], 0, "5月売上")
        XCTAssertEqual(amounts[5], 180_000, "6月売上")
        for month in 6..<12 {
            XCTAssertEqual(amounts[month], 0, "\(month + 1)月売上は0")
        }

        XCTAssertEqual(salesTotalRow!.total, 1_080_000, "年間売上合計")

        // Also verify cash vs credit breakdown
        let cashSalesRow = summary.first { $0.id == "sales-cash" }
        let creditSalesRow = summary.first { $0.id == "sales-credit" }
        XCTAssertNotNil(cashSalesRow, "現金売上行が存在すること")
        XCTAssertNotNil(creditSalesRow, "掛売上行が存在すること")

        // Cash sales: Jan 300k + Mar 150k + Jun 180k = 630k
        XCTAssertEqual(cashSalesRow!.total, 630_000, "現金売上合計")

        // Credit sales: Feb 200k + Apr 250k = 450k
        XCTAssertEqual(creditSalesRow!.total, 450_000, "掛売上合計")
    }

    // MARK: - Test 5: Monthly Summary Expense Totals

    func testAnnualBlueReturn_MonthlySummary_ExpenseTotals() {
        _ = setupFullYear()

        let summary = dataStore.getMonthlySummary(year: 2025)
        let expenseTotalRow = summary.first { $0.id == "expense-total" }
        XCTAssertNotNil(expenseTotalRow, "expense-total 行が存在すること")

        let amounts = expenseTotalRow!.amounts
        XCTAssertEqual(amounts.count, 12, "12ヶ月分のデータ")

        // Expected per-month expenses:
        // Jan: rent(80k) + travel(15k) = 95k
        // Feb: rent(80k) + travel(15k) = 95k
        // Mar: rent(80k) + travel(15k) + supplies(10k) = 105k
        // Apr: rent(80k) = 80k
        // May: rent(80k) = 80k
        // Jun: rent(80k) + supplies(5k) = 85k
        // Jul: rent(80k) = 80k
        // Aug: rent(80k) = 80k
        // Sep: rent(80k) + supplies(8k) = 88k
        // Oct: rent(80k) = 80k
        // Nov: rent(80k) = 80k
        // Dec: rent(80k) + depreciation(59,999 business portion) = 139,999
        XCTAssertEqual(amounts[0], 95_000, "1月経費")
        XCTAssertEqual(amounts[1], 95_000, "2月経費")
        XCTAssertEqual(amounts[2], 105_000, "3月経費")
        XCTAssertEqual(amounts[3], 80_000, "4月経費")
        XCTAssertEqual(amounts[4], 80_000, "5月経費")
        XCTAssertEqual(amounts[5], 85_000, "6月経費")
        XCTAssertEqual(amounts[6], 80_000, "7月経費")
        XCTAssertEqual(amounts[7], 80_000, "8月経費")
        XCTAssertEqual(amounts[8], 88_000, "9月経費")
        XCTAssertEqual(amounts[9], 80_000, "10月経費")
        XCTAssertEqual(amounts[10], 80_000, "11月経費")
        // Dec: 80k rent + 59,999 depreciation (business use)
        XCTAssertEqual(amounts[11], 80_000 + 59_999, "12月経費（家賃+減価償却費）")

        // Verify individual expense rows
        let rentRow = summary.first { $0.id == "expense-acct-rent" }
        XCTAssertNotNil(rentRow, "家賃行が存在すること")
        XCTAssertEqual(rentRow!.total, 960_000, "年間家賃合計")
        XCTAssertTrue(rentRow!.amounts.allSatisfy { $0 == 80_000 }, "毎月80,000円の家賃")

        let travelRow = summary.first { $0.id == "expense-acct-travel" }
        XCTAssertNotNil(travelRow, "交通費行が存在すること")
        XCTAssertEqual(travelRow!.total, 45_000, "年間交通費合計")

        let suppliesRow = summary.first { $0.id == "expense-acct-supplies" }
        XCTAssertNotNil(suppliesRow, "消耗品費行が存在すること")
        XCTAssertEqual(suppliesRow!.total, 23_000, "年間消耗品費合計")
    }

    // MARK: - Test 6: Fixed Asset Depreciation

    func testAnnualBlueReturn_FixedAssetDepreciation() {
        let setup = setupFullYear()

        // MacBook Pro: 300,000 acquisition, 4 years useful life, 80% business use
        // depreciableBasis = 300,000 - 1 (salvage) = 299,999
        // annualStraightLineAmount = 299,999 / 4 = 74,999
        // First year (Jan acquisition): 74,999 * 12/12 = 74,999 (full year)
        // businessAmount = 74,999 * 80 / 100 = 59,999
        // personalAmount = 74,999 - 59,999 = 15,000

        // Verify via DepreciationScheduleBuilder
        let schedule = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets, fiscalYear: 2025
        )
        XCTAssertEqual(schedule.count, 1)

        let macRow = schedule.first { $0.id == setup.macBookAsset.id }
        XCTAssertNotNil(macRow)
        XCTAssertEqual(macRow!.assetName, "MacBook Pro")
        XCTAssertEqual(macRow!.acquisitionCost, 300_000)
        XCTAssertEqual(macRow!.usefulLifeYears, 4)
        XCTAssertEqual(macRow!.currentYearAmount, 74_999, "当期償却額")
        XCTAssertEqual(macRow!.accumulatedAmount, 74_999, "累計償却額（初年度）")
        XCTAssertEqual(macRow!.bookValue, 300_000 - 74_999, "期末帳簿価額")
        XCTAssertEqual(macRow!.businessUsePercent, 80)

        // Verify via DepreciationEngine.calculate
        let calc = DepreciationEngine.calculate(
            asset: setup.macBookAsset,
            fiscalYear: 2025,
            priorAccumulatedDepreciation: 0
        )
        XCTAssertNotNil(calc)
        XCTAssertEqual(calc!.annualAmount, 74_999, "年間償却額")
        XCTAssertEqual(calc!.businessAmount, 59_999, "事業使用分（必要経費算入額）")
        XCTAssertEqual(calc!.personalAmount, 15_000, "家事使用分")
        XCTAssertEqual(calc!.bookValueAfter, 225_001, "償却後帳簿価額")

        // Verify the depreciation journal entry was created
        let depExpBalance = dataStore.getAccountBalance(accountId: "acct-depreciation")
        XCTAssertEqual(depExpBalance.debit, 59_999, "減価償却費（事業使用分）が借方に計上")

        // Owner drawings for personal portion
        let drawingsBalance = dataStore.getAccountBalance(accountId: "acct-owner-drawings")
        XCTAssertEqual(drawingsBalance.debit, 15_000, "事業主貸（家事使用分）が借方に計上")

        // Accumulated depreciation (contra-asset, credit normal)
        let accumBalance = dataStore.getAccountBalance(accountId: "acct-accumulated-depreciation")
        XCTAssertEqual(accumBalance.credit, 74_999, "減価償却累計額が貸方に計上")
    }

    // MARK: - Test 7: Tax Marks

    func testAnnualBlueReturn_TaxMarks() {
        let project = dataStore.addProject(name: "税区分テスト", description: "")

        // Standard rate (10%) income transaction
        let standardIncome = dataStore.addTransaction(
            type: .income, amount: 110_000, date: date(2025, 7, 1),
            categoryId: "cat-sales", memo: "標準税率売上",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 10_000,
            taxCategory: .standardRate,
            counterparty: "C社"
        )
        XCTAssertEqual(standardIncome.taxCategory, .standardRate)

        // Reduced rate (8%) expense transaction
        let reducedExpense = dataStore.addTransaction(
            type: .expense, amount: 10_800, date: date(2025, 7, 5),
            categoryId: "cat-food", memo: "軽減税率経費",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 800,
            taxCategory: .reducedRate,
            counterparty: "D店"
        )
        XCTAssertEqual(reducedExpense.taxCategory, .reducedRate)

        let yearStart = date(2025, 1, 1)
        let yearEnd = date(2025, 12, 31)

        // Verify tax categories appear in cash book
        let cashEntries = dataStore.getSubLedgerEntries(
            type: .cashBook, startDate: yearStart, endDate: yearEnd
        )
        let standardEntries = cashEntries.filter { $0.taxCategory == .standardRate }
        let reducedEntries = cashEntries.filter { $0.taxCategory == .reducedRate }

        XCTAssertFalse(standardEntries.isEmpty, "標準税率エントリが現金出納帳に存在")
        XCTAssertFalse(reducedEntries.isEmpty, "軽減税率エントリが現金出納帳に存在")

        // Verify tax categories appear in general ledger
        let cashLedger = dataStore.getLedgerEntries(
            accountId: "acct-cash", startDate: yearStart, endDate: yearEnd
        )
        let standardLedger = cashLedger.filter { $0.taxCategory == .standardRate }
        let reducedLedger = cashLedger.filter { $0.taxCategory == .reducedRate }

        XCTAssertFalse(standardLedger.isEmpty, "標準税率エントリが総勘定元帳に存在")
        XCTAssertFalse(reducedLedger.isEmpty, "軽減税率エントリが総勘定元帳に存在")

        // Verify consumption tax accounts have correct balances
        // Standard rate income: output tax (仮受消費税) = 10,000
        let outputTaxBalance = dataStore.getAccountBalance(accountId: "acct-output-tax")
        XCTAssertEqual(outputTaxBalance.credit, 10_000, "仮受消費税 = 10,000")

        // Reduced rate expense: input tax (仮払消費税) = 800
        let inputTaxBalance = dataStore.getAccountBalance(accountId: "acct-input-tax")
        XCTAssertEqual(inputTaxBalance.debit, 800, "仮払消費税 = 800")

        // Verify CSV export contains tax category
        let csv = dataStore.exportSubLedgerCSV(
            type: .cashBook, startDate: yearStart, endDate: yearEnd
        )
        XCTAssertTrue(csv.contains("standardRate"), "CSVに標準税率が含まれること")
        XCTAssertTrue(csv.contains("reducedRate"), "CSVに軽減税率が含まれること")
    }

    // MARK: - Test 8: Debit Credit Balance

    func testAnnualBlueReturn_DebitCreditBalance() {
        _ = setupFullYear()

        // Fundamental accounting equation: Total Debits == Total Credits
        // across ALL posted journal entries
        let postedEntryIds = Set(
            dataStore.journalEntries.filter(\.isPosted).map(\.id)
        )

        var totalDebits = 0
        var totalCredits = 0

        for line in dataStore.journalLines {
            guard postedEntryIds.contains(line.entryId) else { continue }
            totalDebits += line.debit
            totalCredits += line.credit
        }

        XCTAssertEqual(totalDebits, totalCredits,
                       "借方合計(\(totalDebits)) == 貸方合計(\(totalCredits)): 会計の基本原則")
        XCTAssertGreaterThan(totalDebits, 0, "仕訳が存在すること")

        // Verify each individual journal entry is balanced
        let entriesGrouped = Dictionary(grouping: dataStore.journalLines) { $0.entryId }
        for (entryId, lines) in entriesGrouped {
            guard postedEntryIds.contains(entryId) else { continue }
            let entryDebit = lines.reduce(0) { $0 + $1.debit }
            let entryCredit = lines.reduce(0) { $0 + $1.credit }
            XCTAssertEqual(entryDebit, entryCredit,
                           "仕訳 \(entryId) の貸借一致: 借方\(entryDebit) == 貸方\(entryCredit)")
        }

        // Additional cross-check: sum of all debit-normal account balances
        // should equal sum of all credit-normal account balances.
        //
        // NOTE: We group by normalBalance, NOT by accountType.
        // Reason: acct-owner-drawings (事業主貸) has accountType == .equity but
        // normalBalance == .debit (it is a contra-equity account shown on the asset
        // side of the balance sheet). Grouping by accountType would place its balance
        // on the right-hand side and break the equation. Using normalBalance is the
        // correct approach: debit-normal accounts always offset credit-normal accounts
        // when the books are in balance.
        var debitNormalTotal = 0
        var creditNormalTotal = 0

        for account in dataStore.accounts {
            let balance = dataStore.getAccountBalance(accountId: account.id)
            if account.normalBalance == .debit {
                debitNormalTotal += balance.balance
            } else {
                creditNormalTotal += balance.balance
            }
        }

        XCTAssertEqual(debitNormalTotal, creditNormalTotal,
                       "借方系科目残高合計(\(debitNormalTotal)) == 貸方系科目残高合計(\(creditNormalTotal)): 会計等式の検証")
    }
}
