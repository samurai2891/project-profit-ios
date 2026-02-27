import SwiftData
import XCTest
@testable import ProjectProfit

final class PPAccountTests: XCTestCase {

    // MARK: - Init Tests

    func testInitWithDefaults() {
        let account = PPAccount(
            id: "acct-cash",
            code: "101",
            name: "現金",
            accountType: .asset
        )

        XCTAssertEqual(account.id, "acct-cash")
        XCTAssertEqual(account.code, "101")
        XCTAssertEqual(account.name, "現金")
        XCTAssertEqual(account.accountType, .asset)
        XCTAssertEqual(account.normalBalance, .debit, "資産の正常残高は借方")
        XCTAssertNil(account.subtype)
        XCTAssertNil(account.parentAccountId)
        XCTAssertFalse(account.isSystem)
        XCTAssertTrue(account.isActive)
        XCTAssertEqual(account.displayOrder, 0)
    }

    func testInitWithAllParameters() {
        let now = Date()
        let account = PPAccount(
            id: "acct-sales",
            code: "401",
            name: "売上高",
            accountType: .revenue,
            normalBalance: .credit,
            subtype: .salesRevenue,
            parentAccountId: nil,
            isSystem: true,
            isActive: true,
            displayOrder: 1,
            createdAt: now,
            updatedAt: now
        )

        XCTAssertEqual(account.id, "acct-sales")
        XCTAssertEqual(account.code, "401")
        XCTAssertEqual(account.name, "売上高")
        XCTAssertEqual(account.accountType, .revenue)
        XCTAssertEqual(account.normalBalance, .credit)
        XCTAssertEqual(account.subtype, .salesRevenue)
        XCTAssertTrue(account.isSystem)
        XCTAssertTrue(account.isActive)
        XCTAssertEqual(account.displayOrder, 1)
        XCTAssertEqual(account.createdAt, now)
        XCTAssertEqual(account.updatedAt, now)
    }

    // MARK: - normalBalance Auto-Derivation Tests

    func testNormalBalanceDefaultsToDebitForAsset() {
        let account = PPAccount(id: "test-asset", code: "100", name: "Test", accountType: .asset)
        XCTAssertEqual(account.normalBalance, .debit)
    }

    func testNormalBalanceDefaultsToDebitForExpense() {
        let account = PPAccount(id: "test-expense", code: "500", name: "Test", accountType: .expense)
        XCTAssertEqual(account.normalBalance, .debit)
    }

    func testNormalBalanceDefaultsToCreditForLiability() {
        let account = PPAccount(id: "test-liability", code: "200", name: "Test", accountType: .liability)
        XCTAssertEqual(account.normalBalance, .credit)
    }

    func testNormalBalanceDefaultsToCreditForEquity() {
        let account = PPAccount(id: "test-equity", code: "300", name: "Test", accountType: .equity)
        XCTAssertEqual(account.normalBalance, .credit)
    }

    func testNormalBalanceDefaultsToCreditForRevenue() {
        let account = PPAccount(id: "test-revenue", code: "400", name: "Test", accountType: .revenue)
        XCTAssertEqual(account.normalBalance, .credit)
    }

    func testNormalBalanceExplicitOverride() {
        let account = PPAccount(
            id: "acct-owner-drawings",
            code: "152",
            name: "事業主貸",
            accountType: .equity,
            normalBalance: .debit
        )
        XCTAssertEqual(account.normalBalance, .debit, "事業主貸は資本だが借方残高")
    }

    // MARK: - isPaymentAccount Tests

    func testIsPaymentAccountForCash() {
        let account = PPAccount(id: "acct-cash", code: "101", name: "現金", accountType: .asset, subtype: .cash)
        XCTAssertTrue(account.isPaymentAccount)
    }

    func testIsPaymentAccountForOrdinaryDeposit() {
        let account = PPAccount(id: "acct-bank", code: "102", name: "普通預金", accountType: .asset, subtype: .ordinaryDeposit)
        XCTAssertTrue(account.isPaymentAccount)
    }

    func testIsPaymentAccountForCreditCard() {
        let account = PPAccount(id: "acct-cc", code: "151", name: "クレジットカード", accountType: .asset, subtype: .creditCard)
        XCTAssertTrue(account.isPaymentAccount)
    }

    func testIsPaymentAccountForAccountsReceivable() {
        let account = PPAccount(id: "acct-ar", code: "103", name: "売掛金", accountType: .asset, subtype: .accountsReceivable)
        XCTAssertTrue(account.isPaymentAccount)
    }

    func testIsPaymentAccountForAccountsPayable() {
        // 買掛金（負債）も支払い方法として口座ピッカーに表示する
        let account = PPAccount(id: "acct-ap", code: "201", name: "買掛金", accountType: .liability, subtype: .accountsPayable)
        XCTAssertTrue(account.isPaymentAccount)
    }

    func testIsPaymentAccountFalseForRevenue() {
        let account = PPAccount(id: "acct-sales", code: "401", name: "売上高", accountType: .revenue, subtype: .salesRevenue)
        XCTAssertFalse(account.isPaymentAccount)
    }

    func testIsPaymentAccountFalseForExpense() {
        let account = PPAccount(id: "acct-rent", code: "501", name: "地代家賃", accountType: .expense, subtype: .rentExpense)
        XCTAssertFalse(account.isPaymentAccount)
    }

    func testIsPaymentAccountFalseForNilSubtype() {
        let account = PPAccount(id: "acct-custom", code: "999", name: "カスタム", accountType: .asset)
        XCTAssertFalse(account.isPaymentAccount)
    }

    // MARK: - SwiftData Persistence Tests

    @MainActor
    func testPersistenceRoundTrip() throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext

        let account = PPAccount(
            id: "acct-cash",
            code: "101",
            name: "現金",
            accountType: .asset,
            subtype: .cash,
            isSystem: true,
            displayOrder: 1
        )
        context.insert(account)
        try context.save()

        let descriptor = FetchDescriptor<PPAccount>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        let result = fetched[0]
        XCTAssertEqual(result.id, "acct-cash")
        XCTAssertEqual(result.code, "101")
        XCTAssertEqual(result.name, "現金")
        XCTAssertEqual(result.accountType, .asset)
        XCTAssertEqual(result.normalBalance, .debit)
        XCTAssertEqual(result.subtype, .cash)
        XCTAssertTrue(result.isSystem)
        XCTAssertEqual(result.displayOrder, 1)
    }

    @MainActor
    func testPersistenceWithNilSubtype() throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext

        let account = PPAccount(
            id: "acct-custom",
            code: "999",
            name: "カスタム勘定",
            accountType: .expense
        )
        context.insert(account)
        try context.save()

        let descriptor = FetchDescriptor<PPAccount>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertNil(fetched[0].subtype)
    }

    @MainActor
    func testUniqueIdConstraint() throws {
        let container = try TestModelContainer.create()
        let context = container.mainContext

        let account1 = PPAccount(id: "acct-cash", code: "101", name: "現金", accountType: .asset)
        let account2 = PPAccount(id: "acct-cash", code: "101", name: "現金（重複）", accountType: .asset)
        context.insert(account1)
        context.insert(account2)
        try context.save()

        let descriptor = FetchDescriptor<PPAccount>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1, "同一idのアカウントは1件のみ保存される")
    }
}
