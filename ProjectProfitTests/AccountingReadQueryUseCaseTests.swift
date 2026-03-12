import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class AccountingReadQueryUseCaseTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!
    var businessId: UUID!
    var canonicalAccounts: [CanonicalAccount]!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        businessId = dataStore.businessProfile?.id
        canonicalAccounts = dataStore.canonicalAccounts()
        XCTAssertNotNil(businessId)
        XCTAssertFalse(canonicalAccounts.isEmpty)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FiscalYearSettings.userDefaultsKey)
        canonicalAccounts = nil
        businessId = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testAccountingHomeSnapshotTracksUnpostedAndSuspenseBalance() {
        let useCase = AccountingHomeQueryUseCase(modelContext: context)
        let baseline = useCase.snapshot()

        _ = mutations(dataStore).addManualJournalEntry(
            date: makeDate(year: 2025, month: 1, day: 10),
            memo: "unposted suspense",
            lines: [
                (accountId: AccountingConstants.suspenseAccountId, debit: 1_200, credit: 0, memo: "")
            ]
        )

        let snapshot = useCase.snapshot()
        XCTAssertEqual(snapshot.unpostedJournalCount, baseline.unpostedJournalCount + 1)
        XCTAssertEqual(snapshot.suspenseBalance, baseline.suspenseBalance + 1_200)
        XCTAssertEqual(snapshot.totalJournalEntries, baseline.totalJournalEntries + 1)
        XCTAssertEqual(snapshot.totalAccounts, dataStore.accounts.filter(\.isActive).count)
        XCTAssertTrue(snapshot.isBootstrapped)
    }

    func testAccountingReportBundleMatchesProjectedCanonicalJournals() {
        let project = mutations(dataStore).addProject(name: "Report Project", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 120_000,
            date: makeDate(year: 2025, month: 5, day: 10),
            categoryId: "cat-sales",
            memo: "income",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: AccountingConstants.cashAccountId
        )
        _ = mutations(dataStore).addManualJournalEntry(
            date: makeDate(year: 2025, month: 5, day: 20),
            memo: "manual supplemental",
            lines: [
                (accountId: "acct-rent", debit: 30_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 30_000, memo: ""),
            ]
        )

        let projected = dataStore.projectedCanonicalJournals(fiscalYear: 2025)
        let expectedTrialBalance = AccountingReportService.generateTrialBalance(
            fiscalYear: 2025,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines,
            startMonth: FiscalYearSettings.startMonth
        )
        let expectedProfitLoss = AccountingReportService.generateProfitLoss(
            fiscalYear: 2025,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines,
            startMonth: FiscalYearSettings.startMonth
        )
        let expectedBalanceSheet = AccountingReportService.generateBalanceSheet(
            fiscalYear: 2025,
            accounts: dataStore.accounts,
            journalEntries: projected.entries,
            journalLines: projected.lines,
            startMonth: FiscalYearSettings.startMonth
        )

        let bundle = AccountingReportQueryUseCase(modelContext: context).reportBundle(fiscalYear: 2025)

        XCTAssertEqual(bundle.trialBalance.rows.map(\.id), expectedTrialBalance.rows.map(\.id))
        XCTAssertEqual(bundle.trialBalance.debitTotal, expectedTrialBalance.debitTotal)
        XCTAssertEqual(bundle.trialBalance.creditTotal, expectedTrialBalance.creditTotal)
        XCTAssertEqual(bundle.profitLoss.totalRevenue, expectedProfitLoss.totalRevenue)
        XCTAssertEqual(bundle.profitLoss.totalExpenses, expectedProfitLoss.totalExpenses)
        XCTAssertEqual(bundle.balanceSheet.totalAssets, expectedBalanceSheet.totalAssets)
        XCTAssertEqual(bundle.balanceSheet.liabilitiesAndEquity, expectedBalanceSheet.liabilitiesAndEquity)
    }

    func testJournalReadQueryUseCaseReturnsProjectedEntriesAndSupplementalMatches() {
        let project = mutations(dataStore).addProject(name: "Journal Project", description: "")
        let manualEntry = try! XCTUnwrap(
            mutations(dataStore).addManualJournalEntry(
                date: makeDate(year: 2025, month: 6, day: 5),
                memo: "Manual Journal Match",
                lines: [
                    (accountId: AccountingConstants.cashAccountId, debit: 50_000, credit: 0, memo: "cash"),
                    (accountId: AccountingConstants.salesAccountId, debit: 0, credit: 50_000, memo: "sales"),
                ]
            )
        )

        let useCase = JournalReadQueryUseCase(modelContext: context)
        let snapshot = useCase.listSnapshot(fiscalYear: 2025)
        XCTAssertEqual(snapshot.businessId, businessId)
        XCTAssertTrue(snapshot.projects.contains(where: { $0.id == project.id }))
        XCTAssertTrue(snapshot.entries.contains(where: { $0.id == manualEntry.id }))

        let detail = useCase.detailSnapshot(entryId: manualEntry.id, fiscalYear: 2025)
        XCTAssertEqual(detail.lines.map(\.displayOrder), [0, 1])
        XCTAssertEqual(detail.lines.first?.accountName, "現金")

        let matchIds = useCase.supplementalMatchIds(
            criteria: JournalSearchCriteria(textQuery: "manual journal match"),
            snapshot: snapshot
        )
        XCTAssertTrue(matchIds.contains(manualEntry.id))

        let excluded = useCase.supplementalMatchIds(
            criteria: JournalSearchCriteria(counterpartyText: "相手先"),
            snapshot: snapshot
        )
        XCTAssertFalse(excluded.contains(manualEntry.id))
    }

    func testLedgerQueryUseCaseMatchesLegacyLedgerBalanceAndEntries() {
        let project = mutations(dataStore).addProject(name: "Ledger Project", description: "")
        _ = mutations(dataStore).addTransaction(
            type: .income,
            amount: 50_000,
            date: makeDate(year: 2025, month: 6, day: 1),
            categoryId: "cat-sales",
            memo: "入金",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: AccountingConstants.cashAccountId,
            counterparty: "A社"
        )
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 20_000,
            date: makeDate(year: 2025, month: 6, day: 2),
            categoryId: "cat-supplies",
            memo: "出金",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: AccountingConstants.cashAccountId
        )

        let useCase = LedgerQueryUseCase(modelContext: context)
        let snapshot = useCase.snapshot(accountId: AccountingConstants.cashAccountId)
        let expectedEntries = dataStore.getLedgerEntries(accountId: AccountingConstants.cashAccountId)
        let expectedBalance = dataStore.getAccountBalance(accountId: AccountingConstants.cashAccountId)

        XCTAssertEqual(snapshot.entries.map(\.runningBalance), expectedEntries.map(\.runningBalance))
        XCTAssertEqual(snapshot.entries.map(\.counterparty), expectedEntries.map(\.counterparty))
        XCTAssertEqual(snapshot.balance.debit, expectedBalance.debit)
        XCTAssertEqual(snapshot.balance.credit, expectedBalance.credit)
        XCTAssertEqual(snapshot.balance.balance, expectedBalance.balance)
    }

    func testSubLedgerQueryUseCaseSupportsFilteringAndSummaryUsesAllPeriodEntries() {
        _ = mutations(dataStore).addManualJournalEntry(
            date: makeDate(year: 2025, month: 7, day: 1),
            memo: "rent",
            lines: [
                (accountId: "acct-rent", debit: 8_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 8_000, memo: ""),
            ]
        )
        _ = mutations(dataStore).addManualJournalEntry(
            date: makeDate(year: 2025, month: 7, day: 2),
            memo: "supplies",
            lines: [
                (accountId: "acct-supplies", debit: 3_000, credit: 0, memo: ""),
                (accountId: AccountingConstants.cashAccountId, debit: 0, credit: 3_000, memo: ""),
            ]
        )

        let useCase = SubLedgerQueryUseCase(modelContext: context)
        let snapshot = useCase.snapshot(type: .expenseBook, year: 2025, accountFilter: "acct-rent")
        let expectedAllEntries = dataStore.getSubLedgerEntries(
            type: .expenseBook,
            startDate: makeDate(year: 2025, month: 1, day: 1),
            endDate: makeDate(year: 2025, month: 12, day: 31)
        )

        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertEqual(snapshot.entries.first?.accountId, "acct-rent")
        XCTAssertEqual(snapshot.summary.count, expectedAllEntries.count)
        XCTAssertEqual(snapshot.summary.debitTotal, expectedAllEntries.reduce(0) { $0 + $1.debit })
        XCTAssertTrue(snapshot.expenseAccounts.contains(where: { $0.id == "acct-rent" }))
    }

    func testClosingQueryUseCaseResolvesDisplayLinesAndYearState() throws {
        createApprovedCanonicalJournal(
            debitLegacyAccountId: AccountingConstants.cashAccountId,
            creditLegacyAccountId: AccountingConstants.salesAccountId,
            amount: 100_000,
            year: 2025
        )
        let closingUseCase = ClosingEntryUseCase(modelContext: context)
        _ = try closingUseCase.generate(businessId: businessId, taxYear: 2025)
        try context.save()
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )

        let snapshot = ClosingQueryUseCase(modelContext: context).snapshot(year: 2025)

        XCTAssertEqual(snapshot.businessId, businessId)
        XCTAssertEqual(snapshot.yearState, .taxClose)
        XCTAssertEqual(snapshot.closingEntry?.entryType, .closing)
        XCTAssertFalse(snapshot.displayLines.isEmpty)
        XCTAssertTrue(snapshot.displayLines.contains(where: { $0.accountName == "売上高" }))
    }

    func testFixedAssetQueryUseCaseReturnsBookValueScheduleAndRelatedEntries() {
        let asset = try! XCTUnwrap(
            dataStore.addFixedAsset(
                name: "MacBook Pro",
                acquisitionDate: makeDate(year: 2025, month: 4, day: 1),
                acquisitionCost: 300_000,
                usefulLifeYears: 4
            )
        )
        _ = dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)

        let useCase = FixedAssetQueryUseCase(modelContext: context)
        let listSnapshot = useCase.listSnapshot(currentYear: 2025)
        let detailSnapshot = useCase.detailSnapshot(assetId: asset.id, currentYear: 2025)
        let expectedBookValue = try! XCTUnwrap(dataStore.previewDepreciationSchedule(asset: asset).first?.bookValueAfter)

        XCTAssertEqual(listSnapshot.assets.map(\.id), [asset.id])
        XCTAssertEqual(listSnapshot.bookValueByAssetId[asset.id], expectedBookValue)
        XCTAssertEqual(detailSnapshot.asset?.id, asset.id)
        XCTAssertFalse(detailSnapshot.schedule.isEmpty)
        XCTAssertEqual(detailSnapshot.relatedEntries.count, 1)
    }

    func testInventoryAndClassificationQueryUseCasesReadPersistedRecords() {
        let project = mutations(dataStore).addProject(name: "Classification Project", description: "")
        _ = mutations(dataStore).addInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 250_000,
            closingInventory: 80_000,
            memo: "棚卸"
        )
        _ = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 5_000,
            date: makeDate(year: 2025, month: 8, day: 1),
            categoryId: "cat-tools",
            memo: "AWS 月額利用料",
            allocations: [(projectId: project.id, ratio: 100)]
        )
        let rule = PPUserRule(keyword: "aws", taxLine: .suppliesExpense, priority: 200)
        context.insert(rule)
        try! context.save()

        let inventorySnapshot = InventoryQueryUseCase(modelContext: context).snapshot(fiscalYear: 2025)
        let classificationSnapshot = ClassificationQueryUseCase(modelContext: context).snapshot()
        let matched = classificationSnapshot.results.first {
            $0.transaction.memo == "AWS 月額利用料"
        }

        XCTAssertEqual(inventorySnapshot.record?.openingInventory, 100_000)
        XCTAssertNil(InventoryQueryUseCase(modelContext: context).snapshot(fiscalYear: 2024).record)
        XCTAssertTrue(classificationSnapshot.userRules.contains(where: { $0.id == rule.id }))
        XCTAssertEqual(matched?.result.source, .userRule)
        XCTAssertEqual(matched?.result.taxLine, .suppliesExpense)
    }

    func testAccountingReadSupportResolvesCanonicalClassificationSuggestionAndApprovedCandidateTaxLine() async throws {
        let legacyAccount = PPAccount(
            id: "acct-cloud-communication",
            code: "612",
            name: "クラウド通信費",
            accountType: .expense,
            subtype: .communicationExpense,
            displayOrder: 999
        )
        let category = PPCategory(
            id: "cat-cloud-communication",
            name: "クラウド通信費",
            type: .expense,
            icon: "wifi",
            linkedAccountId: legacyAccount.id
        )
        let rule = PPUserRule(keyword: "aws", taxLine: .communicationExpense, priority: 300)
        context.insert(legacyAccount)
        context.insert(category)
        context.insert(rule)
        try context.save()

        let canonicalAccountId = UUID()
        let canonicalAccount = CanonicalAccount(
            id: canonicalAccountId,
            businessId: businessId,
            legacyAccountId: legacyAccount.id,
            code: "612",
            name: "クラウド通信費",
            accountType: .expense,
            normalBalance: .debit,
            defaultLegalReportLineId: LegalReportLine.communication.rawValue,
            displayOrder: 999
        )
        try await SwiftDataChartOfAccountsRepository(modelContext: context).save(canonicalAccount)

        let support = AccountingReadSupport(modelContext: context)
        let suggestion = support.classificationSuggestion(
            memo: "AWS 月額利用料",
            transactionType: .expense,
            categoryId: "cat-tools"
        )
        let candidate = PostingCandidate(
            businessId: businessId,
            taxYear: 2025,
            candidateDate: makeDate(year: 2025, month: 8, day: 10),
            proposedLines: [
                PostingCandidateLine(
                    debitAccountId: canonicalAccountId,
                    amount: Decimal(1_200),
                    memo: "AWS 月額利用料"
                )
            ],
            status: .approved,
            source: .ocr,
            memo: "AWS 月額利用料"
        )

        XCTAssertEqual(suggestion?.result.source, .userRule)
        XCTAssertEqual(suggestion?.result.taxLine, .communicationExpense)
        XCTAssertEqual(suggestion?.resolvedCategoryId, category.id)
        XCTAssertEqual(support.resolvedTaxLine(forApprovedCandidate: candidate), .communicationExpense)
    }

    func testEtaxExportContextQueryUseCaseReturnsBusinessAndFallbackProfile() {
        seedTaxYearProfile(
            TaxYearProfile(
                businessId: businessId,
                taxYear: 2025,
                yearLockState: .taxClose,
                taxPackVersion: "2025-v1"
            )
        )

        let populated = EtaxExportContextQueryUseCase(modelContext: context).context(fiscalYear: 2025)
        XCTAssertEqual(populated.businessId, businessId)
        XCTAssertEqual(populated.fallbackTaxYearProfile?.taxYear, 2025)

        let emptyContainer = try! TestModelContainer.create()
        let emptyContext = ModelContext(emptyContainer)
        let empty = EtaxExportContextQueryUseCase(modelContext: emptyContext).context(fiscalYear: 2025)
        XCTAssertNil(empty.businessId)
        XCTAssertNil(empty.fallbackTaxYearProfile)
    }

    private func seedTaxYearProfile(_ profile: TaxYearProfile) {
        let descriptor = FetchDescriptor<TaxYearProfileEntity>(
            predicate: #Predicate {
                $0.businessId == profile.businessId && $0.taxYear == profile.taxYear
            }
        )
        if let existing = try! context.fetch(descriptor).first {
            TaxYearProfileEntityMapper.update(existing, from: profile)
        } else {
            context.insert(TaxYearProfileEntityMapper.toEntity(profile))
        }
        try! context.save()
    }

    private func createApprovedCanonicalJournal(
        debitLegacyAccountId: String,
        creditLegacyAccountId: String,
        amount: Int,
        year: Int
    ) {
        let journalId = UUID()
        let journalDate = makeDate(year: year, month: 6, day: 15)
        let entry = CanonicalJournalEntry(
            id: journalId,
            businessId: businessId,
            taxYear: year,
            journalDate: journalDate,
            voucherNo: VoucherNumber(taxYear: year, month: 6, sequence: nextVoucherSequence(for: year)).value,
            entryType: .normal,
            description: "テスト",
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
    }

    private func nextVoucherSequence(for taxYear: Int) -> Int {
        let currentBusinessId = businessId!
        let descriptor = FetchDescriptor<JournalEntryEntity>(
            predicate: #Predicate { $0.businessId == currentBusinessId && $0.taxYear == taxYear }
        )
        return ((try? context.fetch(descriptor).count) ?? 0) + 1
    }

    private func canonicalAccount(_ legacyAccountId: String) -> CanonicalAccount {
        guard let account = canonicalAccounts.first(where: { $0.legacyAccountId == legacyAccountId }) else {
            fatalError("Canonical account not found for \(legacyAccountId)")
        }
        return account
    }

    private func canonicalAccountId(_ legacyAccountId: String) -> UUID {
        canonicalAccount(legacyAccountId).id
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
