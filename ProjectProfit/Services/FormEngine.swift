import Foundation

/// 申告書式を FilingStyle に応じて生成するファクトリ
@MainActor
enum FormEngine {

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

        let startMonth = FiscalYearSettings.startMonth
        let projected = dataStore.projectedCanonicalJournals(fiscalYear: fiscalYear)
        let accounts = dataStore.accounts
        let profile = dataStore.etaxExportProfile(for: fiscalYear)

        switch filingStyle {
        case .blueGeneral:
            let pl = AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            )
            let bs = AccountingReportService.generateBalanceSheet(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            )
            let inventoryRecord = dataStore.getInventoryRecord(fiscalYear: fiscalYear)
            return EtaxFieldPopulator.populate(
                fiscalYear: fiscalYear,
                profitLoss: pl,
                balanceSheet: bs,
                formType: .blueReturn,
                accounts: accounts,
                profile: profile,
                inventoryRecord: inventoryRecord
            )

        case .blueCashBasis:
            return try CashBasisReturnBuilder.build(
                fiscalYear: fiscalYear,
                dataStore: dataStore,
                profile: profile
            )

        case .white:
            let pl = AccountingReportService.generateProfitLoss(
                fiscalYear: fiscalYear,
                accounts: accounts,
                journalEntries: projected.entries,
                journalLines: projected.lines,
                startMonth: startMonth
            )
            return ShushiNaiyakushoBuilder.build(
                fiscalYear: fiscalYear,
                profitLoss: pl,
                accounts: accounts,
                profile: profile,
                fixedAssets: dataStore.fixedAssets,
                journalLines: projected.lines,
                journalEntries: projected.entries
            )
        }
    }

    /// FilingStyle -> EtaxFormType のマッピング
    static func formType(for filingStyle: FilingStyle) -> EtaxFormType {
        switch filingStyle {
        case .blueGeneral: .blueReturn
        case .blueCashBasis: .blueCashBasis
        case .white: .whiteReturn
        }
    }
}
