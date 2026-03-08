import Foundation
import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ReleasePerformanceGateTests: XCTestCase {
    private enum CorpusSize {
        static let search = 1_000
        static let migration = 1_000
    }

    private enum Threshold {
        static let projectionSeconds = 0.75
        static let searchSeconds = 0.80
        static let exportSeconds = 1.50
        static let migrationSeconds = 0.80
    }

    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var businessId: UUID!
    private var previousFiscalYearStartMonth: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousFiscalYearStartMonth = UserDefaults.standard.object(forKey: FiscalYearSettings.userDefaultsKey)
        UserDefaults.standard.set(FiscalYearSettings.defaultStartMonth, forKey: FiscalYearSettings.userDefaultsKey)
        container = try TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        try seedCanonicalAccounts()
    }

    override func tearDownWithError() throws {
        if let previousFiscalYearStartMonth {
            UserDefaults.standard.set(previousFiscalYearStartMonth, forKey: FiscalYearSettings.userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        }
        previousFiscalYearStartMonth = nil
        businessId = nil
        dataStore = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testProjectionGenerationStaysUnderGate() async throws {
        try await seedCanonicalJournals(count: 400, fiscalYear: 2025)
        dataStore.loadData()

        let elapsed = measureSeconds {
            let projected = dataStore.projectedCanonicalJournals(fiscalYear: 2025)
            _ = AccountingReportService.generateTrialBalance(
                fiscalYear: 2025,
                accounts: dataStore.accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: FiscalYearSettings.startMonth
            )
        }

        print("performance.projection.seconds=\(elapsed)")
        XCTAssertLessThan(elapsed, Threshold.projectionSeconds)
    }

    func testSearchQueriesStayUnderGate() async throws {
        try await seedEvidenceAndJournalSearchCorpus(count: CorpusSize.search, fiscalYear: 2025)

        let elapsed = try await measureSecondsAsync {
            _ = try await EvidenceCatalogUseCase(modelContext: context).search(
                EvidenceSearchCriteria(
                    businessId: businessId,
                    counterpartyText: "検索取引先-149"
                )
            )
            _ = try await JournalSearchUseCase(modelContext: context).search(
                criteria: JournalSearchCriteria(
                    businessId: businessId,
                    counterpartyText: "検索取引先-149"
                )
            )
        }

        print("performance.search.seconds=\(elapsed)")
        XCTAssertLessThan(elapsed, Threshold.searchSeconds)
    }

    func testExportGenerationStaysUnderGate() async throws {
        try await seedCanonicalJournals(count: 240, fiscalYear: 2025)
        dataStore.loadData()
        try ensureTaxClose(for: 2025)

        var previewForm: EtaxForm?
        var exportResult: EtaxExportViewModel.ExportResult?
        let elapsed = measureSeconds {
            let viewModel = EtaxExportViewModel(dataStore: dataStore)
            viewModel.fiscalYear = 2025
            viewModel.generatePreview()
            previewForm = viewModel.exportedForm
            viewModel.exportCsv()
            exportResult = viewModel.exportResult
        }

        let form = try XCTUnwrap(previewForm)
        XCTAssertFalse(form.fields.isEmpty)
        switch try XCTUnwrap(exportResult) {
        case .success(let url):
            let data = try Data(contentsOf: url)
            XCTAssertFalse(data.isEmpty)
        case .failure(let message):
            XCTFail(message)
        }

        print("performance.export.seconds=\(elapsed)")
        XCTAssertLessThan(elapsed, Threshold.exportSeconds)
    }

    func testMigrationDryRunStaysUnderGate() async throws {
        try await seedMigrationCorpus(count: CorpusSize.migration, fiscalYear: 2025)

        let elapsed = try measureSecondsThrowing {
            _ = try MigrationReportRunner(modelContext: context).dryRun()
        }

        print("performance.migration.seconds=\(elapsed)")
        XCTAssertLessThan(elapsed, Threshold.migrationSeconds)
    }

    private func seedCanonicalAccounts() throws {
        let specs: [(String, String, String, CanonicalAccountType, NormalBalance)] = [
            (AccountingConstants.cashAccountId, "101", "現金", .asset, .debit),
            (AccountingConstants.bankAccountId, "102", "普通預金", .asset, .debit),
            (AccountingConstants.salesAccountId, "401", "売上高", .revenue, .credit),
            (AccountingConstants.miscExpenseAccountId, "611", "雑費", .expense, .debit),
            (AccountingConstants.inputTaxAccountId, "151", "仮払消費税", .asset, .debit),
            (AccountingConstants.outputTaxAccountId, "251", "仮受消費税", .liability, .credit)
        ]

        let existing = try context.fetch(FetchDescriptor<CanonicalAccountEntity>())
        for (legacyId, code, name, type, balance) in specs {
            if let entity = existing.first(where: { $0.businessId == businessId && $0.legacyAccountId == legacyId }) {
                entity.code = code
                entity.name = name
                entity.accountTypeRaw = type.rawValue
                entity.normalBalanceRaw = balance.rawValue
            } else {
                context.insert(
                    CanonicalAccountEntityMapper.toEntity(
                        CanonicalAccount(
                            businessId: businessId,
                            legacyAccountId: legacyId,
                            code: code,
                            name: name,
                            accountType: type,
                            normalBalance: balance
                        )
                    )
                )
            }
        }
        try context.save()
    }

    private func seedCanonicalJournals(count: Int, fiscalYear: Int) async throws {
        let repository = SwiftDataCanonicalJournalEntryRepository(modelContext: context)
        let cash = try await canonicalAccount(legacyAccountId: AccountingConstants.cashAccountId)
        let sales = try await canonicalAccount(legacyAccountId: AccountingConstants.salesAccountId)
        let outputTax = try await canonicalAccount(legacyAccountId: AccountingConstants.outputTaxAccountId)

        for index in 0..<count {
            let journalId = UUID()
            let taxableAmount = Decimal(10_000 + index)
            let taxAmount = Decimal(1_000 + (index % 10))
            let day = (index % 28) + 1
            let date = makeDate(year: fiscalYear, month: ((index % 12) + 1), day: day)
            try await repository.save(
                CanonicalJournalEntry(
                    id: journalId,
                    businessId: businessId,
                    taxYear: fiscalYear,
                    journalDate: date,
                    voucherNo: "\(fiscalYear)-\(String(format: "%02d", (index % 12) + 1))-\(String(format: "%05d", index + 1))",
                    lines: [
                        JournalLine(
                            journalId: journalId,
                            accountId: cash.id,
                            debitAmount: taxableAmount + taxAmount,
                            creditAmount: 0,
                            sortOrder: 0
                        ),
                        JournalLine(
                            journalId: journalId,
                            accountId: sales.id,
                            debitAmount: 0,
                            creditAmount: taxableAmount,
                            taxCodeId: TaxCode.standard10.rawValue,
                            sortOrder: 1
                        ),
                        JournalLine(
                            journalId: journalId,
                            accountId: outputTax.id,
                            debitAmount: 0,
                            creditAmount: taxAmount,
                            taxCodeId: TaxCode.standard10.rawValue,
                            sortOrder: 2
                        )
                    ],
                    approvedAt: date,
                    createdAt: date,
                    updatedAt: date
                )
            )
        }
    }

    private func seedEvidenceAndJournalSearchCorpus(count: Int, fiscalYear: Int) async throws {
        let evidenceUseCase = EvidenceCatalogUseCase(modelContext: context)
        let journalRepository = SwiftDataCanonicalJournalEntryRepository(modelContext: context)
        let cash = try await canonicalAccount(legacyAccountId: AccountingConstants.cashAccountId)
        let expense = try await canonicalAccount(legacyAccountId: AccountingConstants.miscExpenseAccountId)
        let inputTax = try await canonicalAccount(legacyAccountId: AccountingConstants.inputTaxAccountId)

        for index in 0..<count {
            let evidence = EvidenceDocument(
                businessId: businessId,
                taxYear: fiscalYear,
                sourceType: .camera,
                legalDocumentType: .receipt,
                storageCategory: .electronicTransaction,
                receivedAt: makeDate(year: fiscalYear, month: 1, day: 1),
                issueDate: makeDate(year: fiscalYear, month: ((index % 12) + 1), day: ((index % 28) + 1)),
                originalFilename: "search-\(index).jpg",
                mimeType: "image/jpeg",
                fileHash: "SEARCH-HASH-\(index)",
                originalFilePath: "search-\(index).jpg",
                ocrText: "検索取引先-\(index) SEARCH-HASH-\(index)",
                extractionVersion: "ocr-v1",
                searchTokens: ["検索取引先-\(index)", "SEARCH-HASH-\(index)"],
                structuredFields: EvidenceStructuredFields(
                    counterpartyName: "検索取引先-\(index)",
                    registrationNumber: String(format: "T%013d", index),
                    totalAmount: Decimal(2_000 + index)
                )
            )
            try await evidenceUseCase.save(evidence)

            let journalId = UUID()
            let baseAmount = Decimal(2_000 + index)
            try await journalRepository.save(
                CanonicalJournalEntry(
                    id: journalId,
                    businessId: businessId,
                    taxYear: fiscalYear,
                    journalDate: evidence.issueDate ?? makeDate(year: fiscalYear, month: 1, day: 1),
                    voucherNo: "\(fiscalYear)-S-\(String(format: "%05d", index + 1))",
                    sourceEvidenceId: evidence.id,
                    lines: [
                        JournalLine(
                            journalId: journalId,
                            accountId: expense.id,
                            debitAmount: baseAmount,
                            creditAmount: 0,
                            taxCodeId: TaxCode.standard10.rawValue,
                            sortOrder: 0
                        ),
                        JournalLine(
                            journalId: journalId,
                            accountId: inputTax.id,
                            debitAmount: Decimal(200),
                            creditAmount: 0,
                            taxCodeId: TaxCode.standard10.rawValue,
                            sortOrder: 1
                        ),
                        JournalLine(
                            journalId: journalId,
                            accountId: cash.id,
                            debitAmount: 0,
                            creditAmount: baseAmount + Decimal(200),
                            sortOrder: 2
                        )
                    ],
                    approvedAt: evidence.issueDate,
                    createdAt: evidence.issueDate ?? Date(),
                    updatedAt: evidence.issueDate ?? Date()
                )
            )
        }

        try await JournalSearchUseCase(modelContext: context).rebuildIndex(businessId: businessId, taxYear: fiscalYear)
    }

    private func seedMigrationCorpus(count: Int, fiscalYear: Int) async throws {
        for index in 0..<count {
            context.insert(
                PPTransaction(
                    type: .expense,
                    amount: 1_000 + index,
                    date: makeDate(year: fiscalYear, month: ((index % 12) + 1), day: ((index % 28) + 1)),
                    categoryId: "cat-tools",
                    memo: "migration-\(index)",
                    paymentAccountId: AccountingConstants.cashAccountId,
                    counterparty: "移行取引先-\(index)"
                )
            )
            context.insert(
                PPDocumentRecord(
                    transactionId: nil,
                    documentType: .receipt,
                    storedFileName: "migration-doc-\(index).pdf",
                    originalFileName: "migration-doc-\(index).pdf",
                    mimeType: "application/pdf",
                    fileSize: 100 + index,
                    contentHash: "MIGRATION-HASH-\(index)",
                    issueDate: makeDate(year: fiscalYear, month: 1, day: 1)
                )
            )
        }
        try context.save()
    }

    private func ensureTaxClose(for fiscalYear: Int) throws {
        XCTAssertTrue(dataStore.transitionFiscalYearState(.softClose, for: fiscalYear))
        XCTAssertTrue(dataStore.transitionFiscalYearState(.taxClose, for: fiscalYear))
    }

    private func canonicalAccount(legacyAccountId: String) async throws -> CanonicalAccount {
        let account = try await ChartOfAccountsUseCase(modelContext: context).account(
            businessId: businessId,
            legacyAccountId: legacyAccountId
        )
        return try XCTUnwrap(account)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date!
    }

    private func measureSeconds(_ block: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return CFAbsoluteTimeGetCurrent() - start
    }

    private func measureSecondsThrowing(_ block: () throws -> Void) throws -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        try block()
        return CFAbsoluteTimeGetCurrent() - start
    }

    private func measureSecondsAsync(_ block: () async throws -> Void) async throws -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        try await block()
        return CFAbsoluteTimeGetCurrent() - start
    }
}
