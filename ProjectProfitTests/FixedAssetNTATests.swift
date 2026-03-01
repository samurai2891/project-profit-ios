import XCTest
import SwiftData
@testable import ProjectProfit

/// 固定資産台帳（NTA p.16-17）の減価償却データ層テスト
/// 必要経費算入額（= 償却額 x 事業専用割合 / 100）を含むNTA準拠の検証
@MainActor
final class FixedAssetNTATests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - 1. 定額法 初年度 (1月取得 = フル12ヶ月)

    func testFixedAsset_StraightLine_FirstYear() {
        // 1,000,000円 / 4年定額法 / 2025年1月取得
        // 償却基礎額 = 1,000,000 - 1 = 999,999
        // 年間償却額 = 999,999 / 4 = 249,999 (端数切捨)
        // 1月取得 → 12ヶ月分 = 249,999 * 12/12 = 249,999
        guard let asset = dataStore.addFixedAsset(
            name: "MacBook Pro",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let schedule = dataStore.previewDepreciationSchedule(asset: asset)
        XCTAssertFalse(schedule.isEmpty, "スケジュールが空でないこと")

        let firstYear = schedule.first { $0.fiscalYear == 2025 }
        XCTAssertNotNil(firstYear, "2025年度のエントリが存在すること")
        XCTAssertEqual(firstYear?.annualAmount, 249_999, "当期償却額 = 249,999")
        XCTAssertEqual(firstYear?.accumulatedDepreciation, 249_999, "初年度累計 = 249,999")
        XCTAssertEqual(firstYear?.bookValueAfter, 750_001, "帳簿価額 = 1,000,000 - 249,999")

        // ScheduleBuilder でも同一の結果を確認
        let rows = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: 2025
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].currentYearAmount, 249_999)
    }

    // MARK: - 2. 定額法 2年目 (累計確認)

    func testFixedAsset_StraightLine_SecondYear() {
        // 2024年1月取得 → 2025年度が2年目
        // 1年目: 249,999、2年目: 249,999、累計: 499,998
        guard let asset = dataStore.addFixedAsset(
            name: "iMac",
            acquisitionDate: date(2024, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let rows = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: 2025
        )
        XCTAssertEqual(rows.count, 1)

        let row = rows[0]
        XCTAssertEqual(row.currentYearAmount, 249_999, "2年目の当期償却額 = 249,999")
        XCTAssertEqual(row.accumulatedAmount, 499_998, "累計償却額 = 249,999 x 2")
        XCTAssertEqual(row.bookValue, 500_002, "帳簿価額 = 1,000,000 - 499,998")
    }

    // MARK: - 3. 事業使用割合80% (必要経費算入額)

    func testFixedAsset_BusinessUsePercent_80() {
        // 300,000円 / 5年 / 80%事業使用
        // 償却基礎額 = 300,000 - 1 = 299,999
        // 年間償却額 = 299,999 / 5 = 59,999
        // 必要経費算入額 = 59,999 * 80 / 100 = 47,999
        guard let asset = dataStore.addFixedAsset(
            name: "デスク",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 300_000,
            usefulLifeYears: 5,
            businessUsePercent: 80
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let schedule = dataStore.previewDepreciationSchedule(asset: asset)
        let firstYear = schedule.first { $0.fiscalYear == 2025 }
        XCTAssertNotNil(firstYear)

        let annualAmount = firstYear!.annualAmount
        XCTAssertEqual(annualAmount, 59_999, "当期償却額 = 59,999")

        let expectedBusinessAmount = annualAmount * 80 / 100
        XCTAssertEqual(firstYear!.businessAmount, expectedBusinessAmount,
                       "必要経費算入額 = 当期償却額 x 80/100")
        XCTAssertEqual(firstYear!.personalAmount, annualAmount - expectedBusinessAmount,
                       "家事使用分 = 当期償却額 - 必要経費算入額")

        // ScheduleBuilder の businessUsePercent フィールドも確認
        let rows = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: 2025
        )
        XCTAssertEqual(rows[0].businessUsePercent, 80)
    }

    // MARK: - 4. 事業使用割合50% (必要経費算入額)

    func testFixedAsset_BusinessUsePercent_50() {
        // 50%事業使用 → deductible = depreciation * 50 / 100
        guard let asset = dataStore.addFixedAsset(
            name: "自宅兼事務所チェア",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 200_000,
            usefulLifeYears: 5,
            businessUsePercent: 50
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        // 償却基礎額 = 200,000 - 1 = 199,999
        // 年間償却額 = 199,999 / 5 = 39,999
        let schedule = dataStore.previewDepreciationSchedule(asset: asset)
        let firstYear = schedule.first { $0.fiscalYear == 2025 }
        XCTAssertNotNil(firstYear)

        let annualAmount = firstYear!.annualAmount
        XCTAssertEqual(annualAmount, 39_999, "当期償却額 = 39,999")

        let deductible = annualAmount * 50 / 100
        XCTAssertEqual(firstYear!.businessAmount, deductible,
                       "必要経費算入額 = 償却額 x 50/100")
        XCTAssertEqual(firstYear!.personalAmount, annualAmount - deductible,
                       "家事使用分 = 償却額 - 必要経費算入額")

        // 事業分と家事分の合計が償却額と一致
        XCTAssertEqual(
            firstYear!.businessAmount + firstYear!.personalAmount,
            firstYear!.annualAmount,
            "事業分 + 家事分 = 償却額"
        )
    }

    // MARK: - 5. 全額償却済み → bookValue = 1 (残存価額1円)

    func testFixedAsset_FullyDepreciated() {
        // 2020年1月取得、4年耐用年数 → 2024年までに999,996償却
        // 2024年に残り3を償却 → 帳簿価額1円
        guard let asset = dataStore.addFixedAsset(
            name: "古いPC",
            acquisitionDate: date(2020, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let schedule = dataStore.previewDepreciationSchedule(asset: asset)
        XCTAssertFalse(schedule.isEmpty)

        // 最終エントリの帳簿価額が1円（備忘価額）
        let lastEntry = schedule.last!
        XCTAssertEqual(lastEntry.bookValueAfter, 1, "残存価額は1円（備忘価額）")
        XCTAssertEqual(lastEntry.accumulatedDepreciation, 999_999,
                       "累計償却額 = 取得価額 - 残存価額")

        // 全額償却後の年度ではスケジュールにcurrentYearAmount=0で表示
        let rows = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: 2026
        )
        XCTAssertEqual(rows.count, 1, "全額償却済み資産もアクティブなら明細に含まれる")
        XCTAssertEqual(rows[0].currentYearAmount, 0, "全額償却後は当期償却額0")
        XCTAssertEqual(rows[0].bookValue, 1, "帳簿価額 = 残存1円")
    }

    // MARK: - 6. 除却済み資産はスケジュールから除外

    func testFixedAsset_DisposedExcluded() {
        guard let asset = dataStore.addFixedAsset(
            name: "除却済みプリンター",
            acquisitionDate: date(2023, 1, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 5
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        // ステータスを除却済みに更新
        let updated = dataStore.updateFixedAsset(
            id: asset.id,
            assetStatus: .disposed,
            disposalDate: .some(date(2024, 6, 15))
        )
        XCTAssertTrue(updated)

        let rows = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: 2025
        )
        XCTAssertTrue(rows.isEmpty, "除却済み資産は明細表から除外される")
    }

    // MARK: - 7. 売却済み資産は除外

    func testFixedAsset_SoldExcluded() {
        guard let asset = dataStore.addFixedAsset(
            name: "売却済みモニター",
            acquisitionDate: date(2023, 1, 1),
            acquisitionCost: 300_000,
            usefulLifeYears: 5
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        // ステータスを売却済みに更新
        let updated = dataStore.updateFixedAsset(
            id: asset.id,
            assetStatus: .sold,
            disposalDate: .some(date(2024, 9, 1)),
            disposalAmount: .some(100_000)
        )
        XCTAssertTrue(updated)

        let rows = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: 2025
        )
        XCTAssertTrue(rows.isEmpty, "売却済み資産は明細表から除外される")
    }

    // MARK: - 8. 将来取得予定は除外

    func testFixedAsset_FutureAcquisitionExcluded() {
        guard dataStore.addFixedAsset(
            name: "来年購入予定のPC",
            acquisitionDate: date(2026, 4, 1),
            acquisitionCost: 800_000,
            usefulLifeYears: 4
        ) != nil else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let rows = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: 2025
        )
        XCTAssertTrue(rows.isEmpty, "対象年度末以降に取得する資産は除外される")

        // DepreciationEngine の直接計算でも nil
        let asset = dataStore.fixedAssets[0]
        let calc = DepreciationEngine.calculate(
            asset: asset,
            fiscalYear: 2025,
            priorAccumulatedDepreciation: 0
        )
        XCTAssertNil(calc, "取得前年度の償却計算は nil")
    }

    // MARK: - 9. 複数資産は取得日順にソート

    func testFixedAsset_SortByAcquisitionDate() {
        dataStore.addFixedAsset(
            name: "3番目: 2025年6月",
            acquisitionDate: date(2025, 6, 1),
            acquisitionCost: 200_000,
            usefulLifeYears: 4
        )
        dataStore.addFixedAsset(
            name: "1番目: 2023年1月",
            acquisitionDate: date(2023, 1, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 5
        )
        dataStore.addFixedAsset(
            name: "2番目: 2024年4月",
            acquisitionDate: date(2024, 4, 1),
            acquisitionCost: 300_000,
            usefulLifeYears: 5
        )

        let rows = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: 2025
        )

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].assetName, "1番目: 2023年1月", "最古の取得日が先")
        XCTAssertEqual(rows[1].assetName, "2番目: 2024年4月")
        XCTAssertEqual(rows[2].assetName, "3番目: 2025年6月", "最新の取得日が後")
    }

    // MARK: - 10. 減価償却仕訳が生成される

    func testFixedAsset_PostDepreciation_CreatesJournalEntry() {
        guard let asset = dataStore.addFixedAsset(
            name: "業務用PC",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4,
            businessUsePercent: 100
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let entry = dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)

        XCTAssertNotNil(entry, "仕訳が生成されること")
        XCTAssertTrue(entry!.isPosted, "仕訳がポスト済みであること")

        // 仕訳明細を確認: 100%事業使用なら2行（借方:減価償却費、貸方:累計額）
        let lines = dataStore.getJournalLines(for: entry!.id)
        XCTAssertEqual(lines.count, 2, "100%事業使用 → 2行仕訳")

        let debitLine = lines.first { $0.debit > 0 }
        XCTAssertEqual(debitLine?.accountId, AccountingConstants.depreciationExpenseAccountId)
        XCTAssertEqual(debitLine?.debit, 249_999)

        let creditLine = lines.first { $0.credit > 0 }
        XCTAssertEqual(creditLine?.accountId, AccountingConstants.accumulatedDepreciationAccountId)
        XCTAssertEqual(creditLine?.credit, 249_999)

        // sourceKey が正しいフォーマット
        let expectedSourceKey = PPFixedAsset.depreciationSourceKey(assetId: asset.id, year: 2025)
        XCTAssertEqual(entry!.sourceKey, expectedSourceKey)
    }

    // MARK: - 11. 複数資産一括計上

    func testFixedAsset_PostAllDepreciations() {
        dataStore.addFixedAsset(
            name: "PC",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 4
        )
        dataStore.addFixedAsset(
            name: "モニター",
            acquisitionDate: date(2025, 3, 1),
            acquisitionCost: 200_000,
            usefulLifeYears: 5
        )
        dataStore.addFixedAsset(
            name: "キーボード",
            acquisitionDate: date(2025, 6, 1),
            acquisitionCost: 100_000,
            usefulLifeYears: 4
        )

        let count = dataStore.postAllDepreciations(fiscalYear: 2025)
        XCTAssertEqual(count, 3, "3資産すべて計上される")

        // 各資産の仕訳が存在することを確認
        for asset in dataStore.fixedAssets {
            let sourceKey = PPFixedAsset.depreciationSourceKey(assetId: asset.id, year: 2025)
            let hasEntry = dataStore.journalEntries.contains { $0.sourceKey == sourceKey }
            XCTAssertTrue(hasEntry, "\(asset.name)の減価償却仕訳が存在する")
        }

        // 冪等性: 再度実行しても新規仕訳は生成されない
        let secondCount = dataStore.postAllDepreciations(fiscalYear: 2025)
        XCTAssertEqual(secondCount, 3, "冪等: 既存仕訳を返すためカウントは同じ")
    }

    // MARK: - 12. ScheduleBuilder結果がDepreciationEngineと一致

    func testFixedAsset_ScheduleBuilder_MatchesEngine() {
        guard let asset = dataStore.addFixedAsset(
            name: "検証用資産",
            acquisitionDate: date(2024, 4, 1),
            acquisitionCost: 600_000,
            usefulLifeYears: 5,
            businessUsePercent: 80
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        // DepreciationEngine で2024年（初年度）を計算
        let priorCalc = DepreciationEngine.calculate(
            asset: asset,
            fiscalYear: 2024,
            priorAccumulatedDepreciation: 0
        )
        XCTAssertNotNil(priorCalc)
        let priorAccumulated = priorCalc!.accumulatedDepreciation

        // DepreciationEngine で2025年（2年目）を計算
        let engineCalc = DepreciationEngine.calculate(
            asset: asset,
            fiscalYear: 2025,
            priorAccumulatedDepreciation: priorAccumulated
        )
        XCTAssertNotNil(engineCalc)

        // ScheduleBuilder で2025年の行を取得
        let rows = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: 2025
        )
        XCTAssertEqual(rows.count, 1)

        let row = rows[0]
        XCTAssertEqual(row.currentYearAmount, engineCalc!.annualAmount,
                       "ScheduleBuilder の当期償却額は DepreciationEngine と一致する")
        XCTAssertEqual(row.accumulatedAmount, engineCalc!.accumulatedDepreciation,
                       "ScheduleBuilder の累計償却額は DepreciationEngine と一致する")
        XCTAssertEqual(row.bookValue, engineCalc!.bookValueAfter,
                       "ScheduleBuilder の帳簿価額は DepreciationEngine と一致する")
        XCTAssertEqual(row.businessUsePercent, 80,
                       "事業使用割合が正しく伝搬される")
    }

    // MARK: - 13. 年中取得 → 初年度月割り

    func testFixedAsset_MidYearAcquisition() {
        // 4月取得 → 初年度 = 13 - 4 = 9ヶ月分
        // 償却基礎額 = 1,000,000 - 1 = 999,999
        // 年間償却額 = 999,999 / 4 = 249,999
        // 初年度 = 249,999 * 9 / 12 = 187,499 (端数切捨)
        guard let asset = dataStore.addFixedAsset(
            name: "4月取得PC",
            acquisitionDate: date(2025, 4, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let schedule = dataStore.previewDepreciationSchedule(asset: asset)
        let firstYear = schedule.first { $0.fiscalYear == 2025 }
        XCTAssertNotNil(firstYear)

        // 4月取得: 4月～12月 = 9ヶ月
        // 249,999 * 9 / 12 = 187,499 (整数除算)
        XCTAssertEqual(firstYear!.annualAmount, 187_499, "初年度月割り = 249,999 * 9/12")

        // 2年目はフル12ヶ月
        let secondYear = schedule.first { $0.fiscalYear == 2026 }
        XCTAssertNotNil(secondYear)
        XCTAssertEqual(secondYear!.annualAmount, 249_999, "2年目はフル年額")

        // 累計が正しいか
        XCTAssertEqual(
            secondYear!.accumulatedDepreciation,
            187_499 + 249_999,
            "2年目累計 = 初年度 + 2年目"
        )

        // 7月取得のケースも検証
        guard let asset7 = dataStore.addFixedAsset(
            name: "7月取得PC",
            acquisitionDate: date(2025, 7, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let schedule7 = dataStore.previewDepreciationSchedule(asset: asset7)
        let firstYear7 = schedule7.first { $0.fiscalYear == 2025 }
        XCTAssertNotNil(firstYear7)

        // 7月取得: 13 - 7 = 6ヶ月
        // 249,999 * 6 / 12 = 124,999
        XCTAssertEqual(firstYear7!.annualAmount, 124_999, "7月取得 → 6ヶ月分 = 124,999")
    }

    // MARK: - 14. 取得→1年目→2年目の完全フロー

    func testFixedAsset_AnnualDepreciationFlow() {
        // 500,000円 / 5年 / 2024年1月取得
        // 償却基礎額 = 500,000 - 1 = 499,999
        // 年間償却額 = 499,999 / 5 = 99,999
        guard let asset = dataStore.addFixedAsset(
            name: "フロー検証資産",
            acquisitionDate: date(2024, 1, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 5
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        // 1年目計上
        let entry1 = dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2024)
        XCTAssertNotNil(entry1, "1年目の仕訳が生成される")

        let lines1 = dataStore.getJournalLines(for: entry1!.id)
        let debit1 = lines1.filter { $0.debit > 0 }.reduce(0) { $0 + $1.debit }
        XCTAssertEqual(debit1, 99_999, "1年目の償却費 = 99,999")

        // 2年目計上
        let entry2 = dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)
        XCTAssertNotNil(entry2, "2年目の仕訳が生成される")

        let lines2 = dataStore.getJournalLines(for: entry2!.id)
        let debit2 = lines2.filter { $0.debit > 0 }.reduce(0) { $0 + $1.debit }
        XCTAssertEqual(debit2, 99_999, "2年目の償却費 = 99,999")

        // 累計がスケジュールと一致するか検証
        let prior = dataStore.calculatePriorAccumulatedDepreciation(
            asset: asset, beforeYear: 2026
        )
        XCTAssertEqual(prior, 199_998, "2年分の累計 = 99,999 x 2")

        // ScheduleBuilder でも整合
        let rows = DepreciationScheduleBuilder.build(
            assets: dataStore.fixedAssets,
            fiscalYear: 2025
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].accumulatedAmount, 199_998, "ScheduleBuilder 累計も一致")
        XCTAssertEqual(rows[0].bookValue, 300_002, "帳簿価額 = 500,000 - 199,998")
    }

    // MARK: - 追加テスト: 事業使用割合ありの仕訳明細 (3行仕訳)

    func testFixedAsset_PostDepreciation_WithBusinessUsePercent_Creates3Lines() {
        // 80%事業使用 → 借方:減価償却費(事業分) + 借方:事業主貸(家事分) + 貸方:累計額
        guard let asset = dataStore.addFixedAsset(
            name: "自宅兼事務所デスク",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 500_000,
            usefulLifeYears: 5,
            businessUsePercent: 80
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        // 償却基礎額 = 499,999、年間 = 99,999
        // 事業分 = 99,999 * 80 / 100 = 79,999
        // 家事分 = 99,999 - 79,999 = 20,000
        let entry = dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)
        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.isPosted)

        let lines = dataStore.getJournalLines(for: entry!.id)
        XCTAssertEqual(lines.count, 3, "80%事業使用 → 3行仕訳")

        let expenseLine = lines.first {
            $0.accountId == AccountingConstants.depreciationExpenseAccountId
        }
        XCTAssertNotNil(expenseLine, "減価償却費の行が存在する")
        XCTAssertEqual(expenseLine?.debit, 79_999, "必要経費算入額 = 79,999")

        let drawingsLine = lines.first {
            $0.accountId == AccountingConstants.ownerDrawingsAccountId
        }
        XCTAssertNotNil(drawingsLine, "事業主貸の行が存在する")
        XCTAssertEqual(drawingsLine?.debit, 20_000, "家事使用分 = 20,000")

        let accumLine = lines.first {
            $0.accountId == AccountingConstants.accumulatedDepreciationAccountId
        }
        XCTAssertNotNil(accumLine, "減価償却累計額の行が存在する")
        XCTAssertEqual(accumLine?.credit, 99_999, "貸方合計 = 当期償却額")

        // 貸借一致
        let totalDebit = (expenseLine?.debit ?? 0) + (drawingsLine?.debit ?? 0)
        XCTAssertEqual(totalDebit, accumLine?.credit ?? 0,
                       "借方合計 == 貸方合計（貸借一致）")
    }

    // MARK: - 追加テスト: 冪等性 (同一年度の二重計上防止)

    func testFixedAsset_PostDepreciation_Idempotent() {
        guard let asset = dataStore.addFixedAsset(
            name: "冪等性検証用",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 400_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let first = dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)
        let second = dataStore.postDepreciation(assetId: asset.id, fiscalYear: 2025)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first!.id, second!.id, "同一年度の二重計上防止: 同じ仕訳が返る")
    }

    // MARK: - 追加テスト: 全年度スケジュールの整合性

    func testFixedAsset_FullSchedule_TotalEqualsDepreciableBasis() {
        guard let asset = dataStore.addFixedAsset(
            name: "全期間検証",
            acquisitionDate: date(2025, 1, 1),
            acquisitionCost: 1_000_000,
            usefulLifeYears: 4
        ) else {
            XCTFail("固定資産追加に失敗")
            return
        }

        let schedule = dataStore.previewDepreciationSchedule(asset: asset)
        XCTAssertFalse(schedule.isEmpty)

        let totalDepreciation = schedule.reduce(0) { $0 + $1.annualAmount }
        XCTAssertEqual(totalDepreciation, 999_999,
                       "全期間の償却合計 = 取得価額 - 残存価額(1円)")

        XCTAssertEqual(schedule.last!.bookValueAfter, 1,
                       "最終帳簿価額 = 残存1円")
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
