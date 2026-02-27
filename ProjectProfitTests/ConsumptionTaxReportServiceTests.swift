import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ConsumptionTaxReportServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var accounts: [PPAccount]!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext

        // デフォルト勘定科目をシード
        for def in AccountingConstants.defaultAccounts {
            let account = PPAccount(
                id: def.id, code: def.code, name: def.name,
                accountType: def.accountType, normalBalance: def.normalBalance,
                subtype: def.subtype, isSystem: true, displayOrder: def.displayOrder
            )
            context.insert(account)
        }
        try! context.save()

        let descriptor = FetchDescriptor<PPAccount>(sortBy: [SortDescriptor(\.displayOrder)])
        accounts = try! context.fetch(descriptor)
    }

    override func tearDown() {
        accounts = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    /// 指定日付・posted 状態で PPJournalEntry を作成し context に挿入する
    private func makeEntry(
        date: Date,
        isPosted: Bool = true,
        entryType: JournalEntryType = .auto,
        memo: String = ""
    ) -> PPJournalEntry {
        let entry = PPJournalEntry(
            sourceKey: "test:\(UUID().uuidString)",
            date: date,
            entryType: entryType,
            memo: memo,
            isPosted: isPosted
        )
        context.insert(entry)
        try! context.save()
        return entry
    }

    /// PPJournalLine を作成し context に挿入する
    private func makeLine(
        entryId: UUID,
        accountId: String,
        debit: Int,
        credit: Int
    ) -> PPJournalLine {
        let line = PPJournalLine(
            entryId: entryId,
            accountId: accountId,
            debit: debit,
            credit: credit
        )
        context.insert(line)
        try! context.save()
        return line
    }

    private func fetchAllEntries() -> [PPJournalEntry] {
        try! context.fetch(FetchDescriptor<PPJournalEntry>())
    }

    private func fetchAllLines() -> [PPJournalLine] {
        try! context.fetch(FetchDescriptor<PPJournalLine>())
    }

    // MARK: - Test: Empty Journal Lines Returns Zero Summary

    func testGenerateSummary_emptyJournalLines_returnsZeroSummary() {
        let summary = ConsumptionTaxReportService.generateSummary(
            fiscalYear: 2025,
            journalEntries: [],
            journalLines: [],
            accounts: accounts
        )

        XCTAssertEqual(summary.fiscalYear, 2025)
        XCTAssertEqual(summary.outputTaxTotal, 0)
        XCTAssertEqual(summary.inputTaxTotal, 0)
        XCTAssertEqual(summary.taxPayable, 0)
        XCTAssertFalse(summary.isRefund)
    }

    // MARK: - Test: Input Tax (仮払消費税) Sums Correctly

    func testGenerateSummary_inputTaxLines_sumsDebitCorrectly() {
        let entry = makeEntry(date: makeDate(year: 2025, month: 6, day: 15))

        let line1 = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.inputTaxAccountId,
            debit: 1_000,
            credit: 0
        )
        let line2 = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.inputTaxAccountId,
            debit: 2_500,
            credit: 0
        )

        let summary = ConsumptionTaxReportService.generateSummary(
            fiscalYear: 2025,
            journalEntries: [entry],
            journalLines: [line1, line2],
            accounts: accounts
        )

        XCTAssertEqual(summary.inputTaxTotal, 3_500)
    }

    // MARK: - Test: Output Tax (仮受消費税) Sums Correctly

    func testGenerateSummary_outputTaxLines_sumsCreditCorrectly() {
        let entry = makeEntry(date: makeDate(year: 2025, month: 3, day: 1))

        let line1 = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.outputTaxAccountId,
            debit: 0,
            credit: 5_000
        )
        let line2 = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.outputTaxAccountId,
            debit: 0,
            credit: 3_000
        )

        let summary = ConsumptionTaxReportService.generateSummary(
            fiscalYear: 2025,
            journalEntries: [entry],
            journalLines: [line1, line2],
            accounts: accounts
        )

        XCTAssertEqual(summary.outputTaxTotal, 8_000)
    }

    // MARK: - Test: Tax Payable Calculation (output - input)

    func testGenerateSummary_taxPayable_equalsOutputMinusInput() {
        let entry = makeEntry(date: makeDate(year: 2025, month: 9, day: 10))

        let outputLine = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.outputTaxAccountId,
            debit: 0,
            credit: 10_000
        )
        let inputLine = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.inputTaxAccountId,
            debit: 3_000,
            credit: 0
        )

        let summary = ConsumptionTaxReportService.generateSummary(
            fiscalYear: 2025,
            journalEntries: [entry],
            journalLines: [outputLine, inputLine],
            accounts: accounts
        )

        XCTAssertEqual(summary.outputTaxTotal, 10_000)
        XCTAssertEqual(summary.inputTaxTotal, 3_000)
        XCTAssertEqual(summary.taxPayable, 7_000)
        XCTAssertFalse(summary.isRefund)
    }

    // MARK: - Test: isRefund When Input > Output

    func testGenerateSummary_isRefund_whenInputExceedsOutput() {
        let entry = makeEntry(date: makeDate(year: 2025, month: 4, day: 20))

        let outputLine = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.outputTaxAccountId,
            debit: 0,
            credit: 2_000
        )
        let inputLine = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.inputTaxAccountId,
            debit: 8_000,
            credit: 0
        )

        let summary = ConsumptionTaxReportService.generateSummary(
            fiscalYear: 2025,
            journalEntries: [entry],
            journalLines: [outputLine, inputLine],
            accounts: accounts
        )

        XCTAssertEqual(summary.taxPayable, -6_000)
        XCTAssertTrue(summary.isRefund)
    }

    // MARK: - Test: Filtering by Fiscal Year

    func testGenerateSummary_filtersLinesByFiscalYear() {
        // 2025年のエントリ（対象）
        let entry2025 = makeEntry(date: makeDate(year: 2025, month: 7, day: 1))
        let line2025Input = makeLine(
            entryId: entry2025.id,
            accountId: AccountingConstants.inputTaxAccountId,
            debit: 1_000,
            credit: 0
        )
        let line2025Output = makeLine(
            entryId: entry2025.id,
            accountId: AccountingConstants.outputTaxAccountId,
            debit: 0,
            credit: 5_000
        )

        // 2024年のエントリ（対象外）
        let entry2024 = makeEntry(date: makeDate(year: 2024, month: 12, day: 31))
        let line2024Input = makeLine(
            entryId: entry2024.id,
            accountId: AccountingConstants.inputTaxAccountId,
            debit: 99_999,
            credit: 0
        )
        let line2024Output = makeLine(
            entryId: entry2024.id,
            accountId: AccountingConstants.outputTaxAccountId,
            debit: 0,
            credit: 99_999
        )

        // 2026年のエントリ（対象外）
        let entry2026 = makeEntry(date: makeDate(year: 2026, month: 1, day: 1))
        let line2026Input = makeLine(
            entryId: entry2026.id,
            accountId: AccountingConstants.inputTaxAccountId,
            debit: 88_888,
            credit: 0
        )

        let allEntries = [entry2025, entry2024, entry2026]
        let allLines = [
            line2025Input, line2025Output,
            line2024Input, line2024Output,
            line2026Input,
        ]

        let summary = ConsumptionTaxReportService.generateSummary(
            fiscalYear: 2025,
            journalEntries: allEntries,
            journalLines: allLines,
            accounts: accounts
        )

        // 2025年分のみが集計されること
        XCTAssertEqual(summary.inputTaxTotal, 1_000)
        XCTAssertEqual(summary.outputTaxTotal, 5_000)
        XCTAssertEqual(summary.taxPayable, 4_000)
        XCTAssertFalse(summary.isRefund)
    }

    // MARK: - Test: Unposted Entries Are Excluded

    func testGenerateSummary_excludesUnpostedEntries() {
        // isPosted = false のエントリは集計から除外される
        let unpostedEntry = makeEntry(
            date: makeDate(year: 2025, month: 5, day: 10),
            isPosted: false
        )
        let line = makeLine(
            entryId: unpostedEntry.id,
            accountId: AccountingConstants.outputTaxAccountId,
            debit: 0,
            credit: 50_000
        )

        let postedEntry = makeEntry(
            date: makeDate(year: 2025, month: 5, day: 11),
            isPosted: true
        )
        let postedLine = makeLine(
            entryId: postedEntry.id,
            accountId: AccountingConstants.outputTaxAccountId,
            debit: 0,
            credit: 3_000
        )

        let summary = ConsumptionTaxReportService.generateSummary(
            fiscalYear: 2025,
            journalEntries: [unpostedEntry, postedEntry],
            journalLines: [line, postedLine],
            accounts: accounts
        )

        // unposted の 50,000 は除外され、posted の 3,000 のみ集計される
        XCTAssertEqual(summary.outputTaxTotal, 3_000)
        XCTAssertEqual(summary.inputTaxTotal, 0)
        XCTAssertEqual(summary.taxPayable, 3_000)
    }

    // MARK: - Test: Non-Tax Account Lines Are Ignored

    func testGenerateSummary_ignoresNonTaxAccountLines() {
        let entry = makeEntry(date: makeDate(year: 2025, month: 8, day: 1))

        // 消費税以外の勘定科目（売上高、現金）の明細行
        let salesLine = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.salesAccountId,
            debit: 0,
            credit: 100_000
        )
        let cashLine = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.cashAccountId,
            debit: 100_000,
            credit: 0
        )
        // 消費税の明細行
        let taxLine = makeLine(
            entryId: entry.id,
            accountId: AccountingConstants.outputTaxAccountId,
            debit: 0,
            credit: 10_000
        )

        let summary = ConsumptionTaxReportService.generateSummary(
            fiscalYear: 2025,
            journalEntries: [entry],
            journalLines: [salesLine, cashLine, taxLine],
            accounts: accounts
        )

        // 消費税勘定科目の行のみ集計されること
        XCTAssertEqual(summary.outputTaxTotal, 10_000)
        XCTAssertEqual(summary.inputTaxTotal, 0)
    }

    func testGenerateSummary_respectsFiscalStartMonth() {
        let beforeFiscalStart = makeEntry(date: makeDate(year: 2025, month: 3, day: 31))
        let inFiscalYear = makeEntry(date: makeDate(year: 2025, month: 4, day: 1))
        let fiscalYearEnd = makeEntry(date: makeDate(year: 2026, month: 3, day: 31))
        let afterFiscalEnd = makeEntry(date: makeDate(year: 2026, month: 4, day: 1))

        let lines = [
            makeLine(entryId: beforeFiscalStart.id, accountId: AccountingConstants.outputTaxAccountId, debit: 0, credit: 100),
            makeLine(entryId: inFiscalYear.id, accountId: AccountingConstants.outputTaxAccountId, debit: 0, credit: 200),
            makeLine(entryId: fiscalYearEnd.id, accountId: AccountingConstants.outputTaxAccountId, debit: 0, credit: 300),
            makeLine(entryId: afterFiscalEnd.id, accountId: AccountingConstants.outputTaxAccountId, debit: 0, credit: 400),
        ]

        let summary = ConsumptionTaxReportService.generateSummary(
            fiscalYear: 2025,
            journalEntries: [beforeFiscalStart, inFiscalYear, fiscalYearEnd, afterFiscalEnd],
            journalLines: lines,
            accounts: accounts,
            startMonth: 4
        )

        XCTAssertEqual(summary.outputTaxTotal, 500)
    }
}
