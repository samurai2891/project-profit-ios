import XCTest
@testable import ProjectProfit

@MainActor
final class ConsumptionTaxReportServiceTests: XCTestCase {
    private let businessId = UUID()
    private let registeredCounterpartyId = UUID()
    private let unregisteredCounterpartyId = UUID()

    private var revenueAccount: CanonicalAccount!
    private var expenseAccount: CanonicalAccount!
    private var cashAccount: CanonicalAccount!
    private var inputTaxAccount: CanonicalAccount!
    private var outputTaxAccount: CanonicalAccount!

    override func setUp() {
        super.setUp()
        revenueAccount = CanonicalAccount(
            id: UUID(),
            businessId: businessId,
            legacyAccountId: AccountingConstants.salesAccountId,
            code: "401",
            name: "売上高",
            accountType: .revenue,
            normalBalance: .credit
        )
        expenseAccount = CanonicalAccount(
            id: UUID(),
            businessId: businessId,
            legacyAccountId: AccountingConstants.miscExpenseAccountId,
            code: "601",
            name: "雑費",
            accountType: .expense,
            normalBalance: .debit
        )
        cashAccount = CanonicalAccount(
            id: UUID(),
            businessId: businessId,
            legacyAccountId: AccountingConstants.cashAccountId,
            code: "101",
            name: "現金",
            accountType: .asset,
            normalBalance: .debit
        )
        inputTaxAccount = CanonicalAccount(
            id: UUID(),
            businessId: businessId,
            legacyAccountId: AccountingConstants.inputTaxAccountId,
            code: "151",
            name: "仮払消費税",
            accountType: .asset,
            normalBalance: .debit
        )
        outputTaxAccount = CanonicalAccount(
            id: UUID(),
            businessId: businessId,
            legacyAccountId: AccountingConstants.outputTaxAccountId,
            code: "251",
            name: "仮受消費税",
            accountType: .liability,
            normalBalance: .credit
        )
    }

    func testGenerateWorksheetBuildsOutputAndQualifiedInputLines() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .taxable,
            vatMethod: .general,
            taxPackVersion: "2025-v1"
        )
        let pack = TaxYearPack(taxYear: 2025, version: "2025-v1")
        let counterparties = [
            Counterparty(
                id: registeredCounterpartyId,
                businessId: businessId,
                displayName: "登録済み取引先",
                invoiceIssuerStatus: .registered
            )
        ]

        let journals = [
            makeOutputEntry(year: 2025, month: 4, day: 15, taxableAmount: 1_000, taxAmount: 100),
            makeInputEntry(
                year: 2025,
                month: 4,
                day: 20,
                taxableAmount: 500,
                taxAmount: 50,
                counterpartyId: registeredCounterpartyId
            )
        ]

        let worksheet = ConsumptionTaxReportService.generateWorksheet(
            fiscalYear: 2025,
            taxYearProfile: profile,
            journalEntries: journals,
            accounts: canonicalAccounts,
            counterparties: counterparties,
            pack: pack
        )
        let summary = ConsumptionTaxReportService.generateSummary(from: worksheet)

        XCTAssertEqual(worksheet.lines.count, 2)
        XCTAssertEqual(worksheet.outputTaxTotal, 100)
        XCTAssertEqual(worksheet.rawInputTaxTotal, 50)
        XCTAssertEqual(worksheet.deductibleInputTaxTotal, 50)
        XCTAssertEqual(summary.taxPayable, 50)
        XCTAssertEqual(
            worksheet.lines.first(where: { $0.direction == .input })?.purchaseCreditMethod,
            .qualifiedInvoice
        )
    }

    func testGenerateWorksheetAppliesTransitionalCreditForUnregisteredCounterparty() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2026,
            vatStatus: .taxable,
            vatMethod: .general,
            taxPackVersion: "2026-v1"
        )
        let pack = TaxYearPack(taxYear: 2026, version: "2026-v1")
        let counterparties = [
            Counterparty(
                id: unregisteredCounterpartyId,
                businessId: businessId,
                displayName: "未登録取引先",
                invoiceIssuerStatus: .unregistered
            )
        ]

        let worksheet = ConsumptionTaxReportService.generateWorksheet(
            fiscalYear: 2026,
            taxYearProfile: profile,
            journalEntries: [
                makeInputEntry(
                    year: 2026,
                    month: 11,
                    day: 10,
                    taxableAmount: 20_000,
                    taxAmount: 2_000,
                    counterpartyId: unregisteredCounterpartyId
                )
            ],
            accounts: canonicalAccounts,
            counterparties: counterparties,
            pack: pack
        )

        let inputLine = try! XCTUnwrap(worksheet.lines.first)
        XCTAssertEqual(inputLine.purchaseCreditMethod, .transitional50)
        XCTAssertEqual(inputLine.taxAmount, 2_000)
        XCTAssertEqual(inputLine.deductibleTaxAmount, 1_000)
        XCTAssertEqual(worksheet.taxPayable, -1_000)
    }

    func testGenerateWorksheetFiltersEntriesOutsideFiscalYear() {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            vatStatus: .taxable,
            vatMethod: .general,
            taxPackVersion: "2025-v1"
        )

        let worksheet = ConsumptionTaxReportService.generateWorksheet(
            fiscalYear: 2025,
            taxYearProfile: profile,
            journalEntries: [
                makeOutputEntry(year: 2024, month: 12, day: 31, taxableAmount: 1_000, taxAmount: 100),
                makeOutputEntry(year: 2025, month: 1, day: 5, taxableAmount: 2_000, taxAmount: 200),
                makeOutputEntry(year: 2026, month: 1, day: 1, taxableAmount: 3_000, taxAmount: 300)
            ],
            accounts: canonicalAccounts
        )

        XCTAssertEqual(worksheet.lines.count, 1)
        XCTAssertEqual(worksheet.outputTaxTotal, 200)
    }

    func testLegacyGenerateSummaryCompatibilityStillSumsInputAndOutputTaxAccounts() {
        let entry = PPJournalEntry(
            sourceKey: "legacy:test",
            date: makeDate(year: 2025, month: 6, day: 1),
            entryType: .auto,
            memo: "legacy",
            isPosted: true
        )
        let lines = [
            PPJournalLine(entryId: entry.id, accountId: AccountingConstants.outputTaxAccountId, debit: 0, credit: 800),
            PPJournalLine(entryId: entry.id, accountId: AccountingConstants.inputTaxAccountId, debit: 300, credit: 0)
        ]

        let summary = ConsumptionTaxReportService.generateSummary(
            fiscalYear: 2025,
            journalEntries: [entry],
            journalLines: lines,
            accounts: []
        )

        XCTAssertEqual(summary.outputTaxTotal, 800)
        XCTAssertEqual(summary.inputTaxTotal, 300)
        XCTAssertEqual(summary.rawInputTaxTotal, 300)
        XCTAssertEqual(summary.taxPayable, 500)
    }

    private var canonicalAccounts: [CanonicalAccount] {
        [revenueAccount, expenseAccount, cashAccount, inputTaxAccount, outputTaxAccount]
    }

    private func makeOutputEntry(
        year: Int,
        month: Int,
        day: Int,
        taxableAmount: Int,
        taxAmount: Int
    ) -> CanonicalJournalEntry {
        let journalId = UUID()
        return CanonicalJournalEntry(
            id: journalId,
            businessId: businessId,
            taxYear: year,
            journalDate: makeDate(year: year, month: month, day: day),
            voucherNo: "\(year)-\(String(format: "%03d", month))-00001",
            lines: [
                JournalLine(
                    journalId: journalId,
                    accountId: cashAccount.id,
                    debitAmount: Decimal(taxableAmount + taxAmount),
                    creditAmount: 0,
                    sortOrder: 0
                ),
                JournalLine(
                    journalId: journalId,
                    accountId: revenueAccount.id,
                    debitAmount: 0,
                    creditAmount: Decimal(taxableAmount),
                    taxCodeId: TaxCode.standard10.rawValue,
                    sortOrder: 1
                ),
                JournalLine(
                    journalId: journalId,
                    accountId: outputTaxAccount.id,
                    debitAmount: 0,
                    creditAmount: Decimal(taxAmount),
                    taxCodeId: TaxCode.standard10.rawValue,
                    sortOrder: 2
                )
            ]
        )
    }

    private func makeInputEntry(
        year: Int,
        month: Int,
        day: Int,
        taxableAmount: Int,
        taxAmount: Int,
        counterpartyId: UUID
    ) -> CanonicalJournalEntry {
        let journalId = UUID()
        return CanonicalJournalEntry(
            id: journalId,
            businessId: businessId,
            taxYear: year,
            journalDate: makeDate(year: year, month: month, day: day),
            voucherNo: "\(year)-\(String(format: "%03d", month))-00002",
            lines: [
                JournalLine(
                    journalId: journalId,
                    accountId: expenseAccount.id,
                    debitAmount: Decimal(taxableAmount),
                    creditAmount: 0,
                    taxCodeId: TaxCode.standard10.rawValue,
                    counterpartyId: counterpartyId,
                    sortOrder: 0
                ),
                JournalLine(
                    journalId: journalId,
                    accountId: inputTaxAccount.id,
                    debitAmount: Decimal(taxAmount),
                    creditAmount: 0,
                    taxCodeId: TaxCode.standard10.rawValue,
                    counterpartyId: counterpartyId,
                    sortOrder: 1
                ),
                JournalLine(
                    journalId: journalId,
                    accountId: cashAccount.id,
                    debitAmount: 0,
                    creditAmount: Decimal(taxableAmount + taxAmount),
                    sortOrder: 2
                )
            ]
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
