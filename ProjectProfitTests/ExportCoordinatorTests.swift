import PDFKit
import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ExportCoordinatorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var businessId: UUID!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        businessId = dataStore.businessProfile?.id
        XCTAssertNotNil(businessId)
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        businessId = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testMakeFileName() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let expectedDate = formatter.string(from: Date())

        let csvFileName = ExportCoordinator.makeFileName(
            target: .profitLoss, fiscalYear: 2026, format: .csv
        )
        XCTAssertEqual(csvFileName, "profit_loss_2026_\(expectedDate).csv")

        let pdfFileName = ExportCoordinator.makeFileName(
            target: .balanceSheet, fiscalYear: 2025, format: .pdf
        )
        XCTAssertEqual(pdfFileName, "balance_sheet_2025_\(expectedDate).pdf")

        let journalFileName = ExportCoordinator.makeFileName(
            target: .journalBook, fiscalYear: 2026, format: .csv
        )
        XCTAssertTrue(journalFileName.hasPrefix("journal_book_2026_"))
        XCTAssertTrue(journalFileName.hasSuffix(".csv"))

        let trialBalanceFileName = ExportCoordinator.makeFileName(
            target: .trialBalance, fiscalYear: 2026, format: .pdf
        )
        XCTAssertTrue(trialBalanceFileName.hasPrefix("trial_balance_2026_"))
        XCTAssertTrue(trialBalanceFileName.hasSuffix(".pdf"))

        let ledgerFileName = ExportCoordinator.makeFileName(
            target: .generalLedger, fiscalYear: 2026, format: .csv
        )
        XCTAssertTrue(ledgerFileName.hasPrefix("general_ledger_2026_"))

        let fixedAssetsFileName = ExportCoordinator.makeFileName(
            target: .fixedAssetRegister, fiscalYear: 2026, format: .csv
        )
        XCTAssertTrue(fixedAssetsFileName.hasPrefix("fixed_asset_register_2026_"))

        let etaxFileName = ExportCoordinator.makeFileName(
            target: .etax, fiscalYear: 2025, format: .xtx
        )
        XCTAssertTrue(etaxFileName.hasPrefix("etax_2025_"))
        XCTAssertTrue(etaxFileName.hasSuffix(".xtx"))

        let xlsxFileName = ExportCoordinator.makeFileName(
            target: .trialBalance, fiscalYear: 2026, format: .xlsx
        )
        XCTAssertEqual(xlsxFileName, "trial_balance_2026_\(expectedDate).xlsx")
    }

    func testExportTargetLabels() {
        XCTAssertEqual(ExportCoordinator.ExportTarget.profitLoss.label, "損益計算書")
        XCTAssertEqual(ExportCoordinator.ExportTarget.balanceSheet.label, "貸借対照表")
        XCTAssertEqual(ExportCoordinator.ExportTarget.trialBalance.label, "残高試算表")
        XCTAssertEqual(ExportCoordinator.ExportTarget.cashBook.label, "現金出納帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.bankAccountBook.label, "預金出納帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.accountsReceivableBook.label, "売掛帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.accountsPayableBook.label, "買掛帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.expenseBook.label, "経費帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.generalLedger.label, "総勘定元帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.journalBook.label, "仕訳帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.transportationExpense.label, "交通費精算書")
        XCTAssertEqual(ExportCoordinator.ExportTarget.whiteTaxBookkeeping.label, "白色申告用 簡易帳簿")
        XCTAssertEqual(ExportCoordinator.ExportTarget.journal.label, "仕訳帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.ledger.label, "総勘定元帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.transactions.label, "取引履歴")
        XCTAssertEqual(ExportCoordinator.ExportTarget.subLedger.label, "補助簿")
        XCTAssertEqual(ExportCoordinator.ExportTarget.etax.label, "e-Tax")
        XCTAssertEqual(ExportCoordinator.ExportTarget.withholdingStatement.label, "支払調書")
        XCTAssertEqual(ExportCoordinator.ExportTarget.fixedAssetRegister.label, "固定資産台帳")
        XCTAssertEqual(ExportCoordinator.ExportTarget.fixedAssetDepreciation.label, "減価償却明細表")
        XCTAssertEqual(ExportCoordinator.ExportTarget.legacyLedgerBook.label, "旧台帳（互換）")
    }

    func testExportFormatExtensions() {
        XCTAssertEqual(ExportCoordinator.ExportFormat.csv.fileExtension, "csv")
        XCTAssertEqual(ExportCoordinator.ExportFormat.pdf.fileExtension, "pdf")
        XCTAssertEqual(ExportCoordinator.ExportFormat.xtx.fileExtension, "xtx")
        XCTAssertEqual(ExportCoordinator.ExportFormat.xlsx.fileExtension, "xlsx")
        XCTAssertEqual(ExportCoordinator.ExportFormat.csv.label, "CSV")
        XCTAssertEqual(ExportCoordinator.ExportFormat.pdf.label, "PDF")
        XCTAssertEqual(ExportCoordinator.ExportFormat.xtx.label, "XTX")
        XCTAssertEqual(ExportCoordinator.ExportFormat.xlsx.label, "Excel")
    }

    func testSupportedFormatMatrixMatchesCurrentUIFlow() {
        XCTAssertEqual(ExportCoordinator.ExportTarget.profitLoss.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.balanceSheet.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.trialBalance.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.cashBook.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.bankAccountBook.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.accountsReceivableBook.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.accountsPayableBook.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.expenseBook.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.generalLedger.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.journalBook.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.transportationExpense.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.whiteTaxBookkeeping.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.journal.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.ledger.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.fixedAssetRegister.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.fixedAssetDepreciation.supportedFormats, [.csv, .pdf, .xlsx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.withholdingStatement.supportedFormats, [.csv, .pdf])
        XCTAssertEqual(ExportCoordinator.ExportTarget.transactions.supportedFormats, [.csv])
        XCTAssertEqual(ExportCoordinator.ExportTarget.subLedger.supportedFormats, [.csv, .pdf])
        XCTAssertEqual(ExportCoordinator.ExportTarget.etax.supportedFormats, [.csv, .xtx])
        XCTAssertEqual(ExportCoordinator.ExportTarget.legacyLedgerBook.supportedFormats, [.csv, .pdf, .xlsx])
    }

    func testRequiresPreflightBoundaries() {
        XCTAssertTrue(ExportCoordinator.ExportTarget.profitLoss.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.balanceSheet.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.trialBalance.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.cashBook.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.bankAccountBook.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.accountsReceivableBook.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.accountsPayableBook.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.expenseBook.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.generalLedger.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.journalBook.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.transportationExpense.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.whiteTaxBookkeeping.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.journal.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.ledger.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.fixedAssetRegister.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.fixedAssetDepreciation.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.etax.requiresPreflight)
        XCTAssertTrue(ExportCoordinator.ExportTarget.withholdingStatement.requiresPreflight)
        XCTAssertFalse(ExportCoordinator.ExportTarget.transactions.requiresPreflight)
        XCTAssertFalse(ExportCoordinator.ExportTarget.subLedger.requiresPreflight)
        XCTAssertFalse(ExportCoordinator.ExportTarget.legacyLedgerBook.requiresPreflight)
    }

    func testExportBlocksWhenPreflightFails() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        XCTAssertThrowsError(
            try ExportCoordinator.export(
                target: .trialBalance,
                format: .csv,
                fiscalYear: 2025,
                modelContext: context
            )
        ) { error in
            guard let exportError = error as? ExportCoordinator.ExportError,
                  case .preflightBlocked(let messages) = exportError
            else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(messages, ["帳票出力は税務締め以降でのみ実行できます"])
        }
    }

    func testUnsupportedFormatReturnsUnsupportedEvenWhenPreflightWouldFail() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)
        assertUnsupportedFormat(target: .trialBalance, format: .xtx, fiscalYear: 2025)
        assertUnsupportedFormat(target: .ledger, format: .xtx, fiscalYear: 2025)
        assertUnsupportedFormat(target: .etax, format: .pdf, fiscalYear: 2025)
        assertUnsupportedFormat(target: .transactions, format: .pdf, fiscalYear: 2025)
        assertUnsupportedFormat(target: .transportationExpense, format: .xtx, fiscalYear: 2025)
    }

    func testSubLedgerExportDoesNotRequirePreflight() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        let url = try ExportCoordinator.export(
            target: .subLedger,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context,
            subLedgerOptions: .init(
                type: .cashBook,
                startDate: nil,
                endDate: nil,
                accountFilter: nil,
                counterpartyFilter: nil
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("date,accountCode,accountName"))
    }

    func testExportSucceedsAfterTaxClose() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)

        let url = try ExportCoordinator.export(
            target: .trialBalance,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        XCTAssertFalse(data.isEmpty)
    }

    func testLedgerExportStillRequiresAccountOptionAfterPreflightPasses() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)

        XCTAssertThrowsError(
            try ExportCoordinator.export(
                target: .ledger,
                format: .pdf,
                fiscalYear: 2025,
                modelContext: context
            )
        ) { error in
            guard let exportError = error as? ExportCoordinator.ExportError,
                  case .ledgerAccountRequired = exportError
            else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testTransactionsExportDoesNotRequirePreflight() throws {
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1_200,
            date: makeDate(year: 2025, month: 1, day: 10),
            categoryId: "cat-tools",
            memo: "export target",
            allocations: []
        )

        let url = try ExportCoordinator.export(
            target: .transactions,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context,
            transactionOptions: .init(transactions: dataStore.transactions)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("export target"))
    }

    func testOfficialCashBookExportUsesLedgerFormat() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5_000,
            date: makeDate(year: 2025, month: 2, day: 4),
            categoryId: "cat-tools",
            memo: "cash book export",
            allocations: []
        )

        let url = try ExportCoordinator.export(
            target: .cashBook,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context,
            skipPreflightValidation: true,
            subLedgerOptions: .init(
                type: .cashBook,
                startDate: nil,
                endDate: nil,
                accountFilter: nil,
                counterpartyFilter: nil
            )
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("月,日,摘要,勘定科目"))
        XCTAssertTrue(text.contains("cash book export"))
    }

    func testOfficialCashBookExportProvidesXlsx() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5_000,
            date: makeDate(year: 2025, month: 2, day: 4),
            categoryId: "cat-tools",
            memo: "cash book xlsx export",
            allocations: []
        )

        let url = try ExportCoordinator.export(
            target: .cashBook,
            format: .xlsx,
            fiscalYear: 2025,
            modelContext: context,
            skipPreflightValidation: true,
            subLedgerOptions: .init(
                type: .cashBook,
                startDate: nil,
                endDate: nil,
                accountFilter: nil,
                counterpartyFilter: nil
            )
        )

        assertXlsxArchive(at: url)
    }

    func testOfficialBankAccountBookExportProvidesXlsx() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 12_000,
            date: makeDate(year: 2025, month: 2, day: 8),
            categoryId: "cat-sales",
            memo: "bank account xlsx export",
            allocations: []
        )

        let url = try ExportCoordinator.export(
            target: .bankAccountBook,
            format: .xlsx,
            fiscalYear: 2025,
            modelContext: context,
            skipPreflightValidation: true,
            subLedgerOptions: .init(
                type: .depositBook,
                startDate: nil,
                endDate: nil,
                accountFilter: nil,
                counterpartyFilter: nil
            )
        )

        assertXlsxArchive(at: url)
    }

    func testOfficialAccountsReceivableBookExportProvidesXlsx() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 18_000,
            date: makeDate(year: 2025, month: 3, day: 3),
            categoryId: "cat-sales",
            memo: "accounts receivable xlsx export",
            allocations: []
        )

        let url = try ExportCoordinator.export(
            target: .accountsReceivableBook,
            format: .xlsx,
            fiscalYear: 2025,
            modelContext: context,
            skipPreflightValidation: true,
            subLedgerOptions: .init(
                type: .accountsReceivableBook,
                startDate: nil,
                endDate: nil,
                accountFilter: nil,
                counterpartyFilter: nil
            )
        )

        assertXlsxArchive(at: url)
    }

    func testOfficialAccountsPayableBookExportProvidesXlsx() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 7_500,
            date: makeDate(year: 2025, month: 3, day: 7),
            categoryId: "cat-tools",
            memo: "accounts payable xlsx export",
            allocations: []
        )

        let url = try ExportCoordinator.export(
            target: .accountsPayableBook,
            format: .xlsx,
            fiscalYear: 2025,
            modelContext: context,
            skipPreflightValidation: true,
            subLedgerOptions: .init(
                type: .accountsPayableBook,
                startDate: nil,
                endDate: nil,
                accountFilter: nil,
                counterpartyFilter: nil
            )
        )

        assertXlsxArchive(at: url)
    }

    func testOfficialExpenseBookExportProvidesXlsx() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 4_200,
            date: makeDate(year: 2025, month: 4, day: 2),
            categoryId: "cat-tools",
            memo: "expense book xlsx export",
            allocations: []
        )

        let url = try ExportCoordinator.export(
            target: .expenseBook,
            format: .xlsx,
            fiscalYear: 2025,
            modelContext: context,
            skipPreflightValidation: true,
            subLedgerOptions: .init(
                type: .expenseBook,
                startDate: nil,
                endDate: nil,
                accountFilter: "acct-tools",
                counterpartyFilter: nil
            )
        )

        assertXlsxArchive(at: url)
    }

    func testOfficialGeneralLedgerExportProvidesXlsx() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)

        _ = createApprovedCanonicalJournal(
            debitLegacyAccountId: "acct-rent",
            creditLegacyAccountId: AccountingConstants.cashAccountId,
            amount: 12_000,
            year: 2025,
            month: 2,
            description: "general ledger xlsx export",
            entryType: .normal,
            sourceCandidateId: UUID()
        )

        let url = try ExportCoordinator.export(
            target: .generalLedger,
            format: .xlsx,
            fiscalYear: 2025,
            modelContext: context,
            ledgerOptions: .init(accountId: "acct-rent", accountName: "地代家賃", accountCode: "622")
        )

        assertXlsxArchive(at: url)
    }

    func testOfficialJournalBookExportProvidesXlsx() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)

        _ = createApprovedCanonicalJournal(
            debitLegacyAccountId: "acct-rent",
            creditLegacyAccountId: AccountingConstants.cashAccountId,
            amount: 8_000,
            year: 2025,
            month: 2,
            description: "journal book xlsx export",
            entryType: .normal,
            sourceCandidateId: UUID()
        )

        let url = try ExportCoordinator.export(
            target: .journalBook,
            format: .xlsx,
            fiscalYear: 2025,
            modelContext: context
        )

        assertXlsxArchive(at: url)
    }

    func testWhiteTaxBookkeepingOfficialExportProvidesCsv() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 50_000,
            date: makeDate(year: 2025, month: 3, day: 10),
            categoryId: "cat-sales",
            memo: "white tax export",
            allocations: []
        )

        let url = try ExportCoordinator.export(
            target: .whiteTaxBookkeeping,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context,
            skipPreflightValidation: true
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("売上金額"))
        XCTAssertTrue(text.contains("2025年分"))
    }

    func testWhiteTaxBookkeepingOfficialExportProvidesXlsx() throws {
        seedTaxYearProfile(year: 2025, state: .softClose)

        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 50_000,
            date: makeDate(year: 2025, month: 3, day: 10),
            categoryId: "cat-sales",
            memo: "white tax xlsx export",
            allocations: []
        )

        let url = try ExportCoordinator.export(
            target: .whiteTaxBookkeeping,
            format: .xlsx,
            fiscalYear: 2025,
            modelContext: context,
            skipPreflightValidation: true
        )

        assertXlsxArchive(at: url)
    }

    func testTransportationExpenseOfficialExportUsesSelectedLegacyBook() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)
        let book = seedLegacyTransportationExpenseBook()

        let url = try ExportCoordinator.export(
            target: .transportationExpense,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context,
            ledgerBookSelectionOptions: .init(bookId: book.id, ledgerType: .transportationExpense)
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("日付,行先,目的（用件）"))
    }

    func testTransportationExpenseOfficialExportProvidesXlsx() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)
        let book = seedLegacyTransportationExpenseBook()

        let url = try ExportCoordinator.export(
            target: .transportationExpense,
            format: .xlsx,
            fiscalYear: 2025,
            modelContext: context,
            ledgerBookSelectionOptions: .init(bookId: book.id, ledgerType: .transportationExpense)
        )

        assertXlsxArchive(at: url)
    }

    func testFixedAssetDepreciationOfficialExportMatchesSpecColumnsAndValues() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)
        seedFixedAsset(
            name: "MacBook Pro",
            acquisitionCost: 360_000,
            usefulLifeYears: 4,
            year: 2025,
            month: 1,
            day: 10
        )

        let url = try ExportCoordinator.export(
            target: .fixedAssetDepreciation,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context
        )

        let lines = normalizedCSVLines(from: url)
        XCTAssertEqual(lines[0], "年分,2025年分")
        XCTAssertEqual(
            lines[1],
            "勘定科目,資産コード,資産名,資産の種類,状態,数量,取得日,取得価額,償却方法,耐用年数,償却率,償却月数,期首帳簿価額,期中増減,減価償却費,特別(割増)償却費,償却費合計,事業専用割合,必要経費算入額,本年末残高,摘要"
        )
        XCTAssertTrue(lines[2].contains("減価償却費"))
        XCTAssertTrue(lines[2].contains("MacBook Pro"))
        XCTAssertTrue(lines[2].contains("定額法"))
        XCTAssertTrue(lines[2].contains("0.250"))
        XCTAssertTrue(lines[2].contains("89999"))
        XCTAssertTrue(lines[2].contains("270001"))
    }

    func testFixedAssetRegisterOfficialExportMatchesSpecColumnsAndValues() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)
        seedFixedAsset(
            name: "MacBook Pro",
            acquisitionCost: 300_000,
            usefulLifeYears: 5,
            businessUsePercent: 80,
            year: 2025,
            month: 1,
            day: 1,
            memo: "register export asset"
        )

        let url = try ExportCoordinator.export(
            target: .fixedAssetRegister,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context
        )

        let lines = normalizedCSVLines(from: url)
        XCTAssertEqual(lines[0], "名称,MacBook Pro")
        XCTAssertTrue(lines[1].hasPrefix("番号,"))
        XCTAssertEqual(lines[2], "種類,固定資産")
        XCTAssertEqual(lines[3], "取得年月日,2025/01/01")
        XCTAssertEqual(lines[4], "耐用年数,5")
        XCTAssertEqual(lines[5], "償却方法,定額法")
        XCTAssertEqual(lines[6], "償却率,0.200")
        XCTAssertEqual(lines[7], "年月日,摘要,取得数量,取得単価,取得金額,償却額,異動数量,異動金額,現在数量,現在金額,事業専用割合,必要経費算入額,備考")
        XCTAssertEqual(lines[8], "2025/01/01,MacBook Pro,1,300000,300000,59999,,,1,300000,0.80,47999,register export asset")
    }

    func testFixedAssetDepreciationPdfContainsFullSpecHeaders() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)
        seedFixedAsset(
            name: "MacBook Pro",
            acquisitionCost: 360_000,
            usefulLifeYears: 4,
            year: 2025,
            month: 1,
            day: 10
        )

        let url = try ExportCoordinator.export(
            target: .fixedAssetDepreciation,
            format: .pdf,
            fiscalYear: 2025,
            modelContext: context
        )

        let text = pdfText(from: url)
        XCTAssertTrue(text.contains("固定資産台帳 兼 減価償却計算表"))
        XCTAssertTrue(text.contains("年分: 2025年分"))
        XCTAssertTrue(text.contains("資産コード"))
        XCTAssertTrue(text.contains("特別(割増)償却費"))
        XCTAssertTrue(text.contains("必要経費算入額"))
        XCTAssertTrue(text.contains("本年末残高"))
        XCTAssertTrue(text.contains("MacBook Pro"))
    }

    func testFixedAssetExportPreservesAllDepreciationMethodLabels() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)
        seedFixedAsset(name: "定額", acquisitionCost: 300_000, usefulLifeYears: 5, depreciationMethod: .straightLine, year: 2025, month: 1, day: 1)
        seedFixedAsset(name: "定率", acquisitionCost: 300_000, usefulLifeYears: 5, depreciationMethod: .decliningBalance, year: 2025, month: 1, day: 1)
        seedFixedAsset(name: "少額一括", acquisitionCost: 90_000, usefulLifeYears: 5, depreciationMethod: .immediateExpense, year: 2025, month: 1, day: 1)
        seedFixedAsset(name: "3年均等", acquisitionCost: 150_000, usefulLifeYears: 3, depreciationMethod: .threeYearEqual, year: 2025, month: 1, day: 1)
        seedFixedAsset(name: "少額特例", acquisitionCost: 280_000, usefulLifeYears: 5, depreciationMethod: .smallBusiness, year: 2025, month: 1, day: 1)

        let url = try ExportCoordinator.export(
            target: .fixedAssetDepreciation,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context
        )

        let joined = normalizedCSVLines(from: url).joined(separator: "\n")
        XCTAssertTrue(joined.contains("定額法"))
        XCTAssertTrue(joined.contains("定率法"))
        XCTAssertTrue(joined.contains("少額一括"))
        XCTAssertTrue(joined.contains("一括償却（3年均等）"))
        XCTAssertTrue(joined.contains("少額減価償却資産特例"))
    }

    func testCanonicalOnlyBookExportsExcludeOrphanLegacySupplementals() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)

        _ = createApprovedCanonicalJournal(
            debitLegacyAccountId: "acct-rent",
            creditLegacyAccountId: AccountingConstants.cashAccountId,
            amount: 12_000,
            year: 2025,
            month: 2,
            description: "Canonical Manual Export",
            entryType: .normal,
            sourceCandidateId: UUID()
        )
        _ = createApprovedCanonicalJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.ownerCapitalAccountId,
            amount: 50_000,
            year: 2025,
            month: 1,
            description: "Canonical Opening Export",
            entryType: .opening
        )
        _ = createApprovedCanonicalJournal(
            debitLegacyAccountId: AccountingConstants.salesAccountId,
            creditLegacyAccountId: AccountingConstants.ownerCapitalAccountId,
            amount: 8_000,
            year: 2025,
            month: 12,
            description: "Canonical Closing Export",
            entryType: .closing
        )
        insertOrphanLegacySupplementalEntry(
            sourceKey: "manual:\(UUID().uuidString)",
            memo: "Orphan Legacy Supplemental",
            debitAccountId: "acct-rent",
            creditAccountId: AccountingConstants.cashAccountId,
            amount: 9_999,
            year: 2025,
            month: 3
        )
        insertOrphanLegacySupplementalEntry(
            sourceKey: "depreciation:\(UUID().uuidString):2025",
            memo: "Legacy Depreciation Supplemental",
            debitAccountId: AccountingConstants.depreciationExpenseAccountId,
            creditAccountId: AccountingConstants.accumulatedDepreciationAccountId,
            amount: 60_000,
            year: 2025,
            month: 4
        )

        let journalURL = try ExportCoordinator.export(
            target: .journal,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context
        )
        let ledgerURL = try ExportCoordinator.export(
            target: .ledger,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context,
            ledgerOptions: .init(accountId: "acct-rent", accountName: "地代家賃", accountCode: "622")
        )
        let subLedgerURL = try ExportCoordinator.export(
            target: .subLedger,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context,
            subLedgerOptions: .init(
                type: .expenseBook,
                startDate: nil,
                endDate: nil,
                accountFilter: "acct-rent",
                counterpartyFilter: nil
            )
        )

        let journalCSV = try String(contentsOf: journalURL, encoding: .utf8)
        let ledgerCSV = try String(contentsOf: ledgerURL, encoding: .utf8)
        let subLedgerCSV = try String(contentsOf: subLedgerURL, encoding: .utf8)

        XCTAssertTrue(journalCSV.contains("Canonical Manual Export"))
        XCTAssertTrue(journalCSV.contains("Canonical Opening Export"))
        XCTAssertTrue(journalCSV.contains("Canonical Closing Export"))
        XCTAssertFalse(journalCSV.contains("Orphan Legacy Supplemental"))

        XCTAssertTrue(ledgerCSV.contains("Canonical Manual Export"))
        XCTAssertFalse(ledgerCSV.contains("Orphan Legacy Supplemental"))

        XCTAssertTrue(subLedgerCSV.contains("Canonical Manual Export"))
        XCTAssertFalse(subLedgerCSV.contains("Orphan Legacy Supplemental"))
        XCTAssertFalse(journalCSV.contains("減価償却費"))
        XCTAssertFalse(ledgerCSV.contains("減価償却費"))
        XCTAssertFalse(subLedgerCSV.contains("減価償却費"))
    }

    func testBookExportsMatchCanonicalReadModelsOnSharedFixture() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)

        _ = createApprovedCanonicalJournal(
            debitLegacyAccountId: "acct-rent",
            creditLegacyAccountId: AccountingConstants.cashAccountId,
            amount: 12_000,
            year: 2025,
            month: 2,
            description: "Canonical Manual Export",
            entryType: .normal,
            sourceCandidateId: UUID()
        )
        _ = createApprovedCanonicalJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.ownerCapitalAccountId,
            amount: 50_000,
            year: 2025,
            month: 1,
            description: "Canonical Opening Export",
            entryType: .opening
        )
        _ = createApprovedCanonicalJournal(
            debitLegacyAccountId: AccountingConstants.salesAccountId,
            creditLegacyAccountId: AccountingConstants.ownerCapitalAccountId,
            amount: 8_000,
            year: 2025,
            month: 12,
            description: "Canonical Closing Export",
            entryType: .closing
        )
        insertOrphanLegacySupplementalEntry(
            sourceKey: "manual:\(UUID().uuidString)",
            memo: "Orphan Legacy Supplemental",
            debitAccountId: "acct-rent",
            creditAccountId: AccountingConstants.cashAccountId,
            amount: 9_999,
            year: 2025,
            month: 3
        )
        insertOrphanLegacySupplementalEntry(
            sourceKey: "depreciation:\(UUID().uuidString):2025",
            memo: "Legacy Depreciation Supplemental",
            debitAccountId: AccountingConstants.depreciationExpenseAccountId,
            creditAccountId: AccountingConstants.accumulatedDepreciationAccountId,
            amount: 90_000,
            year: 2025,
            month: 4
        )

        let support = AccountingReadSupport(modelContext: context)
        let projected = support.projectedCanonicalJournals(fiscalYear: 2025)

        let journalURL = try ExportCoordinator.export(
            target: .journal,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context
        )
        let ledgerURL = try ExportCoordinator.export(
            target: .ledger,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context,
            ledgerOptions: .init(accountId: "acct-rent", accountName: "地代家賃", accountCode: "622")
        )
        let subLedgerURL = try ExportCoordinator.export(
            target: .subLedger,
            format: .csv,
            fiscalYear: 2025,
            modelContext: context,
            subLedgerOptions: .init(
                type: .expenseBook,
                startDate: nil,
                endDate: nil,
                accountFilter: "acct-rent",
                counterpartyFilter: nil
            )
        )

        let journalCSV = try String(contentsOf: journalURL, encoding: .utf8)
        let ledgerCSV = try String(contentsOf: ledgerURL, encoding: .utf8)
        let subLedgerCSV = try String(contentsOf: subLedgerURL, encoding: .utf8)

        XCTAssertEqual(csvDataRowCount(journalCSV), projected.lines.count)
        XCTAssertEqual(csvDataRowCount(ledgerCSV), 1)
        XCTAssertEqual(csvDataRowCount(subLedgerCSV), 1)

        XCTAssertTrue(journalCSV.contains("manual:"))
        XCTAssertTrue(journalCSV.contains("opening:"))
        XCTAssertTrue(journalCSV.contains("closing:"))
        XCTAssertTrue(journalCSV.contains("Canonical Manual Export"))
        XCTAssertTrue(journalCSV.contains("Canonical Opening Export"))
        XCTAssertTrue(journalCSV.contains("Canonical Closing Export"))
        XCTAssertTrue(ledgerCSV.contains("Canonical Manual Export"))
        XCTAssertTrue(subLedgerCSV.contains("Canonical Manual Export"))
        XCTAssertTrue(subLedgerCSV.contains("Canonical Manual Export"))

        XCTAssertFalse(journalCSV.contains("Orphan Legacy Supplemental"))
        XCTAssertFalse(journalCSV.contains("Legacy Depreciation Supplemental"))
        XCTAssertFalse(ledgerCSV.contains("Orphan Legacy Supplemental"))
        XCTAssertFalse(ledgerCSV.contains("Legacy Depreciation Supplemental"))
        XCTAssertFalse(subLedgerCSV.contains("Orphan Legacy Supplemental"))
        XCTAssertFalse(subLedgerCSV.contains("Legacy Depreciation Supplemental"))
    }

    func testEtaxExportRequiresFormOptionAfterPreflightPasses() throws {
        seedTaxYearProfile(year: 2025, state: .taxClose)

        XCTAssertThrowsError(
            try ExportCoordinator.export(
                target: .etax,
                format: .xtx,
                fiscalYear: 2025,
                modelContext: context
            )
        ) { error in
            guard let exportError = error as? ExportCoordinator.ExportError,
                  case .etaxFormRequired = exportError
            else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testLegacyLedgerCsvExportUsesCoordinator() throws {
        let book = seedLegacyCashBook()

        let url = try ExportCoordinator.export(
            format: .csv,
            modelContext: context,
            legacyLedgerOptions: makeLegacyLedgerOptions(book: book)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertTrue(text.contains("月,日,摘要,勘定科目,入金,出金,残高"))
        XCTAssertTrue(text.contains("売上"))
    }

    func testLegacyLedgerPdfExportUsesCoordinator() throws {
        let book = seedLegacyCashBook()

        let url = try ExportCoordinator.export(
            format: .pdf,
            modelContext: context,
            legacyLedgerOptions: makeLegacyLedgerOptions(book: book)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "%PDF")
    }

    func testLegacyLedgerXlsxExportUsesCoordinator() throws {
        let book = seedLegacyCashBook()

        let url = try ExportCoordinator.export(
            format: .xlsx,
            modelContext: context,
            legacyLedgerOptions: makeLegacyLedgerOptions(book: book)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: data.prefix(2), as: UTF8.self), "PK")
    }

    func testLegacyLedgerRejectsUnsupportedXlsxForExpenseBook() {
        let book = seedLegacyExpenseBook()

        XCTAssertThrowsError(
            try ExportCoordinator.export(
                format: .xlsx,
                modelContext: context,
                legacyLedgerOptions: makeLegacyLedgerOptions(book: book)
            )
        ) { error in
            guard let exportError = error as? ExportCoordinator.ExportError,
                  case .unsupportedFormat(let target, let format) = exportError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(target, .legacyLedgerBook)
            XCTAssertEqual(format, .xlsx)
        }
    }

    func testLegacyLedgerRejectsUnsupportedCsvForTransportationExpense() {
        let book = seedLegacyTransportationExpenseBook()

        XCTAssertThrowsError(
            try ExportCoordinator.export(
                format: .csv,
                modelContext: context,
                legacyLedgerOptions: makeLegacyLedgerOptions(book: book)
            )
        ) { error in
            guard let exportError = error as? ExportCoordinator.ExportError,
                  case .unsupportedFormat(let target, let format) = exportError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(target, .legacyLedgerBook)
            XCTAssertEqual(format, .csv)
        }
    }

    func testMaterializeReportXLSXGoldenFixtures() throws {
        let outputDirectory = try makeReportGoldenOutputDirectory()

        try materializeReportFixture(target: .profitLoss, fiscalYear: 2025, outputDirectory: outputDirectory)
        try materializeReportFixture(target: .balanceSheet, fiscalYear: 2025, outputDirectory: outputDirectory)
        try materializeReportFixture(target: .trialBalance, fiscalYear: 2025, outputDirectory: outputDirectory)
        try materializeReportFixture(target: .journal, fiscalYear: 2025, outputDirectory: outputDirectory)
        try materializeReportFixture(
            target: .ledger,
            fiscalYear: 2025,
            outputDirectory: outputDirectory,
            ledgerOptions: .init(accountId: "acct-cash", accountName: "現金", accountCode: "101")
        )
        try materializeReportFixture(target: .fixedAssetRegister, fiscalYear: 2025, outputDirectory: outputDirectory)
        try materializeReportFixture(target: .fixedAssetDepreciation, fiscalYear: 2025, outputDirectory: outputDirectory)
    }

    private func seedTaxYearProfile(year: Int, state: YearLockState) {
        let profile = TaxYearProfile(
            businessId: businessId,
            taxYear: year,
            yearLockState: state,
            taxPackVersion: "\(year)-v1"
        )
        context.insert(TaxYearProfileEntityMapper.toEntity(profile))
        try! context.save()
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makeReportGoldenOutputDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = root.appendingPathComponent(".golden-generated-xlsx", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func materializeReportFixture(
        target: ExportCoordinator.ExportTarget,
        fiscalYear: Int,
        outputDirectory: URL,
        ledgerOptions: ExportCoordinator.LedgerExportOptions? = nil
    ) throws {
        seedTaxYearProfile(year: fiscalYear, state: .taxClose)
        let url = try ExportCoordinator.export(
            target: target,
            format: .xlsx,
            fiscalYear: fiscalYear,
            modelContext: context,
            skipPreflightValidation: true,
            ledgerOptions: ledgerOptions
        )
        let destination = outputDirectory.appendingPathComponent("\(target.filePrefix).xlsx")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        let data = try Data(contentsOf: destination)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "xlsx should be a ZIP archive")
    }

    @discardableResult
    private func createApprovedCanonicalJournal(
        debitLegacyAccountId: String,
        creditLegacyAccountId: String,
        amount: Int,
        year: Int,
        month: Int,
        description: String,
        entryType: CanonicalJournalEntryType,
        sourceCandidateId: UUID? = nil
    ) -> CanonicalJournalEntry {
        let journalId = UUID()
        let journalDate = makeDate(year: year, month: month, day: 15)
        let entry = CanonicalJournalEntry(
            id: journalId,
            businessId: businessId,
            taxYear: year,
            journalDate: journalDate,
            voucherNo: VoucherNumber(taxYear: year, month: month, sequence: nextVoucherSequence(for: year)).value,
            sourceCandidateId: sourceCandidateId,
            entryType: entryType,
            description: description,
            lines: [
                JournalLine(
                    journalId: journalId,
                    accountId: canonicalAccountId(debitLegacyAccountId),
                    debitAmount: Decimal(amount),
                    creditAmount: 0,
                    legalReportLineId: canonicalAccount(debitLegacyAccountId).defaultLegalReportLineId,
                    sortOrder: 0
                ),
                JournalLine(
                    journalId: journalId,
                    accountId: canonicalAccountId(creditLegacyAccountId),
                    debitAmount: 0,
                    creditAmount: Decimal(amount),
                    legalReportLineId: canonicalAccount(creditLegacyAccountId).defaultLegalReportLineId,
                    sortOrder: 1
                ),
            ],
            approvedAt: journalDate,
            createdAt: journalDate,
            updatedAt: journalDate
        )
        context.insert(CanonicalJournalEntryEntityMapper.toEntity(entry))
        try! context.save()
        return entry
    }

    private func insertOrphanLegacySupplementalEntry(
        sourceKey: String,
        memo: String,
        debitAccountId: String,
        creditAccountId: String,
        amount: Int,
        year: Int,
        month: Int
    ) {
        let entryId = UUID()
        let date = makeDate(year: year, month: month, day: 20)
        context.insert(
            PPJournalEntry(
                id: entryId,
                sourceKey: sourceKey,
                date: date,
                entryType: .manual,
                memo: memo,
                isPosted: true,
                createdAt: date,
                updatedAt: date
            )
        )
        context.insert(
            PPJournalLine(
                id: UUID(),
                entryId: entryId,
                accountId: debitAccountId,
                debit: amount,
                credit: 0,
                memo: "",
                displayOrder: 0,
                createdAt: date,
                updatedAt: date
            )
        )
        context.insert(
            PPJournalLine(
                id: UUID(),
                entryId: entryId,
                accountId: creditAccountId,
                debit: 0,
                credit: amount,
                memo: "",
                displayOrder: 1,
                createdAt: date,
                updatedAt: date
            )
        )
        try! context.save()
    }

    private func nextVoucherSequence(for taxYear: Int) -> Int {
        let currentBusinessId = businessId!
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.businessId == currentBusinessId && $0.taxYear == taxYear }
        )
        return ((try? context.fetch(descriptor).count) ?? 0) + 1
    }

    private func canonicalAccount(_ legacyAccountId: String) -> CanonicalAccount {
        guard let account = dataStore.canonicalAccounts().first(where: { $0.legacyAccountId == legacyAccountId }) else {
            fatalError("Canonical account not found for \(legacyAccountId)")
        }
        return account
    }

    private func csvDataRowCount(_ text: String) -> Int {
        let normalized = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return 0 }
        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return max(lines.count - 1, 0)
    }

    private func assertXlsxArchive(at url: URL) {
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try! Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "xlsx should be a ZIP archive")
    }

    private func canonicalAccountId(_ legacyAccountId: String) -> UUID {
        canonicalAccount(legacyAccountId).id
    }

    private func assertUnsupportedFormat(
        target: ExportCoordinator.ExportTarget,
        format: ExportCoordinator.ExportFormat,
        fiscalYear: Int
    ) {
        XCTAssertThrowsError(
            try ExportCoordinator.export(
                target: target,
                format: format,
                fiscalYear: fiscalYear,
                modelContext: context
            )
        ) { error in
            guard let exportError = error as? ExportCoordinator.ExportError,
                  case .unsupportedFormat(let actualTarget, let actualFormat) = exportError else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(actualTarget, target)
            XCTAssertEqual(actualFormat, format)
        }
    }

    private func seedLegacyCashBook() -> SDLedgerBook {
        FeatureFlags.useLegacyLedger = true
        let ledgerStore = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        let metadataJSON = LedgerBridge.encodeCashBookMetadata(CashBookMetadata(carryForward: 100_000))
        let book = ledgerStore.createBook(
            ledgerType: .cashBook,
            title: "現金出納帳",
            metadataJSON: metadataJSON
        )!
        ledgerStore.addEntry(
            to: book.id,
            entry: CashBookEntry(
                month: 1,
                day: 5,
                description: "売上",
                account: "売上高",
                income: 50_000
            )
        )
        return book
    }

    private func seedLegacyExpenseBook() -> SDLedgerBook {
        FeatureFlags.useLegacyLedger = true
        let ledgerStore = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        let metadataJSON = LedgerBridge.encodeExpenseBookMetadata(
            ExpenseBookMetadata(accountName: "消耗品費")
        )
        let book = ledgerStore.createBook(
            ledgerType: .expenseBook,
            title: "経費帳",
            metadataJSON: metadataJSON
        )!
        ledgerStore.addEntry(
            to: book.id,
            entry: ExpenseBookEntry(
                month: 1,
                day: 12,
                counterAccount: "現金",
                description: "インク",
                amount: 3_000
            )
        )
        return book
    }

    private func seedLegacyTransportationExpenseBook() -> SDLedgerBook {
        FeatureFlags.useLegacyLedger = true
        let ledgerStore = LedgerDataStore(modelContext: context, accessMode: .readWrite)
        let metadataJSON = LedgerBridge.encodeTransportationExpenseMetadata(
            TransportationExpenseMetadata(year: 2026)
        )
        let book = ledgerStore.createBook(
            ledgerType: .transportationExpense,
            title: "交通費精算書",
            metadataJSON: metadataJSON
        )!
        ledgerStore.addEntry(
            to: book.id,
            entry: TransportationExpenseEntry(
                id: UUID(),
                date: "2026-03-01",
                destination: "都内",
                purpose: "打ち合わせ",
                transportMethod: "電車",
                routeFrom: "新宿",
                routeTo: "渋谷",
                tripType: .roundTrip,
                amount: 880
            )
        )
        return book
    }

    private func seedFixedAsset(
        name: String,
        acquisitionCost: Int,
        usefulLifeYears: Int,
        businessUsePercent: Int = 100,
        depreciationMethod: PPDepreciationMethod = .straightLine,
        year: Int,
        month: Int,
        day: Int,
        memo: String = "export test asset"
    ) {
        context.insert(
            PPFixedAsset(
                name: name,
                acquisitionDate: makeDate(year: year, month: month, day: day),
                acquisitionCost: acquisitionCost,
                usefulLifeYears: usefulLifeYears,
                depreciationMethod: depreciationMethod,
                memo: memo,
                businessUsePercent: businessUsePercent
            )
        )
        try! context.save()
    }

    private func normalizedCSVLines(from url: URL) -> [String] {
        let text = try! String(contentsOf: url, encoding: .utf8)
        return text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func pdfText(from url: URL) -> String {
        let data = try! Data(contentsOf: url)
        let document = PDFDocument(data: data)
        return (0..<(document?.pageCount ?? 0))
            .compactMap { document?.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    private func makeLegacyLedgerOptions(book: SDLedgerBook) -> ExportCoordinator.LegacyLedgerExportOptions {
        ExportCoordinator.LegacyLedgerExportOptions(
            bookId: book.id,
            bookTitle: book.title,
            ledgerType: book.ledgerType!,
            metadataJSON: book.metadataJSON,
            includeInvoice: book.includeInvoice
        )
    }
}
