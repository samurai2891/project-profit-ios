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
            target: .journal, fiscalYear: 2026, format: .csv
        )
        XCTAssertTrue(journalFileName.hasPrefix("journal_2026_"))
        XCTAssertTrue(journalFileName.hasSuffix(".csv"))

        let trialBalanceFileName = ExportCoordinator.makeFileName(
            target: .trialBalance, fiscalYear: 2026, format: .pdf
        )
        XCTAssertTrue(trialBalanceFileName.hasPrefix("trial_balance_2026_"))
        XCTAssertTrue(trialBalanceFileName.hasSuffix(".pdf"))

        let ledgerFileName = ExportCoordinator.makeFileName(
            target: .ledger, fiscalYear: 2026, format: .csv
        )
        XCTAssertTrue(ledgerFileName.hasPrefix("ledger_2026_"))

        let fixedAssetsFileName = ExportCoordinator.makeFileName(
            target: .fixedAssetRegister, fiscalYear: 2026, format: .csv
        )
        XCTAssertTrue(fixedAssetsFileName.hasPrefix("fixed_asset_register_2026_"))

        let etaxFileName = ExportCoordinator.makeFileName(
            target: .etax, fiscalYear: 2025, format: .xtx
        )
        XCTAssertTrue(etaxFileName.hasPrefix("etax_2025_"))
        XCTAssertTrue(etaxFileName.hasSuffix(".xtx"))
    }

    func testExportTargetLabels() {
        XCTAssertEqual(ExportCoordinator.ExportTarget.profitLoss.label, "損益計算書")
        XCTAssertEqual(ExportCoordinator.ExportTarget.balanceSheet.label, "貸借対照表")
        XCTAssertEqual(ExportCoordinator.ExportTarget.trialBalance.label, "残高試算表")
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
        XCTAssertEqual(ExportCoordinator.ExportTarget.profitLoss.supportedFormats, [.csv, .pdf])
        XCTAssertEqual(ExportCoordinator.ExportTarget.balanceSheet.supportedFormats, [.csv, .pdf])
        XCTAssertEqual(ExportCoordinator.ExportTarget.trialBalance.supportedFormats, [.csv, .pdf])
        XCTAssertEqual(ExportCoordinator.ExportTarget.journal.supportedFormats, [.csv, .pdf])
        XCTAssertEqual(ExportCoordinator.ExportTarget.ledger.supportedFormats, [.csv, .pdf])
        XCTAssertEqual(ExportCoordinator.ExportTarget.fixedAssetRegister.supportedFormats, [.csv, .pdf])
        XCTAssertEqual(ExportCoordinator.ExportTarget.fixedAssetDepreciation.supportedFormats, [.pdf])
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
        assertUnsupportedFormat(target: .fixedAssetDepreciation, format: .csv, fiscalYear: 2025)
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
