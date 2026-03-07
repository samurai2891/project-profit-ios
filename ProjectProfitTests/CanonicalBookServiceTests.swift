import XCTest
@testable import ProjectProfit

@MainActor
final class CanonicalBookServiceTests: XCTestCase {
    private let businessId = UUID()
    private let fiscalYear = 2026

    // MARK: - Helpers

    private func makeAccount(
        id: UUID = UUID(),
        code: String,
        name: String,
        accountType: CanonicalAccountType,
        normalBalance: NormalBalance
    ) -> CanonicalAccount {
        CanonicalAccount(
            id: id,
            businessId: businessId,
            code: code,
            name: name,
            accountType: accountType,
            normalBalance: normalBalance
        )
    }

    private func makeJournal(
        date: Date,
        voucherNo: String = "V-0001",
        description: String = "test",
        lines: [JournalLine],
        entryType: CanonicalJournalEntryType = .normal,
        approved: Bool = true,
        locked: Bool = false
    ) -> CanonicalJournalEntry {
        let id = UUID()
        return CanonicalJournalEntry(
            id: id,
            businessId: businessId,
            taxYear: fiscalYear,
            journalDate: date,
            voucherNo: voucherNo,
            entryType: entryType,
            description: description,
            lines: lines,
            approvedAt: approved ? date : nil,
            lockedAt: locked ? date : nil
        )
    }

    private func makeLine(
        journalId: UUID = UUID(),
        accountId: UUID,
        debit: Decimal = 0,
        credit: Decimal = 0,
        taxCodeId: String? = nil,
        counterpartyId: UUID? = nil
    ) -> JournalLine {
        JournalLine(
            journalId: journalId,
            accountId: accountId,
            debitAmount: debit,
            creditAmount: credit,
            taxCodeId: taxCodeId,
            counterpartyId: counterpartyId
        )
    }

    private func dateInFiscalYear(month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: fiscalYear, month: month, day: day))!
    }

    // MARK: - Journal Book Tests

    func testGenerateJournalBookReturnsEntries() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let journal = makeJournal(
            date: dateInFiscalYear(month: 3, day: 1),
            description: "売上",
            lines: [
                makeLine(accountId: cashAccount.id, debit: 10000, credit: 0),
                makeLine(accountId: salesAccount.id, debit: 0, credit: 10000),
            ]
        )

        let result = CanonicalBookService.generateJournalBook(
            journals: [journal],
            accounts: [cashAccount, salesAccount]
        )

        XCTAssertEqual(result.count, 1, "仕訳帳エントリが1件であるべき")
        XCTAssertEqual(result.first?.lines.count, 2, "明細行が2行であるべき")
        XCTAssertEqual(result.first?.description, "売上")
    }

    func testJournalBookResolvesAccountNames() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let journal = makeJournal(
            date: dateInFiscalYear(month: 4, day: 1),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 5000),
                makeLine(accountId: salesAccount.id, credit: 5000),
            ]
        )

        let result = CanonicalBookService.generateJournalBook(
            journals: [journal],
            accounts: [cashAccount, salesAccount]
        )

        let cashLine = result.first?.lines.first { $0.accountId == cashAccount.id }
        XCTAssertEqual(cashLine?.accountCode, "101")
        XCTAssertEqual(cashLine?.accountName, "現金")
    }

    func testJournalBookFiltersDateRange() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let jan = makeJournal(
            date: dateInFiscalYear(month: 1, day: 15),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 1000),
                makeLine(accountId: salesAccount.id, credit: 1000),
            ]
        )
        let jun = makeJournal(
            date: dateInFiscalYear(month: 6, day: 15),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 2000),
                makeLine(accountId: salesAccount.id, credit: 2000),
            ]
        )

        let rangeStart = dateInFiscalYear(month: 4, day: 1)
        let rangeEnd = dateInFiscalYear(month: 12, day: 31)

        let result = CanonicalBookService.generateJournalBook(
            journals: [jan, jun],
            accounts: [cashAccount, salesAccount],
            dateRange: rangeStart...rangeEnd
        )

        XCTAssertEqual(result.count, 1, "日付範囲外の仕訳は除外されるべき")
    }

    func testJournalBookSortsByDate() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let later = makeJournal(
            date: dateInFiscalYear(month: 6, day: 1),
            voucherNo: "V-0002",
            lines: [
                makeLine(accountId: cashAccount.id, debit: 2000),
                makeLine(accountId: salesAccount.id, credit: 2000),
            ]
        )
        let earlier = makeJournal(
            date: dateInFiscalYear(month: 1, day: 1),
            voucherNo: "V-0001",
            lines: [
                makeLine(accountId: cashAccount.id, debit: 1000),
                makeLine(accountId: salesAccount.id, credit: 1000),
            ]
        )

        let result = CanonicalBookService.generateJournalBook(
            journals: [later, earlier],
            accounts: [cashAccount, salesAccount]
        )

        XCTAssertEqual(result.first?.voucherNo, "V-0001", "日付順にソートされるべき")
        XCTAssertEqual(result.last?.voucherNo, "V-0002")
    }

    func testJournalBookLockedFlag() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let journal = makeJournal(
            date: dateInFiscalYear(month: 3, day: 1),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 1000),
                makeLine(accountId: salesAccount.id, credit: 1000),
            ],
            locked: true
        )

        let result = CanonicalBookService.generateJournalBook(
            journals: [journal],
            accounts: [cashAccount, salesAccount]
        )

        XCTAssertTrue(result.first?.isLocked == true, "lockedAt が設定されていれば isLocked = true であるべき")
    }

    func testJournalBookResolvesCounterpartyName() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)
        let counterpartyId = UUID()

        let journal = makeJournal(
            date: dateInFiscalYear(month: 5, day: 1),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 3000, counterpartyId: counterpartyId),
                makeLine(accountId: salesAccount.id, credit: 3000),
            ]
        )

        let result = CanonicalBookService.generateJournalBook(
            journals: [journal],
            accounts: [cashAccount, salesAccount],
            counterparties: [counterpartyId: "テスト商店"]
        )

        let cashLine = result.first?.lines.first { $0.accountId == cashAccount.id }
        XCTAssertEqual(cashLine?.counterpartyName, "テスト商店")
    }

    // MARK: - General Ledger Tests

    func testGenerateGeneralLedgerCalculatesRunningBalance() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let journal1 = makeJournal(
            date: dateInFiscalYear(month: 1, day: 1),
            description: "売上1",
            lines: [
                makeLine(accountId: cashAccount.id, debit: 10000, credit: 0),
                makeLine(accountId: salesAccount.id, debit: 0, credit: 10000),
            ]
        )
        let journal2 = makeJournal(
            date: dateInFiscalYear(month: 2, day: 1),
            description: "売上2",
            lines: [
                makeLine(accountId: cashAccount.id, debit: 5000, credit: 0),
                makeLine(accountId: salesAccount.id, debit: 0, credit: 5000),
            ]
        )

        let result = CanonicalBookService.generateGeneralLedger(
            journals: [journal1, journal2],
            accountId: cashAccount.id,
            accounts: [cashAccount, salesAccount]
        )

        XCTAssertEqual(result.count, 2, "現金勘定の元帳行が2件であるべき")
        XCTAssertEqual(result[0].runningBalance, 10000, "1件目の残高は10,000であるべき")
        XCTAssertEqual(result[1].runningBalance, 15000, "2件目の残高は15,000であるべき")
    }

    func testGeneralLedgerCreditNormalRunningBalance() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let journal1 = makeJournal(
            date: dateInFiscalYear(month: 1, day: 1),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 20000),
                makeLine(accountId: salesAccount.id, credit: 20000),
            ]
        )
        let journal2 = makeJournal(
            date: dateInFiscalYear(month: 2, day: 1),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 8000),
                makeLine(accountId: salesAccount.id, credit: 8000),
            ]
        )

        let result = CanonicalBookService.generateGeneralLedger(
            journals: [journal1, journal2],
            accountId: salesAccount.id,
            accounts: [cashAccount, salesAccount]
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].runningBalance, 20000, "貸方正常残高: credit - debit = 20,000")
        XCTAssertEqual(result[1].runningBalance, 28000, "貸方正常残高: 累計 = 28,000")
    }

    func testGeneralLedgerResolvesCounterAccount() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let journal = makeJournal(
            date: dateInFiscalYear(month: 3, day: 15),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 5000),
                makeLine(accountId: salesAccount.id, credit: 5000),
            ]
        )

        let result = CanonicalBookService.generateGeneralLedger(
            journals: [journal],
            accountId: cashAccount.id,
            accounts: [cashAccount, salesAccount]
        )

        XCTAssertEqual(result.first?.counterAccountId, salesAccount.id, "相手勘定が売上高であるべき")
        XCTAssertEqual(result.first?.counterAccountName, "売上高")
    }

    func testGeneralLedgerFiltersDateRange() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let jan = makeJournal(
            date: dateInFiscalYear(month: 1, day: 10),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 1000),
                makeLine(accountId: salesAccount.id, credit: 1000),
            ]
        )
        let jul = makeJournal(
            date: dateInFiscalYear(month: 7, day: 10),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 2000),
                makeLine(accountId: salesAccount.id, credit: 2000),
            ]
        )

        let rangeStart = dateInFiscalYear(month: 6, day: 1)
        let rangeEnd = dateInFiscalYear(month: 12, day: 31)

        let result = CanonicalBookService.generateGeneralLedger(
            journals: [jan, jul],
            accountId: cashAccount.id,
            accounts: [cashAccount, salesAccount],
            dateRange: rangeStart...rangeEnd
        )

        XCTAssertEqual(result.count, 1, "範囲外の仕訳は除外されるべき")
        XCTAssertEqual(result.first?.debitAmount, 2000)
    }

    func testGeneralLedgerEmptyWhenNoMatchingAccount() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)
        let unmatchedAccountId = UUID()

        let journal = makeJournal(
            date: dateInFiscalYear(month: 3, day: 1),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 1000),
                makeLine(accountId: salesAccount.id, credit: 1000),
            ]
        )

        let result = CanonicalBookService.generateGeneralLedger(
            journals: [journal],
            accountId: unmatchedAccountId,
            accounts: [cashAccount, salesAccount]
        )

        XCTAssertTrue(result.isEmpty, "対象勘定科目に該当する行がなければ空であるべき")
    }

    // MARK: - Subsidiary Ledger Tests

    func testGenerateSubsidiaryLedgerCashFiltersCorrectAccounts() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let expenseAccount = makeAccount(code: "509", name: "消耗品費", accountType: .expense, normalBalance: .debit)

        let journal = makeJournal(
            date: dateInFiscalYear(month: 4, day: 1),
            description: "消耗品購入",
            lines: [
                makeLine(accountId: expenseAccount.id, debit: 3000, credit: 0),
                makeLine(accountId: cashAccount.id, debit: 0, credit: 3000),
            ]
        )

        let result = CanonicalBookService.generateSubsidiaryLedger(
            journals: [journal],
            type: .cash,
            accounts: [cashAccount, expenseAccount]
        )

        XCTAssertEqual(result.count, 1, "現金出納帳は現金勘定の行のみ")
        XCTAssertEqual(result.first?.accountId, cashAccount.id)
        XCTAssertEqual(result.first?.creditAmount, 3000)
        XCTAssertEqual(result.first?.runningBalance, -3000, "現金（借方正常）: 0 + 0 - 3000 = -3000")
    }

    func testSubsidiaryLedgerDepositResolvesDepositAccounts() {
        let depositAccount = makeAccount(code: "102", name: "普通預金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)

        let journal = makeJournal(
            date: dateInFiscalYear(month: 5, day: 1),
            lines: [
                makeLine(accountId: depositAccount.id, debit: 50000),
                makeLine(accountId: salesAccount.id, credit: 50000),
            ]
        )

        let result = CanonicalBookService.generateSubsidiaryLedger(
            journals: [journal],
            type: .deposit,
            accounts: [depositAccount, salesAccount, cashAccount]
        )

        XCTAssertEqual(result.count, 1, "預金出納帳は預金勘定の行のみ")
        XCTAssertEqual(result.first?.accountId, depositAccount.id)
        XCTAssertEqual(result.first?.runningBalance, 50000)
    }

    func testSubsidiaryLedgerAccountsReceivable() {
        let arAccount = makeAccount(code: "103", name: "売掛金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let journal = makeJournal(
            date: dateInFiscalYear(month: 6, day: 1),
            lines: [
                makeLine(accountId: arAccount.id, debit: 20000),
                makeLine(accountId: salesAccount.id, credit: 20000),
            ]
        )

        let result = CanonicalBookService.generateSubsidiaryLedger(
            journals: [journal],
            type: .accountsReceivable,
            accounts: [arAccount, salesAccount]
        )

        XCTAssertEqual(result.count, 1, "売掛帳は売掛金勘定の行のみ")
        XCTAssertEqual(result.first?.accountId, arAccount.id)
        XCTAssertEqual(result.first?.runningBalance, 20000)
    }

    func testSubsidiaryLedgerAccountsPayable() {
        let apAccount = makeAccount(code: "201", name: "買掛金", accountType: .liability, normalBalance: .credit)
        let expenseAccount = makeAccount(code: "509", name: "消耗品費", accountType: .expense, normalBalance: .debit)

        let journal = makeJournal(
            date: dateInFiscalYear(month: 7, day: 1),
            lines: [
                makeLine(accountId: expenseAccount.id, debit: 15000),
                makeLine(accountId: apAccount.id, credit: 15000),
            ]
        )

        let result = CanonicalBookService.generateSubsidiaryLedger(
            journals: [journal],
            type: .accountsPayable,
            accounts: [apAccount, expenseAccount]
        )

        XCTAssertEqual(result.count, 1, "買掛帳は買掛金勘定の行のみ")
        XCTAssertEqual(result.first?.accountId, apAccount.id)
        XCTAssertEqual(result.first?.runningBalance, 15000, "買掛金（貸方正常）: credit - debit = 15,000")
    }

    func testSubsidiaryLedgerExpenseIncludesAllExpenseAccounts() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let suppliesAccount = makeAccount(code: "509", name: "消耗品費", accountType: .expense, normalBalance: .debit)
        let travelAccount = makeAccount(code: "503", name: "旅費交通費", accountType: .expense, normalBalance: .debit)

        let journal1 = makeJournal(
            date: dateInFiscalYear(month: 3, day: 1),
            lines: [
                makeLine(accountId: suppliesAccount.id, debit: 5000),
                makeLine(accountId: cashAccount.id, credit: 5000),
            ]
        )
        let journal2 = makeJournal(
            date: dateInFiscalYear(month: 4, day: 1),
            lines: [
                makeLine(accountId: travelAccount.id, debit: 8000),
                makeLine(accountId: cashAccount.id, credit: 8000),
            ]
        )

        let result = CanonicalBookService.generateSubsidiaryLedger(
            journals: [journal1, journal2],
            type: .expense,
            accounts: [cashAccount, suppliesAccount, travelAccount]
        )

        XCTAssertEqual(result.count, 2, "経費帳は全費用勘定の行を含むべき")
        let accountIds = Set(result.map(\.accountId))
        XCTAssertTrue(accountIds.contains(suppliesAccount.id), "消耗品費が含まれるべき")
        XCTAssertTrue(accountIds.contains(travelAccount.id), "旅費交通費が含まれるべき")
    }

    func testSubsidiaryLedgerExpenseExcludesArchivedAccounts() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let archivedExpense = CanonicalAccount(
            businessId: businessId,
            code: "599",
            name: "廃止済費用",
            accountType: .expense,
            normalBalance: .debit,
            archivedAt: Date()
        )

        let journal = makeJournal(
            date: dateInFiscalYear(month: 5, day: 1),
            lines: [
                makeLine(accountId: archivedExpense.id, debit: 1000),
                makeLine(accountId: cashAccount.id, credit: 1000),
            ]
        )

        let result = CanonicalBookService.generateSubsidiaryLedger(
            journals: [journal],
            type: .expense,
            accounts: [cashAccount, archivedExpense]
        )

        XCTAssertTrue(result.isEmpty, "アーカイブ済み費用科目は経費帳から除外されるべき")
    }

    func testSubsidiaryLedgerRunningBalancePerAccount() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let suppliesAccount = makeAccount(code: "509", name: "消耗品費", accountType: .expense, normalBalance: .debit)
        let travelAccount = makeAccount(code: "503", name: "旅費交通費", accountType: .expense, normalBalance: .debit)

        let journal1 = makeJournal(
            date: dateInFiscalYear(month: 1, day: 1),
            lines: [
                makeLine(accountId: suppliesAccount.id, debit: 3000),
                makeLine(accountId: cashAccount.id, credit: 3000),
            ]
        )
        let journal2 = makeJournal(
            date: dateInFiscalYear(month: 2, day: 1),
            lines: [
                makeLine(accountId: travelAccount.id, debit: 7000),
                makeLine(accountId: cashAccount.id, credit: 7000),
            ]
        )
        let journal3 = makeJournal(
            date: dateInFiscalYear(month: 3, day: 1),
            lines: [
                makeLine(accountId: suppliesAccount.id, debit: 2000),
                makeLine(accountId: cashAccount.id, credit: 2000),
            ]
        )

        let result = CanonicalBookService.generateSubsidiaryLedger(
            journals: [journal1, journal2, journal3],
            type: .expense,
            accounts: [cashAccount, suppliesAccount, travelAccount]
        )

        XCTAssertEqual(result.count, 3)
        // 消耗品費: 3000, 旅費交通費: 7000, 消耗品費: 3000+2000=5000
        XCTAssertEqual(result[0].runningBalance, 3000, "消耗品費 1件目: 3,000")
        XCTAssertEqual(result[1].runningBalance, 7000, "旅費交通費 1件目: 7,000")
        XCTAssertEqual(result[2].runningBalance, 5000, "消耗品費 2件目: 3,000 + 2,000 = 5,000")
    }

    func testSubsidiaryLedgerReturnsEmptyForNoMatchingAccounts() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)

        let journal = makeJournal(
            date: dateInFiscalYear(month: 3, day: 1),
            lines: [
                makeLine(accountId: cashAccount.id, debit: 1000),
                makeLine(accountId: salesAccount.id, credit: 1000),
            ]
        )

        // 経費帳だが費用勘定がない
        let result = CanonicalBookService.generateSubsidiaryLedger(
            journals: [journal],
            type: .expense,
            accounts: [cashAccount, salesAccount]
        )

        XCTAssertTrue(result.isEmpty, "対象勘定科目が存在しなければ空であるべき")
    }

    func testSubsidiaryLedgerResolvesCounterAccountName() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let suppliesAccount = makeAccount(code: "509", name: "消耗品費", accountType: .expense, normalBalance: .debit)

        let journal = makeJournal(
            date: dateInFiscalYear(month: 8, day: 1),
            lines: [
                makeLine(accountId: cashAccount.id, credit: 4000),
                makeLine(accountId: suppliesAccount.id, debit: 4000),
            ]
        )

        let result = CanonicalBookService.generateSubsidiaryLedger(
            journals: [journal],
            type: .cash,
            accounts: [cashAccount, suppliesAccount]
        )

        XCTAssertEqual(result.first?.counterAccountId, suppliesAccount.id, "相手勘定IDが消耗品費であるべき")
        XCTAssertEqual(result.first?.counterAccountName, "消耗品費", "相手勘定名が消耗品費であるべき")
    }

    // MARK: - Empty Journals

    func testEmptyJournalsReturnsEmptyResults() {
        let cashAccount = makeAccount(code: "101", name: "現金", accountType: .asset, normalBalance: .debit)
        let salesAccount = makeAccount(code: "401", name: "売上高", accountType: .revenue, normalBalance: .credit)
        let accounts = [cashAccount, salesAccount]
        let emptyJournals: [CanonicalJournalEntry] = []

        let journalBook = CanonicalBookService.generateJournalBook(
            journals: emptyJournals,
            accounts: accounts
        )
        XCTAssertTrue(journalBook.isEmpty, "空の仕訳では仕訳帳も空であるべき")

        let ledger = CanonicalBookService.generateGeneralLedger(
            journals: emptyJournals,
            accountId: cashAccount.id,
            accounts: accounts
        )
        XCTAssertTrue(ledger.isEmpty, "空の仕訳では元帳も空であるべき")

        let subLedger = CanonicalBookService.generateSubsidiaryLedger(
            journals: emptyJournals,
            type: .cash,
            accounts: accounts
        )
        XCTAssertTrue(subLedger.isEmpty, "空の仕訳では補助元帳も空であるべき")
    }
}
