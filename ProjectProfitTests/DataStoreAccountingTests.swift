import XCTest
import SwiftData
@testable import ProjectProfit

@MainActor
final class DataStoreAccountingTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Manual Journal Entry CRUD

    func testAddManualJournalEntry() {
        let entry = mutations(dataStore).addManualJournalEntry(
            date: Date(),
            memo: "決算整理仕訳",
            lines: [
                (accountId: "acct-rent", debit: 10000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 10000, memo: ""),
            ]
        )

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.entryType, .manual)
        XCTAssertEqual(entry?.memo, "決算整理仕訳")
        XCTAssertTrue(entry?.isPosted ?? false, "Balanced entry should be posted")
    }

    func testAddManualJournalEntryUnbalanced() {
        let entry = mutations(dataStore).addManualJournalEntry(
            date: Date(),
            memo: "不均衡仕訳",
            lines: [
                (accountId: "acct-rent", debit: 10000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 5000, memo: ""),
            ]
        )

        XCTAssertNotNil(entry)
        XCTAssertFalse(entry?.isPosted ?? true, "Unbalanced entry should NOT be posted")
    }

    func testAddManualJournalEntryEmptyLines() {
        let entry = mutations(dataStore).addManualJournalEntry(
            date: Date(),
            memo: "空",
            lines: []
        )

        XCTAssertNil(entry, "Empty lines should return nil")
    }

    func testDeleteManualJournalEntry() {
        let entry = mutations(dataStore).addManualJournalEntry(
            date: Date(),
            memo: "削除テスト",
            lines: [
                (accountId: "acct-rent", debit: 5000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 5000, memo: ""),
            ]
        )
        let entryId = entry!.id

        XCTAssertTrue(dataStore.journalEntries.contains { $0.id == entryId })

        mutations(dataStore).deleteManualJournalEntry(id: entryId)

        XCTAssertFalse(dataStore.journalEntries.contains { $0.id == entryId })
        XCTAssertTrue(dataStore.journalLines.filter { $0.entryId == entryId }.isEmpty)
    }

    func testDeleteAutoJournalEntryIsIgnored() async {
        // Auto entries should not be deletable via manual delete
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let tx = mutations(dataStore).addTransaction(
            type: .expense, amount: 1000, date: Date(),
            categoryId: "cat-tools", memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            candidateSource: .manual
        )
        let syncResult = await mutations(dataStore).syncCanonicalArtifacts(forTransactionId: tx.id, source: .manual)
        guard case let .synced(_, journalId) = syncResult.postingStatus else {
            XCTFail("Transaction should be synced to canonical journal before deletion test")
            return
        }

        let countBefore = dataStore.canonicalJournalEntries().count
        mutations(dataStore).deleteManualJournalEntry(id: journalId)
        XCTAssertEqual(dataStore.canonicalJournalEntries().count, countBefore, "Auto entry should not be deleted")
        XCTAssertTrue(dataStore.canonicalJournalEntries().contains { $0.id == journalId })
    }

    // MARK: - Account Balance

    func testGetAccountBalance() async {
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense, amount: 3000, date: Date(),
            categoryId: "cat-tools", memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            candidateSource: .manual
        )
        _ = await mutations(dataStore).syncCanonicalArtifacts(
            forTransactionId: transaction.id,
            source: .manual
        )

        // 経費仕訳: 借方=acct-supplies(3000), 貸方=acct-cash(3000)
        // acct-cash は資産=借方正常 → 残高 = 0-3000 = -3000
        let cashBalance = dataStore.getAccountBalance(accountId: "acct-cash")
        XCTAssertEqual(cashBalance.credit, 3000)
        XCTAssertEqual(cashBalance.balance, -3000)
    }

    func testGetAccountBalanceWithMultipleTransactions() async {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        let income = mutations(dataStore).addTransaction(
            type: .income, amount: 50000, date: Date(),
            categoryId: "cat-project-income", memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            candidateSource: .manual
        )

        let expense = mutations(dataStore).addTransaction(
            type: .expense, amount: 10000, date: Date(),
            categoryId: "cat-tools", memo: "",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            candidateSource: .manual
        )
        _ = await mutations(dataStore).syncCanonicalArtifacts(
            forTransactionId: income.id,
            source: .manual
        )
        _ = await mutations(dataStore).syncCanonicalArtifacts(
            forTransactionId: expense.id,
            source: .manual
        )

        // 収入: 借方=acct-cash(50000)
        // 経費: 貸方=acct-cash(10000)
        // 残高 = 50000 - 10000 = 40000 (debit normal)
        let cashBalance = dataStore.getAccountBalance(accountId: "acct-cash")
        XCTAssertEqual(cashBalance.debit, 50000)
        XCTAssertEqual(cashBalance.credit, 10000)
        XCTAssertEqual(cashBalance.balance, 40000)
    }

    // MARK: - Ledger Entries

    func testGetLedgerEntries() async {
        let project = mutations(dataStore).addProject(name: "P1", description: "")

        let income = mutations(dataStore).addTransaction(
            type: .income, amount: 20000, date: Date(),
            categoryId: "cat-project-income", memo: "売上1",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            candidateSource: .manual
        )

        let expense = mutations(dataStore).addTransaction(
            type: .expense, amount: 5000, date: Date(),
            categoryId: "cat-tools", memo: "ツール代",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            candidateSource: .manual
        )
        _ = await mutations(dataStore).syncCanonicalArtifacts(
            forTransactionId: income.id,
            source: .manual
        )
        _ = await mutations(dataStore).syncCanonicalArtifacts(
            forTransactionId: expense.id,
            source: .manual
        )

        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertEqual(entries.count, 2)

        // 最初の取引で残高が正（入金）
        if let first = entries.first {
            XCTAssertEqual(first.debit, 20000)
            XCTAssertEqual(first.runningBalance, 20000)
        }

        // 2番目の取引で残高が減少（出金）
        if entries.count >= 2 {
            XCTAssertEqual(entries[1].credit, 5000)
            XCTAssertEqual(entries[1].runningBalance, 15000)
        }
    }

    func testGetLedgerEntriesEmpty() {
        let entries = dataStore.getLedgerEntries(accountId: "acct-cash")
        XCTAssertTrue(entries.isEmpty)
    }

    func testDefaultPaymentAccountPreferenceReturnsBusinessProfileValue() {
        let businessId = UUID()
        dataStore.businessProfile = BusinessProfile(
            id: businessId,
            ownerName: "Canonical Owner",
            defaultPaymentAccountId: "acct-bank"
        )

        XCTAssertEqual(dataStore.defaultPaymentAccountPreference, "acct-bank")
    }

    func testCanonicalExportProfilesReturnsBusinessDefaultPaymentAccount() {
        let businessId = UUID()
        dataStore.businessProfile = BusinessProfile(
            id: businessId,
            ownerName: "Canonical Owner",
            defaultPaymentAccountId: "acct-bank"
        )
        dataStore.currentTaxYearProfile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            taxPackVersion: "2025-v1"
        )

        let profiles = dataStore.canonicalExportProfiles(for: 2025)

        XCTAssertEqual(profiles?.business.defaultPaymentAccountId, "acct-bank")
    }

    func testCanonicalExportProfilesReturnsTaxYearSettings() {
        let businessId = UUID()
        dataStore.businessProfile = BusinessProfile(
            id: businessId,
            ownerName: "Canonical Owner",
            businessName: "Canonical商店"
        )
        dataStore.currentTaxYearProfile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            filingStyle: .white,
            blueDeductionLevel: .none,
            bookkeepingBasis: .singleEntry,
            vatStatus: .exempt,
            vatMethod: .general,
            taxPackVersion: "2025-v1"
        )

        let profiles = dataStore.canonicalExportProfiles(for: 2025)

        XCTAssertEqual(profiles?.taxYear.isBlueReturn, false)
        XCTAssertEqual(profiles?.taxYear.bookkeepingBasis, .singleEntry)
    }

    func testProfileSensitivePayloadLoadsFromCanonicalSecureStore() {
        let businessId = UUID()
        let payload = ProfileSensitivePayload.fromLegacyProfile(
            ownerNameKana: "カノニカル",
            postalCode: "1500001",
            address: "東京都渋谷区1-2-3",
            phoneNumber: "09012345678",
            dateOfBirth: Date(timeIntervalSince1970: 1_700_000_000),
            businessCategory: "ソフトウェア開発",
            myNumberFlag: true,
            includeSensitiveInExport: false
        )
        defer { _ = ProfileSecureStore.delete(profileId: businessId.uuidString) }

        dataStore.businessProfile = BusinessProfile(id: businessId, ownerName: "Canonical Owner")
        XCTAssertTrue(ProfileSecureStore.save(payload, profileId: businessId.uuidString))

        let loaded = dataStore.profileSensitivePayload

        XCTAssertEqual(loaded?.ownerNameKana, "カノニカル")
        XCTAssertEqual(loaded?.postalCode, "1500001")
        XCTAssertEqual(loaded?.businessCategory, "ソフトウェア開発")
        XCTAssertEqual(loaded?.includeSensitiveInExport, false)
    }

    func testProfileSensitivePayloadReturnsNilWithoutBusinessProfile() {
        dataStore.businessProfile = nil

        let loaded = dataStore.profileSensitivePayload

        XCTAssertNil(loaded, "No sensitive payload should load without a canonical business profile")
    }

    func testCanonicalExportProfilesIncludesSensitivePayloadFromSecureStore() {
        let businessId = UUID()
        let canonicalProfileId = businessId.uuidString
        let payload = ProfileSensitivePayload.fromLegacyProfile(
            ownerNameKana: "ヤマダタロウ",
            postalCode: "1000001",
            address: "東京都千代田区千代田1-1",
            phoneNumber: "0312345678",
            dateOfBirth: Date(timeIntervalSince1970: 946_684_800),
            businessCategory: "ソフトウェア開発",
            myNumberFlag: true,
            includeSensitiveInExport: true
        )
        defer { _ = ProfileSecureStore.delete(profileId: canonicalProfileId) }

        dataStore.businessProfile = BusinessProfile(
            id: businessId,
            ownerName: "Canonical Owner"
        )
        dataStore.currentTaxYearProfile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            taxPackVersion: "2025-v1"
        )
        XCTAssertTrue(ProfileSecureStore.save(payload, profileId: canonicalProfileId))

        let profiles = dataStore.canonicalExportProfiles(for: 2025)

        XCTAssertEqual(profiles?.sensitive?.ownerNameKana, "ヤマダタロウ")
        XCTAssertEqual(profiles?.sensitive?.postalCode, "1000001")
        XCTAssertEqual(profiles?.sensitive?.address, "東京都千代田区千代田1-1")
        XCTAssertEqual(profiles?.sensitive?.phoneNumber, "0312345678")
        XCTAssertEqual(profiles?.sensitive?.businessCategory, "ソフトウェア開発")
        XCTAssertEqual(profiles?.sensitive?.myNumberFlag, true)
        XCTAssertEqual(profiles?.sensitive?.dateOfBirth, Date(timeIntervalSince1970: 946_684_800))
    }

    func testCanonicalExportProfilesReturnsNilSensitiveWhenSecureStoreEmpty() {
        let businessId = UUID()
        let canonicalProfileId = businessId.uuidString
        _ = ProfileSecureStore.delete(profileId: canonicalProfileId)

        dataStore.businessProfile = BusinessProfile(
            id: businessId,
            ownerName: "Canonical Owner"
        )
        dataStore.currentTaxYearProfile = TaxYearProfile(
            businessId: businessId,
            taxYear: 2025,
            taxPackVersion: "2025-v1"
        )

        let profiles = dataStore.canonicalExportProfiles(for: 2025)

        XCTAssertNotNil(profiles, "profiles should exist when business and taxYear are set")
        XCTAssertNil(profiles?.sensitive, "sensitive should be nil when secure store has no data")
    }

    func testLegacyLedgerDiagnosticsAreEmptyWithoutLegacyData() {
        let diagnostics = dataStore.legacyLedgerDiagnostics()

        XCTAssertEqual(diagnostics.legacyBookCount, 0)
        XCTAssertEqual(diagnostics.legacyEntryCount, 0)
        XCTAssertEqual(diagnostics.legacyJournalBookCount, 0)
        XCTAssertEqual(diagnostics.legacyJournalEntryCount, 0)
    }

    func testLegacyLedgerDiagnosticsCompareCanonicalAndLegacyJournalCounts() throws {
        _ = mutations(dataStore).addManualJournalEntry(
            date: Date(),
            memo: "canonical",
            lines: [
                (accountId: "acct-rent", debit: 1000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 1000, memo: "")
            ]
        )

        let legacyJournalBook = SDLedgerBook(
            ledgerType: .journal,
            title: "Legacy Journal"
        )
        context.insert(legacyJournalBook)
        context.insert(
            SDLedgerEntry(
                bookId: legacyJournalBook.id,
                entryJSON: "{}",
                sortOrder: 0
            )
        )
        try context.save()

        let diagnostics = dataStore.legacyLedgerDiagnostics()

        XCTAssertEqual(diagnostics.legacyBookCount, 1)
        XCTAssertEqual(diagnostics.legacyEntryCount, 1)
        XCTAssertEqual(diagnostics.legacyJournalBookCount, 1)
        XCTAssertEqual(diagnostics.legacyJournalEntryCount, 1)
        XCTAssertEqual(diagnostics.canonicalJournalEntryCount, 0)
        XCTAssertEqual(diagnostics.journalEntryDelta, -1)
    }

    func testDataStoreMutationsDoNotModifyLegacyLedgerCounts() async throws {
        let legacyCashBook = SDLedgerBook(
            ledgerType: .cashBook,
            title: "Legacy Cash Book"
        )
        context.insert(legacyCashBook)
        context.insert(
            SDLedgerEntry(
                bookId: legacyCashBook.id,
                entryJSON: "{}",
                sortOrder: 0
            )
        )
        try context.save()

        let before = dataStore.legacyLedgerDiagnostics()
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1200,
            date: Date(),
            categoryId: "cat-tools",
            memo: "legacy should stay read-only",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )
        _ = await mutations(dataStore).syncCanonicalArtifacts(forTransactionId: transaction.id, source: .manual)
        let after = dataStore.legacyLedgerDiagnostics()

        XCTAssertEqual(after.legacyBookCount, before.legacyBookCount)
        XCTAssertEqual(after.legacyEntryCount, before.legacyEntryCount)
        XCTAssertEqual(after.legacyJournalBookCount, before.legacyJournalBookCount)
        XCTAssertEqual(after.legacyJournalEntryCount, before.legacyJournalEntryCount)
        XCTAssertGreaterThan(after.canonicalJournalEntryCount, before.canonicalJournalEntryCount)
    }

    func testUserInitiatedLegacyTransactionMutationsAreRejectedWhenCanonicalPostingEnabled() {
        FeatureFlags.useCanonicalPosting = true
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let beforeCount = dataStore.transactions.count

        let addResult = mutations(dataStore).addTransactionResult(
            type: .expense,
            amount: 1200,
            date: Date(),
            categoryId: "cat-tools",
            memo: "manual blocked",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            mutationSource: .userInitiated
        )

        switch addResult {
        case .success:
            XCTFail("user initiated add should be blocked during canonical cutover")
        case .failure(let error):
            XCTAssertEqual(error.errorDescription, AppError.legacyTransactionMutationDisabled.errorDescription)
        }
        XCTAssertEqual(dataStore.transactions.count, beforeCount)

        let systemTransaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 800,
            date: Date(),
            categoryId: "cat-tools",
            memo: "system generated",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash"
        )

        let didUpdate = mutations(dataStore).updateTransaction(
            id: systemTransaction.id,
            memo: "blocked update",
            mutationSource: .userInitiated
        )
        XCTAssertFalse(didUpdate)
        XCTAssertEqual(systemTransaction.memo, "system generated")

        mutations(dataStore).deleteTransaction(
            id: systemTransaction.id,
            mutationSource: .userInitiated
        )
        XCTAssertNil(systemTransaction.deletedAt)
        XCTAssertEqual(
            dataStore.lastError?.errorDescription,
            AppError.legacyTransactionMutationDisabled.errorDescription
        )
    }

    func testLegacySystemTransactionMutationsDoNotAutoSyncCanonicalArtifactsWhenCanonicalPostingEnabled() async throws {
        FeatureFlags.useCanonicalPosting = true
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let fiscalYear = fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        let beforeJournals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)

        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 2400,
            date: Date(),
            categoryId: "cat-tools",
            memo: "system generated legacy helper",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            candidateSource: .manual,
            enqueueCanonicalSync: false
        )

        let candidateBeforeSync = try await workflow.candidate(transaction.id)
        let journalsAfterAdd = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)
        XCTAssertNil(candidateBeforeSync)
        XCTAssertNil(transaction.journalEntryId)
        XCTAssertEqual(journalsAfterAdd.count, beforeJournals.count)

        let didUpdate = mutations(dataStore).updateTransaction(
            id: transaction.id,
            memo: "updated legacy helper",
            candidateSource: .manual,
            enqueueCanonicalSync: false
        )
        XCTAssertTrue(didUpdate)
        XCTAssertEqual(transaction.memo, "updated legacy helper")

        let journalsAfterUpdate = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)
        let candidateAfterUpdate = try await workflow.candidate(transaction.id)
        XCTAssertNil(candidateAfterUpdate)
        XCTAssertNil(transaction.journalEntryId)
        XCTAssertEqual(journalsAfterUpdate.count, beforeJournals.count)

        let syncResult = await mutations(dataStore).syncCanonicalArtifacts(forTransactionId: transaction.id, source: .manual)
        guard case let .synced(candidateId, journalId) = syncResult.postingStatus else {
            return XCTFail("explicit sync should still create canonical artifacts")
        }

        let candidateAfterSync = try await workflow.candidate(candidateId)
        let journalsAfterSync = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)
        XCTAssertEqual(candidateAfterSync?.id, transaction.id)
        XCTAssertEqual(transaction.journalEntryId, journalId)
        XCTAssertEqual(journalsAfterSync.count, beforeJournals.count + 1)
    }

    func testUserInitiatedManualJournalMutationsAreRejectedWhenCanonicalPostingEnabled() {
        FeatureFlags.useCanonicalPosting = true
        let beforeCount = dataStore.journalEntries.count

        let blockedEntry = mutations(dataStore).addManualJournalEntry(
            date: Date(),
            memo: "manual blocked",
            lines: [
                (accountId: "acct-rent", debit: 1000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 1000, memo: ""),
            ],
            mutationSource: .userInitiated
        )

        XCTAssertNil(blockedEntry)
        XCTAssertEqual(dataStore.journalEntries.count, beforeCount)
        XCTAssertEqual(
            dataStore.lastError?.errorDescription,
            AppError.legacyManualJournalMutationDisabled.errorDescription
        )

        let systemEntry = mutations(dataStore).addManualJournalEntry(
            date: Date(),
            memo: "system generated journal",
            lines: [
                (accountId: "acct-rent", debit: 1000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 1000, memo: ""),
            ]
        )
        XCTAssertNotNil(systemEntry)

        if let systemEntry {
            mutations(dataStore).deleteManualJournalEntry(
                id: systemEntry.id,
                mutationSource: .userInitiated
            )
            XCTAssertTrue(dataStore.journalEntries.contains { $0.id == systemEntry.id })
            XCTAssertEqual(
                dataStore.lastError?.errorDescription,
                AppError.legacyManualJournalMutationDisabled.errorDescription
            )
        }
    }

    func testSaveManualPostingCandidateCreatesDraftWithoutLegacyTransaction() async throws {
        FeatureFlags.useCanonicalPosting = true
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let beforeTransactionCount = dataStore.transactions.count
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let fiscalYear = fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        let beforeJournals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)

        let result = await dataStore.saveManualPostingCandidate(
            type: .expense,
            amount: 12_000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "manual candidate",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxDeductibleRate: 100,
            taxAmount: 1_200,
            taxCodeId: TaxCode.standard10.rawValue,
            isTaxIncluded: false,
            candidateSource: .manual
        )

        let candidate: PostingCandidate
        switch result {
        case .success(let savedCandidate):
            candidate = savedCandidate
        case .failure(let error):
            XCTFail("manual candidate save should succeed: \(error.localizedDescription)")
            return
        }

        XCTAssertEqual(candidate.status, .draft)
        XCTAssertEqual(candidate.source, .manual)
        XCTAssertEqual(candidate.counterpartyId, nil)
        XCTAssertTrue(candidate.proposedLines.allSatisfy { $0.projectAllocationId == project.id })
        XCTAssertEqual(candidate.legacySnapshot?.categoryId, "cat-tools")
        XCTAssertEqual(candidate.legacySnapshot?.paymentAccountId, "acct-cash")
        XCTAssertEqual(candidate.legacySnapshot?.taxAmount, 1_200)
        XCTAssertEqual(candidate.legacySnapshot?.taxCodeId, TaxCode.standard10.rawValue)
        XCTAssertEqual(candidate.legacySnapshot?.taxRate, 10)
        XCTAssertEqual(candidate.legacySnapshot?.taxCategory, .standardRate)
        XCTAssertEqual(dataStore.transactions.count, beforeTransactionCount)

        let pendingCandidates = try await workflow.pendingCandidates(businessId: businessId)
        let journals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)

        XCTAssertTrue(pendingCandidates.contains(where: { $0.id == candidate.id }))
        XCTAssertEqual(journals.count, beforeJournals.count)
    }

    func testSaveManualPostingCandidateSplitsProjectAllocationsAcrossLines() async throws {
        FeatureFlags.useCanonicalPosting = true
        let projectA = mutations(dataStore).addProject(name: "P1", description: "")
        let projectB = mutations(dataStore).addProject(name: "P2", description: "")

        let result = await dataStore.saveManualPostingCandidate(
            type: .expense,
            amount: 10_000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "allocation candidate",
            allocations: [
                (projectId: projectA.id, ratio: 60),
                (projectId: projectB.id, ratio: 40),
            ],
            paymentAccountId: "acct-cash",
            candidateSource: .manual
        )

        let candidate: PostingCandidate
        switch result {
        case .success(let savedCandidate):
            candidate = savedCandidate
        case .failure(let error):
            XCTFail("allocation candidate save should succeed: \(error.localizedDescription)")
            return
        }

        let groupedAmounts = Dictionary(grouping: candidate.proposedLines, by: \.projectAllocationId)
            .mapValues { lines in
                lines.reduce(Decimal.zero) { $0 + $1.amount }
            }

        XCTAssertEqual(groupedAmounts[.some(projectA.id)], Decimal(12_000))
        XCTAssertEqual(groupedAmounts[.some(projectB.id)], Decimal(8_000))
        XCTAssertFalse(candidate.proposedLines.contains(where: { $0.projectAllocationId == nil }))
    }

    func testApprovePostingCandidateCreatesCanonicalJournalWithoutLegacyMirrorTransaction() async throws {
        FeatureFlags.useCanonicalPosting = true
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "Approval Queue Project", description: "")
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let fiscalYear = fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        let beforeJournals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)
        let beforeTransactions = dataStore.transactions.count

        let candidateResult = await dataStore.saveManualPostingCandidate(
            type: .expense,
            amount: 12_000,
            date: Date(),
            categoryId: "cat-tools",
            memo: "approval queue candidate",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxDeductibleRate: 100,
            taxAmount: 1_200,
            taxCodeId: TaxCode.standard10.rawValue,
            isTaxIncluded: false,
            candidateSource: .manual
        )

        let candidate: PostingCandidate
        switch candidateResult {
        case .success(let savedCandidate):
            candidate = savedCandidate
        case .failure(let error):
            XCTFail("manual candidate save should succeed: \(error.localizedDescription)")
            return
        }

        let approval = try await dataStore.approvePostingCandidate(
            candidateId: candidate.id,
            description: "approval queue approved"
        )
        let journals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)

        XCTAssertEqual(journals.count, beforeJournals.count + 1)
        XCTAssertEqual(dataStore.transactions.count, beforeTransactions)
        XCTAssertEqual(approval.candidate.status, .approved)
        XCTAssertFalse(dataStore.transactions.contains { $0.journalEntryId == approval.journal.id })
        XCTAssertEqual(dataStore.getProjectSummary(projectId: project.id)?.totalExpense, 12_000)
    }

    func testApproveRecurringItemsCreatesCanonicalJournalWithoutLegacyMirrorTransaction() async throws {
        FeatureFlags.useCanonicalPosting = true
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "Recurring Candidate Project", description: "")
        _ = mutations(dataStore).addRecurring(
            name: "定期費用",
            type: .expense,
            amount: 6_000,
            categoryId: "cat-tools",
            memo: "preview recurring",
            allocationMode: .manual,
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1,
            paymentAccountId: "acct-cash",
            counterparty: "定期先株式会社"
        )

        let previewItems = await dataStore.previewRecurringTransactions()
        let approvedIds = Set(previewItems.map(\.id))
        let beforeTransactions = dataStore.transactions.count
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let fiscalYear = fiscalYear(for: Date(), startMonth: FiscalYearSettings.startMonth)
        let beforeJournals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)

        let generated = await dataStore.approveRecurringItems(approvedIds)

        let journals = try await workflow.journals(businessId: businessId, taxYear: fiscalYear)
        XCTAssertEqual(generated, 1)
        XCTAssertEqual(dataStore.transactions.count, beforeTransactions)
        XCTAssertEqual(journals.count, beforeJournals.count + 1)
        XCTAssertTrue(journals.contains(where: { $0.entryType == .recurring }))
        XCTAssertEqual(dataStore.getProjectSummary(projectId: project.id)?.totalExpense, 6_000)
    }

    func testImportTransactionsCreatesCanonicalJournalWithoutLegacyMirrorTransaction() async throws {
        FeatureFlags.useCanonicalPosting = true
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let beforeTransactions = dataStore.transactions.count
        let workflow = PostingWorkflowUseCase(modelContext: context)
        let beforeJournals = try await workflow.journals(businessId: businessId, taxYear: 2026)
        let beforePending = try await workflow.pendingCandidates(businessId: businessId)
        let csv = """
        日付,種類,金額,カテゴリ,プロジェクト,メモ,支払口座,税率,税込区分,税区分
        2026-01-10,経費,5500,ツール,ImportProject(100%),CSV取り込み,acct-cash,10,税込,課税（10%）
        """

        let result = await mutations(dataStore).importTransactions(from: csv)
        let journals = try await workflow.journals(businessId: businessId, taxYear: 2026)
        let pending = try await workflow.pendingCandidates(businessId: businessId)
        let project = try XCTUnwrap(dataStore.projects.first { $0.name == "ImportProject" })

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.evidenceCount, 1)
        XCTAssertEqual(result.candidateCount, 1)
        XCTAssertEqual(dataStore.transactions.count, beforeTransactions)
        XCTAssertEqual(journals.count, beforeJournals.count)
        XCTAssertEqual(pending.count, beforePending.count + 1)
        XCTAssertTrue(pending.contains(where: { $0.source == .importFile && $0.status == .needsReview }))
        XCTAssertTrue(dataStore.projects.contains(where: { $0.id == project.id }))
    }

    func testLoadDataSeedsCanonicalAccountsForLegacyAccounts() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let repository = SwiftDataChartOfAccountsRepository(modelContext: context)

        let cash = try await repository.findByLegacyId(
            businessId: businessId,
            legacyAccountId: "acct-cash"
        )
        let supplies = try await repository.findByLegacyId(
            businessId: businessId,
            legacyAccountId: "acct-supplies"
        )

        XCTAssertEqual(cash?.code, "101")
        XCTAssertEqual(cash?.name, "現金")
        XCTAssertEqual(cash?.defaultLegalReportLineId, LegalReportLine.cash.rawValue)
        XCTAssertEqual(supplies?.code, "509")
        XCTAssertEqual(supplies?.name, "消耗品費")
        XCTAssertEqual(supplies?.defaultLegalReportLineId, LegalReportLine.consumables.rawValue)
    }

    func testSyncCanonicalArtifactsCreatesPostingForDefaultLegacyAccountIds() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1200,
            date: Date(),
            categoryId: "cat-tools",
            memo: "工具代",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterparty: "山田商事",
            candidateSource: .manual
        )

        let result = await mutations(dataStore).syncCanonicalArtifacts(forTransactionId: transaction.id, source: .manual)
        guard case let .synced(counterpartyId) = result.counterpartyStatus else {
            return XCTFail("取引先は canonical master に保存される前提")
        }
        guard case let .synced(candidateId, journalId) = result.postingStatus else {
            return XCTFail("default acct-* の legacy account id も canonical account に解決できる前提")
        }

        let counterpartyUseCase = CounterpartyMasterUseCase(modelContext: context)
        let counterparties = try await counterpartyUseCase.searchCounterparties(
            businessId: businessId,
            query: "山田商事"
        )
        let chartOfAccountsUseCase = ChartOfAccountsUseCase(modelContext: context)
        let suppliesAccount = try await chartOfAccountsUseCase.account(
            businessId: businessId,
            legacyAccountId: "acct-supplies"
        )
        let cashAccount = try await chartOfAccountsUseCase.account(
            businessId: businessId,
            legacyAccountId: "acct-cash"
        )
        let candidateRepository = SwiftDataPostingCandidateRepository(modelContext: context)
        let journalUseCase = PostingWorkflowUseCase(modelContext: context)
        let candidate = try await candidateRepository.findById(candidateId)
        let journals = try await journalUseCase.journals(
            businessId: businessId,
            taxYear: fiscalYear(for: transaction.date, startMonth: FiscalYearSettings.startMonth)
        )
        let journal = try XCTUnwrap(journals.first { $0.id == journalId })
        let candidateAccountIds = Set(
            try XCTUnwrap(candidate?.proposedLines.compactMap { line in
                line.debitAccountId ?? line.creditAccountId
            })
        )

        XCTAssertEqual(counterparties.map(\.id), [counterpartyId])
        XCTAssertEqual(journal.id, transaction.journalEntryId)
        XCTAssertEqual(journal.sourceCandidateId, candidateId)
        XCTAssertEqual(candidateAccountIds, Set([try XCTUnwrap(suppliesAccount?.id), try XCTUnwrap(cashAccount?.id)]))
        XCTAssertEqual(Set(candidate?.proposedLines.compactMap(\.legalReportLineId) ?? []), Set([LegalReportLine.consumables.rawValue, LegalReportLine.cash.rawValue]))
        XCTAssertEqual(Set(journal.lines.compactMap(\.legalReportLineId)), Set([LegalReportLine.consumables.rawValue, LegalReportLine.cash.rawValue]))
        XCTAssertEqual(Set(journal.lines.map(\.accountId)), Set([try XCTUnwrap(suppliesAccount?.id), try XCTUnwrap(cashAccount?.id)]))
    }

    func testSyncCanonicalArtifactsCreatesAndUpsertsCanonicalPostingWhenLegacyAccountIdsAreUUIDStrings() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let fixture = try makeUUIDBackedExpenseFixture()
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1800,
            date: Date(),
            categoryId: fixture.categoryId,
            memo: "UUID経費",
            allocations: [(projectId: fixture.project.id, ratio: 100)],
            paymentAccountId: fixture.paymentAccountId,
            counterparty: "合同会社テスト",
            candidateSource: .manual
        )

        let firstSync = await mutations(dataStore).syncCanonicalArtifacts(forTransactionId: transaction.id, source: .manual)
        guard case let .synced(counterpartyId) = firstSync.counterpartyStatus else {
            return XCTFail("取引先は同期される前提")
        }
        guard case let .synced(candidateId, journalId) = firstSync.postingStatus else {
            return XCTFail("UUID 形式の legacy account id は posting sync できる前提")
        }

        let candidateRepository = SwiftDataPostingCandidateRepository(modelContext: context)
        let journalRepository = SwiftDataCanonicalJournalEntryRepository(modelContext: context)
        let firstCandidate = try await candidateRepository.findById(candidateId)
        let firstJournal = try await journalRepository.findById(journalId)
        let initialVoucherNo = try XCTUnwrap(firstJournal?.voucherNo)

        XCTAssertEqual(journalId, transaction.journalEntryId)
        XCTAssertEqual(firstJournal?.sourceCandidateId, candidateId)
        XCTAssertEqual(firstCandidate?.counterpartyId, counterpartyId)
        XCTAssertEqual(firstCandidate?.source, .manual)
        XCTAssertEqual(firstCandidate?.proposedLines.count, 2)
        XCTAssertEqual(firstJournal?.businessId, businessId)
        XCTAssertEqual(firstJournal?.totalDebit, Decimal(1800))
        XCTAssertEqual(firstJournal?.totalCredit, Decimal(1800))

        mutations(dataStore).updateTransaction(
            id: transaction.id,
            amount: 2400,
            memo: "UUID経費 更新後",
            counterparty: "合同会社テスト",
            candidateSource: .manual
        )
        let secondSync = await mutations(dataStore).syncCanonicalArtifacts(forTransactionId: transaction.id, source: .manual)
        guard case let .synced(updatedCandidateId, updatedJournalId) = secondSync.postingStatus else {
            return XCTFail("更新後も posting sync できる前提")
        }

        let updatedCandidate = try await candidateRepository.findById(updatedCandidateId)
        let updatedJournal = try await journalRepository.findById(updatedJournalId)

        XCTAssertEqual(updatedJournalId, journalId)
        XCTAssertEqual(updatedJournal?.sourceCandidateId, updatedCandidateId)
        XCTAssertEqual(updatedCandidate?.proposedLines.map(\.amount), [Decimal(2400), Decimal(2400)])
        XCTAssertEqual(updatedJournal?.voucherNo, initialVoucherNo)
        XCTAssertEqual(updatedJournal?.totalDebit, Decimal(2400))
        XCTAssertEqual(updatedJournal?.totalCredit, Decimal(2400))
        XCTAssertEqual(updatedJournal?.description, "UUID経費 更新後")
    }

    func testSyncCanonicalCounterpartyForRecurringPersistsCounterpartyMaster() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "Recurring Project", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "サーバー代",
            type: .expense,
            amount: 3000,
            categoryId: "cat-tools",
            memo: "月額",
            allocationMode: .manual,
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1,
            counterparty: "定期先株式会社"
        )

        let status = await dataStore.syncCanonicalCounterparty(forRecurringId: recurring.id)
        guard case let .synced(counterpartyId) = status else {
            return XCTFail("定期取引の取引先も canonical master に保存される前提")
        }

        let useCase = CounterpartyMasterUseCase(modelContext: context)
        let counterparties = try await useCase.searchCounterparties(
            businessId: businessId,
            query: "定期先株式会社"
        )

        XCTAssertEqual(counterparties.map(\.id), [counterpartyId])
    }

    func testAddTransactionStoresCounterpartyIdAndCanonicalDisplayName() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "登録先株式会社",
            defaultTaxCodeId: TaxCode.standard10.rawValue
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)

        let project = mutations(dataStore).addProject(name: "P1", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1200,
            date: Date(),
            categoryId: "cat-tools",
            memo: "counterparty id",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterpartyId: counterparty.id,
            counterparty: "任意入力値",
            candidateSource: .manual
        )

        XCTAssertEqual(transaction.counterpartyId, counterparty.id)
        XCTAssertEqual(transaction.counterparty, "登録先株式会社")
    }

    func testAddRecurringStoresCounterpartyIdAndCanonicalDisplayName() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "定期登録先株式会社"
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)

        let project = mutations(dataStore).addProject(name: "Recurring Project", description: "")
        let recurring = mutations(dataStore).addRecurring(
            name: "月額費用",
            type: .expense,
            amount: 2000,
            categoryId: "cat-tools",
            memo: "recurring counterparty id",
            allocationMode: .manual,
            allocations: [(projectId: project.id, ratio: 100)],
            frequency: .monthly,
            dayOfMonth: 1,
            counterpartyId: counterparty.id,
            counterparty: "任意入力値"
        )

        XCTAssertEqual(recurring.counterpartyId, counterparty.id)
        XCTAssertEqual(recurring.counterparty, "定期登録先株式会社")
    }

    func testLedgerAndSubLedgerPreferCounterpartyDisplayNameResolvedById() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let counterparty = Counterparty(
            businessId: businessId,
            displayName: "マスタ優先表示"
        )
        try await CounterpartyMasterUseCase(modelContext: context).save(counterparty)

        let project = mutations(dataStore).addProject(name: "Ledger Project", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1500,
            date: Date(),
            categoryId: "cat-tools",
            memo: "ledger display",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterpartyId: counterparty.id,
            counterparty: "旧表示名",
            candidateSource: .manual
        )
        _ = await mutations(dataStore).syncCanonicalArtifacts(
            forTransactionId: transaction.id,
            source: .manual
        )

        let ledgerEntries = dataStore.getLedgerEntries(accountId: "acct-cash")
        let subLedgerEntries = dataStore.getSubLedgerEntries(type: .expenseBook, accountFilter: "acct-supplies")

        XCTAssertEqual(ledgerEntries.first?.counterparty, "マスタ優先表示")
        XCTAssertEqual(subLedgerEntries.first?.counterparty, "マスタ優先表示")
    }

    func testSyncCanonicalArtifactsStoresExplicitTaxCodeOnCandidateAndCounterparty() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "Tax Project", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1100,
            date: Date(),
            categoryId: "cat-tools",
            memo: "課税経費",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 100,
            taxRate: 10,
            isTaxIncluded: true,
            taxCategory: .standardRate,
            counterparty: "税コード商事",
            candidateSource: .manual
        )

        let result = await mutations(dataStore).syncCanonicalArtifacts(forTransactionId: transaction.id, source: .manual)
        guard case let .synced(candidateId, _) = result.postingStatus else {
            return XCTFail("canonical posting が作成される前提")
        }

        let candidateRepository = SwiftDataPostingCandidateRepository(modelContext: context)
        let candidate = try await candidateRepository.findById(candidateId)
        let counterpartyUseCase = CounterpartyMasterUseCase(modelContext: context)
        let counterparties = try await counterpartyUseCase.searchCounterparties(
            businessId: businessId,
            query: "税コード商事"
        )

        XCTAssertEqual(Set(candidate?.proposedLines.compactMap(\.taxCodeId) ?? []), [TaxCode.standard10.rawValue])
        XCTAssertEqual(candidate?.taxAnalysis?.taxAmount, Decimal(100))
        XCTAssertEqual(counterparties.first?.defaultTaxCodeId, TaxCode.standard10.rawValue)
    }

    func testLoadDataBackfillsTransactionTaxCodeIdFromLegacyFields() throws {
        let transaction = PPTransaction(
            type: .expense,
            amount: 1_100,
            date: Date(),
            categoryId: "cat-tools",
            memo: "legacy tax",
            allocations: [],
            paymentAccountId: "acct-cash",
            taxAmount: 100,
            taxRate: 10,
            isTaxIncluded: true,
            taxCategory: .standardRate
        )
        transaction.taxCodeId = nil
        context.insert(transaction)
        try context.save()

        dataStore.loadData()

        let reloaded = try XCTUnwrap(dataStore.allTransactions.first(where: { $0.id == transaction.id }))
        XCTAssertEqual(reloaded.taxCodeId, TaxCode.standard10.rawValue)
        XCTAssertEqual(reloaded.resolvedTaxCategory, .standardRate)
    }

    func testSyncCanonicalArtifactsFallsBackToCounterpartyDefaultTaxCode() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let project = mutations(dataStore).addProject(name: "Tax Default Project", description: "")

        let firstTransaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1080,
            date: Date(),
            categoryId: "cat-tools",
            memo: "初回",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            taxAmount: 80,
            taxRate: 8,
            isTaxIncluded: true,
            taxCategory: .reducedRate,
            counterparty: "軽減取引先",
            candidateSource: .manual
        )
        _ = await mutations(dataStore).syncCanonicalArtifacts(forTransactionId: firstTransaction.id, source: .manual)

        let secondTransaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1200,
            date: Date(),
            categoryId: "cat-tools",
            memo: "2回目",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            counterparty: "軽減取引先",
            candidateSource: .manual
        )
        let secondResult = await mutations(dataStore).syncCanonicalArtifacts(forTransactionId: secondTransaction.id, source: .manual)
        guard case let .synced(candidateId, _) = secondResult.postingStatus else {
            return XCTFail("counterparty default tax code で posting sync できる前提")
        }

        let candidateRepository = SwiftDataPostingCandidateRepository(modelContext: context)
        let candidate = try await candidateRepository.findById(candidateId)

        XCTAssertEqual(Set(candidate?.proposedLines.compactMap(\.taxCodeId) ?? []), [TaxCode.reduced8.rawValue])
    }

    func testSyncCanonicalArtifactsFallsBackToCanonicalAccountDefaultTaxCode() async throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let chartOfAccountsUseCase = ChartOfAccountsUseCase(modelContext: context)
        let fetchedSuppliesAccount = try await chartOfAccountsUseCase.account(
            businessId: businessId,
            legacyAccountId: "acct-supplies"
        )
        let suppliesAccount = try XCTUnwrap(fetchedSuppliesAccount)
        try await chartOfAccountsUseCase.save(
            suppliesAccount.updated(defaultTaxCodeId: .some(TaxCode.standard10.rawValue))
        )

        let project = mutations(dataStore).addProject(name: "Account Default Project", description: "")
        let transaction = mutations(dataStore).addTransaction(
            type: .expense,
            amount: 1200,
            date: Date(),
            categoryId: "cat-tools",
            memo: "勘定科目既定税コード",
            allocations: [(projectId: project.id, ratio: 100)],
            paymentAccountId: "acct-cash",
            candidateSource: .manual
        )

        let result = await mutations(dataStore).syncCanonicalArtifacts(forTransactionId: transaction.id, source: .manual)
        guard case let .synced(candidateId, _) = result.postingStatus else {
            return XCTFail("勘定科目既定税コードで posting sync できる前提")
        }

        let candidateRepository = SwiftDataPostingCandidateRepository(modelContext: context)
        let candidate = try await candidateRepository.findById(candidateId)

        XCTAssertEqual(Set(candidate?.proposedLines.compactMap(\.taxCodeId) ?? []), [TaxCode.standard10.rawValue])
    }

    func testProjectedCanonicalJournalsIncludeApprovedEvidenceJournal() async throws {
        let useCase = ReceiptEvidenceIntakeUseCase(modelContext: context)
        let reviewedDate = Date(timeIntervalSince1970: 1_772_841_600)
        let request = ReceiptEvidenceIntakeRequest(
            receiptData: ReceiptData(
                totalAmount: 1200,
                date: "2026-03-07",
                storeName: "文具センター",
                registrationNumber: nil,
                estimatedCategory: "tools",
                itemSummary: "ノート"
            ),
            ocrText: "文具センター\n合計 1,200円",
            sourceType: .camera,
            fileData: Data("jpeg".utf8),
            originalFileName: "approval-queue.jpg",
            mimeType: "image/jpeg",
            reviewedAmount: 1200,
            reviewedDate: reviewedDate,
            transactionType: .expense,
            categoryId: "cat-tools",
            memo: "[レシート] 文具センター - ノート",
            lineItems: [LineItem(name: "ノート", quantity: 1, unitPrice: 1200)],
            linkedProjectIds: [],
            paymentAccountId: "acct-cash",
            transferToAccountId: nil,
            taxDeductibleRate: 100,
            taxCodeId: nil,
            isTaxIncluded: false,
            taxAmount: nil,
            registrationNumber: nil,
            counterpartyId: nil,
            counterpartyName: "文具センター",
            isWithholdingEnabled: false,
            withholdingTaxCodeId: nil,
            withholdingTaxAmount: nil
        )

        let result = try await useCase.intake(request)
        defer { ReceiptImageStore.deleteDocumentFile(fileName: result.evidence.originalFilePath) }

        let journal = try await PostingWorkflowUseCase(modelContext: context)
            .approveCandidate(candidateId: result.candidate.id)
        let projected = dataStore.projectedCanonicalJournals(
            fiscalYear: fiscalYear(for: reviewedDate, startMonth: FiscalYearSettings.startMonth)
        )

        XCTAssertTrue(projected.entries.contains { $0.id == journal.id })
        XCTAssertEqual(projected.lines.filter { $0.entryId == journal.id }.count, journal.lines.count)
    }

    func testProjectedCanonicalJournalsRetainLegacyManualEntries() {
        let entry = mutations(dataStore).addManualJournalEntry(
            date: Date(),
            memo: "補助仕訳",
            lines: [
                (accountId: "acct-rent", debit: 1000, credit: 0, memo: ""),
                (accountId: "acct-cash", debit: 0, credit: 1000, memo: "")
            ]
        )

        let projected = dataStore.projectedCanonicalJournals()

        XCTAssertTrue(projected.entries.contains { $0.id == entry?.id })
        XCTAssertEqual(projected.lines.filter { $0.entryId == entry?.id }.count, 2)
    }

    private func makeUUIDBackedExpenseFixture() throws -> (project: PPProject, paymentAccountId: String, categoryId: String) {
        let paymentAccountId = UUID().uuidString
        let expenseAccountId = UUID().uuidString
        context.insert(
            PPAccount(
                id: paymentAccountId,
                code: "991",
                name: "UUID現金",
                accountType: .asset,
                subtype: .cash,
                isSystem: false,
                displayOrder: 991
            )
        )
        context.insert(
            PPAccount(
                id: expenseAccountId,
                code: "992",
                name: "UUID経費",
                accountType: .expense,
                subtype: .miscExpense,
                isSystem: false,
                displayOrder: 992
            )
        )
        try context.save()
        dataStore.loadData()

        let category = dataStore.addCategory(name: "UUID経費カテゴリ", type: .expense, icon: "wrench")
        dataStore.updateCategoryLinkedAccount(categoryId: category.id, accountId: expenseAccountId)
        let project = mutations(dataStore).addProject(name: "UUID Project", description: "")
        return (project, paymentAccountId, category.id)
    }
}

final class FeatureFlagsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        super.tearDown()
    }

    func testUseLegacyLedgerDefaultsToDisabled() {
        XCTAssertFalse(FeatureFlags.useLegacyLedger)
    }

    func testUseLegacyLedgerCanBeEnabledExplicitly() {
        FeatureFlags.useLegacyLedger = true

        XCTAssertTrue(FeatureFlags.useLegacyLedger)
    }

    func testResetToDefaultsClearsLegacyLedgerOverride() {
        FeatureFlags.useLegacyLedger = true

        FeatureFlags.resetToDefaults()

        XCTAssertFalse(FeatureFlags.useLegacyLedger)
    }

    func testSwitchToCanonicalDisablesLegacyLedger() {
        FeatureFlags.useLegacyLedger = true

        FeatureFlags.switchToCanonical()

        XCTAssertFalse(FeatureFlags.useLegacyLedger)
    }
}
