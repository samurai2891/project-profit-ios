import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class LegacyDataMigrationExecutorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try TestModelContainer.create()
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testExecuteMapsLegacyJournalLineAccountsToCanonicalIds() throws {
        let businessId = UUID()
        let mappedCanonicalId = UUID()

        context.insert(
            CanonicalAccountEntity(
                accountId: mappedCanonicalId,
                businessId: businessId,
                legacyAccountId: AccountingConstants.cashAccountId,
                code: "101",
                name: "現金",
                accountTypeRaw: CanonicalAccountType.asset.rawValue,
                normalBalanceRaw: NormalBalance.debit.rawValue
            )
        )

        context.insert(
            PPAccount(
                id: AccountingConstants.cashAccountId,
                code: "101",
                name: "現金",
                accountType: .asset,
                subtype: .cash,
                isSystem: true
            )
        )
        context.insert(
            PPAccount(
                id: AccountingConstants.salesAccountId,
                code: "401",
                name: "売上高",
                accountType: .revenue,
                subtype: .salesRevenue,
                isSystem: true
            )
        )

        let entryId = UUID()
        context.insert(
            PPJournalEntry(
                id: entryId,
                sourceKey: PPJournalEntry.manualSourceKey(entryId),
                date: Date(timeIntervalSince1970: 1_735_689_600),
                entryType: .manual,
                memo: "legacy journal",
                isPosted: true
            )
        )
        context.insert(
            PPJournalLine(
                entryId: entryId,
                accountId: AccountingConstants.cashAccountId,
                debit: 1000,
                credit: 0,
                displayOrder: 0
            )
        )
        context.insert(
            PPJournalLine(
                entryId: entryId,
                accountId: AccountingConstants.salesAccountId,
                debit: 0,
                credit: 1000,
                displayOrder: 1
            )
        )
        try context.save()

        let result = try LegacyDataMigrationExecutor(modelContext: context).execute(businessId: businessId)
        XCTAssertEqual(result.journalsMigrated, 1)

        let migratedEntries = try context.fetch(FetchDescriptor<JournalEntryEntity>())
        let migratedLines = try context.fetch(FetchDescriptor<JournalLineEntity>())
        XCTAssertEqual(migratedEntries.count, 1)
        XCTAssertEqual(migratedLines.count, 2)

        let linesBySortOrder = Dictionary(uniqueKeysWithValues: migratedLines.map { ($0.sortOrder, $0) })
        XCTAssertEqual(linesBySortOrder[0]?.accountId, mappedCanonicalId)
        XCTAssertEqual(
            linesBySortOrder[1]?.accountId,
            LegacyAccountCanonicalMapper.canonicalAccountId(
                businessId: businessId,
                legacyAccountId: AccountingConstants.salesAccountId
            )
        )
    }
}
