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
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        fixedAssetRepository: (any FixedAssetRepository)? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.modelContext = modelContext
        self.fixedAssetRepository = fixedAssetRepository ?? SwiftDataFixedAssetRepository(modelContext: modelContext)
        self.calendar = calendar
    }

    func saveAsset(existingAssetId: UUID?, input: FixedAssetUpsertInput) throws {
        if let existingAssetId {
            try updateAsset(id: existingAssetId, input: input)
            return
        }
        _ = try createAsset(input: input)
    }

    func createAsset(input: FixedAssetUpsertInput) throws -> PPFixedAsset {
        let acquisitionFiscalYear = fiscalYear(for: input.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        try validateYearIsOpen(acquisitionFiscalYear)

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
        try saveChanges()
        return asset
    }

    func updateAsset(id: UUID, input: FixedAssetUpsertInput) throws {
        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: id) else {
                throw AppError.fixedAssetNotFound(id: id)
            }
            asset = fetched
        } catch {
            throw wrapped(error)
        }

        let currentFiscalYear = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        try validateYearIsOpen(currentFiscalYear)

        let updatedFiscalYear = fiscalYear(for: input.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        try validateYearIsOpen(updatedFiscalYear)

        asset.name = input.name
        asset.acquisitionDate = input.acquisitionDate
        asset.acquisitionCost = input.acquisitionCost
        asset.usefulLifeYears = input.usefulLifeYears
        asset.depreciationMethod = input.depreciationMethod
        asset.salvageValue = input.salvageValue
        asset.businessUsePercent = input.businessUsePercent
        asset.memo = input.memo
        asset.updatedAt = Date()

        try saveChanges()
    }

    func disposeAsset(id: UUID, disposalDate: Date, disposalAmount: Int? = nil) throws {
        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: id) else {
                throw AppError.fixedAssetNotFound(id: id)
            }
            asset = fetched
        } catch {
            throw wrapped(error)
        }

        let acquisitionFiscalYear = fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth)
        try validateYearIsOpen(acquisitionFiscalYear)
        let disposalFiscalYear = fiscalYear(for: disposalDate, startMonth: FiscalYearSettings.startMonth)
        try validateYearIsOpen(disposalFiscalYear)

        asset.assetStatus = .disposed
        asset.disposalDate = disposalDate
        asset.disposalAmount = disposalAmount
        asset.updatedAt = Date()

        try saveChanges()
    }

    func deleteAsset(id: UUID) throws {
        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: id) else {
                throw AppError.fixedAssetNotFound(id: id)
            }
            asset = fetched
        } catch {
            throw wrapped(error)
        }

        let depreciationEntries = depreciationEntries(forAssetId: id)
        try validateYearsOpenForDeletion(asset: asset, depreciationEntries: depreciationEntries)

        for entry in depreciationEntries {
            let linesToDelete = journalLines().filter { $0.entryId == entry.id }
            for line in linesToDelete {
                modelContext.delete(line)
            }
            modelContext.delete(entry)
        }

        fixedAssetRepository.delete(asset)
        try saveChanges()
    }

    func postDepreciation(assetId: UUID, fiscalYear: Int) throws -> PPJournalEntry? {
        try validateYearIsOpen(fiscalYear)

        let asset: PPFixedAsset
        do {
            guard let fetched = try fixedAssetRepository.fixedAsset(id: assetId) else {
                throw AppError.fixedAssetNotFound(id: assetId)
            }
            asset = fetched
        } catch {
            throw wrapped(error)
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
            try saveChanges()
        }

        return entry
    }

    func postAllDepreciations(fiscalYear: Int) throws -> Int {
        try validateYearIsOpen(fiscalYear)

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
            try saveChanges()
        }

        return count
    }

    private func saveChanges() throws {
        do {
            try WorkflowPersistenceSupport.save(modelContext: modelContext)
        } catch {
            throw AppError.saveFailed(underlying: error)
        }
    }

    private func validateYearIsOpen(_ year: Int) throws {
        if WorkflowPersistenceSupport.isYearLocked(modelContext: modelContext, year: year) {
            throw AppError.yearLocked(year: year)
        }
    }

    private func validateYearsOpenForDeletion(asset: PPFixedAsset, depreciationEntries: [PPJournalEntry]) throws {
        var affectedYears: Set<Int> = [
            fiscalYear(for: asset.acquisitionDate, startMonth: FiscalYearSettings.startMonth),
        ]
        if let disposalDate = asset.disposalDate {
            affectedYears.insert(fiscalYear(for: disposalDate, startMonth: FiscalYearSettings.startMonth))
        }

        for entry in depreciationEntries {
            affectedYears.insert(try depreciationEntryYear(sourceKey: entry.sourceKey, assetId: asset.id))
        }

        for year in affectedYears.sorted() {
            try validateYearIsOpen(year)
        }
    }

    private func wrapped(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .saveFailed(underlying: error)
    }

    private func depreciationEntries(forAssetId assetId: UUID) -> [PPJournalEntry] {
        let prefix = depreciationSourceKeyPrefix(assetId: assetId)
        return journalEntries().filter { $0.sourceKey.hasPrefix(prefix) }
    }

    private func depreciationEntryYear(sourceKey: String, assetId: UUID) throws -> Int {
        let prefix = depreciationSourceKeyPrefix(assetId: assetId)
        guard sourceKey.hasPrefix(prefix),
              let year = Int(sourceKey.dropFirst(prefix.count)) else {
            throw AppError.invalidInput(message: "減価償却仕訳の年度キーが不正です")
        }
        return year
    }

    private func depreciationSourceKeyPrefix(assetId: UUID) -> String {
        "depreciation:\(assetId.uuidString):"
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
