import Foundation
import SwiftData

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
    private let modelContext: ModelContext
    private let fixedAssetRepository: any FixedAssetRepository
    private let reloadFixedAssets: @MainActor () -> Void
    private let reloadJournalState: @MainActor () -> Void
    private let setError: @MainActor (AppError?) -> Void
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        fixedAssetRepository: (any FixedAssetRepository)? = nil,
        reloadFixedAssets: @escaping @MainActor () -> Void = {},
        reloadJournalState: @escaping @MainActor () -> Void = {},
        setError: @escaping @MainActor (AppError?) -> Void = { _ in },
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.modelContext = modelContext
        self.fixedAssetRepository = fixedAssetRepository ?? SwiftDataFixedAssetRepository(modelContext: modelContext)
        self.reloadFixedAssets = reloadFixedAssets
        self.reloadJournalState = reloadJournalState
        self.setError = setError
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
        guard !isYearLocked(acquisitionFiscalYear) else {
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

        guard saveChanges() else {
            return nil
        }

        setError(nil)
        reloadFixedAssets()
        return asset
    }

    @discardableResult
    func updateAsset(id: UUID, input: FixedAssetUpsertInput) -> Bool {
        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: id) else {
                setError(.fixedAssetNotFound(id: id))
                return false
            }
            asset = fetched
        } catch {
            setError(.saveFailed(underlying: error))
            return false
        }

        let currentFiscalYear = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !isYearLocked(currentFiscalYear) else {
            return false
        }

        let updatedFiscalYear = fiscalYear(for: input.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !isYearLocked(updatedFiscalYear) else {
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

        guard saveChanges() else {
            return false
        }

        setError(nil)
        reloadFixedAssets()
        return true
    }

    @discardableResult
    func disposeAsset(id: UUID, disposalDate: Date, disposalAmount: Int? = nil) -> Bool {
        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: id) else {
                setError(.fixedAssetNotFound(id: id))
                return false
            }
            asset = fetched
        } catch {
            setError(.saveFailed(underlying: error))
            return false
        }

        let acquisitionFiscalYear = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !isYearLocked(acquisitionFiscalYear) else {
            return false
        }

        asset.assetStatus = .disposed
        asset.disposalDate = disposalDate
        asset.disposalAmount = disposalAmount
        asset.updatedAt = Date()

        guard saveChanges() else {
            return false
        }

        setError(nil)
        reloadFixedAssets()
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
            setError(.saveFailed(underlying: error))
            return false
        }

        let acquisitionFiscalYear = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        guard !isYearLocked(acquisitionFiscalYear) else {
            return false
        }

        let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
        let currentYear = calendar.component(.year, from: Date())

        if acquisitionYear <= currentYear {
            for year in acquisitionYear...currentYear {
                let sourceKey = PPFixedAsset.depreciationSourceKey(assetId: id, year: year)
                if let entry = journalEntries().first(where: { $0.sourceKey == sourceKey }) {
                    let linesToDelete = journalLines().filter { $0.entryId == entry.id }
                    for line in linesToDelete {
                        modelContext.delete(line)
                    }
                    modelContext.delete(entry)
                }
            }
        }

        fixedAssetRepository.delete(asset)

        guard saveChanges() else {
            return false
        }

        setError(nil)
        reloadFixedAssets()
        reloadJournalState()
        return true
    }

    @discardableResult
    func postDepreciation(assetId: UUID, fiscalYear: Int) -> PPJournalEntry? {
        guard !isYearLocked(fiscalYear) else {
            return nil
        }

        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: assetId) else {
                setError(.fixedAssetNotFound(id: assetId))
                return nil
            }
            asset = fetched
        } catch {
            setError(.saveFailed(underlying: error))
            return nil
        }

        let priorAccumulated = calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
        let engine = DepreciationEngine(modelContext: modelContext)
        let entry = engine.postDepreciation(
            asset: asset,
            fiscalYear: fiscalYear,
            priorAccumulated: priorAccumulated,
            accounts: accounts()
        )

        if entry != nil {
            guard saveChanges() else {
                return nil
            }
            setError(nil)
            reloadJournalState()
        }

        return entry
    }

    @discardableResult
    func postAllDepreciations(fiscalYear: Int) -> Int {
        guard !isYearLocked(fiscalYear) else {
            return 0
        }

        var count = 0
        let engine = DepreciationEngine(modelContext: modelContext)

        for asset in fixedAssets() where asset.assetStatus == .active {
            let priorAccumulated = calculatePriorAccumulatedDepreciation(asset: asset, beforeYear: fiscalYear)
            let entry = engine.postDepreciation(
                asset: asset,
                fiscalYear: fiscalYear,
                priorAccumulated: priorAccumulated,
                accounts: accounts()
            )
            if entry != nil {
                count += 1
            }
        }

        if count > 0 {
            guard saveChanges() else {
                return 0
            }
            setError(nil)
            reloadJournalState()
        }

        return count
    }

    private func saveChanges() -> Bool {
        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
            return true
        } catch {
            setError(.saveFailed(underlying: error))
            return false
        }
    }

    private func isYearLocked(_ year: Int) -> Bool {
        guard !WorkflowPersistenceSupport.isYearLocked(modelContext: modelContext, year: year) else {
            setError(.yearLocked(year: year))
            return true
        }
        return false
    }

    private func fixedAssets() -> [PPFixedAsset] {
        let descriptor = FetchDescriptor<PPFixedAsset>(sortBy: [SortDescriptor(\.acquisitionDate)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func journalEntries() -> [PPJournalEntry] {
        let descriptor = FetchDescriptor<PPJournalEntry>(sortBy: [SortDescriptor(\.date)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func journalLines() -> [PPJournalLine] {
        let descriptor = FetchDescriptor<PPJournalLine>(sortBy: [SortDescriptor(\.displayOrder)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func accounts() -> [PPAccount] {
        let descriptor = FetchDescriptor<PPAccount>(sortBy: [SortDescriptor(\.displayOrder)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func calculatePriorAccumulatedDepreciation(asset: PPFixedAsset, beforeYear: Int) -> Int {
        let acquisitionYear = calendar.component(.year, from: asset.acquisitionDate)
        var accumulated = 0

        for year in acquisitionYear..<beforeYear {
            guard let calc = DepreciationEngine.calculate(
                asset: asset,
                fiscalYear: year,
                priorAccumulatedDepreciation: accumulated
            ) else {
                continue
            }
            accumulated = calc.accumulatedDepreciation
        }

        return accumulated
    }
}
