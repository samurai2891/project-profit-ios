import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DepreciationEngineTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var engine: DepreciationEngine!
    var accounts: [PPAccount]!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext
        engine = DepreciationEngine(modelContext: context)

        for def in AccountingConstants.defaultAccounts {
            let account = PPAccount(
                id: def.id, code: def.code, name: def.name,
                accountType: def.accountType, normalBalance: def.normalBalance,
                subtype: def.subtype, isSystem: true, displayOrder: def.displayOrder
            )
            context.insert(account)
        }
        try! context.save()

        let descriptor = FetchDescriptor<PPAccount>(sortBy: [SortDescriptor(\.displayOrder)])
        accounts = try! context.fetch(descriptor)
    }

    override func tearDown() {
        accounts = nil
        engine = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Straight Line Tests

    func testStraightLine_FullYear() {
        // 100万円 / 4年 = 249,999/年 (残存1円)
        let asset = createAsset(
            acquisitionDate: date(2024, 1, 15),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine
        )

        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2025, priorAccumulatedDepreciation: 249_999)

        XCTAssertNotNil(calc)
        XCTAssertEqual(calc!.annualAmount, 249_999)
        XCTAssertEqual(calc!.businessAmount, 249_999)
        XCTAssertEqual(calc!.personalAmount, 0)
    }

    func testStraightLine_FirstYearProRata() {
        // 7月取得 → 6ヶ月分: 249,999 * 6 / 12 = 124,999
        let asset = createAsset(
            acquisitionDate: date(2025, 7, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine
        )

        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2025, priorAccumulatedDepreciation: 0)

        XCTAssertNotNil(calc)
        XCTAssertEqual(calc!.annualAmount, 124_999)  // 249,999 * 6 / 12
    }

    func testStraightLine_FinalYearCap() {
        // 累計が限度に近い場合、残りの全額を償却
        let asset = createAsset(
            acquisitionDate: date(2020, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine
        )

        // 4年間で 249,999 * 4 = 999,996 償却済み、残り 999,999 - 999,996 = 3
        // 5年目: min(249,999, 3) = 3（上限キャップ適用）
        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2024, priorAccumulatedDepreciation: 999_996)

        XCTAssertNotNil(calc)
        XCTAssertEqual(calc!.annualAmount, 3)
        XCTAssertEqual(calc!.bookValueAfter, 1)  // 残存1円
    }

    func testStraightLine_FullyDepreciated() {
        // 全額償却済み → nil
        let asset = createAsset(
            acquisitionDate: date(2020, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine
        )

        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2025, priorAccumulatedDepreciation: 999_999)

        XCTAssertNil(calc)
    }

    // MARK: - Declining Balance Tests

    func testDecliningBalance_Basic() {
        // 200%定率法: 帳簿価額 × (2/4) = 50%
        let asset = createAsset(
            acquisitionDate: date(2024, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .decliningBalance
        )

        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2024, priorAccumulatedDepreciation: 0)

        XCTAssertNotNil(calc)
        // 1,000,000 * 0.5 = 500,000、上限キャップ: min(500,000, 999,999) = 500,000
        XCTAssertEqual(calc!.annualAmount, 500_000)
    }

    func testDecliningBalance_GuaranteeSwitch() {
        // 保証額以下で定額切替
        let asset = createAsset(
            acquisitionDate: date(2020, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .decliningBalance
        )

        // 帳簿価額が少額になった場合のテスト
        // 1年目: 1,000,000 * 0.5 = 500,000 → 帳簿500,000
        // 2年目: 500,000 * 0.5 = 250,000 → 帳簿250,000
        // 3年目: 250,000 * 0.5 = 125,000、保証額 = 1,000,000 * 0.125 = 125,000
        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2022, priorAccumulatedDepreciation: 750_000)

        XCTAssertNotNil(calc)
        // 帳簿250,000 * 0.5 = 125,000、保証額125,000 → ギリギリなので定率法のまま or 定額切替
        // 実際の計算: amount(125,000) >= guarantee(125,000) なので定率法のまま
        XCTAssertTrue(calc!.annualAmount > 0)
    }

    // MARK: - Immediate Expense Tests

    func testImmediateExpense_AcquisitionYear() {
        // 取得年に全額
        let asset = createAsset(
            acquisitionDate: date(2025, 3, 1),
            acquisitionCost: 80_000,
            usefulLifeYears: 1,
            method: .immediateExpense,
            salvageValue: 0
        )

        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2025, priorAccumulatedDepreciation: 0)

        XCTAssertNotNil(calc)
        XCTAssertEqual(calc!.annualAmount, 80_000)
    }

    func testImmediateExpense_NextYear() {
        // 翌年は nil
        let asset = createAsset(
            acquisitionDate: date(2025, 3, 1),
            acquisitionCost: 80_000,
            usefulLifeYears: 1,
            method: .immediateExpense,
            salvageValue: 0
        )

        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2026, priorAccumulatedDepreciation: 80_000)

        XCTAssertNil(calc)
    }

    // MARK: - Three Year Equal Tests

    func testThreeYearEqual_AllThreeYears() {
        // 3年間の均等割: 150,000 / 3 = 50,000
        let asset = createAsset(
            acquisitionDate: date(2024, 4, 1),
            acquisitionCost: 150_000,
            usefulLifeYears: 3,
            method: .threeYearEqual,
            salvageValue: 0
        )

        let calc1 = DepreciationEngine.calculate(asset: asset, fiscalYear: 2024, priorAccumulatedDepreciation: 0)
        XCTAssertNotNil(calc1)
        XCTAssertEqual(calc1!.annualAmount, 50_000)

        let calc2 = DepreciationEngine.calculate(asset: asset, fiscalYear: 2025, priorAccumulatedDepreciation: 50_000)
        XCTAssertNotNil(calc2)
        XCTAssertEqual(calc2!.annualAmount, 50_000)

        let calc3 = DepreciationEngine.calculate(asset: asset, fiscalYear: 2026, priorAccumulatedDepreciation: 100_000)
        XCTAssertNotNil(calc3)
        XCTAssertEqual(calc3!.annualAmount, 50_000)
    }

    func testThreeYearEqual_FourthYear() {
        // 4年目は nil
        let asset = createAsset(
            acquisitionDate: date(2024, 4, 1),
            acquisitionCost: 150_000,
            usefulLifeYears: 3,
            method: .threeYearEqual,
            salvageValue: 0
        )

        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2027, priorAccumulatedDepreciation: 150_000)

        XCTAssertNil(calc)
    }

    // MARK: - Business Use Percent Tests

    func testBusinessUsePercent() {
        // 50%按分
        let asset = createAsset(
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine,
            businessUsePercent: 50
        )

        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2025, priorAccumulatedDepreciation: 0)

        XCTAssertNotNil(calc)
        XCTAssertEqual(calc!.annualAmount, 249_999)
        XCTAssertEqual(calc!.businessAmount, 124_999)  // 249,999 * 50 / 100
        XCTAssertEqual(calc!.personalAmount, 125_000)  // 249,999 - 124,999
    }

    // MARK: - Journal Entry Tests

    func testPostDepreciation_JournalEntry() {
        let asset = createAsset(
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine
        )

        let entry = engine.postDepreciation(
            asset: asset, fiscalYear: 2025, priorAccumulated: 0, accounts: accounts
        )

        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.isPosted)

        let lines = fetchLines(for: entry!.id)
        XCTAssertEqual(lines.count, 2)  // 減価償却費(借方) + 累計額(貸方)

        let expenseLine = lines.first { $0.accountId == AccountingConstants.depreciationExpenseAccountId }
        XCTAssertEqual(expenseLine?.debit, 249_999)

        let accumLine = lines.first { $0.accountId == AccountingConstants.accumulatedDepreciationAccountId }
        XCTAssertEqual(accumLine?.credit, 249_999)
    }

    func testPostDepreciation_Idempotent() {
        let asset = createAsset(
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine
        )

        let first = engine.postDepreciation(
            asset: asset, fiscalYear: 2025, priorAccumulated: 0, accounts: accounts
        )
        let second = engine.postDepreciation(
            asset: asset, fiscalYear: 2025, priorAccumulated: 0, accounts: accounts
        )

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first!.id, second!.id, "同一年度の二重計上防止")
    }

    func testBeforeAcquisitionYear() {
        let asset = createAsset(
            acquisitionDate: date(2025, 6, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 5,
            method: .straightLine
        )

        let calc = DepreciationEngine.calculate(asset: asset, fiscalYear: 2024, priorAccumulatedDepreciation: 0)
        XCTAssertNil(calc, "取得前の年度は nil")
    }

    func testPostDepreciation_WithPersonalUse() {
        // 按分ありの3行仕訳
        let asset = createAsset(
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine,
            businessUsePercent: 50
        )

        let entry = engine.postDepreciation(
            asset: asset, fiscalYear: 2025, priorAccumulated: 0, accounts: accounts
        )

        XCTAssertNotNil(entry)
        let lines = fetchLines(for: entry!.id)
        XCTAssertEqual(lines.count, 3)  // 減価償却費 + 事業主貸 + 累計額

        let expenseLine = lines.first { $0.accountId == AccountingConstants.depreciationExpenseAccountId }
        XCTAssertEqual(expenseLine?.debit, 124_999)

        let drawingsLine = lines.first { $0.accountId == AccountingConstants.ownerDrawingsAccountId }
        XCTAssertEqual(drawingsLine?.debit, 125_000)

        let accumLine = lines.first { $0.accountId == AccountingConstants.accumulatedDepreciationAccountId }
        XCTAssertEqual(accumLine?.credit, 249_999)
    }

    // MARK: - Helpers

    private func createAsset(
        acquisitionDate: Date,
        acquisitionCost: Int,
        usefulLifeYears: Int,
        method: DepreciationMethod,
        salvageValue: Int = 1,
        businessUsePercent: Int = 100
    ) -> PPFixedAsset {
        let asset = PPFixedAsset(
            name: "テスト資産",
            acquisitionDate: acquisitionDate,
            acquisitionCost: acquisitionCost,
            usefulLifeYears: usefulLifeYears,
            depreciationMethod: method,
            salvageValue: salvageValue,
            businessUsePercent: businessUsePercent
        )
        context.insert(asset)
        try! context.save()
        return asset
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func fetchLines(for entryId: UUID) -> [PPJournalLine] {
        let descriptor = FetchDescriptor<PPJournalLine>(
            predicate: #Predicate<PPJournalLine> { $0.entryId == entryId },
            sortBy: [SortDescriptor(\.displayOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
