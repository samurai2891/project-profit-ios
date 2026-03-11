import Foundation

struct FixedAssetUpsertInput: Equatable, Sendable {
    let name: String
    let acquisitionDate: Date
    let acquisitionCost: Int
    let usefulLifeYears: Int
    let depreciationMethod: PPDepreciationMethod
    let salvageValue: Int
    let businessUsePercent: Int
    let memo: String?
}

@MainActor
struct FixedAssetWorkflowUseCase {
    private let dataStore: DataStore
    private let fixedAssetRepository: any FixedAssetRepository
    private let calendar: Calendar

    init(
        dataStore: DataStore,
        fixedAssetRepository: (any FixedAssetRepository)? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.dataStore = dataStore
        self.fixedAssetRepository = fixedAssetRepository ?? SwiftDataFixedAssetRepository(modelContext: dataStore.modelContext)
        self.calendar = calendar
    }

    @discardableResult
    func saveAsset(existingAssetId: UUID?, input: FixedAssetUpsertInput) -> Bool {
        if let existingAssetId {
            return updateAsset(id: existingAssetId, input: input)
        }
        return createAsset(input: input) != nil
    }

    @discardableResult
    func createAsset(input: FixedAssetUpsertInput) -> PPFixedAsset? {
        let acquisitionFiscalYear = fiscalYear(for: input.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !dataStore.isYearLocked(acquisitionFiscalYear) else {
            return nil
        }

        let asset = PPFixedAsset(
            name: input.name,
            acquisitionDate: input.acquisitionDate,
            acquisitionCost: input.acquisitionCost,
            usefulLifeYears: input.usefulLifeYears,
            depreciationMethod: input.depreciationMethod,
            salvageValue: input.salvageValue,
            memo: input.memo,
            businessUsePercent: input.businessUsePercent
        )
        fixedAssetRepository.insert(asset)

        guard dataStore.save() else {
            return nil
        }

        dataStore.refreshFixedAssets()
        return asset
    }

    @discardableResult
    func updateAsset(id: UUID, input: FixedAssetUpsertInput) -> Bool {
        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: id) else {
                dataStore.lastError = .fixedAssetNotFound(id: id)
                return false
            }
            asset = fetched
        } catch {
            return false
        }

        let currentFiscalYear = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !dataStore.isYearLocked(currentFiscalYear) else {
            return false
        }

        let updatedFiscalYear = fiscalYear(for: input.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !dataStore.isYearLocked(updatedFiscalYear) else {
            return false
        }

        asset.name = input.name
        asset.acquisitionDate = input.acquisitionDate
        asset.acquisitionCost = input.acquisitionCost
        asset.usefulLifeYears = input.usefulLifeYears
        asset.depreciationMethod = input.depreciationMethod
        asset.salvageValue = input.salvageValue
        asset.businessUsePercent = input.businessUsePercent
        asset.memo = input.memo
        asset.updatedAt = Date()

        guard dataStore.save() else {
            return false
        }

        dataStore.refreshFixedAssets()
        return true
    }

    @discardableResult
    func disposeAsset(id: UUID, disposalDate: Date, disposalAmount: Int? = nil) -> Bool {
        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: id) else {
                dataStore.lastError = .fixedAssetNotFound(id: id)
                return false
            }
            asset = fetched
        } catch {
            return false
        }

        let acquisitionFiscalYear = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !dataStore.isYearLocked(acquisitionFiscalYear) else {
            return false
        }

        asset.assetStatus = .disposed
        asset.disposalDate = disposalDate
        asset.disposalAmount = disposalAmount
        asset.updatedAt = Date()

        guard dataStore.save() else {
            return false
        }

        dataStore.refreshFixedAssets()
        return true
    }

    @discardableResult
    func deleteAsset(id: UUID) -> Bool {
        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: id) else {
                return false
            }
            asset = fetched
        } catch {
            return false
        }

        let acquisitionFiscalYear = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !dataStore.isYearLocked(acquisitionFiscalYear) else {
            return false
        }

        let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
        let currentYear = calendar.component(.year, from: Date())

        if acquisitionYear <= currentYear {
            for year in acquisitionYear...currentYear {
                let sourceKey = PPFixedAsset.depreciationSourceKey(assetId: id, year: year)
                if let entry = dataStore.journalEntries.first(where: { $0.sourceKey == sourceKey }) {
                    let linesToDelete = dataStore.journalLines.filter { $0.entryId == entry.id }
                    for line in linesToDelete {
                        dataStore.modelContext.delete(line)
                    }
                    dataStore.modelContext.delete(entry)
                }
            }
        }

        fixedAssetRepository.delete(asset)

        guard dataStore.save() else {
            return false
        }

        dataStore.refreshFixedAssets()
        dataStore.refreshJournalEntries()
        dataStore.refreshJournalLines()
        return true
    }

    @discardableResult
    func postDepreciation(assetId: UUID, fiscalYear: Int) -> PPJournalEntry? {
        guard !dataStore.isYearLocked(fiscalYear) else {
            return nil
        }

        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: assetId) else {
                dataStore.lastError = .fixedAssetNotFound(id: assetId)
                return nil
            }
            asset = fetched
        } catch {
            return nil
        }

        let priorAccumulated = dataStore.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
        let engine = DepreciationEngine(modelContext: dataStore.modelContext)
        let entry = engine.postDepreciation(
            asset: asset,
            fiscalYear: fiscalYear,
            priorAccumulated: priorAccumulated,
            accounts: dataStore.accounts
        )

        if entry != nil {
            guard dataStore.save() else {
                return nil
            }
            dataStore.refreshJournalEntries()
            dataStore.refreshJournalLines()
        }

        return entry
    }

    @discardableResult
    func postAllDepreciations(fiscalYear: Int) -> Int {
        guard !dataStore.isYearLocked(fiscalYear) else {
            return 0
        }

        var count = 0
        let engine = DepreciationEngine(modelContext: dataStore.modelContext)

        for asset in dataStore.fixedAssets where asset.assetStatus == .active {
            let priorAccumulated = dataStore.calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
            let entry = engine.postDepreciation(
                asset: asset,
                fiscalYear: fiscalYear,
                priorAccumulated: priorAccumulated,
                accounts: dataStore.accounts
            )
            if entry != nil {
                count += 1
            }
        }

        if count > 0 {
            guard dataStore.save() else {
                return 0
            }
            dataStore.refreshJournalEntries()
            dataStore.refreshJournalLines()
        }

        return count
    }
}
