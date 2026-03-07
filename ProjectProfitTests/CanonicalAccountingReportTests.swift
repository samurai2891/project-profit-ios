import XCTest
@testable import ProjectProfit

/// AccountingReportService の canonical（Decimalベース）オーバーロードをテストする
@MainActor
final class CanonicalAccountingReportTests: XCTestCase {
    private let businessId = UUID()
    private let fiscalYear = 2026

    // MARK: - Helpers

    private func makeAccount(
        code: String,
        name: String,
        accountType: CanonicalAccountType,
        normalBalance: NormalBalance
    ) -> CanonicalAccount {
        CanonicalAccount(
            businessId: businessId,
            code: code,
            name: name,
            accountType: accountType,
            normalBalance: normalBalance
        )
    }

    private func makeJournal(
        date: Date,
        lines: [JournalLine],
        entryType: CanonicalJournalEntryType = .normal,
        approved: Bool = true
    ) -> CanonicalJournalEntry {
        let id = UUID()
        return CanonicalJournalEntry(
            id: id,
            businessId: businessId,
            taxYear: fiscalYear,
            journalDate: date,
            voucherNo: "V-\(id.uuidString.prefix(4))",
            entryType: entryType,
            lines: lines,
            approvedAt: approved ? date : nil
        )
    }

    private func makeLine(
        journalId: UUID = UUID(),
        accountId: UUID,
        debit: Decimal = 0,
        credit: Decimal = 0
    ) -> JournalLine {
        JournalLine(
            journalId: journalId,
            accountId: accountId,
            debitAmount: debit,
            creditAmount: credit
        )
    }

    /// 年度内の日付を生成する
    private func dateInFiscalYear(month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: fiscalYear, month: month, day: day))!
    }

    // MARK: - Trial Balance

    /// 基本的な試算表生成をテストする
    func testCanonicalTrialBalance() {
        let cashAccount = makeAccount(code: "100", name: "現金", accountType: .asset, normalBalance: .debit)
        let revenueAccount = makeAccount(code: "400", name: "売上高", accountType: .revenue, normalBalance: .credit)
        let accounts = [cashAccount, revenueAccount]

        let journalId = UUID()
        let journal = makeJournal(
            date: dateInFiscalYear(month: 3, day: 15),
            lines: [
                makeLine(journalId: journalId, accountId: cashAccount.id, debit: 100_000),
                makeLine(journalId: journalId, accountId: revenueAccount.id, credit: 100_000),
            ]
        )

        let report = AccountingReportService.generateTrialBalance(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journals: [journal]
        )

        XCTAssertEqual(report.rows.count, 2)
        XCTAssertEqual(report.fiscalYear, fiscalYear)

        let cashRow = report.rows.first { $0.code == "100" }
        XCTAssertNotNil(cashRow)
        XCTAssertEqual(cashRow?.debit, 100_000)
        XCTAssertEqual(cashRow?.credit, 0)
        XCTAssertEqual(cashRow?.balance, 100_000)

        let revenueRow = report.rows.first { $0.code == "400" }
        XCTAssertNotNil(revenueRow)
        XCTAssertEqual(revenueRow?.debit, 0)
        XCTAssertEqual(revenueRow?.credit, 100_000)
        XCTAssertEqual(revenueRow?.balance, 100_000)
    }

    /// 試算表の借方合計と貸方合計が一致することを確認
    func testCanonicalTrialBalanceIsBalanced() {
        let cashAccount = makeAccount(code: "100", name: "現金", accountType: .asset, normalBalance: .debit)
        let revenueAccount = makeAccount(code: "400", name: "売上高", accountType: .revenue, normalBalance: .credit)
        let expenseAccount = makeAccount(code: "500", name: "消耗品費", accountType: .expense, normalBalance: .debit)
        let accounts = [cashAccount, revenueAccount, expenseAccount]

        let j1Id = UUID()
        let j1 = makeJournal(
            date: dateInFiscalYear(month: 4, day: 1),
            lines: [
                makeLine(journalId: j1Id, accountId: cashAccount.id, debit: 200_000),
                makeLine(journalId: j1Id, accountId: revenueAccount.id, credit: 200_000),
            ]
        )

        let j2Id = UUID()
        let j2 = makeJournal(
            date: dateInFiscalYear(month: 5, day: 10),
            lines: [
                makeLine(journalId: j2Id, accountId: expenseAccount.id, debit: 30_000),
                makeLine(journalId: j2Id, accountId: cashAccount.id, credit: 30_000),
            ]
        )

        let report = AccountingReportService.generateTrialBalance(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journals: [j1, j2]
        )

        XCTAssertTrue(report.isBalanced, "借方合計(\(report.debitTotal))と貸方合計(\(report.creditTotal))は一致すべき")
        XCTAssertEqual(report.debitTotal, report.creditTotal)
    }

    // MARK: - Profit & Loss

    /// 収益と費用が正しく分離されて計算されることを確認
    func testCanonicalProfitLoss() {
        let cashAccount = makeAccount(code: "100", name: "現金", accountType: .asset, normalBalance: .debit)
        let revenueAccount = makeAccount(code: "400", name: "売上高", accountType: .revenue, normalBalance: .credit)
        let expenseAccount = makeAccount(code: "500", name: "消耗品費", accountType: .expense, normalBalance: .debit)
        let accounts = [cashAccount, revenueAccount, expenseAccount]

        let j1Id = UUID()
        let j1 = makeJournal(
            date: dateInFiscalYear(month: 6, day: 1),
            lines: [
                makeLine(journalId: j1Id, accountId: cashAccount.id, debit: 150_000),
                makeLine(journalId: j1Id, accountId: revenueAccount.id, credit: 150_000),
            ]
        )

        let j2Id = UUID()
        let j2 = makeJournal(
            date: dateInFiscalYear(month: 7, day: 15),
            lines: [
                makeLine(journalId: j2Id, accountId: expenseAccount.id, debit: 40_000),
                makeLine(journalId: j2Id, accountId: cashAccount.id, credit: 40_000),
            ]
        )

        let report = AccountingReportService.generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journals: [j1, j2]
        )

        XCTAssertEqual(report.totalRevenue, 150_000, "売上高は150,000であるべき")
        XCTAssertEqual(report.totalExpenses, 40_000, "費用は40,000であるべき")
        XCTAssertEqual(report.netIncome, 110_000, "当期純利益は110,000であるべき")
        XCTAssertEqual(report.revenueItems.count, 1)
        XCTAssertEqual(report.expenseItems.count, 1)
    }

    // MARK: - Balance Sheet

    /// 資産 = 負債 + 資本（当期純利益含む）の等式が成立することを確認
    func testCanonicalBalanceSheet() {
        let cashAccount = makeAccount(code: "100", name: "現金", accountType: .asset, normalBalance: .debit)
        let liabilityAccount = makeAccount(code: "200", name: "買掛金", accountType: .liability, normalBalance: .credit)
        let revenueAccount = makeAccount(code: "400", name: "売上高", accountType: .revenue, normalBalance: .credit)
        let expenseAccount = makeAccount(code: "500", name: "消耗品費", accountType: .expense, normalBalance: .debit)
        let accounts = [cashAccount, liabilityAccount, revenueAccount, expenseAccount]

        // 売上: 現金200,000 / 売上200,000
        let j1Id = UUID()
        let j1 = makeJournal(
            date: dateInFiscalYear(month: 3, day: 1),
            lines: [
                makeLine(journalId: j1Id, accountId: cashAccount.id, debit: 200_000),
                makeLine(journalId: j1Id, accountId: revenueAccount.id, credit: 200_000),
            ]
        )

        // 費用: 消耗品50,000 / 買掛金50,000
        let j2Id = UUID()
        let j2 = makeJournal(
            date: dateInFiscalYear(month: 4, day: 1),
            lines: [
                makeLine(journalId: j2Id, accountId: expenseAccount.id, debit: 50_000),
                makeLine(journalId: j2Id, accountId: liabilityAccount.id, credit: 50_000),
            ]
        )

        let report = AccountingReportService.generateBalanceSheet(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journals: [j1, j2]
        )

        // 資産: 現金 200,000
        XCTAssertEqual(report.totalAssets, 200_000, "資産合計は200,000であるべき")
        // 負債: 買掛金 50,000
        XCTAssertEqual(report.totalLiabilities, 50_000, "負債合計は50,000であるべき")
        // 資本: 当期純利益 150,000 (200,000 - 50,000)
        XCTAssertEqual(report.totalEquity, 150_000, "資本合計は150,000であるべき")
        // 等式: 資産 = 負債 + 資本
        XCTAssertTrue(report.isBalanced, "資産(\(report.totalAssets)) = 負債+資本(\(report.liabilitiesAndEquity))であるべき")
    }

    // MARK: - Empty Journals

    /// 空の仕訳データでは空のレポートが返る
    func testEmptyJournals() {
        let cashAccount = makeAccount(code: "100", name: "現金", accountType: .asset, normalBalance: .debit)
        let revenueAccount = makeAccount(code: "400", name: "売上高", accountType: .revenue, normalBalance: .credit)
        let accounts = [cashAccount, revenueAccount]
        let emptyJournals: [CanonicalJournalEntry] = []

        // Trial Balance
        let tb = AccountingReportService.generateTrialBalance(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journals: emptyJournals
        )
        XCTAssertTrue(tb.rows.isEmpty, "仕訳がなければ試算表の行は空であるべき")
        XCTAssertTrue(tb.isBalanced, "空の試算表は貸借一致であるべき")

        // Profit & Loss
        let pl = AccountingReportService.generateProfitLoss(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journals: emptyJournals
        )
        XCTAssertTrue(pl.revenueItems.isEmpty, "仕訳がなければ収益項目は空であるべき")
        XCTAssertTrue(pl.expenseItems.isEmpty, "仕訳がなければ費用項目は空であるべき")
        XCTAssertEqual(pl.netIncome, 0, "仕訳がなければ当期純利益は0であるべき")

        // Balance Sheet
        let bs = AccountingReportService.generateBalanceSheet(
            fiscalYear: fiscalYear,
            accounts: accounts,
            journals: emptyJournals
        )
        XCTAssertTrue(bs.assetItems.isEmpty, "仕訳がなければ資産項目は空であるべき")
        XCTAssertTrue(bs.liabilityItems.isEmpty, "仕訳がなければ負債項目は空であるべき")
        XCTAssertTrue(bs.equityItems.isEmpty, "仕訳がなければ資本項目は空であるべき")
        XCTAssertTrue(bs.isBalanced, "空のB/Sは貸借一致であるべき")
    }
}
