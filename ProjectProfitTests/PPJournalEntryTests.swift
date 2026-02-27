import SwiftData
import XCTest
@testable import ProjectProfit

final class PPJournalEntryTests: XCTestCase {

    // MARK: - PPJournalEntry Init Tests

    func testInitWithDefaults() {
        let entry = PPJournalEntry(
            sourceKey: "tx:test",
            date: Date(),
            entryType: .auto
        )

        XCTAssertFalse(entry.id.uuidString.isEmpty)
        XCTAssertEqual(entry.sourceKey, "tx:test")
        XCTAssertEqual(entry.entryType, .auto)
        XCTAssertEqual(entry.memo, "")
        XCTAssertFalse(entry.isPosted)
    }

    func testInitWithAllParameters() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let now = Date()

        let entry = PPJournalEntry(
            id: id,
            sourceKey: "manual:abc",
            date: date,
            entryType: .manual,
            memo: "決算整理仕訳",
            isPosted: true,
            createdAt: now,
            updatedAt: now
        )

        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.sourceKey, "manual:abc")
        XCTAssertEqual(entry.date, date)
        XCTAssertEqual(entry.entryType, .manual)
        XCTAssertEqual(entry.memo, "決算整理仕訳")
        XCTAssertTrue(entry.isPosted)
        XCTAssertEqual(entry.createdAt, now)
        XCTAssertEqual(entry.updatedAt, now)
    }

    func testEntryTypeStoredCorrectly() {
        for entryType in JournalEntryType.allCases {
            let entry = PPJournalEntry(
                sourceKey: "test:\(entryType.rawValue)",
                date: Date(),
                entryType: entryType
            )
            XCTAssertEqual(entry.entryType, entryType)
        }
    }

    // MARK: - sourceKey Computed Properties Tests

    func testSourceTransactionIdFromTransactionSourceKey() {
        let txId = UUID()
        let entry = PPJournalEntry(
            sourceKey: PPJournalEntry.transactionSourceKey(txId),
            date: Date(),
            entryType: .auto
        )

        XCTAssertEqual(entry.sourceTransactionId, txId)
    }

    func testSourceTransactionIdReturnsNilForManualKey() {
        let entry = PPJournalEntry(
            sourceKey: PPJournalEntry.manualSourceKey(UUID()),
            date: Date(),
            entryType: .manual
        )

        XCTAssertNil(entry.sourceTransactionId)
    }

    func testSourceTransactionIdReturnsNilForOpeningKey() {
        let entry = PPJournalEntry(
            sourceKey: PPJournalEntry.openingSourceKey(year: 2026),
            date: Date(),
            entryType: .opening
        )

        XCTAssertNil(entry.sourceTransactionId)
    }

    func testSourceTransactionIdReturnsNilForClosingKey() {
        let entry = PPJournalEntry(
            sourceKey: PPJournalEntry.closingSourceKey(year: 2026),
            date: Date(),
            entryType: .closing
        )

        XCTAssertNil(entry.sourceTransactionId)
    }

    func testTransactionSourceKeyFormat() {
        let txId = UUID()
        let key = PPJournalEntry.transactionSourceKey(txId)
        XCTAssertEqual(key, "tx:\(txId.uuidString)")
        XCTAssertTrue(key.hasPrefix("tx:"))
    }

    func testManualSourceKeyFormat() {
        let entryId = UUID()
        let key = PPJournalEntry.manualSourceKey(entryId)
        XCTAssertEqual(key, "manual:\(entryId.uuidString)")
        XCTAssertTrue(key.hasPrefix("manual:"))
    }

    func testSourceTransactionIdReturnsNilForMalformedUUID() {
        let entry = PPJournalEntry(sourceKey: "tx:not-a-uuid", date: Date(), entryType: .auto)
        XCTAssertNil(entry.sourceTransactionId)
    }

    func testSourceTransactionIdReturnsNilForEmptyUUID() {
        let entry = PPJournalEntry(sourceKey: "tx:", date: Date(), entryType: .auto)
        XCTAssertNil(entry.sourceTransactionId)
    }

    func testOpeningSourceKeyFormat() {
        let key = PPJournalEntry.openingSourceKey(year: 2026)
        XCTAssertEqual(key, "opening:2026")
    }

    func testClosingSourceKeyFormat() {
        let key = PPJournalEntry.closingSourceKey(year: 2026)
        XCTAssertEqual(key, "closing:2026")
    }

    // MARK: - PPJournalLine Init Tests

    func testLineInitWithDefaults() {
        let entryId = UUID()
        let line = PPJournalLine(
            entryId: entryId,
            accountId: "acct-cash",
            debit: 10000,
            credit: 0
        )

        XCTAssertFalse(line.id.uuidString.isEmpty)
        XCTAssertEqual(line.entryId, entryId)
        XCTAssertEqual(line.accountId, "acct-cash")
        XCTAssertEqual(line.debit, 10000)
        XCTAssertEqual(line.credit, 0)
        XCTAssertEqual(line.memo, "")
        XCTAssertEqual(line.displayOrder, 0)
    }

    func testLineInitWithAllParameters() {
        let id = UUID()
        let entryId = UUID()
        let now = Date()

        let line = PPJournalLine(
            id: id,
            entryId: entryId,
            accountId: "acct-sales",
            debit: 0,
            credit: 50000,
            memo: "売上計上",
            displayOrder: 1,
            createdAt: now,
            updatedAt: now
        )

        XCTAssertEqual(line.id, id)
        XCTAssertEqual(line.entryId, entryId)
        XCTAssertEqual(line.accountId, "acct-sales")
        XCTAssertEqual(line.debit, 0)
        XCTAssertEqual(line.credit, 50000)
        XCTAssertEqual(line.memo, "売上計上")
        XCTAssertEqual(line.displayOrder, 1)
        XCTAssertEqual(line.createdAt, now)
        XCTAssertEqual(line.updatedAt, now)
    }

    // MARK: - PPJournalLine Computed Properties Tests

    func testLineIsDebit() {
        let line = PPJournalLine(entryId: UUID(), accountId: "acct-cash", debit: 10000, credit: 0)
        XCTAssertTrue(line.isDebit)
        XCTAssertFalse(line.isCredit)
    }

    func testLineIsCredit() {
        let line = PPJournalLine(entryId: UUID(), accountId: "acct-sales", debit: 0, credit: 50000)
        XCTAssertFalse(line.isDebit)
        XCTAssertTrue(line.isCredit)
    }

    func testLineAmountReturnsDebit() {
        let line = PPJournalLine(entryId: UUID(), accountId: "acct-cash", debit: 10000, credit: 0)
        XCTAssertEqual(line.amount, 10000)
    }

    func testLineAmountReturnsCredit() {
        let line = PPJournalLine(entryId: UUID(), accountId: "acct-sales", debit: 0, credit: 50000)
        XCTAssertEqual(line.amount, 50000)
    }

    func testLineAmountReturnsZeroWhenBothZero() {
        let line = PPJournalLine(entryId: UUID(), accountId: "acct-cash", debit: 0, credit: 0)
        XCTAssertEqual(line.amount, 0)
    }

    // MARK: - SwiftData Persistence Tests

    @MainActor
    func testEntryPersistenceRoundTrip() throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext

        let txId = UUID()
        let entry = PPJournalEntry(
            sourceKey: PPJournalEntry.transactionSourceKey(txId),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            entryType: .auto,
            memo: "テスト仕訳",
            isPosted: true
        )
        context.insert(entry)
        try context.save()

        let descriptor = FetchDescriptor<PPJournalEntry>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        let result = fetched[0]
        XCTAssertEqual(result.sourceKey, "tx:\(txId.uuidString)")
        XCTAssertEqual(result.entryType, .auto)
        XCTAssertEqual(result.memo, "テスト仕訳")
        XCTAssertTrue(result.isPosted)
        XCTAssertEqual(result.sourceTransactionId, txId)
    }

    @MainActor
    func testLinePersistenceRoundTrip() throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext

        let entryId = UUID()
        let line = PPJournalLine(
            entryId: entryId,
            accountId: "acct-cash",
            debit: 10000,
            credit: 0,
            memo: "現金入金",
            displayOrder: 1
        )
        context.insert(line)
        try context.save()

        let descriptor = FetchDescriptor<PPJournalLine>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        let result = fetched[0]
        XCTAssertEqual(result.entryId, entryId)
        XCTAssertEqual(result.accountId, "acct-cash")
        XCTAssertEqual(result.debit, 10000)
        XCTAssertEqual(result.credit, 0)
        XCTAssertEqual(result.memo, "現金入金")
        XCTAssertEqual(result.displayOrder, 1)
    }

    @MainActor
    func testMultipleLinesWithSameEntryId() throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext

        let entryId = UUID()
        let debitLine = PPJournalLine(entryId: entryId, accountId: "acct-cash", debit: 10000, credit: 0, displayOrder: 0)
        let creditLine = PPJournalLine(entryId: entryId, accountId: "acct-sales", debit: 0, credit: 10000, displayOrder: 1)

        context.insert(debitLine)
        context.insert(creditLine)
        try context.save()

        var descriptor = FetchDescriptor<PPJournalLine>(
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        descriptor.predicate = #Predicate { $0.entryId == entryId }
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 2)

        // 個別行の検証
        let first = fetched[0]
        XCTAssertEqual(first.accountId, "acct-cash")
        XCTAssertEqual(first.debit, 10000)
        XCTAssertEqual(first.credit, 0)
        XCTAssertEqual(first.displayOrder, 0)

        let second = fetched[1]
        XCTAssertEqual(second.accountId, "acct-sales")
        XCTAssertEqual(second.debit, 0)
        XCTAssertEqual(second.credit, 10000)
        XCTAssertEqual(second.displayOrder, 1)

        // 貸借一致
        let totalDebit = fetched.reduce(0) { $0 + $1.debit }
        let totalCredit = fetched.reduce(0) { $0 + $1.credit }
        XCTAssertEqual(totalDebit, totalCredit, "借方合計と貸方合計が一致すること")
    }

    @MainActor
    func testUniqueSourceKeyConstraint() throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext

        let entry1 = PPJournalEntry(sourceKey: "tx:same-key", date: Date(), entryType: .auto, memo: "最初")
        let entry2 = PPJournalEntry(sourceKey: "tx:same-key", date: Date(), entryType: .auto, memo: "重複")

        context.insert(entry1)
        context.insert(entry2)
        try context.save()

        let descriptor = FetchDescriptor<PPJournalEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1, "同一sourceKeyの仕訳は1件のみ保存される")
    }
}
