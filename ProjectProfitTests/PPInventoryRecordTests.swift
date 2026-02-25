import SwiftData
import XCTest
@testable import ProjectProfit

final class PPInventoryRecordTests: XCTestCase {

    // MARK: - Initialization

    func testInitWithAllFields() {
        let id = UUID()
        let now = Date()
        let record = PPInventoryRecord(
            id: id,
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000,
            memo: "テストメモ",
            createdAt: now,
            updatedAt: now
        )

        XCTAssertEqual(record.id, id)
        XCTAssertEqual(record.fiscalYear, 2025)
        XCTAssertEqual(record.openingInventory, 100_000)
        XCTAssertEqual(record.purchases, 500_000)
        XCTAssertEqual(record.closingInventory, 80_000)
        XCTAssertEqual(record.memo, "テストメモ")
        XCTAssertEqual(record.createdAt, now)
        XCTAssertEqual(record.updatedAt, now)
    }

    func testDefaultOptionalFieldsAreNil() {
        let record = PPInventoryRecord(fiscalYear: 2025)

        XCTAssertNil(record.memo)
    }

    func testDefaultNumericFieldsAreZero() {
        let record = PPInventoryRecord(fiscalYear: 2025)

        XCTAssertEqual(record.openingInventory, 0)
        XCTAssertEqual(record.purchases, 0)
        XCTAssertEqual(record.closingInventory, 0)
    }

    func testConvenienceInitWithMemo() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 50_000,
            purchases: 200_000,
            closingInventory: 30_000,
            memo: "決算整理用"
        )

        XCTAssertEqual(record.memo, "決算整理用")
        XCTAssertEqual(record.fiscalYear, 2025)
        XCTAssertEqual(record.openingInventory, 50_000)
        XCTAssertEqual(record.purchases, 200_000)
        XCTAssertEqual(record.closingInventory, 30_000)
    }

    // MARK: - Negative Value Clamping

    func testNegativeValuesClampedToZero() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: -100,
            purchases: -200,
            closingInventory: -300
        )

        XCTAssertEqual(record.openingInventory, 0)
        XCTAssertEqual(record.purchases, 0)
        XCTAssertEqual(record.closingInventory, 0)
    }

    // MARK: - Cost of Goods Sold

    func testCostOfGoodsSoldStandardCase() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 80_000
        )

        // COGS = 100,000 + 500,000 - 80,000 = 520,000
        XCTAssertEqual(record.costOfGoodsSold, 520_000)
    }

    func testCostOfGoodsSoldWhenClosingExceedsOpeningPlusPurchases() {
        // Edge case: closingInventory > openingInventory + purchases
        // This would yield a negative COGS.
        // Since init clamps to max(0, value), closingInventory can only be
        // set to a non-negative value, but it can still exceed the sum.
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 50_000,
            purchases: 30_000,
            closingInventory: 100_000
        )

        // COGS = 50,000 + 30,000 - 100,000 = -20,000
        XCTAssertEqual(record.costOfGoodsSold, -20_000)
    }

    func testCostOfGoodsSoldWithZeroValues() {
        let record = PPInventoryRecord(fiscalYear: 2025)

        // COGS = 0 + 0 - 0 = 0
        XCTAssertEqual(record.costOfGoodsSold, 0)
    }

    func testCostOfGoodsSoldWhenClosingEqualsOpeningPlusPurchases() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 200_000,
            closingInventory: 300_000
        )

        // COGS = 100,000 + 200,000 - 300,000 = 0
        XCTAssertEqual(record.costOfGoodsSold, 0)
    }

    func testCostOfGoodsSoldWithNoClosingInventory() {
        let record = PPInventoryRecord(
            fiscalYear: 2025,
            openingInventory: 100_000,
            purchases: 500_000,
            closingInventory: 0
        )

        // COGS = 100,000 + 500,000 - 0 = 600,000
        XCTAssertEqual(record.costOfGoodsSold, 600_000)
    }
}
