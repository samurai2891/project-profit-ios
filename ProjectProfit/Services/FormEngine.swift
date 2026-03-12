import Foundation
import SwiftData

/// 申告書式を FilingStyle に応じて生成するファクトリ
@MainActor
enum FormEngine {
    struct BuildInput {
        let fiscalYear: Int
        let startMonth: Int
        let accounts: [PPAccount]
        let categories: [PPCategory]
        let fixedAssets: [PPFixedAsset]
        let inventoryRecord: PPInventoryRecord?
        let businessProfile: BusinessProfile?
        let taxYearProfile: TaxYearProfile?
        let sensitivePayload: ProfileSensitivePayload?
        let projectedEntries: [PPJournalEntry]
        let projectedLines: [PPJournalLine]
        let canonicalJournals: [CanonicalJournalEntry]
        let postingCandidatesById: [UUID: PostingCandidate]
    }

    enum FormEngineError: LocalizedError {
        case unsupportedFilingStyle(FilingStyle)
        case unsupportedTaxYear(Int)
        case dataUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedFilingStyle(let style):
                return "申告形式「\(style.displayName)」は未対応です"
            case .unsupportedTaxYear(let year):
                return "\(year)年分のフォーム定義に未対応です"
            case .dataUnavailable:
                return "帳簿データが取得できません"
            }
        }
    }

    /// FilingStyle に応じた EtaxForm を生成
    static func build(
        filingStyle: FilingStyle,
        dataStore: DataStore,
        fiscalYear: Int
    ) throws -> EtaxForm {
        let formType = formType(for: filingStyle)

        guard TaxYearDefinitionLoader.isSupported(year: fiscalYear, formType: formType) else {
            throw FormEngineError.unsupportedTaxYear(fiscalYear)
        }

        let input = try makeBuildInput(dataStore: dataStore, fiscalYear: fiscalYear)

        switch filingStyle {
        case .blueGeneral:
            let pl = AccountingReportService.generateProfitLoss(
                fiscalYear: input.fiscalYear,
                accounts: input.accounts,
                journalEntries: input.projectedEntries,
                journalLines: input.projectedLines,
                startMonth: input.startMonth
            )
            let bs = AccountingReportService.generateBalanceSheet(
                fiscalYear: input.fiscalYear,
                accounts: input.accounts,
                journalEntries: input.projectedEntries,
                journalLines: input.projectedLines,
                startMonth: input.startMonth
            )
            return EtaxFieldPopulator.populate(
                fiscalYear: input.fiscalYear,
                profitLoss: pl,
                balanceSheet: bs,
                formType: .blueReturn,
                accounts: input.accounts,
                businessProfile: input.businessProfile,
                taxYearProfile: input.taxYearProfile,
                sensitivePayload: input.sensitivePayload,
                inventoryRecord: input.inventoryRecord
            )

        case .blueCashBasis:
            return try CashBasisReturnBuilder.build(input: input)

        case .white:
            let pl = AccountingReportService.generateProfitLoss(
                fiscalYear: input.fiscalYear,
                accounts: input.accounts,
                journalEntries: input.projectedEntries,
                journalLines: input.projectedLines,
                startMonth: input.startMonth
            )
            return ShushiNaiyakushoBuilder.build(profitLoss: pl, input: input)
        }
    }

    static func makeBuildInput(
        dataStore: DataStore,
        fiscalYear: Int
    ) throws -> BuildInput {
        let startMonth = FiscalYearSettings.startMonth
        let projected = dataStore.projectedCanonicalJournals(fiscalYear: fiscalYear)
        let canonical = dataStore.canonicalExportProfiles(for: fiscalYear)
        let canonicalJournals = dataStore.canonicalJournalEntries(fiscalYear: fiscalYear)
        let candidateIds = Set(canonicalJournals.compactMap(\.sourceCandidateId))

        return BuildInput(
            fiscalYear: fiscalYear,
            startMonth: startMonth,
            accounts: dataStore.accounts,
            categories: dataStore.categories,
            fixedAssets: dataStore.fixedAssets,
            inventoryRecord: dataStore.getInventoryRecord(fiscalYear: fiscalYear),
            businessProfile: canonical?.business,
            taxYearProfile: canonical?.taxYear,
            sensitivePayload: canonical?.sensitive,
            projectedEntries: projected.entries,
            projectedLines: projected.lines,
            canonicalJournals: canonicalJournals,
            postingCandidatesById: try fetchPostingCandidates(
                ids: candidateIds,
                modelContext: dataStore.modelContext
            )
        )
    }

    /// FilingStyle -> EtaxFormType のマッピング
    static func formType(for filingStyle: FilingStyle) -> EtaxFormType {
        switch filingStyle {
        case .blueGeneral: .blueReturn
        case .blueCashBasis: .blueCashBasis
        case .white: .whiteReturn
        }
    }

    private static func fetchPostingCandidates(
        ids: Set<UUID>,
        modelContext: ModelContext
    ) throws -> [UUID: PostingCandidate] {
        guard !ids.isEmpty else {
            return [:]
        }

        let descriptor = FetchDescriptor<PostingCandidateEntity>()
        let entities = try modelContext.fetch(descriptor)
        return entities.reduce(into: [UUID: PostingCandidate]()) { result, entity in
            guard ids.contains(entity.candidateId) else {
                return
            }
            let candidate = PostingCandidateEntityMapper.toDomain(entity)
            result[candidate.id] = candidate
        }
    }
}
