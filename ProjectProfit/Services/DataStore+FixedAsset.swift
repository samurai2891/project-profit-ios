import SwiftData
import SwiftUI

// MARK: - DataStore Fixed Asset Extension

extension DataStore {

    // MARK: - CRUD

    @discardableResult
    func addFixedAsset(
        name: String,
        acquisitionDate: Date,
        acquisitionCost: Int,
        usefulLifeYears: Int,
        depreciationMethod: PPDepreciationMethod = .straightLine,
        salvageValue: Int = 1,
        businessUsePercent: Int = 100,
        memo: String? = nil
    ) -> PPFixedAsset? {
        let acquisitionFiscalYear = fiscalYear(for: acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !isYearLocked(acquisitionFiscalYear) else { return nil }

        let asset = PPFixedAsset(
            name: name,
            acquisitionDate: acquisitionDate,
            acquisitionCost: acquisitionCost,
            usefulLifeYears: usefulLifeYears,
            depreciationMethod: depreciationMethod,
            salvageValue: salvageValue,
            memo: memo,
            businessUsePercent: businessUsePercent
        )
        modelContext.insert(asset)
        save()
        refreshFixedAssets()
        return asset
    }

    @discardableResult
    func updateFixedAsset(
        id: UUID,
        name: String? = nil,
        acquisitionDate: Date? = nil,
        acquisitionCost: Int? = nil,
        usefulLifeYears: Int? = nil,
        depreciationMethod: PPDepreciationMethod? = nil,
        salvageValue: Int? = nil,
        assetStatus: PPAssetStatus? = nil,
        disposalDate: Date?? = nil,
        disposalAmount: Int?? = nil,
        businessUsePercent: Int? = nil,
        memo: String?? = nil
    ) -> Bool {
        guard let asset = fixedAssets.first(where: { $0.id == id }) else {
            lastError = .fixedAssetNotFound(id: id)
            return false
        }
        let currentFiscalYear = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !isYearLocked(currentFiscalYear) else { return false }
        if let acquisitionDate {
            let updatedFiscalYear = fiscalYear(for: acquisitionDate, startMonth: FiscalYearSettings.startMonth)
            guard !isYearLocked(updatedFiscalYear) else { return false }
        }

        if let name { asset.name = name }
        if let acquisitionDate { asset.acquisitionDate = acquisitionDate }
        if let acquisitionCost { asset.acquisitionCost = acquisitionCost }
        if let usefulLifeYears { asset.usefulLifeYears = usefulLifeYears }
        if let depreciationMethod { asset.depreciationMethod = depreciationMethod }
        if let salvageValue { asset.salvageValue = salvageValue }
        if let assetStatus { asset.assetStatus = assetStatus }
        if let disposalDate { asset.disposalDate = disposalDate }
        if let disposalAmount { asset.disposalAmount = disposalAmount }
        if let businessUsePercent { asset.businessUsePercent = businessUsePercent }
        if let memo { asset.memo = memo }
        asset.updatedAt = Date()

        save()
        refreshFixedAssets()
        return true
    }

    @discardableResult
    func deleteFixedAsset(id: UUID) -> Bool {
        guard let asset = fixedAssets.first(where: { $0.id == id }) else { return false }
        let acquisitionFiscalYear = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !isYearLocked(acquisitionFiscalYear) else { return false }

        // 関連する減価償却仕訳も削除
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
        let currentYear = calendar.component(.year, from: Date())

        for year in acquisitionYear...currentYear {
            let sourceKey = PPFixedAsset.depreciationSourceKey(assetId: id, year: year)
            if let entry = journalEntries.first(where: { $0.sourceKey == sourceKey }) {
                let linesToDelete = journalLines.filter { $0.entryId == entry.id }
                for line in linesToDelete {
                    modelContext.delete(line)
                }
                modelContext.delete(entry)
            }
        }

        modelContext.delete(asset)
        save()
        refreshFixedAssets()
        refreshJournalEntries()
        refreshJournalLines()
        return true
    }

    func getFixedAsset(id: UUID) -> PPFixedAsset? {
        fixedAssets.first { $0.id == id }
    }

    // MARK: - Depreciation Posting

    /// 指定資産の指定年度の減価償却を計上する
    @discardableResult
    func postDepreciation(assetId: UUID, fiscalYear: Int) -> PPJournalEntry? {
        guard !isYearLocked(fiscalYear) else { return nil }
        guard let asset = fixedAssets.first(where: { $0.id == assetId }) else {
            lastError = .fixedAssetNotFound(id: assetId)
            return nil
        }

        let priorAccumulated = calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
        let engine = DepreciationEngine(modelContext: modelContext)
        let entry = engine.postDepreciation(
            asset: asset,
            fiscalYear: fiscalYear,
            priorAccumulated: priorAccumulated,
            accounts: accounts
        )

        if entry != nil {
            save()
            refreshJournalEntries()
            refreshJournalLines()
        }
        return entry
    }

    /// 全資産の指定年度の減価償却を一括計上する
    @discardableResult
    func postAllDepreciations(fiscalYear: Int) -> Int {
        guard !isYearLocked(fiscalYear) else { return 0 }

        var count = 0
        let engine = DepreciationEngine(modelContext: modelContext)

        for asset in fixedAssets where asset.assetStatus == .active {
            let priorAccumulated = calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
            let entry = engine.postDepreciation(
                asset: asset,
                fiscalYear: fiscalYear,
                priorAccumulated: priorAccumulated,
                accounts: accounts
            )
            if entry != nil { count += 1 }
        }

        if count > 0 {
            save()
            refreshJournalEntries()
            refreshJournalLines()
        }
        return count
    }

    /// 指定年度より前の累計償却額を計算する
    func calculatePriorAccumulatedDepreciation(asset: PPFixedAsset, beforeYear: Int) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
        var accumulated = 0

        for year in acquisitionYear..<beforeYear {
            guard let calc = DepreciationEngine.calculate(
                asset: asset,
                fiscalYear: year,
                priorAccumulatedDepreciation: accumulated
            ) else { continue }
            accumulated = calc.accumulatedDepreciation
        }

        return accumulated
    }

    /// 指定資産の全年度償却スケジュールをプレビューする
    func previewDepreciationSchedule(asset: PPFixedAsset) -> [DepreciationCalculation] {
        let calendar = Calendar(identifier: .gregorian)
        let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
        let currentYear = calendar.component(.year, from: Date())
        // 耐用年数 + 余裕を持ってスケジュールを生成
        let endYear = acquisitionYear + asset.usefulLifeYears + 1

        var schedule: [DepreciationCalculation] = []
        var accumulated = 0

        for year in acquisitionYear...max(currentYear, endYear) {
            guard let calc = DepreciationEngine.calculate(
                asset: asset,
                fiscalYear: year,
                priorAccumulatedDepreciation: accumulated
            ) else { continue }
            schedule.append(calc)
            accumulated = calc.accumulatedDepreciation
        }

        return schedule
    }
}
