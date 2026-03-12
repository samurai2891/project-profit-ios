import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class CanonicalPostingSupportTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var support: CanonicalPostingSupport!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        FeatureFlags.useCanonicalPosting = true
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        support = CanonicalPostingSupport(modelContext: context)
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        support = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testBuildApprovedPostingFallsBackToLegacyTaxFields() throws {
        let snapshot = try support.snapshot()
        let posting = try support.buildApprovedPosting(
            seed: makeSeed(
                amount: 11_000,
                taxCodeId: nil,
                taxRate: 10,
                isTaxIncluded: true,
                taxCategory: .standardRate
            ),
            snapshot: snapshot
        )

        XCTAssertEqual(
            Set(posting.candidate.proposedLines.compactMap(\.taxCodeId)),
            [TaxCode.standard10.rawValue]
        )
    }

    func testResolveCounterpartyReferenceUpdatesExistingDefaultTaxCode() throws {
        let businessId = try XCTUnwrap(dataStore.businessProfile?.id)
        let existing = Counterparty(
            businessId: businessId,
            displayName: "山田商店"
        )
        context.insert(CounterpartyEntityMapper.toEntity(existing))
        try context.save()

        let resolved = try support.resolveCounterpartyReference(
            explicitId: nil,
            rawName: "山田商店",
            defaultTaxCodeId: TaxCode.standard10.rawValue,
            businessId: businessId
        )

        let descriptor = FetchDescriptor<CounterpartyEntity>(
            predicate: #Predicate { $0.counterpartyId == existing.id }
        )
        let entity = try XCTUnwrap(context.fetch(descriptor).first)

        XCTAssertEqual(resolved.id, existing.id)
        XCTAssertEqual(entity.defaultTaxCodeId, TaxCode.standard10.rawValue)
    }

    func testPersistApprovedPostingUpdatesExistingJournalAndAllocations() throws {
        let snapshot = try support.snapshot()
        let projectA = mutations(dataStore).addProject(name: "PJ A", description: "")
        let projectB = mutations(dataStore).addProject(name: "PJ B", description: "")
        let transactionId = UUID()
        let firstSeed = makeSeed(
            id: transactionId,
            amount: 10_000,
            createdAt: makeDate(year: 2026, month: 1, day: 10),
            updatedAt: makeDate(year: 2026, month: 1, day: 10)
        )
        let firstPosting = try support.buildApprovedPosting(
            seed: firstSeed,
            snapshot: snapshot
        )
        let firstJournal = try support.persistApprovedPosting(
            posting: firstPosting,
            allocations: [(projectId: projectA.id, ratio: 100)]
        )

        let updatedPosting = try support.buildApprovedPosting(
            seed: makeSeed(
                id: transactionId,
                amount: 10_000,
                createdAt: firstSeed.createdAt,
                updatedAt: makeDate(year: 2026, month: 1, day: 11),
                journalEntryId: firstJournal.id
            ),
            snapshot: snapshot
        )
        let updatedJournal = try support.persistApprovedPosting(
            posting: updatedPosting,
            allocations: [
                (projectId: projectA.id, ratio: 50),
                (projectId: projectB.id, ratio: 50)
            ]
        )

        let journals = try context.fetch(FetchDescriptor<JournalEntryEntity>())
        let candidateEntities = try context.fetch(FetchDescriptor<PostingCandidateEntity>())
        let projectIds = Set(updatedJournal.lines.compactMap(\.projectAllocationId))

        XCTAssertEqual(journals.count, 1)
        XCTAssertEqual(candidateEntities.count, 1)
        XCTAssertEqual(updatedJournal.id, firstJournal.id)
        XCTAssertEqual(projectIds, Set([projectA.id, projectB.id]))
    }

    func testSyncApprovedCandidatePreservesExistingVoucherAndCreatedAt() async throws {
        let snapshot = try support.snapshot()
        let project = mutations(dataStore).addProject(name: "PJ Sync", description: "")
        let transactionId = UUID()
        let initialSeed = makeSeed(
            id: transactionId,
            createdAt: makeDate(year: 2026, month: 1, day: 10),
            updatedAt: makeDate(year: 2026, month: 1, day: 10)
        )
        let initialPosting = try support.buildApprovedPosting(
            seed: initialSeed,
            snapshot: snapshot
        )
        let initialJournal = try support.persistApprovedPosting(
            posting: initialPosting,
            allocations: [(projectId: project.id, ratio: 100)]
        )

        let syncedPosting = try support.buildApprovedPosting(
            seed: makeSeed(
                id: transactionId,
                amount: 12_000,
                createdAt: initialSeed.createdAt,
                updatedAt: makeDate(year: 2026, month: 1, day: 11),
                journalEntryId: initialJournal.id
            ),
            snapshot: snapshot
        )
        let syncedJournal = try await support.syncApprovedCandidate(
            posting: syncedPosting,
            allocations: [(projectId: project.id, ratio: 100)]
        )

        XCTAssertEqual(syncedJournal.id, initialJournal.id)
        XCTAssertEqual(syncedJournal.voucherNo, initialJournal.voucherNo)
        XCTAssertEqual(syncedJournal.createdAt, initialJournal.createdAt)
    }

    private func makeSeed(
        id: UUID = UUID(),
        amount: Int = 10_000,
        taxCodeId: String? = TaxCode.standard10.rawValue,
        taxRate: Int? = 10,
        isTaxIncluded: Bool? = false,
        taxCategory: TaxCategory? = .standardRate,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        journalEntryId: UUID? = nil
    ) -> CanonicalPostingSeed {
        CanonicalPostingSeed(
            id: id,
            type: .expense,
            amount: amount,
            date: makeDate(year: 2026, month: 1, day: 10),
            categoryId: "cat-tools",
            memo: "support test",
            recurringId: nil,
            paymentAccountId: "acct-cash",
            transferToAccountId: nil,
            taxDeductibleRate: 100,
            taxAmount: nil,
            taxCodeId: taxCodeId,
            taxRate: taxRate,
            isTaxIncluded: isTaxIncluded,
            taxCategory: taxCategory,
            receiptImagePath: nil,
            lineItems: [],
            counterpartyId: nil,
            counterpartyName: "取引先C",
            source: .manual,
            createdAt: createdAt,
            updatedAt: updatedAt,
            journalEntryId: journalEntryId
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
