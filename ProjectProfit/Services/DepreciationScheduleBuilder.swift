import Foundation

// MARK: - DepreciationScheduleRow

/// 減価償却明細表の1行
struct DepreciationScheduleRow: Identifiable {
    let id: UUID              // assetId
    let assetName: String
    let acquisitionDate: Date
    let acquisitionCost: Int
    let usefulLifeYears: Int
    let depreciationMethod: DepreciationMethod
    let currentYearAmount: Int      // 当期償却額
    let accumulatedAmount: Int      // 累計償却額
    let bookValue: Int              // 期末帳簿価額
    let businessUsePercent: Int
}

// MARK: - DepreciationScheduleBuilder

/// 減価償却明細表ビルダー
@MainActor
enum DepreciationScheduleBuilder {

    /// 固定資産リストから指定年度の減価償却明細表を生成する
    /// - Parameters:
    ///   - assets: 固定資産の配列
    ///   - fiscalYear: 対象年度
    /// - Returns: 取得日順にソートされた減価償却明細行の配列
    static func build(
        assets: [PPFixedAsset],
        fiscalYear: Int
    ) -> [DepreciationScheduleRow] {
        let calendar = Calendar(identifier: .gregorian)

        let activeAssets = assets.filter { $0.assetStatus == .active }

        let rows: [DepreciationScheduleRow] = activeAssets.compactMap { asset in
            let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)

            // 対象年度末までに取得されていない資産は除外
            guard acquisitionYear <= fiscalYear else { return nil }

            // 取得年度から前年度までの累計償却額を計算
            let priorAccumulated = calculatePriorAccumulated(
                asset: asset,
                fromYear: acquisitionYear,
                toYearExclusive: fiscalYear
            )

            // 対象年度の償却計算
            let calculation = DepreciationEngine.calculate(
                asset: asset,
                fiscalYear: fiscalYear,
                priorAccumulatedDepreciation: priorAccumulated
            )

            if let calc = calculation {
                return DepreciationScheduleRow(
                    id: asset.id,
                    assetName: asset.name,
                    acquisitionDate: asset.acquisitionDate,
                    acquisitionCost: asset.acquisitionCost,
                    usefulLifeYears: asset.usefulLifeYears,
                    depreciationMethod: asset.depreciationMethod,
                    currentYearAmount: calc.annualAmount,
                    accumulatedAmount: calc.accumulatedDepreciation,
                    bookValue: calc.bookValueAfter,
                    businessUsePercent: asset.businessUsePercent
                )
            }

            // 償却結果なし（全額償却済み等）でも取得済み資産は明細に含める
            let bookValue = asset.acquisitionCost - priorAccumulated
            return DepreciationScheduleRow(
                id: asset.id,
                assetName: asset.name,
                acquisitionDate: asset.acquisitionDate,
                acquisitionCost: asset.acquisitionCost,
                usefulLifeYears: asset.usefulLifeYears,
                depreciationMethod: asset.depreciationMethod,
                currentYearAmount: 0,
                accumulatedAmount: priorAccumulated,
                bookValue: bookValue,
                businessUsePercent: asset.businessUsePercent
            )
        }

        return rows.sorted { $0.acquisitionDate < $1.acquisitionDate }
    }

    // MARK: - Private

    /// 取得年度から指定年度（排他）までの累計償却額を計算する
    /// - Parameters:
    ///   - asset: 固定資産
    ///   - fromYear: 開始年度（取得年度）
    ///   - toYearExclusive: 終了年度（排他、この年度は含まない）
    /// - Returns: 累計償却額
    private static func calculatePriorAccumulated(
        asset: PPFixedAsset,
        fromYear: Int,
        toYearExclusive: Int
    ) -> Int {
        var accumulated = 0

        for year in fromYear..<toYearExclusive {
            guard let calc = DepreciationEngine.calculate(
                asset: asset,
                fiscalYear: year,
                priorAccumulatedDepreciation: accumulated
            ) else {
                // この年度の償却がなければ累計は変わらない
                continue
            }
            accumulated = calc.accumulatedDepreciation
        }

        return accumulated
    }
}
