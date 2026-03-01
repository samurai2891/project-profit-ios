import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DepreciationScheduleBuilderTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Empty Assets

    func testBuild_EmptyAssets_ReturnsEmpty() {
        let rows = DepreciationScheduleBuilder.build(assets: [], fiscalYear: 2025)

        XCTAssertTrue(rows.isEmpty, "空の資産配列からは空の明細が返る")
    }

    // MARK: - Single Asset Schedule Row

    func testBuild_SingleAsset_GeneratesCorrectRow() {
        // 定額法: 取得価額1,000,000円 / 耐用年数4年 = 年間249,999円（残存1円）
        // 2025年1月取得 → 2025年度: 初年度12ヶ月分 = 249,999
        let asset = createAsset(
            name: "パソコン",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine
        )

        let rows = DepreciationScheduleBuilder.build(assets: [asset], fiscalYear: 2025)

        XCTAssertEqual(rows.count, 1)

        let row = rows[0]
        XCTAssertEqual(row.id, asset.id)
        XCTAssertEqual(row.assetName, "パソコン")
        XCTAssertEqual(row.acquisitionDate, date(2025, 1, 1))
        XCTAssertEqual(row.acquisitionCost, 1_000_000)
        XCTAssertEqual(row.usefulLifeYears, 4)
        XCTAssertEqual(row.depreciationMethod, .straightLine)
        XCTAssertEqual(row.businessUsePercent, 100)

        // 初年度（1月取得 → 12ヶ月分）: 249,999
        XCTAssertEqual(row.currentYearAmount, 249_999)
        XCTAssertEqual(row.accumulatedAmount, 249_999)
        XCTAssertEqual(row.bookValue, 1_000_000 - 249_999)
    }

    func testBuild_SecondYear_AccumulatesCorrectly() {
        // 2024年1月取得、2025年度の明細を生成
        // 1年目(2024): 249,999、2年目(2025): 249,999、累計: 499,998
        let asset = createAsset(
            name: "デスク",
            acquisitionDate: date(2024, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine
        )

        let rows = DepreciationScheduleBuilder.build(assets: [asset], fiscalYear: 2025)

        XCTAssertEqual(rows.count, 1)

        let row = rows[0]
        XCTAssertEqual(row.currentYearAmount, 249_999)
        XCTAssertEqual(row.accumulatedAmount, 499_998)
        XCTAssertEqual(row.bookValue, 1_000_000 - 499_998)
    }

    // MARK: - Fully Depreciated Asset (Book Value = 1)

    func testBuild_FullyDepreciated_ShowsZeroCurrentYear() {
        // 取得価額1,000,000円、耐用年数4年、2020年1月取得
        // 年間249,999円 x 4年 = 999,996、5年目に残り3円を償却 → 残存1円
        // 2026年度（全額償却後）→ currentYearAmount = 0
        let asset = createAsset(
            name: "古いPC",
            acquisitionDate: date(2020, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            method: .straightLine
        )

        let rows = DepreciationScheduleBuilder.build(assets: [asset], fiscalYear: 2026)

        XCTAssertEqual(rows.count, 1)

        let row = rows[0]
        XCTAssertEqual(row.currentYearAmount, 0)
        XCTAssertEqual(row.bookValue, 1, "全額償却後は残存価額1円")
    }

    // MARK: - Disposed Asset Excluded

    func testBuild_DisposedAsset_IsExcluded() {
        let asset = createAsset(
            name: "廃棄済み機器",
            acquisitionDate: date(2023, 1, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 5,
            method: .straightLine,
            assetStatus: .disposed
        )

        let rows = DepreciationScheduleBuilder.build(assets: [asset], fiscalYear: 2025)

        XCTAssertTrue(rows.isEmpty, "除却済み資産は明細から除外される")
    }

    func testBuild_SoldAsset_IsExcluded() {
        let asset = createAsset(
            name: "売却済み機器",
            acquisitionDate: date(2023, 1, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 5,
            method: .straightLine,
            assetStatus: .sold
        )

        let rows = DepreciationScheduleBuilder.build(assets: [asset], fiscalYear: 2025)

        XCTAssertTrue(rows.isEmpty, "売却済み資産は明細から除外される")
    }

    func testBuild_MixedStatuses_OnlyActiveIncluded() {
        let active = createAsset(
            name: "使用中資産",
            acquisitionDate: date(2024, 1, 1),
            acquisitionCost: 300_000,
            usefulLifeYears: 5,
            method: .straightLine
        )
        let disposed = createAsset(
            name: "除却済み",
            acquisitionDate: date(2023, 1, 1),
            acquisitionCost: 200_000,
            usefulLifeYears: 3,
            method: .straightLine,
            assetStatus: .disposed
        )
        let fullyDep = createAsset(
            name: "償却完了",
            acquisitionDate: date(2020, 1, 1),
            acquisitionCost: 100_000,
            usefulLifeYears: 3,
            method: .straightLine,
            assetStatus: .fullyDepreciated
        )

        let rows = DepreciationScheduleBuilder.build(
            assets: [active, disposed, fullyDep],
            fiscalYear: 2025
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].assetName, "使用中資産")
    }

    // MARK: - Schedule Row Matches DepreciationEngine.calculate()

    func testBuild_MatchesDepreciationEngineCalculation() {
        let asset = createAsset(
            name: "検証用資産",
            acquisitionDate: date(2024, 4, 1),
            acquisitionCost: 600_000,
            usefulLifeYears: 5,
            method: .straightLine,
            businessUsePercent: 80
        )

        // DepreciationEngine で同じ計算を再現
        // 1年目(2024): 初年度月割 → (599,999/5) * (13-4)/12 = 119,999 * 9/12 = 89,999
        let priorCalc = DepreciationEngine.calculate(
            asset: asset,
            fiscalYear: 2024,
            priorAccumulatedDepreciation: 0
        )
        XCTAssertNotNil(priorCalc)
        let priorAccumulated = priorCalc!.accumulatedDepreciation

        // 2年目(2025)
        let expectedCalc = DepreciationEngine.calculate(
            asset: asset,
            fiscalYear: 2025,
            priorAccumulatedDepreciation: priorAccumulated
        )
        XCTAssertNotNil(expectedCalc)

        let rows = DepreciationScheduleBuilder.build(assets: [asset], fiscalYear: 2025)

        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.currentYearAmount, expectedCalc!.annualAmount,
                        "ScheduleBuilder の当期償却額は DepreciationEngine と一致する")
        XCTAssertEqual(row.accumulatedAmount, expectedCalc!.accumulatedDepreciation,
                        "ScheduleBuilder の累計償却額は DepreciationEngine と一致する")
        XCTAssertEqual(row.bookValue, expectedCalc!.bookValueAfter,
                        "ScheduleBuilder の帳簿価額は DepreciationEngine と一致する")
    }

    // MARK: - Sort Order

    func testBuild_SortsByAcquisitionDate() {
        let newer = createAsset(
            name: "新しい資産",
            acquisitionDate: date(2025, 6, 1),
            acquisitionCost: 200_000,
            usefulLifeYears: 3,
            method: .straightLine
        )
        let older = createAsset(
            name: "古い資産",
            acquisitionDate: date(2024, 1, 1),
            acquisitionCost: 300_000,
            usefulLifeYears: 5,
            method: .straightLine
        )

        let rows = DepreciationScheduleBuilder.build(assets: [newer, older], fiscalYear: 2025)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].assetName, "古い資産", "取得日が早い資産が先に来る")
        XCTAssertEqual(rows[1].assetName, "新しい資産")
    }

    // MARK: - Future Acquisition Excluded

    func testBuild_FutureAcquisition_IsExcluded() {
        let asset = createAsset(
            name: "来年取得予定",
            acquisitionDate: date(2026, 3, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 5,
            method: .straightLine
        )

        let rows = DepreciationScheduleBuilder.build(assets: [asset], fiscalYear: 2025)

        XCTAssertTrue(rows.isEmpty, "対象年度末以降に取得する資産は除外される")
    }

    // MARK: - Helpers

    private func createAsset(
        name: String = "テスト資産",
        acquisitionDate: Date,
        acquisitionCost: Int,
        usefulLifeYears: Int,
        method: PPDepreciationMethod,
        salvageValue: Int = 1,
        assetStatus: PPAssetStatus = .active,
        businessUsePercent: Int = 100
    ) -> PPFixedAsset {
        let asset = PPFixedAsset(
            name: name,
            acquisitionDate: acquisitionDate,
            acquisitionCost: acquisitionCost,
            usefulLifeYears: usefulLifeYears,
            depreciationMethod: method,
            salvageValue: salvageValue,
            assetStatus: assetStatus,
            businessUsePercent: businessUsePercent
        )
        context.insert(asset)
        try! context.save()
        return asset
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
