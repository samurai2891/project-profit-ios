import XCTest
@testable import ProjectProfit

final class AccountingConstantsTests: XCTestCase {

    // MARK: - Default Accounts Tests

    func testDefaultAccountsCount() {
        XCTAssertEqual(AccountingConstants.defaultAccounts.count, 26)
    }

    func testAllAccountIdsAreUnique() {
        let ids = AccountingConstants.defaultAccounts.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "勘定科目IDに重複があります")
    }

    func testAllAccountCodesAreUnique() {
        let codes = AccountingConstants.defaultAccounts.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count, "勘定科目コードに重複があります")
    }

    func testAssetAccountsCount() {
        // 現金, 普通預金, 売掛金, 前払費用, クレジットカード + 減価償却累計額(contra-asset) + 仮勘定(B/S表示のためasset) = 7
        let assets = AccountingConstants.defaultAccounts.filter { $0.accountType == .asset }
        XCTAssertEqual(assets.count, 7)
    }

    func testEquityAccountsCount() {
        // 事業主貸(equity+debit) + 元入金 + 事業主借 = 3
        let equity = AccountingConstants.defaultAccounts.filter { $0.accountType == .equity }
        XCTAssertEqual(equity.count, 3)
    }

    func testLiabilityAccountsCount() {
        let liabilities = AccountingConstants.defaultAccounts.filter { $0.accountType == .liability }
        XCTAssertEqual(liabilities.count, 2)
    }

    func testRevenueAccountsCount() {
        let revenue = AccountingConstants.defaultAccounts.filter { $0.accountType == .revenue }
        XCTAssertEqual(revenue.count, 2)
    }

    func testExpenseAccountsCount() {
        // 12 e-Tax 経費区分のみ（仮勘定は asset に移動）
        let expenses = AccountingConstants.defaultAccounts.filter { $0.accountType == .expense }
        XCTAssertEqual(expenses.count, 12)
    }

    func testCashAccountDefinition() {
        let cash = AccountingConstants.defaultAccountsById["acct-cash"]
        XCTAssertNotNil(cash)
        XCTAssertEqual(cash?.code, "101")
        XCTAssertEqual(cash?.name, "現金")
        XCTAssertEqual(cash?.accountType, .asset)
        XCTAssertEqual(cash?.normalBalance, .debit)
        XCTAssertEqual(cash?.subtype, .cash)
    }

    func testOwnerDrawingsIsEquityWithDebitBalance() {
        let drawings = AccountingConstants.defaultAccountsById["acct-owner-drawings"]
        XCTAssertNotNil(drawings)
        XCTAssertEqual(drawings?.accountType, .equity, "事業主貸は資本区分")
        XCTAssertEqual(drawings?.normalBalance, .debit, "事業主貸は借方残高")
        XCTAssertEqual(drawings?.code, "152")
    }

    func testOwnerCapitalDefinition() {
        let capital = AccountingConstants.defaultAccountsById["acct-owner-capital"]
        XCTAssertNotNil(capital)
        XCTAssertEqual(capital?.code, "301")
        XCTAssertEqual(capital?.name, "元入金")
        XCTAssertEqual(capital?.accountType, .equity)
        XCTAssertEqual(capital?.normalBalance, .credit)
        XCTAssertEqual(capital?.subtype, .ownerCapital)
    }

    func testSuspenseAccountDefinition() {
        let suspense = AccountingConstants.defaultAccountsById["acct-suspense"]
        XCTAssertNotNil(suspense)
        XCTAssertEqual(suspense?.code, "900")
        XCTAssertEqual(suspense?.accountType, .asset)
    }

    func testCodeSchemeConsistency() {
        for account in AccountingConstants.defaultAccounts {
            let codePrefix = account.code.prefix(1)
            switch account.accountType {
            case .asset:
                // 仮勘定は asset だが 9xx コード（特殊枠）
                XCTAssertTrue(["1", "9"].contains(String(codePrefix)), "\(account.name)(\(account.code)) は1xxまたは9xxコードであるべき")
            case .liability:
                XCTAssertEqual(codePrefix, "2", "\(account.name)(\(account.code)) は2xxコードであるべき")
            case .equity:
                // 事業主貸は特殊 (152)
                XCTAssertTrue(["1", "3"].contains(String(codePrefix)), "\(account.name)(\(account.code)) は1xxまたは3xxコードであるべき")
            case .revenue:
                XCTAssertEqual(codePrefix, "4", "\(account.name)(\(account.code)) は4xxコードであるべき")
            case .expense:
                XCTAssertEqual(codePrefix, "5", "\(account.name)(\(account.code)) は5xxコードであるべき")
            }
        }
    }

    // MARK: - Category Mapping Tests

    func testCategoryMappingCount() {
        XCTAssertEqual(AccountingConstants.categoryToAccountMapping.count, 13)
    }

    func testAllMappedAccountIdsExistInDefaultAccounts() {
        let accountIds = Set(AccountingConstants.defaultAccounts.map(\.id))
        for (categoryId, accountId) in AccountingConstants.categoryToAccountMapping {
            XCTAssertTrue(accountIds.contains(accountId), "カテゴリ \(categoryId) のマッピング先 \(accountId) がデフォルト勘定科目に存在しません")
        }
    }

    func testHostingMapsToCommuncation() {
        XCTAssertEqual(AccountingConstants.categoryToAccountMapping["cat-hosting"], "acct-communication")
    }

    func testToolsMapsToSupplies() {
        XCTAssertEqual(AccountingConstants.categoryToAccountMapping["cat-tools"], "acct-supplies")
    }

    func testAdsMapsToAdvertising() {
        XCTAssertEqual(AccountingConstants.categoryToAccountMapping["cat-ads"], "acct-advertising")
    }

    func testContractorMapsToOutsourcing() {
        XCTAssertEqual(AccountingConstants.categoryToAccountMapping["cat-contractor"], "acct-outsourcing")
    }

    func testSalesMapsToSalesRevenue() {
        XCTAssertEqual(AccountingConstants.categoryToAccountMapping["cat-sales"], "acct-sales")
    }

    func testServiceMapsToSalesRevenue() {
        XCTAssertEqual(AccountingConstants.categoryToAccountMapping["cat-service"], "acct-sales")
    }

    func testOtherIncomeMapsToOtherIncome() {
        XCTAssertEqual(AccountingConstants.categoryToAccountMapping["cat-other-income"], "acct-other-income")
    }

    func testOtherExpenseMapsToMisc() {
        XCTAssertEqual(AccountingConstants.categoryToAccountMapping["cat-other-expense"], "acct-misc")
    }

    // MARK: - Well-Known IDs Tests

    func testWellKnownIds() {
        XCTAssertEqual(AccountingConstants.cashAccountId, "acct-cash")
        XCTAssertEqual(AccountingConstants.bankAccountId, "acct-bank")
        XCTAssertEqual(AccountingConstants.ownerDrawingsAccountId, "acct-owner-drawings")
        XCTAssertEqual(AccountingConstants.ownerContributionsAccountId, "acct-owner-contributions")
        XCTAssertEqual(AccountingConstants.ownerCapitalAccountId, "acct-owner-capital")
        XCTAssertEqual(AccountingConstants.salesAccountId, "acct-sales")
        XCTAssertEqual(AccountingConstants.suspenseAccountId, "acct-suspense")
    }
}
