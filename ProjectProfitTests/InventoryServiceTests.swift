import XCTest
@testable import ProjectProfit

@MainActor
final class InventoryServiceTests: XCTestCase {

    // MARK: - Valid Inventory Record

    func testGenerateCOGSLines_ValidRecord() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        )

        let lines = InventoryService.generateCOGSLines(record: record)

        // 期首振替(2行) + 仕入振替(2行) + 期末振替(2行) = 6行
        XCTAssertEqual(lines.count, 6)
    }

    // MARK: - Account IDs

    func testGenerateCOGSLines_CorrectAccountIds() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        )

        let lines = InventoryService.generateCOGSLines(record: record)

        // 期首棚卸高振替: Dr 売上原価、Cr 期首商品棚卸高
        let openingDebit = lines[0]
        XCTAssertEqual(openingDebit.accountId, AccountingConstants.cogsAccountId)
        XCTAssertEqual(openingDebit.memo, "期首棚卸高振替")

        let openingCredit = lines[1]
        XCTAssertEqual(openingCredit.accountId, AccountingConstants.openingInventoryAccountId)
        XCTAssertEqual(openingCredit.memo, "期首棚卸高振替")

        // 当期仕入高振替: Dr 売上原価、Cr 仕入高
        let purchasesDebit = lines[2]
        XCTAssertEqual(purchasesDebit.accountId, AccountingConstants.cogsAccountId)
        XCTAssertEqual(purchasesDebit.memo, "当期仕入高振替")

        let purchasesCredit = lines[3]
        XCTAssertEqual(purchasesCredit.accountId, AccountingConstants.purchasesAccountId)
        XCTAssertEqual(purchasesCredit.memo, "当期仕入高振替")

        // 期末棚卸高振替: Dr 期末商品棚卸高、Cr 売上原価
        let closingDebit = lines[4]
        XCTAssertEqual(closingDebit.accountId, AccountingConstants.closingInventoryAccountId)
        XCTAssertEqual(closingDebit.memo, "期末棚卸高振替")

        let closingCredit = lines[5]
        XCTAssertEqual(closingCredit.accountId, AccountingConstants.cogsAccountId)
        XCTAssertEqual(closingCredit.memo, "期末棚卸高振替")
    }

    // MARK: - Amounts

    func testGenerateCOGSLines_CorrectAmounts() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        )

        let lines = InventoryService.generateCOGSLines(record: record)

        // 期首棚卸高振替
        XCTAssertEqual(lines[0].debit, 100_000)
        XCTAssertEqual(lines[0].credit, 0)
        XCTAssertEqual(lines[1].debit, 0)
        XCTAssertEqual(lines[1].credit, 100_000)

        // 当期仕入高振替
        XCTAssertEqual(lines[2].debit, 500_000)
        XCTAssertEqual(lines[2].credit, 0)
        XCTAssertEqual(lines[3].debit, 0)
        XCTAssertEqual(lines[3].credit, 500_000)

        // 期末棚卸高振替
        XCTAssertEqual(lines[4].debit, 80_000)
        XCTAssertEqual(lines[4].credit, 0)
        XCTAssertEqual(lines[5].debit, 0)
        XCTAssertEqual(lines[5].credit, 80_000)
    }

    func testGenerateCOGSLines_DebitCreditBalance() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        )

        let lines = InventoryService.generateCOGSLines(record: record)

        let totalDebit = lines.reduce(0) { $0 + $1.debit }
        let totalCredit = lines.reduce(0) { $0 + $1.credit }

        XCTAssertEqual(totalDebit, totalCredit, "借方合計と貸方合計は一致する")

        // 借方合計 = 売上原価(100,000 + 500,000) + 期末棚卸高(80,000) = 680,000
        XCTAssertEqual(totalDebit, 680_000)
    }

    func testGenerateCOGSLines_NetCOGSAmount() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        )

        let lines = InventoryService.generateCOGSLines(record: record)

        // 売上原価勘定の純額 = 借方合計 - 貸方合計
        let cogsLines = lines.filter { $0.accountId == AccountingConstants.cogsAccountId }
        let cogsDebit = cogsLines.reduce(0) { $0 + $1.debit }
        let cogsCredit = cogsLines.reduce(0) { $0 + $1.credit }
        let netCOGS = cogsDebit - cogsCredit

        // COGS = 期首(100,000) + 仕入(500,000) - 期末(80,000) = 520,000
        XCTAssertEqual(netCOGS, 520_000, "売上原価の純額は期首+仕入-期末と一致する")
        XCTAssertEqual(netCOGS, record.costOfGoodsSold)
    }

    // MARK: - Zero Inventory Values

    func testGenerateCOGSLines_AllZeros_ReturnsEmpty() {
        let record = PPInventoryRecord(fiscalYear: 2025)

        let lines = InventoryService.generateCOGSLines(record: record)

        XCTAssertTrue(lines.isEmpty, "全てゼロの場合は仕訳行なし")
    }

    func testGenerateCOGSLines_OnlyOpeningInventory() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 0,
            closingInventory: 0
        )

        let lines = InventoryService.generateCOGSLines(record: record)

        // 期首振替のみ: 2行
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].accountId, AccountingConstants.cogsAccountId)
        XCTAssertEqual(lines[0].debit, 100_000)
        XCTAssertEqual(lines[1].accountId, AccountingConstants.openingInventoryAccountId)
        XCTAssertEqual(lines[1].credit, 100_000)
    }

    func testGenerateCOGSLines_OnlyPurchases() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 0,
            purchases: 300_000,
            closingInventory: 0
        )

        let lines = InventoryService.generateCOGSLines(record: record)

        // 仕入振替のみ: 2行
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].accountId, AccountingConstants.cogsAccountId)
        XCTAssertEqual(lines[0].debit, 300_000)
        XCTAssertEqual(lines[1].accountId, AccountingConstants.purchasesAccountId)
        XCTAssertEqual(lines[1].credit, 300_000)
    }

    func testGenerateCOGSLines_OnlyClosingInventory() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 0,
            purchases: 0,
            closingInventory: 50_000
        )

        let lines = InventoryService.generateCOGSLines(record: record)

        // 期末振替のみ: 2行
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].accountId, AccountingConstants.closingInventoryAccountId)
        XCTAssertEqual(lines[0].debit, 50_000)
        XCTAssertEqual(lines[1].accountId, AccountingConstants.cogsAccountId)
        XCTAssertEqual(lines[1].credit, 50_000)
    }

    // MARK: - Source Key

    func testCogsSourceKey_Format() {
        let key = InventoryService.cogsSourceKey(fiscalYear: 2025)

        XCTAssertEqual(key, "cogs:2025")
    }

    func testCogsSourceKey_DifferentYears() {
        let key2024 = InventoryService.cogsSourceKey(fiscalYear: 2024)
        let key2025 = InventoryService.cogsSourceKey(fiscalYear: 2025)

        XCTAssertNotEqual(key2024, key2025, "年度が異なればキーも異なる")
    }
}
