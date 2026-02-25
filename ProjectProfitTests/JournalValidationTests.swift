import SwiftData
import XCTest
@testable import ProjectProfit

final class JournalValidationTests: XCTestCase {

    // MARK: - Balanced Entry Tests

    func testValidateBalancedEntry_NoIssues() {
        let entry = PPJournalEntry(
            sourceKey: "tx:\(UUID())", date: Date(), entryType: .auto, isPosted: true
        )
        let lines = [
            PPJournalLine(entryId: entry.id, accountId: "acct-cash", debit: 10_000, credit: 0),
            PPJournalLine(entryId: entry.id, accountId: "acct-sales", debit: 0, credit: 10_000),
        ]

        let issues = JournalValidationService.validateEntry(entry, lines: lines)
        XCTAssertTrue(issues.isEmpty)
    }

    func testValidateUnbalancedEntry() {
        let entry = PPJournalEntry(
            sourceKey: "tx:\(UUID())", date: Date(), entryType: .auto, isPosted: true
        )
        let lines = [
            PPJournalLine(entryId: entry.id, accountId: "acct-cash", debit: 10_000, credit: 0),
            PPJournalLine(entryId: entry.id, accountId: "acct-sales", debit: 0, credit: 9_000),
        ]

        let issues = JournalValidationService.validateEntry(entry, lines: lines)
        XCTAssertTrue(issues.contains(where: {
            if case .unbalanced(let d, let c) = $0 { return d == 10_000 && c == 9_000 }
            return false
        }))
    }

    // MARK: - Empty Entry Tests

    func testValidateEmptyEntry() {
        let entry = PPJournalEntry(
            sourceKey: "tx:\(UUID())", date: Date(), entryType: .auto
        )

        let issues = JournalValidationService.validateEntry(entry, lines: [])
        XCTAssertTrue(issues.contains(where: {
            if case .emptyEntry = $0 { return true }
            return false
        }))
    }

    // MARK: - Line Validation Tests

    func testValidateLine_NegativeDebit() {
        let line = PPJournalLine(entryId: UUID(), accountId: "acct-cash", debit: -100, credit: 0)

        let issues = JournalValidationService.validateLines([line])
        XCTAssertFalse(issues.isEmpty)
    }

    // MARK: - Account Existence Check

    @MainActor
    func testValidateWithAccounts_MissingAccount() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PPAccount.self, configurations: config)
        let context = container.mainContext

        let account = PPAccount(id: "acct-cash", code: "101", name: "現金", accountType: .asset, subtype: .cash, isSystem: true)
        context.insert(account)
        try context.save()

        let entry = PPJournalEntry(sourceKey: "tx:\(UUID())", date: Date(), entryType: .auto)
        let lines = [
            PPJournalLine(entryId: entry.id, accountId: "acct-cash", debit: 10_000, credit: 0),
            PPJournalLine(entryId: entry.id, accountId: "acct-nonexistent", debit: 0, credit: 10_000),
        ]

        let issues = JournalValidationService.validateEntry(entry, lines: lines, accounts: [account])
        XCTAssertTrue(issues.contains(where: {
            if case .missingAccount(let id) = $0 { return id == "acct-nonexistent" }
            return false
        }))
    }

    // MARK: - Locked Fiscal Year Tests

    func testValidateLockedFiscalYear() {
        let profile = PPAccountingProfile(fiscalYear: 2025, lockedAt: Date())
        let entry = PPJournalEntry(
            sourceKey: "tx:\(UUID())",
            date: Calendar(identifier: .gregorian).date(from: DateComponents(year: 2025, month: 6, day: 15))!,
            entryType: .auto
        )
        let lines = [
            PPJournalLine(entryId: entry.id, accountId: "acct-cash", debit: 10_000, credit: 0),
            PPJournalLine(entryId: entry.id, accountId: "acct-sales", debit: 0, credit: 10_000),
        ]

        let issues = JournalValidationService.validateEntry(entry, lines: lines, profile: profile)
        XCTAssertTrue(issues.contains(where: {
            if case .lockedFiscalYear(let year) = $0 { return year == 2025 }
            return false
        }))
    }

    func testValidateUnlockedFiscalYear_NoIssue() {
        let profile = PPAccountingProfile(fiscalYear: 2025)
        let entry = PPJournalEntry(
            sourceKey: "tx:\(UUID())",
            date: Calendar(identifier: .gregorian).date(from: DateComponents(year: 2025, month: 6, day: 15))!,
            entryType: .auto
        )
        let lines = [
            PPJournalLine(entryId: entry.id, accountId: "acct-cash", debit: 10_000, credit: 0),
            PPJournalLine(entryId: entry.id, accountId: "acct-sales", debit: 0, credit: 10_000),
        ]

        let issues = JournalValidationService.validateEntry(entry, lines: lines, profile: profile)
        XCTAssertTrue(issues.isEmpty)
    }

    // MARK: - Fiscal Year Date Validation

    func testDateInFiscalYear_WithinRange() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2025, month: 6, day: 15))!
        let issue = JournalValidationService.validateDateInFiscalYear(date: date, fiscalYear: 2025)
        XCTAssertNil(issue)
    }

    func testDateOutOfFiscalYear() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 12, day: 31))!
        let issue = JournalValidationService.validateDateInFiscalYear(date: date, fiscalYear: 2025)
        XCTAssertNotNil(issue)
    }

    // MARK: - Multi-line Entry Tests

    func testThreeLineExpenseEntryIsBalanced() {
        let entry = PPJournalEntry(sourceKey: "tx:\(UUID())", date: Date(), entryType: .auto)
        let lines = [
            PPJournalLine(entryId: entry.id, accountId: "acct-communication", debit: 80_000, credit: 0),
            PPJournalLine(entryId: entry.id, accountId: "acct-owner-drawings", debit: 20_000, credit: 0),
            PPJournalLine(entryId: entry.id, accountId: "acct-cash", debit: 0, credit: 100_000),
        ]

        let issues = JournalValidationService.validateEntry(entry, lines: lines)
        XCTAssertTrue(issues.isEmpty)
    }

    // MARK: - Issue Description Tests

    func testIssueDescriptions() {
        let unbalanced = JournalValidationIssue.unbalanced(debitTotal: 100, creditTotal: 90)
        XCTAssertTrue(unbalanced.description.contains("貸借不一致"))

        let missing = JournalValidationIssue.missingAccount(accountId: "acct-xxx")
        XCTAssertTrue(missing.description.contains("acct-xxx"))

        let empty = JournalValidationIssue.emptyEntry
        XCTAssertTrue(empty.description.contains("明細行がありません"))

        let locked = JournalValidationIssue.lockedFiscalYear(year: 2025)
        XCTAssertTrue(locked.description.contains("ロック済み"))
    }
}
