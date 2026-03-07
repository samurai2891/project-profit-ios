import XCTest
@testable import ProjectProfit

final class CanonicalJournalEntryTests: XCTestCase {

    private let businessId = UUID()
    private let accountCash = UUID()
    private let accountSales = UUID()

    // MARK: - 借貸一致チェック

    func testBalancedEntry() {
        let journalId = UUID()
        let entry = CanonicalJournalEntry(
            businessId: businessId,
            taxYear: 2025,
            journalDate: Date(),
            voucherNo: "2025-001-00001",
            lines: [
                JournalLine(journalId: journalId, accountId: accountCash, debitAmount: 550000),
                JournalLine(journalId: journalId, accountId: accountSales, creditAmount: 550000)
            ]
        )

        XCTAssertTrue(entry.isBalanced)
        XCTAssertEqual(entry.totalDebit, 550000)
        XCTAssertEqual(entry.totalCredit, 550000)
    }

    func testUnbalancedEntry() {
        let journalId = UUID()
        let entry = CanonicalJournalEntry(
            businessId: businessId,
            taxYear: 2025,
            journalDate: Date(),
            voucherNo: "2025-001-00002",
            lines: [
                JournalLine(journalId: journalId, accountId: accountCash, debitAmount: 100000),
                JournalLine(journalId: journalId, accountId: accountSales, creditAmount: 90000)
            ]
        )

        XCTAssertFalse(entry.isBalanced)
    }

    // MARK: - 複合仕訳

    func testCompoundEntry() {
        let journalId = UUID()
        let accountRent = UUID()
        let entry = CanonicalJournalEntry(
            businessId: businessId,
            taxYear: 2025,
            journalDate: Date(),
            voucherNo: "2025-001-00003",
            entryType: .normal,
            lines: [
                JournalLine(journalId: journalId, accountId: accountRent, debitAmount: 110000),
                JournalLine(journalId: journalId, accountId: accountCash, creditAmount: 110000)
            ]
        )

        XCTAssertTrue(entry.isBalanced)
        XCTAssertEqual(entry.lines.count, 2)
    }

    // MARK: - イミュータブル更新

    func testImmutableUpdate() {
        let journalId = UUID()
        let original = CanonicalJournalEntry(
            businessId: businessId,
            taxYear: 2025,
            journalDate: Date(),
            voucherNo: "2025-001-00004",
            description: "元の摘要"
        )

        let updated = original.updated(
            description: "更新後の摘要",
            approvedAt: Date()
        )

        XCTAssertEqual(original.description, "元の摘要")
        XCTAssertNil(original.approvedAt)

        XCTAssertEqual(updated.description, "更新後の摘要")
        XCTAssertNotNil(updated.approvedAt)
        XCTAssertEqual(original.id, updated.id)
    }

    // MARK: - 伝票番号

    func testVoucherNumberFormat() {
        let voucher = VoucherNumber(taxYear: 2025, month: 1, sequence: 1)
        XCTAssertEqual(voucher.value, "2025-001-00001")
        XCTAssertEqual(voucher.taxYear, 2025)
        XCTAssertEqual(voucher.month, 1)
        XCTAssertEqual(voucher.sequence, 1)
    }

    func testVoucherNumberComparable() {
        let first = VoucherNumber(taxYear: 2025, month: 1, sequence: 1)
        let second = VoucherNumber(taxYear: 2025, month: 1, sequence: 2)
        let nextMonth = VoucherNumber(taxYear: 2025, month: 2, sequence: 1)

        XCTAssertTrue(first < second)
        XCTAssertTrue(second < nextMonth)
    }

    // MARK: - JournalLine

    func testJournalLineDebitCredit() {
        let journalId = UUID()
        let debitLine = JournalLine(journalId: journalId, accountId: accountCash, debitAmount: 50000)
        XCTAssertTrue(debitLine.isDebit)
        XCTAssertFalse(debitLine.isCredit)
        XCTAssertEqual(debitLine.amount, 50000)

        let creditLine = JournalLine(journalId: journalId, accountId: accountSales, creditAmount: 50000)
        XCTAssertFalse(creditLine.isDebit)
        XCTAssertTrue(creditLine.isCredit)
        XCTAssertEqual(creditLine.amount, 50000)
    }
}
