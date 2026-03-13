import Foundation

/// 申告書式を FilingStyle に応じて生成するファクトリ
@MainActor
enum FormEngine {
    struct BuildInput {
        let fiscalYear: Int
        let startMonth: Int
        let canonicalAccounts: [CanonicalAccount]
        let legacyAccountsById: [String: PPAccount]
        let categoryNamesById: [String: String]
        let fixedAssets: [PPFixedAsset]
        let inventoryRecord: PPInventoryRecord?
        let businessProfile: BusinessProfile?
        let taxYearProfile: TaxYearProfile?
        let sensitivePayload: ProfileSensitivePayload?
        let canonicalProfitLoss: CanonicalProfitLossReport
        let canonicalBalanceSheet: CanonicalBalanceSheetReport
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
        input: BuildInput
    ) throws -> EtaxForm {
        let formType = formType(for: filingStyle)

        guard TaxYearDefinitionLoader.isSupported(year: input.fiscalYear, formType: formType) else {
            throw FormEngineError.unsupportedTaxYear(input.fiscalYear)
        }

        switch filingStyle {
        case .blueGeneral:
            return EtaxFieldPopulator.populate(
                fiscalYear: input.fiscalYear,
                canonicalProfitLoss: input.canonicalProfitLoss,
                canonicalBalanceSheet: input.canonicalBalanceSheet,
                formType: .blueReturn,
                canonicalAccounts: input.canonicalAccounts,
                legacyAccountsById: input.legacyAccountsById,
                businessProfile: input.businessProfile,
                taxYearProfile: input.taxYearProfile,
                sensitivePayload: input.sensitivePayload,
                inventoryRecord: input.inventoryRecord
            )

        case .blueCashBasis:
            return try CashBasisReturnBuilder.build(input: input)

        case .white:
            return ShushiNaiyakushoBuilder.build(
                canonicalProfitLoss: input.canonicalProfitLoss,
                input: input
            )
        }
    }

    static func makeBuildInput(
        dataStore: DataStore,
        fiscalYear: Int
    ) throws -> BuildInput {
        BuildInput(
            snapshot: EtaxFormBuildQueryUseCase(modelContext: dataStore.modelContext)
                .snapshot(fiscalYear: fiscalYear)
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

    static func build(
        filingStyle: FilingStyle,
        dataStore: DataStore,
        fiscalYear: Int
    ) throws -> EtaxForm {
        try build(
            filingStyle: filingStyle,
            input: makeBuildInput(dataStore: dataStore, fiscalYear: fiscalYear)
        )
    }
}

extension FormEngine.BuildInput {
    init(snapshot: EtaxFormBuildSnapshot) {
        self.init(
            fiscalYear: snapshot.fiscalYear,
            startMonth: snapshot.startMonth,
            canonicalAccounts: snapshot.canonicalAccounts,
            legacyAccountsById: snapshot.legacyAccountsById,
            categoryNamesById: snapshot.categoryNamesById,
            fixedAssets: snapshot.fixedAssets,
            inventoryRecord: snapshot.inventoryRecord,
            businessProfile: snapshot.businessProfile,
            taxYearProfile: snapshot.taxYearProfile,
            sensitivePayload: snapshot.sensitivePayload,
            canonicalProfitLoss: snapshot.canonicalProfitLoss,
            canonicalBalanceSheet: snapshot.canonicalBalanceSheet,
            canonicalJournals: snapshot.canonicalJournals,
            postingCandidatesById: snapshot.postingCandidatesById
        )
    }
}
